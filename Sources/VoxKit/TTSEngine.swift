import Foundation
import AVFoundation

/// Text-to-speech: the system synthesizer (free, offline) or any OpenAI-compatible
/// /audio/speech endpoint (OpenAI / Groq / SiliconFlow / custom). Cloud API keys are
/// shared with transcription via the Keychain.
enum TTSEngine {
    static let systemID = "system"
    static let providerIDs = [systemID, "openai", "groq", "siliconflow", "custom"]

    /// Cloud endpoints reject very long inputs (OpenAI caps at 4096 chars)
    static let maxInputLength = 4000

    static func name(_ id: String) -> String {
        id == systemID ? L.t("System Voice (Apple)", "系统语音 (Apple)") : Providers.by(id).displayName
    }

    static func needsKey(_ id: String) -> Bool { id != systemID }

    static func defaultModel(_ id: String) -> String {
        switch id {
        case "openai": return "gpt-4o-mini-tts"
        case "groq": return "playai-tts"
        case "siliconflow": return "FunAudioLLM/CosyVoice2-0.5B"
        default: return ""
        }
    }

    static func defaultVoice(_ id: String) -> String {
        switch id {
        case "openai": return "alloy"
        case "groq": return "Fritz-PlayAI"
        case "siliconflow": return "FunAudioLLM/CosyVoice2-0.5B:anna"
        default: return ""
        }
    }

    static let openAIVoices = ["alloy", "ash", "ballad", "coral", "echo", "fable", "nova", "onyx", "sage", "shimmer"]

    static func model(for id: String) -> String {
        let stored = UserDefaults.standard.string(forKey: "tts.model.\(id)") ?? ""
        return stored.isEmpty ? defaultModel(id) : stored
    }

    static func voice(for id: String) -> String {
        let stored = UserDefaults.standard.string(forKey: "tts.voice.\(id)") ?? ""
        return stored.isEmpty ? defaultVoice(id) : stored
    }

    /// System voices for the picker, current-UI-language ones first
    static func systemVoices() -> [AVSpeechSynthesisVoice] {
        let supported = ["zh", "en", "es", "fr", "ja"]
        let all = AVSpeechSynthesisVoice.speechVoices()
            .filter { voice in supported.contains(where: { voice.language.hasPrefix($0) }) }
            .sorted { ($0.language, $0.name) < ($1.language, $1.name) }
        let preferred = L.zh ? "zh" : "en"
        return all.sorted { ($0.language.hasPrefix(preferred) ? 0 : 1) < ($1.language.hasPrefix(preferred) ? 0 : 1) }
    }

    // MARK: Generation

    /// Synthesizes `text` into an audio file in `directory` and returns the ready-to-store item.
    static func generate(text: String, providerID: String, speed: Double, into directory: URL) async throws -> SpeechItem {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw VoxError.message(L.t("Enter some text first", "请输入要朗读的文本"))
        }
        guard providerID == systemID || trimmed.count <= maxInputLength else {
            throw VoxError.message(L.t("Text too long (\(trimmed.count) chars): cloud TTS caps at ~\(maxInputLength) chars per request",
                                       "文本过长（\(trimmed.count) 字）：云端语音单次最多约 \(maxInputLength) 字，请分段生成"))
        }

        let model = model(for: providerID)
        let voice = voice(for: providerID)
        let ext = providerID == systemID ? "caf" : "mp3"
        let fileName = "\(UUID().uuidString).\(ext)"
        let dest = directory.appendingPathComponent(fileName)

        var duration: TimeInterval = 0
        if providerID == systemID {
            duration = try await synthesizeSystem(text: trimmed, voiceID: voice, speed: speed, to: dest)
        } else {
            let data = try await synthesizeCloud(text: trimmed, providerID: providerID, model: model, voice: voice, speed: speed)
            try data.write(to: dest, options: .atomic)
            if let f = try? AVAudioFile(forReading: dest), f.processingFormat.sampleRate > 0 {
                duration = Double(f.length) / f.processingFormat.sampleRate
            }
        }

