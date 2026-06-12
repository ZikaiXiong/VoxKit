import Foundation

/// ElevenLabs client (xi-api-key auth): Scribe transcription and text-to-speech.
enum ElevenLabsClient {
    private static func apiKey() throws -> String {
        guard let key = Keychain.get(account: "elevenlabs"), !key.isEmpty else {
            throw VoxError.message(L.t("ElevenLabs has no API key. Add one in Settings.",
                                       "ElevenLabs 还没有配置 API Key，请到「设置」填写"))
        }
        return key
    }

    private static func baseURL() -> String {
        let base = ProviderConfig.baseURL(Providers.elevenlabs).trimmingCharacters(in: .whitespaces)
        return base.hasSuffix("/") ? String(base.dropLast()) : base
    }

    // MARK: Speech-to-text (Scribe)

    static func transcribe(fileURL: URL, model: String, language: String?) async throws -> String {
        let key = try apiKey()
        guard let url = URL(string: baseURL() + "/v1/speech-to-text") else {
            throw VoxError.message(L.t("Invalid API URL", "API 地址无效"))
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 1800
        request.setValue(key, forHTTPHeaderField: "xi-api-key")
        let boundary = "voxkit-\(UUID().uuidString)"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()
        func appendField(_ name: String, _ value: String) {
            body.appendUTF8("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"\r\n\r\n\(value)\r\n")
        }
        appendField("model_id", model)
        if let language, !language.isEmpty { appendField("language_code", language) }
        let audio = try Data(contentsOf: fileURL)
        let ext = fileURL.pathExtension.isEmpty ? "wav" : fileURL.pathExtension
        body.appendUTF8("--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"audio.\(ext)\"\r\nContent-Type: audio/\(ext == "mp3" ? "mpeg" : ext)\r\n\r\n")
        body.append(audio)
        body.appendUTF8("\r\n--\(boundary)--\r\n")

        let (data, response) = try await URLSession.shared.upload(for: request, from: body)
        try check(response: response, data: data)
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let text = json["text"] as? String else {
            throw VoxError.message(L.t("Could not parse response from ElevenLabs", "无法解析 ElevenLabs 的转写结果"))
        }
        return text
    }

    // MARK: Text-to-speech

    static func synthesize(text: String, voiceID: String, model: String) async throws -> Data {
        let key = try apiKey()
        guard let url = URL(string: baseURL() + "/v1/text-to-speech/\(voiceID)") else {
            throw VoxError.message(L.t("Invalid API URL", "API 地址无效"))
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 300
        request.setValue(key, forHTTPHeaderField: "xi-api-key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "text": text,
            "model_id": model,
        ])
        let (data, response) = try await URLSession.shared.data(for: request)
        try check(response: response, data: data)
        guard data.count > 200 else {
            throw VoxError.message(L.t("ElevenLabs returned empty audio", "ElevenLabs 返回的音频为空"))
        }
        return data
    }

    private static func check(response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else {
            throw VoxError.message(L.t("No response from ElevenLabs", "ElevenLabs 无响应"))
        }
        guard http.statusCode == 200 else {
            var message = String(data: data, encoding: .utf8) ?? ""
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let detail = json["detail"] as? [String: Any],
               let msg = detail["message"] as? String { message = msg }
            throw VoxError.message("ElevenLabs \(http.statusCode): \(String(message.prefix(300)))")
        }
    }
}
