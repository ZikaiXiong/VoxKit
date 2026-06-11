import Foundation

/// Bilingual UI: every string is written inline in both languages; `L.t(zh, en)` picks one by the current UI language.
/// AppState triggers a full redraw after the language changes.
enum L {
    /// Effective language: "zh" or "en"
    static var lang: String = resolve(UserDefaults.standard.string(forKey: "uiLang") ?? "system")

    static var zh: Bool { lang == "zh" }

    /// App display name follows the interface language — never mixed.
    static var appName: String { t("声记", "VoxKit") }

    static func t(_ zhText: String, _ enText: String) -> String {
        zh ? zhText : enText
    }

    /// pref: "system" / "zh" / "en"
    static func apply(_ pref: String) {
        lang = resolve(pref)
    }

    private static func resolve(_ pref: String) -> String {
        switch pref {
        case "zh", "en": return pref
        default:
            let first = Locale.preferredLanguages.first ?? "zh"
            return first.hasPrefix("zh") ? "zh" : "en"
        }
    }
}

// MARK: - Localized provider names and hints

extension Provider {
    var displayName: String {
        switch id {
        case "apple": return L.t("本机识别 (Apple)", "On-Device (Apple)")
        case "openai": return "OpenAI"
        case "groq": return "Groq"
        case "siliconflow": return L.t("硅基流动 SiliconFlow", "SiliconFlow")
        case "assemblyai": return "AssemblyAI"
        case "custom": return L.t("自定义（OpenAI 兼容）", "Custom (OpenAI-compatible)")
        default: return name
        }
    }

    var hint: String {
        switch id {
        case "apple":
            return L.t("系统自带语音识别，离线免费，无需密钥；适合快速听写。",
                       "Built-in speech recognition. Free, offline, no key needed.")
        case "openai":
            return L.t("在 platform.openai.com 获取 API Key。单文件上限 25MB。",
                       "Get an API key at platform.openai.com. 25MB per file.")
        case "groq":
            return L.t("在 console.groq.com 获取 API Key，速度极快、有免费额度。",
                       "Get an API key at console.groq.com. Very fast, free tier available.")
        case "siliconflow":
            return L.t("在 siliconflow.cn 获取 API Key，国内直连，中文效果好。",
                       "Get an API key at siliconflow.cn. Great for Chinese.")
        case "assemblyai":
            return L.t("在 assemblyai.com 获取 Key。会议级：长音频免分段，输出说话人分离稿。",
                       "Get a key at assemblyai.com. Meeting-grade: long audio, speaker diarization.")
        case "custom":
            return L.t("任何 OpenAI 兼容的 /audio/transcriptions 服务，在「高级」里填地址和模型名。",
                       "Any OpenAI-compatible /audio/transcriptions service. Set URL & models under Advanced.")
        default: return keyHint
        }
    }
}
