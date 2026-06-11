import Foundation

/// AssemblyAI client: upload → create transcript job → poll until done.
/// Handles hours-long audio in one request and can return speaker-diarized utterances.
enum AssemblyAITranscriber {
    static func transcribe(fileURL: URL, provider: Provider, model: String,
                           language: String?, diarize: Bool) async throws -> String {
        guard let key = Keychain.get(account: provider.id), !key.isEmpty else {
            throw VoxError.message(L.t("\(provider.displayName) 还没有配置 API Key，请到「设置」填写",
                                       "\(provider.displayName) has no API key. Add one in Settings."))
        }
        let base = ProviderConfig.baseURL(provider).trimmingCharacters(in: .whitespaces)
        guard let baseURL = URL(string: base.hasSuffix("/") ? String(base.dropLast()) : base) else {
            throw VoxError.message(L.t("API 地址无效：\(base)", "Invalid API URL: \(base)"))
        }

        // 1. Upload audio (streamed from disk — meeting files can be hundreds of MB)
        var upload = URLRequest(url: baseURL.appendingPathComponent("v2/upload"))
        upload.httpMethod = "POST"
        upload.timeoutInterval = 1800
        upload.setValue(key, forHTTPHeaderField: "authorization")
        upload.setValue("application/octet-stream", forHTTPHeaderField: "content-type")
        let (uploadData, uploadResponse) = try await URLSession.shared.upload(for: upload, fromFile: fileURL)
        guard (uploadResponse as? HTTPURLResponse)?.statusCode == 200,
              let uploadJSON = try? JSONSerialization.jsonObject(with: uploadData) as? [String: Any],
              let audioURL = uploadJSON["upload_url"] as? String else {
            throw VoxError.message(apiError(from: uploadData, fallback: L.t("AssemblyAI 上传失败", "AssemblyAI upload failed")))
        }

        // 2. Create the transcription job.
        // `speech_models` is a priority list: universal-3-pro covers EN/ES/PT/FR/DE/IT
        // and automatically falls back to universal-2 for other languages (e.g. Chinese).
        let speechModels = model == "universal-3-pro" ? ["universal-3-pro", "universal-2"] : [model]
        var body: [String: Any] = [
            "audio_url": audioURL,
            "speech_models": speechModels,
            "speaker_labels": diarize,
        ]
        if let language, !language.isEmpty {
            body["language_code"] = language
        } else {
            body["language_detection"] = true
        }
        var create = URLRequest(url: baseURL.appendingPathComponent("v2/transcript"))
        create.httpMethod = "POST"
        create.timeoutInterval = 60
        create.setValue(key, forHTTPHeaderField: "authorization")
        create.setValue("application/json", forHTTPHeaderField: "content-type")
        create.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (createData, createResponse) = try await URLSession.shared.data(for: create)
        guard let createHTTP = createResponse as? HTTPURLResponse, createHTTP.statusCode == 200,
              let createJSON = try? JSONSerialization.jsonObject(with: createData) as? [String: Any],
              let jobID = createJSON["id"] as? String else {
            throw VoxError.message(apiError(from: createData, fallback: L.t("AssemblyAI 创建任务失败", "AssemblyAI job creation failed")))
        }

        // 3. Poll until completed (audio is processed at a multiple of real time)
        let pollURL = baseURL.appendingPathComponent("v2/transcript/\(jobID)")
        let deadline = Date().addingTimeInterval(1800)
        while true {
            try Task.checkCancellation()
            guard Date() < deadline else {
                throw VoxError.message(L.t("AssemblyAI 处理超时", "AssemblyAI processing timed out"))
            }
            try? await Task.sleep(nanoseconds: 3_000_000_000)

            var poll = URLRequest(url: pollURL)
            poll.setValue(key, forHTTPHeaderField: "authorization")
            let (data, _) = try await URLSession.shared.data(for: poll)
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let status = json["status"] as? String else { continue }

            switch status {
            case "completed":
                return format(json, diarized: diarize)
            case "error":
                let message = json["error"] as? String ?? L.t("未知错误", "unknown error")
                throw VoxError.message("AssemblyAI: \(message)")
            default:
                continue   // queued / processing
            }
        }
    }

    /// Formats the result; with diarization each utterance becomes "[mm:ss] Speaker A: …"
    private static func format(_ json: [String: Any], diarized: Bool) -> String {
        if diarized,
           let utterances = json["utterances"] as? [[String: Any]],
           !utterances.isEmpty {
            let lines = utterances.compactMap { u -> String? in
                guard let text = (u["text"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
                      !text.isEmpty else { return nil }
                let speaker = (u["speaker"] as? String) ?? "?"
                let startMS = (u["start"] as? Int) ?? 0
                let stamp = Format.mmss(Double(startMS) / 1000)
                return "[\(stamp)] \(L.t("说话人", "Speaker")) \(speaker)\(L.t("：", ": "))\(text)"
            }
            if !lines.isEmpty { return lines.joined(separator: "\n\n") }
        }
        return (json["text"] as? String) ?? ""
    }

    private static func apiError(from data: Data, fallback: String) -> String {
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let message = json["error"] as? String {
            return "AssemblyAI: \(message)"
        }
        return fallback
    }
}