        return SpeechItem(text: trimmed, providerID: providerID, model: model,
                          voice: providerID == systemID ? systemVoiceName(voice) : voice,
                          fileName: fileName, duration: duration)
    }

    private static func systemVoiceName(_ identifier: String) -> String {
        guard !identifier.isEmpty, let v = AVSpeechSynthesisVoice(identifier: identifier) else {
            return L.t("Default", "默认")
        }
        return v.name
    }

    // MARK: System synthesizer (writes a CAF file)

    private static func synthesizeSystem(text: String, voiceID: String, speed: Double, to url: URL) async throws -> TimeInterval {
        final class Holder: @unchecked Sendable {
            let synthesizer = AVSpeechSynthesizer()
            var file: AVAudioFile?
            var resumed = false
        }
        let holder = Holder()

        let utterance = AVSpeechUtterance(string: text)
        if !voiceID.isEmpty, let voice = AVSpeechSynthesisVoice(identifier: voiceID) {
            utterance.voice = voice
        } else {
            utterance.voice = AVSpeechSynthesisVoice(language: L.zh ? "zh-CN" : "en-US")
        }
        // AVSpeech rate: 0.5 is normal; map the 0.5×–2× UI slider into a usable band
        utterance.rate = Float(min(max(0.5 + (speed - 1.0) * 0.15, 0.2), 0.9))

        return try await withCheckedThrowingContinuation { continuation in
            holder.synthesizer.write(utterance) { buffer in
                guard let pcm = buffer as? AVAudioPCMBuffer else { return }
                if pcm.frameLength == 0 {
                    // Zero-length buffer marks the end of synthesis
                    guard !holder.resumed else { return }
                    holder.resumed = true
                    let duration = holder.file.map { Double($0.length) / $0.processingFormat.sampleRate } ?? 0
                    continuation.resume(returning: duration)
                    return
                }
                do {
                    if holder.file == nil {
                        holder.file = try AVAudioFile(forWriting: url, settings: pcm.format.settings)
                    }
                    try holder.file?.write(from: pcm)
                } catch {
                    guard !holder.resumed else { return }
                    holder.resumed = true
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    // MARK: OpenAI-compatible /audio/speech

    private static func synthesizeCloud(text: String, providerID: String, model: String,
                                        voice: String, speed: Double) async throws -> Data {
        let provider = Providers.by(providerID)
        let base = ProviderConfig.baseURL(provider).trimmingCharacters(in: .whitespaces)
        guard !base.isEmpty,
              let url = URL(string: base.hasSuffix("/") ? base + "audio/speech" : base + "/audio/speech") else {
            throw VoxError.message(L.t("Invalid API URL for \(provider.displayName)", "\(provider.displayName) 的 API 地址无效"))
        }
        guard let key = Keychain.get(account: provider.id), !key.isEmpty else {
            throw VoxError.message(L.t("\(provider.displayName) has no API key (shared with transcription — add one in Settings)",
                                       "\(provider.displayName) 未配置 API Key（与转写共用，可在设置中填写）"))
        }
        guard !model.isEmpty else {
            throw VoxError.message(L.t("Enter a TTS model name", "请填写语音模型名"))
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 300
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        var payload: [String: Any] = [
            "model": model,
            "input": text,
            "voice": voice,
            "response_format": "mp3",
        ]
        if abs(speed - 1.0) > 0.01 { payload["speed"] = speed }
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw VoxError.message(L.t("No response from \(provider.displayName)", "\(provider.displayName) 无响应"))
        }
        guard http.statusCode == 200 else {
            var message = String(data: data, encoding: .utf8) ?? ""
            if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let err = obj["error"] as? [String: Any], let msg = err["message"] as? String {
                message = msg
            }
            throw VoxError.message("\(provider.displayName) \(http.statusCode): \(String(message.prefix(300)))")
        }
        guard data.count > 200 else {
            throw VoxError.message(L.t("\(provider.displayName) returned empty audio", "\(provider.displayName) 返回的音频为空"))
        }
        return data
    }
}
