import Foundation

struct Suggestion: Identifiable {
    var id: UUID { rule.id }
    let rule: CorrectionRule
    let occurrences: Int
}

/// Correction learning engine:
/// - Diffs the model output against the user's edits to extract replacement pairs (homophones like 佳明→嘉明)
/// - A pair seen ≥2 times activates automatically; later transcripts get suggestions / auto-fixes
/// - Active pairs + manual hotwords are injected as a prompt into supporting cloud models, improving recognition at the source
enum Learner {
    // MARK: Pair extraction (character-level diff)

    static func extractPairs(original: String, corrected: String) -> [(String, String)] {
        guard original != corrected else { return [] }
        let o = Array(original), c = Array(corrected)
        guard o.count <= 30_000, c.count <= 30_000 else { return [] }   // cap on diff cost

        let diff = c.difference(from: o)
        var removed = Set<Int>(), inserted = Set<Int>()
        for change in diff {
            switch change {
            case .remove(let offset, _, _): removed.insert(offset)
            case .insert(let offset, _, _): inserted.insert(offset)
            }
        }

        var pairs: [(String, String)] = []
        var i = 0, j = 0
        while i < o.count || j < c.count {
            let iRem = i < o.count && removed.contains(i)
            let jIns = j < c.count && inserted.contains(j)
            if iRem && jIns {
                var a = "", b = ""
                while i < o.count && removed.contains(i) { a.append(o[i]); i += 1 }
                while j < c.count && inserted.contains(j) { b.append(c[j]); j += 1 }
                if isMeaningfulPair(a, b) { pairs.append((a, b)) }
            } else if iRem {
                while i < o.count && removed.contains(i) { i += 1 }
            } else if jIns {
                while j < c.count && inserted.contains(j) { j += 1 }
            } else {
                i += 1; j += 1
            }
        }
        return pairs
    }

    private static func isMeaningfulPair(_ a: String, _ b: String) -> Bool {
        let ta = a.trimmingCharacters(in: .whitespacesAndNewlines)
        let tb = b.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !ta.isEmpty, !tb.isEmpty, ta != tb else { return false }
        guard ta.count <= 12, tb.count <= 12 else { return false }
        let punctuation = CharacterSet.punctuationCharacters.union(.symbols).union(.whitespacesAndNewlines)
        let aOnlyPunct = ta.unicodeScalars.allSatisfy { punctuation.contains($0) }
        let bOnlyPunct = tb.unicodeScalars.allSatisfy { punctuation.contains($0) }
        return !aOnlyPunct && !bOnlyPunct
    }

    // MARK: Suggestions and application

    static func suggestions(for text: String, rules: [CorrectionRule]) -> [Suggestion] {
        guard !text.isEmpty else { return [] }
        return rules.filter(\.isActive).compactMap { rule in
            let n = text.components(separatedBy: rule.original).count - 1
            return n > 0 ? Suggestion(rule: rule, occurrences: n) : nil
        }
        .sorted { $0.rule.count > $1.rule.count }
    }

    static func apply(_ rule: CorrectionRule, to text: String) -> String {
        text.replacingOccurrences(of: rule.original, with: rule.replacement)
    }

    /// Applies all active rules; returns (new text, total replacement count)
    static func applyActiveRules(_ rules: [CorrectionRule], to text: String) -> (String, Int) {
        var result = text
        var total = 0
        for rule in rules.filter(\.isActive) {
            let n = result.components(separatedBy: rule.original).count - 1
            if n > 0 {
                result = result.replacingOccurrences(of: rule.original, with: rule.replacement)
                total += n
            }
        }
        return (result, total)
    }

    /// Hotword prompt (injected into cloud models to bias recognition)
    static func hotwordPrompt(_ lexicon: LexiconData) -> String? {
        var words = lexicon.hotwords
        words += lexicon.rules.filter(\.isActive).sorted { $0.count > $1.count }.map(\.replacement)
        var seen = Set<String>()
        let unique = words.filter { $0.count >= 2 && seen.insert($0).inserted }.prefix(24)
        guard !unique.isEmpty else { return nil }
        return "常用词汇：" + unique.joined(separator: "、")
    }

    // MARK: Frequent-token stats (mining hotword candidates from corrected texts)

    private static let stopwords: Set<String> = [
        "所以", "我们", "你们", "他们", "这个", "那个", "就是", "然后", "一个", "什么",
        "时候", "现在", "可以", "没有", "知道", "觉得", "其实", "这样", "但是", "因为",
        "如果", "还是", "的话", "不是", "这些", "那些", "大家", "一下", "这里", "那里",
        "and", "the", "that", "this", "with", "have", "from", "they", "will",
        "what", "about", "there", "which", "would", "could", "should", "your",
    ]

    static func frequentTokens(in texts: [String], excluding existing: Set<String>) -> [(String, Int)] {
        var counts: [String: Int] = [:]
        for text in texts {
            var latin = ""
            var cjk = ""
            func flushLatin() {
                if latin.count >= 3 { counts[latin, default: 0] += 1 }
                latin = ""
            }
            func flushCJK() {
                if (2...6).contains(cjk.count) { counts[cjk, default: 0] += 1 }
                cjk = ""
            }
            for scalar in text.unicodeScalars {
                // CJK ideographs + Japanese kana count as one run category
                if (0x4E00...0x9FFF).contains(scalar.value) || (0x3040...0x30FF).contains(scalar.value) {
                    flushLatin()
                    cjk.unicodeScalars.append(scalar)
                } else if CharacterSet.alphanumerics.contains(scalar), scalar.value < 0x3000 {
                    // Latin incl. accented letters (Spanish/French)
                    flushCJK()
                    latin.unicodeScalars.append(scalar)
                } else {
                    flushLatin(); flushCJK()
                }
            }
            flushLatin(); flushCJK()
        }
        return counts
            .filter { $0.value >= 3 && !existing.contains($0.key) && !stopwords.contains($0.key.lowercased()) }
            .sorted { $0.value > $1.value }
            .prefix(30)
            .map { ($0.key, $0.value) }
    }
}
