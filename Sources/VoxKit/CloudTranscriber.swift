import Foundation

/// OpenAI-compatible /audio/transcriptions client (shared by OpenAI / Groq / SiliconFlow / custom services)
enum CloudTranscriber {
    static func transcribe(fileURL: URL, provider: Provider, model: String,
                           language: String?, prompt: String?) async throws -> String {
        let base = ProviderConfig.baseURL(provider).trimmingCharacters(in: .whitespaces)
        guard !base.isEmpty else {
            throw VoxError.message(L.t("\(provider.displayName) has no API URL. Set it in Settings.",
                                       "\(provider.displayName) 没有配置 API 地址，请到「设置」填写"))
        }
        let endpoint = base.hasSuffix("/") ? base + "audio/transcriptions" : base + "/audio/transcriptions"
        guard let url = URL(string: endpoint) else {
            throw VoxError.message(L.t("Invalid API URL: \(endpoint)", "API 地址无效：\(endpoint)"))
        }
        guard let key = Keychain.get(account: provider.id), !key.isEmpty else {
            throw VoxError.message(L.t("\(provider.displayName) has no API key. Add one in Settings.",
                                       "\(provider.displayName) 还没有配置 API Key，请到「设置」填写"))
        }
        guard !model.isEmpty else {
            throw VoxError.message(L.t("\(provider.displayName) has no model selected", "\(provider.displayName) 没有选择模型"))
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 900
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")

        let boundary = "voxkit-\(UUID().uuidString)"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()
        func appendField(_ name: String, _ value: String) {
            body.appendUTF8("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"\r\n\r\n\(value)\r\n")
        }
        appendField("model", model)
        // Diarizing models return speaker-labeled segments and require a chunking strategy
        let diarized = model.contains("diarize")
        if diarized {
            appendField("response_format", "diarized_json")
            appendField("chunking_strategy", "auto")
        } else {
            appendField("response_format", "json")
        }
        if let language, !language.isEmpty { appendField("language", language) }
        if let prompt, !prompt.isEmpty, !diarized { appendField("prompt", prompt) }

        let ext = fileURL.pathExtension.lowercased()
        let mime: String
        switch ext {
        case "wav": mime = "audio/wav"
        case "m4a", "mp4": mime = "audio/mp4"
        case "mp3": mime = "audio/mpeg"
        case "flac": mime = "audio/flac"
        case "ogg": mime = "audio/ogg"
        case "aiff", "aif": mime = "audio/aiff"
        default: mime = "application/octet-stream"
        }
        let audio = try Data(contentsOf: fileURL)
        body.appendUTF8("--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"audio.\(ext.isEmpty ? "wav" : ext)\"\r\nContent-Type: \(mime)\r\n\r\n")
        body.append(audio)
        body.appendUTF8("\r\n--\(boundary)--\r\n")

        let (data, response) = try await URLSession.shared.upload(for: request, from: body)
        guard let http = response as? HTTPURLResponse else {
            throw VoxError.message(L.t("No response from \(provider.displayName)", "\(provider.displayName) 无响应"))
        }
        guard http.statusCode == 200 else {
            var message = String(data: data, encoding: .utf8) ?? ""
            if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let err = obj["error"] as? [String: Any],
               let msg = err["message"] as? String {
                message = msg
            }
            throw VoxError.message("\(provider.displayName) \(http.statusCode): \(String(message.prefix(300)))")
        }
        if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            // diarized_json: format segments as "[mm:ss] Speaker A: …" paragraphs
            if diarized, let segments = obj["segments"] as? [[String: Any]], !segments.isEmpty {
                let lines = segments.compactMap { segment -> String? in
                    guard let text = (segment["text"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
                          !text.isEmpty else { return nil }
                    let speaker = (segment["speaker"] as? String) ?? "?"
                    let start = (segment["start"] as? Double) ?? 0
                    return "[\(Format.mmss(start))] \(L.t("Speaker", "说话人")) \(speaker)\(L.t(": ", "："))\(text)"
                }
                if !lines.isEmpty { return lines.joined(separator: "\n\n") }
            }
            if let text = obj["text"] as? String {
                return text
            }
        }
        if let text = String(data: data, encoding: .utf8), !text.isEmpty {
            return text   // some services return plain text directly
        }
        throw VoxError.message(L.t("Could not parse response from \(provider.displayName)", "无法解析 \(provider.displayName) 的转写结果"))
    }
}

extension Data {
    mutating func appendUTF8(_ string: String) {
        if let d = string.data(using: .utf8) { append(d) }
    }
}
