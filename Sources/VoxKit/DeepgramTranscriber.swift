import Foundation

/// Deepgram client: raw audio bytes POSTed to /v1/listen with query parameters.
enum DeepgramTranscriber {
    static func transcribe(fileURL: URL, provider: Provider, model: String, language: String?) async throws -> String {
        guard let key = Keychain.get(account: provider.id), !key.isEmpty else {
            throw VoxError.message(L.t("\(provider.displayName) has no API key. Add one in Settings.",
                                       "\(provider.displayName) 还没有配置 API Key，请到「设置」填写"))
        }
        let base = ProviderConfig.baseURL(provider).trimmingCharacters(in: .whitespaces)
        var components = URLComponents(string: (base.hasSuffix("/") ? String(base.dropLast()) : base) + "/v1/listen")
        let diarize = (UserDefaults.standard.object(forKey: "deepgram.diarize") as? Bool) ?? false
        var query = [
            URLQueryItem(name: "model", value: model),
            URLQueryItem(name: "smart_format", value: "true"),
        ]
        if diarize {
            query.append(URLQueryItem(name: "diarize", value: "true"))
            query.append(URLQueryItem(name: "utterances", value: "true"))
        }
        if model == "nova-3" {
            // nova-3's single-language mode is English-only; everything else
            // (incl. Chinese and code-switching) goes through multilingual mode
            query.append(URLQueryItem(name: "language", value: language == "en" ? "en" : "multi"))
        } else if let language, !language.isEmpty {
            query.append(URLQueryItem(name: "language", value: language))
        } else {
            query.append(URLQueryItem(name: "detect_language", value: "true"))
        }
        components?.queryItems = query
        guard let url = components?.url else {
            throw VoxError.message(L.t("Invalid API URL: \(base)", "API 地址无效：\(base)"))
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 900
        request.setValue("Token \(key)", forHTTPHeaderField: "Authorization")
        request.setValue(mimeType(for: fileURL), forHTTPHeaderField: "Content-Type")

        let (data, response) = try await URLSession.shared.upload(for: request, fromFile: fileURL)
        guard let http = response as? HTTPURLResponse else {
            throw VoxError.message(L.t("No response from \(provider.displayName)", "\(provider.displayName) 无响应"))
        }
        guard http.statusCode == 200 else {
            var message = String(data: data, encoding: .utf8) ?? ""
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let err = json["err_msg"] as? String { message = err }
            throw VoxError.message("\(provider.displayName) \(http.statusCode): \(String(message.prefix(300)))")
        }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let results = json["results"] as? [String: Any] else {
            throw VoxError.message(L.t("Could not parse response from \(provider.displayName)",
                                       "无法解析 \(provider.displayName) 的转写结果"))
        }
        // With diarization, format utterances as "[mm:ss] Speaker 1: …"
        if diarize, let utterances = results["utterances"] as? [[String: Any]], !utterances.isEmpty {
            let lines = utterances.compactMap { utterance -> String? in
                guard let text = (utterance["transcript"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
                      !text.isEmpty else { return nil }
                let speaker = (utterance["speaker"] as? Int).map(String.init) ?? "?"
                let start = (utterance["start"] as? Double) ?? 0
                return "[\(Format.mmss(start))] \(L.t("Speaker", "说话人")) \(speaker)\(L.t(": ", "："))\(text)"
            }
            if !lines.isEmpty { return lines.joined(separator: "\n\n") }
        }
        guard let channels = results["channels"] as? [[String: Any]],
              let alternatives = channels.first?["alternatives"] as? [[String: Any]],
              let transcript = alternatives.first?["transcript"] as? String else {
            throw VoxError.message(L.t("Could not parse response from \(provider.displayName)",
                                       "无法解析 \(provider.displayName) 的转写结果"))
        }
        return transcript
    }

    private static func mimeType(for url: URL) -> String {
        switch url.pathExtension.lowercased() {
        case "wav": return "audio/wav"
        case "m4a", "mp4": return "audio/mp4"
        case "mp3": return "audio/mpeg"
        case "flac": return "audio/flac"
        case "aiff", "aif": return "audio/aiff"
        default: return "application/octet-stream"
        }
    }
}
