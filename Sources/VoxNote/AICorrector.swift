import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// AI grammar/typo correction: sends the transcript along with the user's lexicon to a language model for targeted proofreading.
/// Mis-recognitions vary wildly while the correct terms stay fixed — so the model corrects
/// with the glossary in mind and full context, rather than doing fixed pair replacements.
enum AICorrector {
    static let appleID = "apple-llm"

    // MARK: Configuration (written to UserDefaults by the Settings page)

    static var autoEnabled: Bool { UserDefaults.standard.bool(forKey: "ai.auto") }

    static var providerID: String { UserDefaults.standard.string(forKey: "ai.provider") ?? appleID }

    static func defaultModel(for pid: String) -> String {
        switch pid {
        case "openai": return "gpt-4o-mini"
        case "groq": return "llama-3.3-70b-versatile"
        case "siliconflow": return "Qwen/Qwen2.5-7B-Instruct"
        default: return ""
        }
    }

    static func model(for pid: String) -> String {
        let stored = UserDefaults.standard.string(forKey: "ai.model.\(pid)") ?? ""
        return stored.isEmpty ? defaultModel(for: pid) : stored
    }

    /// Whether the on-device Apple model is available (macOS 26+ with Apple Intelligence enabled)
    static var appleAvailable: Bool {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            if case .available = SystemLanguageModel.default.availability { return true }
        }
        #endif
        return false
    }

    static var isConfigured: Bool {
        if providerID == appleID { return appleAvailable }
        return Keychain.has(account: providerID) && !model(for: providerID).isEmpty
    }

    static var configuredLabel: String {
        providerID == appleID
            ? L.t("Apple 智能（本机）", "Apple Intelligence (on-device)")
            : "\(Providers.by(providerID).displayName) · \(model(for: providerID))"
    }

    // MARK: Correction entry point

    static func correct(text: String, language: String, lexicon: LexiconData) async throws -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return text }
        guard isConfigured else {
            throw VoxError.message(L.t("AI 修正还没有配置，请到「设置 → AI 修正」选择模型。",
                                       "AI correction is not configured. See Settings → AI Correction."))
        }
        let system = systemPrompt(language: language, lexicon: lexicon)
        let chunks = split(trimmed, maxLength: providerID == appleID ? 1500 : 2600)

        var results: [String] = []
        for chunk in chunks {
            let fixed: String
            if providerID == appleID {
                fixed = try await appleCorrect(chunk: chunk, instructions: system)
            } else {
                fixed = try await chatCorrect(chunk: chunk, system: system)
            }
            results.append(fixed.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return results.joined(separator: "\n\n")
    }

    private static func systemPrompt(language: String, lexicon: LexiconData) -> String {
        var glossary = ""
        let hotwords = (lexicon.hotwords + lexicon.rules.filter(\.isActive).map(\.replacement))
        var seen = Set<String>()
        let words = hotwords.filter { seen.insert($0).inserted }.prefix(40)
        if !words.isEmpty {
            glossary += L.t("用户词库（这些词必须拼写正确）：", "User glossary (these terms must be spelled exactly): ")
                + words.joined(separator: "、") + "\n"
        }
        let pairs = lexicon.rules.filter(\.isActive).prefix(30).map { "\($0.original)→\($0.replacement)" }
        if !pairs.isEmpty {
            glossary += L.t("历史纠错对照（左边是常见误识别，右边是正确写法）：", "Known mis-recognitions (wrong→right): ")
                + pairs.joined(separator: "，") + "\n"
        }
        let langHint: String
        switch language {
        case "en": langHint = "The text is in English."
        case "zh": langHint = "文本为中文。"
        default: langHint = L.t("文本可能是中文、英文或混合。", "The text may be Chinese, English, or mixed.")
        }
        return L.t("""
            你是语音听写文本的校对助手。修正下面语音转写文本中的错别字、同音字误识别、漏标或错标的标点。\(langHint)
            \(glossary)要求：
            1. 保持原意和口语风格，不增删内容、不改写句式、不做总结；
            2. 保留所有换行和形如 [12:34] 的时间戳；
            3. 优先按用户词库修正专有名词；
            4. 只输出修正后的文本，不要任何解释。
            """, """
            You are a proofreader for speech-to-text transcripts. Fix typos, homophone mis-recognitions, and punctuation in the transcript below. \(langHint)
            \(glossary)Rules:
            1. Preserve the meaning and spoken style; do not add, remove, or summarize content;
            2. Keep all line breaks and timestamps like [12:34];
            3. Prefer the user glossary for proper nouns;
            4. Output ONLY the corrected text, no explanations.
            """)
    }

    /// Groups paragraphs split on blank lines, hard-splitting oversized ones, keeping each chunk within maxLength characters
    static func split(_ text: String, maxLength: Int) -> [String] {
        let paragraphs = text.components(separatedBy: "\n\n")
        var chunks: [String] = []
        var current = ""
        func flush() {
            let t = current.trimmingCharacters(in: .whitespacesAndNewlines)
            if !t.isEmpty { chunks.append(t) }
            current = ""
        }
        for p in paragraphs {
            if p.count > maxLength {
                flush()
                var rest = Substring(p)
                while rest.count > maxLength {
                    let cut = rest.index(rest.startIndex, offsetBy: maxLength)
                    chunks.append(String(rest[..<cut]))
                    rest = rest[cut...]
                }
                if !rest.isEmpty { chunks.append(String(rest)) }
            } else if current.count + p.count + 2 > maxLength {
                flush()
                current = p
            } else {
                current = current.isEmpty ? p : current + "\n\n" + p
            }
        }
        flush()
        return chunks.isEmpty ? [text] : chunks
    }

    // MARK: On-device Apple model

    private static func appleCorrect(chunk: String, instructions: String) async throws -> String {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            guard case .available = SystemLanguageModel.default.availability else {
                throw VoxError.message(L.t("Apple 智能当前不可用（需在系统设置中开启 Apple Intelligence）。",
                                           "Apple Intelligence is unavailable. Enable it in System Settings."))
            }
            let session = LanguageModelSession(instructions: instructions)
            let response = try await session.respond(to: chunk)
            return response.content
        }
        #endif
        throw VoxError.message(L.t("Apple 本地大模型需要 macOS 26 及以上。",
                                   "On-device Apple model requires macOS 26 or later."))
    }

    // MARK: OpenAI-compatible chat/completions

    private static func chatCorrect(chunk: String, system: String) async throws -> String {
        let provider = Providers.by(providerID)
        let base = ProviderConfig.baseURL(provider).trimmingCharacters(in: .whitespaces)
        guard !base.isEmpty,
              let url = URL(string: (base.hasSuffix("/") ? base + "chat/completions" : base + "/chat/completions")) else {
            throw VoxError.message(L.t("\(provider.displayName) 的 API 地址无效。", "Invalid API URL for \(provider.displayName)."))
        }
        guard let key = Keychain.get(account: provider.id), !key.isEmpty else {
            throw VoxError.message(L.t("\(provider.displayName) 未配置 API Key。", "\(provider.displayName) has no API key."))
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 300
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let payload: [String: Any] = [
            "model": model(for: provider.id),
            "temperature": 0.2,
            "messages": [
                ["role": "system", "content": system],
                ["role": "user", "content": chunk],
            ],
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw VoxError.message(L.t("\(provider.displayName) 无响应", "No response from \(provider.displayName)"))
        }
        guard http.statusCode == 200 else {
            var message = String(data: data, encoding: .utf8) ?? ""
            if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let err = obj["error"] as? [String: Any], let msg = err["message"] as? String {
                message = msg
            }
            throw VoxError.message("\(provider.displayName) \(http.statusCode)：\(String(message.prefix(300)))")
        }
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = obj["choices"] as? [[String: Any]],
              let msg = choices.first?["message"] as? [String: Any],
              let content = msg["content"] as? String else {
            throw VoxError.message(L.t("无法解析 AI 修正结果", "Could not parse AI correction response"))
        }
        return content
    }
}
