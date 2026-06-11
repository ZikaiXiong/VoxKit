import Foundation

// MARK: - Core types

enum VoxError: LocalizedError {
    case message(String)
    var errorDescription: String? {
        if case .message(let m) = self { return m }
        return nil
    }
}

enum TranscriptionMode: String, Codable, CaseIterable, Identifiable {
    case quick
    case meeting

    var id: String { rawValue }
    var label: String { self == .quick ? L.t("Quick Dictation", "快速听写") : L.t("Meeting", "会议记录") }
    var icon: String { self == .quick ? "bolt.fill" : "person.2.wave.2.fill" }
}

enum LanguageChoice: String, Codable, CaseIterable, Identifiable {
    case auto
    case zh
    case en
    case es
    case fr
    case ja

    var id: String { rawValue }
    var label: String {
        switch self {
        case .auto: return L.t("Auto Detect", "自动检测")
        case .zh: return "中文"
        case .en: return "English"
        case .es: return "Español"
        case .fr: return "Français"
        case .ja: return "日本語"
        }
    }
    /// `language` parameter sent to cloud APIs; omitted when auto-detecting
    var apiCode: String? { self == .auto ? nil : rawValue }
}

// MARK: - Transcript versions and sessions

struct TranscriptVersion: Codable, Identifiable, Hashable {
    var id = UUID()
    var date = Date()
    var providerID: String
    var model: String
    var language: String
    var originalText: String
    var correctedText: String?
    var chunkCount: Int = 1
    var note: String?

    /// Prefers the corrected text when available
    var displayText: String {
        if let c = correctedText, !c.isEmpty { return c }
        return originalText
    }
    var hasCorrection: Bool { (correctedText ?? "").isEmpty == false && correctedText != originalText }
}

struct Session: Codable, Identifiable, Hashable {
    var id = UUID()
    var title: String
    var date = Date()
    var mode: TranscriptionMode
    var duration: TimeInterval
    var audioFileName: String
    var language: String = "auto"
    var transcripts: [TranscriptVersion] = []
    var currentTranscriptID: UUID?

    var current: TranscriptVersion? {
        if let id = currentTranscriptID, let v = transcripts.first(where: { $0.id == id }) { return v }
        return transcripts.last
    }

    static func autoTitle(mode: TranscriptionMode, date: Date = Date()) -> String {
        "\(mode.label) \(Format.shortDate(date))"
    }
}

// MARK: - Lexicon (correction rules / hotwords)

struct CorrectionRule: Codable, Identifiable, Hashable {
    var id = UUID()
    var original: String
    var replacement: String
    var count: Int = 1
    var enabled: Bool = true
    var isManual: Bool = false
    var updated = Date()

    /// Manually added rules take effect immediately; learned rules activate after 2 occurrences
    var isActive: Bool { enabled && (isManual || count >= 2) }
}

struct LexiconData: Codable {
    var rules: [CorrectionRule] = []
    var hotwords: [String] = []
}

// MARK: - Generated speech (text-to-speech)

struct SpeechItem: Codable, Identifiable, Hashable {
    var id = UUID()
    var date = Date()
    var text: String
    var providerID: String
    var model: String
    var voice: String
    var fileName: String
    var duration: TimeInterval

    var preview: String {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.count > 80 ? String(t.prefix(80)) + "…" : t
    }
}

// MARK: - Formatting helpers

enum Format {
    static func mmss(_ t: TimeInterval) -> String {
        let s = Int(t.rounded())
        if s >= 3600 {
            return String(format: "%d:%02d:%02d", s / 3600, (s % 3600) / 60, s % 60)
        }
        return String(format: "%02d:%02d", s / 60, s % 60)
    }

    static func shortDate(_ d: Date) -> String {
        let f = DateFormatter()
        if L.zh {
            f.dateFormat = "M月d日 HH:mm"
        } else {
            f.locale = Locale(identifier: "en_US_POSIX")
            f.dateFormat = "MMM d, HH:mm"
        }
        return f.string(from: d)
    }
}
