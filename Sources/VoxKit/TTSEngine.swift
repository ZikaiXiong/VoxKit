import Foundation
import AVFoundation

/// Text-to-speech: the system synthesizer (free, offline) or any OpenAI-compatible
/// /audio/speech endpoint (OpenAI / Groq / SiliconFlow / custom). Cloud API keys are
/// shared with transcription via the Keychain.
enum TTSEngine {
    static let systemID = "system"
    static let providerIDs = [systemID, "openai", "elevenlabs", "groq", "siliconflow", "custom"]

    /// A selectable voice: `id` is the API value, `label` what the picker shows
    struct Voice: Identifiable, Hashable {
        let id: String
        let label: String
    }

    /// Cloud endpoints reject very long inputs (OpenAI caps at 4096 chars)
    static let maxInputLength = 4000

    static func name(_ id: String) -> String {
        id == systemID ? L.t("System Voice (Apple)", "系统语音 (Apple)") : Providers.by(id).displayName
    }

    static func needsKey(_ id: String) -> Bool { id != systemID }

    /// Selectable models per provider — pickers everywhere, no typing
    static func models(_ id: String) -> [String] {
        switch id {
        case "openai": return ["gpt-4o-mini-tts", "tts-1", "tts-1-hd"]
        case "elevenlabs": return ["eleven_multilingual_v2", "eleven_turbo_v2_5", "eleven_v3"]
        case "groq": return ["playai-tts"]
        case "siliconflow": return ["FunAudioLLM/CosyVoice2-0.5B", "fishaudio/fish-speech-1.5"]
        default: return []
        }
    }

    /// Selectable voices per provider
    static func voices(_ id: String) -> [Voice] {
        switch id {
        case "openai":
            return ["alloy", "ash", "ballad", "coral", "echo", "fable", "nova", "onyx", "sage", "shimmer"]
                .map { Voice(id: $0, label: $0) }
        case "elevenlabs":
            // Stable premade voice IDs from the public ElevenLabs voice library
            return [
                Voice(id: "21m00Tcm4TlvDq8ikWAM", label: "Rachel"),
                Voice(id: "EXAVITQu4vr4xnSDxMaL", label: "Sarah"),
                Voice(id: "JBFqnCBsd6RMkjVDRZzb", label: "George"),
                Voice(id: "pNInz6obpgDQGcFmaJgB", label: "Adam"),
                Voice(id: "IKne3meq5aSn9XLyUdCD", label: "Charlie"),
                Voice(id: "pFZP5JQG7iQjIQuC4Bku", label: "Lily"),
            ]
        case "groq":
            return ["Fritz-PlayAI", "Arista-PlayAI", "Atlas-PlayAI", "Celeste-PlayAI", "Quinn-PlayAI", "Thunder-PlayAI"]
                .map { Voice(id: $0, label: $0.replacingOccurrences(of: "-PlayAI", with: "")) }
        case "siliconflow":
            // Voice names; the request prepends the selected model ("model:name")
            return ["anna", "bella", "benjamin", "charles", "claire", "david", "diana"]
                .map { Voice(id: $0, label: $0) }
        default:
            return []
        }
    }

    static func defaultModel(_ id: String) -> String { models(id).first ?? "" }

    static func defaultVoice(_ id: String) -> String { voices(id).first?.id ?? "" }

    static func model(for id: String) -> String {
        let stored = UserDefaults.standard.string(forKey: "tts.model.\(id)") ?? ""
        if id != "custom", !models(id).isEmpty, !models(id).contains(stored) { return defaultModel(id) }
        return stored.isEmpty ? defaultModel(id) : stored
    }

    static func voice(for id: String) -> String {
        let stored = UserDefaults.standard.string(forKey: "tts.voice.\(id)") ?? ""
        if id != "custom", id != systemID, !voices(id).isEmpty, !voices(id).contains(where: { $0.id == stored }) {
            return defaultVoice(id)
        }
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

        let voiceLabel: String
        if providerID == systemID {
            voiceLabel = systemVoiceName(voice)
        } else {
            voiceLabel = voices(providerID).first(where: { $0.id == voice })?.label ?? voice
        }
        return SpeechItem(text: trimmed, providerID: providerID, model: model,
                          voice: voiceLabel,
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
        if providerID == "elevenlabs" {
            return try await ElevenLabsClient.synthesize(text: text, voiceID: voice, model: model)
        }
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
        // SiliconFlow expects "model:voiceName"
        let voiceValue = providerID == "siliconflow" ? "\(model):\(voice)" : voice
        var payload: [String: Any] = [
            "model": model,
            "input": text,
            "voice": voiceValue,
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
