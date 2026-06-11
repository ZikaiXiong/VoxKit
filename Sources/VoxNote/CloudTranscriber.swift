import Foundation

/// OpenAI-compatible /audio/transcriptions client (shared by OpenAI / Groq / SiliconFlow / custom services)
enum CloudTranscriber {
    static func transcribe(fileURL: URL, provider: Provider, model: String,
                           language: String?, prompt: String?) async throws -> String {
        let base = ProviderConfig.baseURL(provider).trimmingCharacters(in: .whitespaces)
        guard !base.isEmpty else {
            throw VoxError.message(L.t("\(provider.displayName) 没有配置 API 地址，请到「设置」填写",
                                       "\(provider.displayName) has no API URL. Set it in Settings."))
        }
        let endpoint = base.hasSuffix("/") ? base + "audio/transcriptions" : base + "/audio/transcriptions"
        guard let url = URL(string: endpoint) else {
            throw VoxError.message(L.t("API 地址无效：\(endpoint)", "Invalid API URL: \(endpoint)"))
        }
        guard let key = Keychain.get(account: provider.id), !key.isEmpty else {
            throw VoxError.message(L.t("\(provider.displayName) 还没有配置 API Key，请到「设置」填写",
                                       "\(provider.displayName) has no API key. Add one in Settings."))
        }
        guard !model.isEmpty else {
            throw VoxError.message(L.t("\(provider.displayName) 没有选择模型", "\(provider.displayName) has no model selected"))
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 900
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")

        let boundary = "voxnote-\(UUID().uuidString)"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()
        func appendField(_ name: String, _ value: String) {
            body.appendUTF8("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"\r\n\r\n\(value)\r\n")
        }
        appendField("model", model)
        appendField("response_format", "json")
        if let language, !language.isEmpty { appendField("language", language) }
        if let prompt, !prompt.isEmpty { appendField("prompt", prompt) }

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
            throw VoxError.message(L.t("\(provider.displayName) 无响应", "No response from \(provider.displayName)"))
        }
        guard http.statusCode == 200 else {
            var message = String(data: data, encoding: .utf8) ?? ""
            if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let err = obj["error"] as? [String: Any],
               let msg = err["message"] as? String {
                message = msg
            }
            throw VoxError.message("\(provider.displayName) \(http.statusCode)：\(String(message.prefix(300)))")
        }
        if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let text = obj["text"] as? String {
            return text
        }
        if let text = String(data: data, encoding: .utf8), !text.isEmpty {
            return text   // some services return plain text directly
        }
        throw VoxError.message(L.t("无法解析 \(provider.displayName) 的转写结果", "Could not parse response from \(provider.displayName)"))
    }
}

extension Data {
    mutating func appendUTF8(_ string: String) {
        if let d = string.data(using: .utf8) { append(d) }
    }
}
