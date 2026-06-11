import Foundation

/// Vocabulary learning. Short wrong→right replacement pairs proved too
/// context-dependent to reapply safely, so the lexicon stores *words* instead:
/// when the user corrects a transcript, the terms they typed in are extracted
/// and promoted to hotwords. Models then fix similar-sounding mistakes in
/// context rather than via mechanical substitution.
enum Learner {
    // MARK: Vocabulary extraction from corrections

    /// Words the user introduced while editing — candidates for the lexicon.
    static func vocabularyFromCorrection(original: String, corrected: String) -> [String] {
        extractPairs(original: original, corrected: corrected)
            .map { $0.1.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter(isVocabularyWord)
    }

    /// Character-level diff (Myers via CollectionDifference) producing
    /// (removed, inserted) runs at aligned positions.
    static func extractPairs(original: String, corrected: String) -> [(String, String)] {
        guard original != corrected else { return [] }
        let o = Array(original), c = Array(corrected)
        guard o.count <= 30_000, c.count <= 30_000 else { return [] }   // diff cost cap

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
                pairs.append((a, b))
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

    /// A lexicon entry must look like a word or term, not punctuation noise
    /// or a sentence-sized rewrite.
    static func isVocabularyWord(_ text: String) -> Bool {
        guard (2...20).contains(text.count) else { return false }
        let letters = CharacterSet.letters
        guard text.unicodeScalars.contains(where: { letters.contains($0) }) else { return false }
        // Reject anything longer than a short compound term
        guard text.components(separatedBy: .whitespaces).count <= 3 else { return false }
        return true
    }

    // MARK: Hotword prompt

    /// Vocabulary list injected into transcription prompts (and AI correction)
    static func hotwordPrompt(_ lexicon: LexiconData) -> String? {
        var seen = Set<String>()
        let unique = lexicon.hotwords
            .filter { $0.count >= 2 && seen.insert($0).inserted }
            .prefix(24)
        guard !unique.isEmpty else { return nil }
        return "常用词汇：" + unique.joined(separator: "、")
    }

    // MARK: Frequent-token mining

    private static let stopwords: Set<String> = [
        "所以", "我们", "你们", "他们", "这个", "那个", "就是", "然后", "一个", "什么",
        "时候", "现在", "可以", "没有", "知道", "觉得", "其实", "这样", "但是", "因为",
        "如果", "还是", "的话", "不是", "这些", "那些", "大家", "一下", "这里", "那里",
        "and", "the", "that", "this", "with", "have", "from", "they", "will",
        "what", "about", "there", "which", "would", "could", "should", "your",
    ]

    /// Frequent words mined from transcripts — hotword candidates for the Lexicon page
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
