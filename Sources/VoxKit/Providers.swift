import Foundation

/// A speech transcription service (on-device or cloud)
struct Provider: Identifiable, Hashable {
    let id: String
    let name: String
    let needsKey: Bool
    /// Base URL of the OpenAI-compatible API, e.g. https://api.openai.com/v1
    let defaultBaseURL: String
    let models: [String]
    /// Whether the API accepts a prompt parameter (used to inject hotwords for better proper-noun accuracy)
    let supportsPrompt: Bool
    /// Default max seconds per chunk (longer audio is split automatically)
    let defaultChunkSeconds: Double
    /// Per-file upload limit (MB)
    let maxUploadMB: Double
    let icon: String
    let keyHint: String
}

enum Providers {
    static let appleLocal = Provider(
        id: "apple", name: "On-Device (Apple)", needsKey: false,
        defaultBaseURL: "", models: ["on-device"],
        supportsPrompt: false, defaultChunkSeconds: 55, maxUploadMB: .infinity,
        icon: "apple.logo", keyHint: "Built-in speech recognition. Free, offline, no key needed.")

    static let openai = Provider(
        id: "openai", name: "OpenAI", needsKey: true,
        defaultBaseURL: "https://api.openai.com/v1",
        models: ["gpt-4o-mini-transcribe", "gpt-4o-transcribe", "gpt-4o-transcribe-diarize", "whisper-1"],
        supportsPrompt: true, defaultChunkSeconds: 600, maxUploadMB: 25,
        icon: "sparkle", keyHint: "Get an API key at platform.openai.com. 25MB per file.")

    static let groq = Provider(
        id: "groq", name: "Groq", needsKey: true,
        defaultBaseURL: "https://api.groq.com/openai/v1",
        models: ["whisper-large-v3-turbo", "whisper-large-v3", "distil-whisper-large-v3-en"],
        supportsPrompt: true, defaultChunkSeconds: 600, maxUploadMB: 25,
        icon: "bolt.horizontal.fill", keyHint: "Get an API key at console.groq.com. Fast, free tier available.")

    static let siliconflow = Provider(
        id: "siliconflow", name: "SiliconFlow", needsKey: true,
        defaultBaseURL: "https://api.siliconflow.cn/v1",
        models: ["FunAudioLLM/SenseVoiceSmall"],
        supportsPrompt: false, defaultChunkSeconds: 300, maxUploadMB: 25,
        icon: "cloud.fill", keyHint: "Get an API key at siliconflow.cn. Great for Chinese.")

    static let zhipu = Provider(
        id: "zhipu", name: "Zhipu GLM", needsKey: true,
        defaultBaseURL: "https://open.bigmodel.cn/api/paas/v4",
        models: ["glm-asr-2512", "glm-asr"],
        supportsPrompt: false, defaultChunkSeconds: 55, maxUploadMB: 25,
        icon: "brain.fill", keyHint: "Zhipu BigModel key — strong Chinese recognition.")

    // Raw-body REST API (POST audio bytes to /v1/listen)
    static let deepgram = Provider(
        id: "deepgram", name: "Deepgram", needsKey: true,
        defaultBaseURL: "https://api.deepgram.com",
        models: ["nova-3", "nova-2"],
        supportsPrompt: false, defaultChunkSeconds: 1200, maxUploadMB: 200,
        icon: "waveform.badge.magnifyingglass", keyHint: "Deepgram key — top English accuracy, very fast.")

    // Own multipart API with an xi-api-key header
    static let elevenlabs = Provider(
        id: "elevenlabs", name: "ElevenLabs", needsKey: true,
        defaultBaseURL: "https://api.elevenlabs.io",
        models: ["scribe_v2", "scribe_v1"],
        supportsPrompt: false, defaultChunkSeconds: 3600, maxUploadMB: 500,
        icon: "ear.fill", keyHint: "ElevenLabs key — multilingual Scribe transcription and premium voices.")

    // Async REST API (upload → create → poll); handles hours-long audio natively, so no chunking
    static let assemblyai = Provider(
        id: "assemblyai", name: "AssemblyAI", needsKey: true,
        defaultBaseURL: "https://api.assemblyai.com",
        models: ["universal-3-pro", "universal-2"],
        supportsPrompt: false, defaultChunkSeconds: 14400, maxUploadMB: 2048,
        icon: "person.2.wave.2.fill",
        keyHint: "AssemblyAI key — meeting-grade transcription with speaker diarization.")

    static let custom = Provider(
        id: "custom", name: "Custom (OpenAI-compatible)", needsKey: true,
        defaultBaseURL: "",
        models: [],
        supportsPrompt: true, defaultChunkSeconds: 600, maxUploadMB: 25,
        icon: "wrench.and.screwdriver.fill", keyHint: "Any OpenAI-compatible /audio/transcriptions service.")

    static let all: [Provider] = [appleLocal, openai, groq, deepgram, elevenlabs, assemblyai, siliconflow, zhipu, custom]
    static let cloud: [Provider] = [openai, groq, deepgram, elevenlabs, assemblyai, siliconflow, zhipu, custom]

    static func by(_ id: String) -> Provider {
        all.first { $0.id == id } ?? appleLocal
    }
}

/// Provider parameters the user can override in Settings (stored in UserDefaults)
enum ProviderConfig {
    static func baseURL(_ p: Provider) -> String {
        let v = UserDefaults.standard.string(forKey: "base.\(p.id)") ?? ""
        return v.isEmpty ? p.defaultBaseURL : v
    }

    static func chunkSeconds(_ p: Provider) -> Double {
        let v = UserDefaults.standard.double(forKey: "chunk.\(p.id)")
        return v > 0 ? v : p.defaultChunkSeconds
    }

    static func models(_ p: Provider) -> [String] {
        if p.id == "custom" {
            let raw = UserDefaults.standard.string(forKey: "models.custom") ?? ""
            let list = raw.split(whereSeparator: { $0 == "," || $0 == "，" || $0 == "\n" })
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            return list
        }
        return p.models
    }
}
