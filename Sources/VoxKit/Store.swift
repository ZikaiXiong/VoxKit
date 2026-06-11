import Foundation
import SwiftUI
import AVFoundation

/// Data hub: session history + lexicon, persisted as JSON under ~/Library/Application Support/VoxKit
@MainActor
final class Store: ObservableObject {
    @Published private(set) var sessions: [Session] = []
    @Published private(set) var speechItems: [SpeechItem] = []
    @Published var lexicon = LexiconData()

    let rootDir: URL
    let audioDir: URL
    let speechDir: URL
    private var saveTask: Task<Void, Never>?

    init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        rootDir = base.appendingPathComponent("VoxKit", isDirectory: true)
        audioDir = rootDir.appendingPathComponent("Audio", isDirectory: true)
        speechDir = rootDir.appendingPathComponent("Speech", isDirectory: true)
        try? FileManager.default.createDirectory(at: audioDir, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: speechDir, withIntermediateDirectories: true)
        load()
    }

    private var sessionsFile: URL { rootDir.appendingPathComponent("sessions.json") }
    private var lexiconFile: URL { rootDir.appendingPathComponent("lexicon.json") }
    private var speechFile: URL { rootDir.appendingPathComponent("speech.json") }

    private func load() {
        if let data = try? Data(contentsOf: sessionsFile),
           let decoded = try? JSONDecoder().decode([Session].self, from: data) {
            sessions = decoded
        }
        if let data = try? Data(contentsOf: lexiconFile),
           let decoded = try? JSONDecoder().decode(LexiconData.self, from: data) {
            lexicon = decoded
        }
        if let data = try? Data(contentsOf: speechFile),
           let decoded = try? JSONDecoder().decode([SpeechItem].self, from: data) {
            speechItems = decoded
        }
    }

    func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 600_000_000)
            guard !Task.isCancelled else { return }
            self?.saveNow()
        }
    }

    func saveNow() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(sessions) { try? data.write(to: sessionsFile, options: .atomic) }
        if let data = try? encoder.encode(lexicon) { try? data.write(to: lexiconFile, options: .atomic) }
        if let data = try? encoder.encode(speechItems) { try? data.write(to: speechFile, options: .atomic) }
    }

    // MARK: Generated speech

    func speechURL(for item: SpeechItem) -> URL {
        speechDir.appendingPathComponent(item.fileName)
    }

    func addSpeech(_ item: SpeechItem) {
        speechItems.insert(item, at: 0)
        scheduleSave()
    }

    func deleteSpeech(_ item: SpeechItem) {
        try? FileManager.default.removeItem(at: speechURL(for: item))
        speechItems.removeAll { $0.id == item.id }
        scheduleSave()
    }

    // MARK: Audio files

    func newAudioURL(ext: String = "wav") -> URL {
        audioDir.appendingPathComponent("\(UUID().uuidString).\(ext)")
    }

    func audioURL(for session: Session) -> URL {
        audioDir.appendingPathComponent(session.audioFileName)
    }

    // MARK: Session operations

    func session(_ id: UUID?) -> Session? {
        guard let id else { return nil }
        return sessions.first { $0.id == id }
    }

    func add(_ session: Session) {
        sessions.insert(session, at: 0)
        scheduleSave()
    }

    func update(_ session: Session) {
        guard let i = sessions.firstIndex(where: { $0.id == session.id }) else { return }
        sessions[i] = session
        scheduleSave()
    }

    func delete(_ session: Session) {
        try? FileManager.default.removeItem(at: audioURL(for: session))
        sessions.removeAll { $0.id == session.id }
        scheduleSave()
    }

    func appendTranscript(_ version: TranscriptVersion, to sessionID: UUID) {
        guard let i = sessions.firstIndex(where: { $0.id == sessionID }) else { return }
        sessions[i].transcripts.append(version)
        sessions[i].currentTranscriptID = version.id
        scheduleSave()
    }

    func updateTranscript(sessionID: UUID, transcriptID: UUID, mutate: (inout TranscriptVersion) -> Void) {
        guard let i = sessions.firstIndex(where: { $0.id == sessionID }),
              let j = sessions[i].transcripts.firstIndex(where: { $0.id == transcriptID }) else { return }
        mutate(&sessions[i].transcripts[j])
        scheduleSave()
    }

    func setCurrentTranscript(sessionID: UUID, transcriptID: UUID) {
        guard let i = sessions.firstIndex(where: { $0.id == sessionID }) else { return }
        sessions[i].currentTranscriptID = transcriptID
        scheduleSave()
    }

    func titleBinding(for sessionID: UUID) -> Binding<String> {
        Binding(
            get: { [weak self] in self?.session(sessionID)?.title ?? "" },
            set: { [weak self] newValue in
                guard let self, let i = self.sessions.firstIndex(where: { $0.id == sessionID }) else { return }
                self.sessions[i].title = newValue
                self.scheduleSave()
            })
    }

    func correctedBinding(sessionID: UUID, transcriptID: UUID) -> Binding<String> {
        Binding(
            get: { [weak self] in
                guard let s = self?.session(sessionID),
                      let v = s.transcripts.first(where: { $0.id == transcriptID }) else { return "" }
                return v.correctedText ?? v.originalText
            },
            set: { [weak self] newValue in
                self?.updateTranscript(sessionID: sessionID, transcriptID: transcriptID) { $0.correctedText = newValue }
            })
    }

    /// Imports an external audio file: transcodes it to the library's standard
    /// 16kHz WAV off the main thread, then creates a session for it.
    func importAudio(from url: URL) async throws -> Session {
        let dest = newAudioURL()
        do {
            let duration = try await Task.detached(priority: .userInitiated) {
                try AudioChunker.transcodeToStandardWAV(from: url, to: dest)
            }.value
            let session = Session(
                title: url.deletingPathExtension().lastPathComponent,
                mode: .meeting, duration: duration,
                audioFileName: dest.lastPathComponent)
            add(session)
            return session
        } catch {
            try? FileManager.default.removeItem(at: dest)
            throw error
        }
    }

    // MARK: Lexicon operations

    /// Learns from one correction; returns the number of pairs extracted
    @discardableResult
    func learn(original: String, corrected: String) -> Int {
        let pairs = Learner.extractPairs(original: original, corrected: corrected)
        guard !pairs.isEmpty else { return 0 }
        for (a, b) in pairs {
            if let i = lexicon.rules.firstIndex(where: { $0.original == a && $0.replacement == b }) {
                lexicon.rules[i].count += 1
                lexicon.rules[i].updated = Date()
            } else {
                lexicon.rules.append(CorrectionRule(original: a, replacement: b))
            }
        }
        lexicon.rules.sort { $0.count > $1.count }
        scheduleSave()
        return pairs.count
    }

    func addManualRule(original: String, replacement: String) {
        let a = original.trimmingCharacters(in: .whitespaces)
        let b = replacement.trimmingCharacters(in: .whitespaces)
        guard !a.isEmpty, !b.isEmpty, a != b else { return }
        if let i = lexicon.rules.firstIndex(where: { $0.original == a && $0.replacement == b }) {
            lexicon.rules[i].isManual = true
            lexicon.rules[i].enabled = true
        } else {
            lexicon.rules.insert(CorrectionRule(original: a, replacement: b, isManual: true), at: 0)
        }
        scheduleSave()
    }

    func deleteRule(_ rule: CorrectionRule) {
        lexicon.rules.removeAll { $0.id == rule.id }
        scheduleSave()
    }

    func toggleRule(_ rule: CorrectionRule) {
        guard let i = lexicon.rules.firstIndex(where: { $0.id == rule.id }) else { return }
        lexicon.rules[i].enabled.toggle()
        scheduleSave()
    }

    func addHotword(_ word: String) {
        let w = word.trimmingCharacters(in: .whitespaces)
        guard !w.isEmpty, !lexicon.hotwords.contains(w) else { return }
        lexicon.hotwords.append(w)
        scheduleSave()
    }

    func removeHotword(_ word: String) {
        lexicon.hotwords.removeAll { $0 == word }
        scheduleSave()
    }

    /// Frequent-token candidates from all transcripts (corrected or original)
    func frequentTokenCandidates() -> [(String, Int)] {
        let texts = sessions.flatMap { $0.transcripts.map(\.displayText) }
        let existing = Set(lexicon.hotwords)
        return Learner.frequentTokens(in: texts, excluding: existing)
    }
}
