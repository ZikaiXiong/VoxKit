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
        id: "apple", name: "本机识别 (Apple)", needsKey: false,
        defaultBaseURL: "", models: ["on-device"],
        supportsPrompt: false, defaultChunkSeconds: 55, maxUploadMB: .infinity,
        icon: "apple.logo", keyHint: "系统自带语音识别，离线免费，无需密钥；适合快速听写。")

    static let openai = Provider(
        id: "openai", name: "OpenAI", needsKey: true,
        defaultBaseURL: "https://api.openai.com/v1",
        models: ["gpt-4o-mini-transcribe", "gpt-4o-transcribe", "whisper-1"],
        supportsPrompt: true, defaultChunkSeconds: 600, maxUploadMB: 25,
        icon: "sparkle", keyHint: "在 platform.openai.com 获取 API Key。单文件上限 25MB。")

    static let groq = Provider(
        id: "groq", name: "Groq", needsKey: true,
        defaultBaseURL: "https://api.groq.com/openai/v1",
        models: ["whisper-large-v3-turbo", "whisper-large-v3"],
        supportsPrompt: true, defaultChunkSeconds: 600, maxUploadMB: 25,
        icon: "bolt.horizontal.fill", keyHint: "在 console.groq.com 获取 API Key，速度极快、有免费额度。")

    static let siliconflow = Provider(
        id: "siliconflow", name: "硅基流动 SiliconFlow", needsKey: true,
        defaultBaseURL: "https://api.siliconflow.cn/v1",
        models: ["FunAudioLLM/SenseVoiceSmall"],
        supportsPrompt: false, defaultChunkSeconds: 300, maxUploadMB: 25,
        icon: "cloud.fill", keyHint: "在 siliconflow.cn 获取 API Key，国内直连，中文效果好。")

    // Async REST API (upload → create → poll); handles hours-long audio natively, so no chunking
    static let assemblyai = Provider(
        id: "assemblyai", name: "AssemblyAI", needsKey: true,
        defaultBaseURL: "https://api.assemblyai.com",
        models: ["universal-3-pro", "universal-2"],
        supportsPrompt: false, defaultChunkSeconds: 14400, maxUploadMB: 2048,
        icon: "person.2.wave.2.fill",
        keyHint: "AssemblyAI key — meeting-grade transcription with speaker diarization.")

    static let custom = Provider(
        id: "custom", name: "自定义（OpenAI 兼容）", needsKey: true,
        defaultBaseURL: "",
        models: [],
        supportsPrompt: true, defaultChunkSeconds: 600, maxUploadMB: 25,
        icon: "wrench.and.screwdriver.fill", keyHint: "任何 OpenAI 兼容的 /audio/transcriptions 服务，在「高级」里填地址和模型名。")

    static let all: [Provider] = [appleLocal, openai, groq, siliconflow, assemblyai, custom]
    static let cloud: [Provider] = [openai, groq, siliconflow, assemblyai, custom]

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
