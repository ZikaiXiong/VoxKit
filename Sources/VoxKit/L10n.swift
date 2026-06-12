import Foundation

/// UI localization. English is the source language: every string is written inline
/// as `L.t(english, chinese)`, and Spanish/French/Japanese resolve through the
/// `Translations` tables keyed by the English string (falling back to English).
/// AppState triggers a full redraw after the language changes.
enum L {
    static let supported = ["en", "zh", "es", "fr", "ja"]

    /// Effective language code; defaults to English when the system language is unsupported
    static var lang: String = resolve(UserDefaults.standard.string(forKey: "uiLang") ?? "system")

    static var zh: Bool { lang == "zh" }

    /// App display name follows the interface language — never mixed.
    static var appName: String { zh ? "声记" : "VoxKit" }

    static func t(_ english: String, _ chinese: String) -> String {
        switch lang {
        case "en": return english
        case "zh": return chinese
        case "es": return Translations.es[english] ?? english
        case "fr": return Translations.fr[english] ?? english
        case "ja": return Translations.ja[english] ?? english
        default: return english
        }
    }

    /// pref: "system" or one of `supported`
    static func apply(_ pref: String) {
        lang = resolve(pref)
    }

    private static func resolve(_ pref: String) -> String {
        if supported.contains(pref) { return pref }
        let system = Locale.preferredLanguages.first ?? "en"
        for code in ["zh", "es", "fr", "ja"] where system.hasPrefix(code) { return code }
        return "en"
    }
}

// MARK: - Localized provider names and hints

extension Provider {
    var displayName: String {
        switch id {
        case "apple": return L.t("On-Device (Apple)", "本机识别 (Apple)")
        case "openai": return "OpenAI"
        case "groq": return "Groq"
        case "siliconflow": return L.t("SiliconFlow", "硅基流动 SiliconFlow")
        case "assemblyai": return "AssemblyAI"
        case "deepgram": return "Deepgram"
        case "elevenlabs": return "ElevenLabs"
        case "zhipu": return L.t("Zhipu GLM", "智谱 GLM")
        case "custom": return L.t("Custom (OpenAI-compatible)", "自定义（OpenAI 兼容）")
        default: return name
        }
    }

    var hint: String {
        switch id {
        case "apple":
            return L.t("Built-in speech recognition. Free, offline, no key needed.",
                       "系统自带语音识别，离线免费，无需密钥；适合快速听写。")
        case "openai":
            return L.t("Get an API key at platform.openai.com. 25MB per file.",
                       "在 platform.openai.com 获取 API Key。单文件上限 25MB。")
        case "groq":
            return L.t("Get an API key at console.groq.com. Very fast, free tier available.",
                       "在 console.groq.com 获取 API Key，速度极快、有免费额度。")
        case "siliconflow":
            return L.t("Get an API key at siliconflow.cn. Great for Chinese.",
                       "在 siliconflow.cn 获取 API Key，国内直连，中文效果好。")
        case "assemblyai":
            return L.t("Get a key at assemblyai.com. Meeting-grade: long audio, speaker diarization.",
                       "在 assemblyai.com 获取 Key。会议级：长音频免分段，输出说话人分离稿。")
        case "deepgram":
            return L.t("Get a key at console.deepgram.com. Top English accuracy, very fast; $200 free credit.",
                       "在 console.deepgram.com 获取 Key。英文准确率顶级、速度快，注册送 $200 额度。")
        case "elevenlabs":
            return L.t("Get a key at elevenlabs.io. Multilingual Scribe transcription + premium TTS voices.",
                       "在 elevenlabs.io 获取 Key。Scribe 多语转写 + 顶级 TTS 音色。")
        case "zhipu":
            return L.t("Get a key at open.bigmodel.cn. Strong Chinese recognition (GLM-ASR).",
                       "在 open.bigmodel.cn 获取 Key。GLM-ASR 中文识别强。")
        case "custom":
            return L.t("Any OpenAI-compatible /audio/transcriptions service. Set URL & models under Advanced.",
                       "任何 OpenAI 兼容的 /audio/transcriptions 服务，在「高级」里填地址和模型名。")
        default: return keyHint
        }
    }
}
