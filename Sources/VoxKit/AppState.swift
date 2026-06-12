import SwiftUI
import AVFoundation
import AppKit

enum MainPage: String, CaseIterable, Identifiable {
    case record, speak, history, lexicon, settings
    var id: String { rawValue }
    var title: String {
        switch self {
        case .record: return L.t("Dictate", "听写")
        case .speak: return L.t("Speak", "朗读")
        case .history: return L.t("History", "历史")
        case .lexicon: return L.t("Lexicon", "词典")
        case .settings: return L.t("Settings", "设置")
        }
    }
    var icon: String {
        switch self {
        case .record: return "mic.fill"
        case .speak: return "speaker.wave.2.fill"
        case .history: return "clock.fill"
        case .lexicon: return "character.book.closed.fill"
        case .settings: return "gearshape.fill"
        }
    }
}

@MainActor
final class AppState: ObservableObject, @unchecked Sendable {
    static let shared = AppState()

    enum Phase: Equatable {
        case idle
        case recording
        case paused
        case processing
        case done(String, Bool)   // message, success
    }

    // UI state
    @Published var phase: Phase = .idle
    @Published var activeMode: TranscriptionMode = .quick
    /// Dictation and meetings remember their own provider/model — switching the
    /// segmented mode control swaps the whole selection.
    @Published var uiMode: TranscriptionMode = .quick {
        didSet { if uiMode != oldValue { reloadSelection() } }
    }
    @Published var liveText = ""
    @Published var selectedPage: MainPage? = .record
    @Published var selectedSessionID: UUID?
    @Published var errorMessage: String?
    /// Fine-grained status text while processing ("Transcribing…" / "AI correcting…")
    @Published var processingDetail: String?

    /// Quick-dictation result currently shown in the review panel
    struct ReviewTarget {
        let sessionID: UUID
        let transcriptID: UUID
        let originalDisplay: String
    }
    @Published var reviewTarget: ReviewTarget?

    /// UI language preference: "system" / "zh" / "en"
    @Published var uiLangPref: String {
        didSet {
            UserDefaults.standard.set(uiLangPref, forKey: "uiLang")
            L.apply(uiLangPref)
        }
    }

    /// Selected microphone UID ("" = follow system default)
    @Published var micUID: String {
        didSet { UserDefaults.standard.set(micUID, forKey: "micUID") }
    }

    /// Number of files currently being imported/transcoded
    @Published var importingCount = 0

    // Model selection
    @Published private(set) var providerID: String
    @Published private(set) var model: String
    @Published var language: LanguageChoice {
        didSet { UserDefaults.standard.set(language.rawValue, forKey: "language") }
    }

    let store = Store()
    let recorder = AudioRecorder()
    let service = TranscriptionService()
    private let live = AppleLiveRecognizer()
    private var usingLive = false
    /// Provider/model captured at recording start (per-mode selection)
    private(set) var activeProvider: Provider = Providers.appleLocal
    private var activeModel = ""

    var isRecording: Bool { phase == .recording || phase == .paused }

    private init() {
        let defaults = UserDefaults.standard
        providerID = Self.storedProvider(for: .quick)
        model = ""
        language = LanguageChoice(rawValue: defaults.string(forKey: "language") ?? "auto") ?? .auto
        uiLangPref = defaults.string(forKey: "uiLang") ?? "system"
        micUID = defaults.string(forKey: "micUID") ?? ""
        L.apply(uiLangPref)
        live.onUpdate = { [weak self] text in
            Task { @MainActor in self?.liveText = text }
        }
        // Engine delivered no audio even after automatic rebuilds — surface it clearly
        recorder.onStartupFailure = { [weak self] in
            Task { @MainActor in
                guard let self, self.isRecording else { return }
                self.recorder.cancel()
                self.live.cancel()
                self.usingLive = false
                self.liveText = ""
                self.phase = .idle
                HUDController.shared.hide()
                self.errorMessage = L.t("The microphone delivered no audio (it may be busy or not ready) even after automatic retries. Press the hotkey again, or pick another mic on the Dictate page.",
                    "麦克风没有送出音频（可能被其他应用占用或设备未就绪），自动重试后仍失败。请再按一次快捷键重试，或在「听写」页换一个麦克风。")
            }
        }
        restoreModel()
    }

    var provider: Provider { Providers.by(providerID) }

    // MARK: Model selection (remembered per mode)

    /// Stored provider for a mode, with first-run smart defaults based on configured keys:
    /// meetings lean AssemblyAI (diarization), dictation leans OpenAI.
    nonisolated static func storedProvider(for mode: TranscriptionMode) -> String {
        let defaults = UserDefaults.standard
        if let v = defaults.string(forKey: "provider.\(mode.rawValue)"),
           Providers.all.contains(where: { $0.id == v }) {
            return v
        }
        if mode == .meeting, Keychain.has(account: "assemblyai") { return "assemblyai" }
        if mode == .quick, Keychain.has(account: "openai") { return "openai" }
        if let legacy = defaults.string(forKey: "providerID"),
           Providers.all.contains(where: { $0.id == legacy }) {
            return legacy
        }
        return "apple"
    }

    func provider(for mode: TranscriptionMode) -> Provider {
        Providers.by(Self.storedProvider(for: mode))
    }

    func resolvedModel(forProvider pid: String, mode: TranscriptionMode? = nil) -> String {
        let models = ProviderConfig.models(Providers.by(pid))
        let effectiveMode = mode ?? uiMode
        if let saved = UserDefaults.standard.string(forKey: "model.\(effectiveMode.rawValue).\(pid)"),
           models.contains(saved) {
            return saved
        }
        if let legacy = UserDefaults.standard.string(forKey: "model.\(pid)"), models.contains(legacy) {
            return legacy
        }
        // Meetings on OpenAI default to the diarizing model (speaker labels)
        if effectiveMode == .meeting, pid == "openai", models.contains("gpt-4o-transcribe-diarize") {
            return "gpt-4o-transcribe-diarize"
        }
        return models.first ?? ""
    }

    func selectProvider(_ id: String) {
        providerID = id
        UserDefaults.standard.set(id, forKey: "provider.\(uiMode.rawValue)")
        restoreModel()
    }

    func selectModel(_ m: String) {
        model = m
        UserDefaults.standard.set(m, forKey: "model.\(uiMode.rawValue).\(providerID)")
    }

    private func restoreModel() {
        model = resolvedModel(forProvider: providerID)
    }

    private func reloadSelection() {
        providerID = Self.storedProvider(for: uiMode)
        restoreModel()
    }

    var providerBinding: Binding<String> {
        Binding(get: { self.providerID }, set: { self.selectProvider($0) })
    }
    var modelBinding: Binding<String> {
        Binding(get: { self.model }, set: { self.selectModel($0) })
    }

    /// Per-mode bindings for the Settings page
    func providerBinding(for mode: TranscriptionMode) -> Binding<String> {
        Binding(get: { Self.storedProvider(for: mode) },
                set: { newID in
                    UserDefaults.standard.set(newID, forKey: "provider.\(mode.rawValue)")
                    if mode == self.uiMode {
                        self.providerID = newID
                        self.restoreModel()
                    }
                    self.objectWillChange.send()
                })
    }

    func modelBinding(for mode: TranscriptionMode) -> Binding<String> {
        Binding(get: {
            let pid = Self.storedProvider(for: mode)
            return self.resolvedModel(forProvider: pid, mode: mode)
        }, set: { m in
            let pid = Self.storedProvider(for: mode)
            UserDefaults.standard.set(m, forKey: "model.\(mode.rawValue).\(pid)")
            if mode == self.uiMode { self.model = m }
            self.objectWillChange.send()
        })
    }

    // MARK: Recording flow

    func toggleQuick() {
        switch phase {
        case .idle, .done:
            Task { await startRecording(.quick) }
        case .recording, .paused:
            if activeMode == .quick {
                Task { await stopAndFinish() }
            } else {
                errorMessage = L.t("A meeting recording is in progress. Stop it from the main window first.",
                                   "正在进行会议录音，请先在主窗口结束。")
            }
        case .processing:
            break
        }
    }

    func startRecording(_ mode: TranscriptionMode) async {
        guard phase == .idle || isDonePhase else { return }
        // A lingering review panel from the previous dictation closes silently
        if reviewTarget != nil { finishReview(editedText: nil) }
        guard await AudioRecorder.ensurePermission() else {
            errorMessage = L.t("Microphone access denied: allow VoxKit under System Settings → Privacy & Security → Microphone.",
                               "未获得麦克风权限：请在「系统设置 → 隐私与安全性 → 麦克风」中允许「声记」。")
            return
        }
        // Snapshot the mode's own provider/model — the picker may change mid-recording
        let provider = provider(for: mode)
        if provider.needsKey && !Keychain.has(account: provider.id) {
            errorMessage = L.t("\(provider.displayName) has no API key yet. Add one in Settings, or switch to On-Device.",
                               "\(provider.displayName) 还没有配置 API Key，请到「设置」中填写，或切换到「本机识别」。")
            selectedPage = .settings
            return
        }
        activeProvider = provider
        activeModel = resolvedModel(forProvider: provider.id, mode: mode)

        let url = store.newAudioURL()
        liveText = ""
        usingLive = false

        // On-device recognition + Quick Dictation → live streaming text
        if provider.id == "apple" && mode == .quick {
            let lang = TranscriptionService.effectiveAppleLang(language)
            let preferOnDevice = (UserDefaults.standard.object(forKey: "apple.onDevice") as? Bool) ?? true
            if await live.start(language: lang, preferOnDevice: preferOnDevice) {
                usingLive = true
                recorder.bufferHandler = { [live] buffer in live.append(buffer) }
            }
        }
        if !usingLive { recorder.bufferHandler = nil }

        do {
            // Resolve the selected microphone; fall back to system default if unplugged
            let device = AudioDeviceManager.shared.resolve(uid: micUID)
            if !micUID.isEmpty && device == nil { micUID = "" }
            try recorder.start(to: url, device: device)
        } catch {
            live.cancel()
            errorMessage = L.t("Failed to start recording: ", "录音启动失败：") + error.localizedDescription
            return
        }

        activeMode = mode
        phase = .recording
        if mode == .quick { HUDController.shared.show() }
    }

    private var isDonePhase: Bool {
        if case .done = phase { return true }
        return false
    }

    func pauseOrResume() {
        if phase == .recording {
            recorder.pause()
            phase = .paused
        } else if phase == .paused {
            recorder.resume()
            phase = .recording
        }
    }

    func cancelRecording() {
        guard isRecording else { return }
        recorder.cancel()
        live.cancel()
        usingLive = false
        liveText = ""
        phase = .idle
        HUDController.shared.hide()
    }

    func stopAndFinish() async {
        guard isRecording else { return }
        let mode = activeMode
        phase = .processing
        let duration = recorder.elapsed

        let micWasLive = recorder.isReceivingAudio
        guard let url = recorder.stop(), duration > 0.4 else {
            live.cancel()
            usingLive = false
            if let url = recorder.fileURL { try? FileManager.default.removeItem(at: url) }
            finishQuickHUD(micWasLive
                           ? L.t("Too short, cancelled", "录音太短，已取消")
                           : L.t("Mic wasn't ready yet — try again", "麦克风尚未就绪，请再试一次"),
                           success: false)
            return
        }

        let session = Session(
            title: Session.autoTitle(mode: mode),
            mode: mode, duration: duration,
            audioFileName: url.lastPathComponent,
            language: language.rawValue)
        store.add(session)

        if mode == .quick {
            var delivered = false
            if usingLive {
                let text = await live.finish()
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    var version = TranscriptVersion(
                        providerID: "apple", model: "on-device",
                        language: language.rawValue, originalText: trimmed)
                    // Optional: AI grammar correction (with glossary)
                    if AICorrector.autoEnabled && AICorrector.isConfigured {
                        processingDetail = L.t("AI correcting…", "AI 修正中…")
                        if let outcome = try? await AICorrector.correct(
                            text: version.displayText, language: version.language, lexicon: store.lexicon),
                           outcome.hasChange {
                            version.correctedText = outcome.text
                            let tag = L.t("AI corrected", "AI 修正")
                            version.note = version.note.map { $0 + " · " + tag } ?? tag
                        }
                        processingDetail = nil
                    }
                    store.appendTranscript(version, to: session.id)
                    deliverQuickResult(version.displayText, sessionID: session.id, transcriptID: version.id)
                    delivered = true
                }
            }
            usingLive = false
            if !delivered {
                // Cloud providers, or fallback to file transcription when live recognition produced nothing
                let version = await service.transcribe(session: session, provider: activeProvider, model: activeModel,
                                                       language: language, store: store)
                if let version {
                    deliverQuickResult(version.displayText, sessionID: session.id, transcriptID: version.id)
                } else {
                    finishQuickHUD(L.t("Failed — audio saved to History", "转写失败，录音已保存到历史"), success: false)
                }
            }
        } else {
            usingLive = false
            phase = .idle
            selectedSessionID = session.id
            selectedPage = .history
            let p = activeProvider, m = activeModel, lang = language
            Task { await self.service.transcribe(session: session, provider: p, model: m, language: lang, store: self.store) }
        }
    }

    func retranscribe(session: Session, providerID: String, model: String) {
        let p = Providers.by(providerID)
        if p.needsKey && !Keychain.has(account: p.id) {
            errorMessage = L.t("\(p.displayName) has no API key yet. Add one in Settings.",
                               "\(p.displayName) 还没有配置 API Key，请到「设置」中填写。")
            return
        }
        let lang = LanguageChoice(rawValue: session.language) ?? .auto
        Task { await self.service.transcribe(session: session, provider: p, model: model, language: lang, store: self.store) }
    }

    /// Imports audio files (drag & drop or open panel) — transcodes then transcribes on demand.
    func importAudioFiles(_ urls: [URL]) {
        let supported: Set<String> = ["wav", "mp3", "m4a", "aac", "flac", "aif", "aiff", "caf", "mp4"]
        Task {
            for url in urls {
                guard supported.contains(url.pathExtension.lowercased()) else {
                    errorMessage = L.t("Unsupported format: \(url.lastPathComponent) (wav / mp3 / m4a / aac / flac / aiff / caf)",
                                       "不支持的格式：\(url.lastPathComponent)（支持 wav / mp3 / m4a / aac / flac / aiff / caf）")
                    continue
                }
                importingCount += 1
                defer { importingCount -= 1 }
                do {
                    let session = try await store.importAudio(from: url)
                    selectedPage = .history
                    selectedSessionID = session.id
                } catch {
                    errorMessage = L.t("Import failed: ", "导入失败：") + error.localizedDescription
                }
            }
        }
    }

    /// Manually triggers AI correction (button on the detail page)
    func aiCorrect(sessionID: UUID, transcriptID: UUID) {
        guard AICorrector.isConfigured else {
            errorMessage = L.t("AI correction is not configured. See Settings → AI Correction.",
                               "AI 修正还没有配置，请到「设置 → AI 修正」选择模型。")
            selectedPage = .settings
            return
        }
        guard service.progress[sessionID] == nil else { return }
        Task {
            guard let session = store.session(sessionID),
                  let version = session.transcripts.first(where: { $0.id == transcriptID }) else { return }
            service.progress[sessionID] = .init(done: 1, total: 1, label: L.t("AI correcting…", "AI 修正中…"))
            defer { service.progress[sessionID] = nil }
            do {
                let outcome = try await AICorrector.correct(
                    text: version.displayText, language: version.language, lexicon: store.lexicon)
                if outcome.hasChange {
                    var tag = L.t("AI corrected", "AI 修正")
                    if outcome.skippedChunks > 0 {
                        tag += L.t(" (\(outcome.skippedChunks) chunk(s) skipped)", "（\(outcome.skippedChunks) 段跳过）")
                    }
                    let finalTag = tag
                    store.updateTranscript(sessionID: sessionID, transcriptID: transcriptID) {
                        $0.correctedText = outcome.text
                        $0.note = $0.note.map { n in n.contains(finalTag) ? n : n + " · " + finalTag } ?? finalTag
                    }
                } else if outcome.skippedChunks > 0 {
                    errorMessage = L.t("The AI output drifted too far from the original or was blocked by guardrails; the original text was kept. Retry, or switch the correction model in Settings.",
                                       "AI 修正结果与原文偏离过大或被安全护栏拦截，已保留原文。可重试或在设置中换一个修正模型。")
                } else {
                    errorMessage = L.t("AI found nothing to fix.", "AI 检查完毕，没有发现需要修正的地方。")
                }
            } catch {
                errorMessage = L.t("AI correction failed: ", "AI 修正失败：") + error.localizedDescription
            }
        }
    }

    // MARK: Quick Dictation wrap-up

    private func deliverQuickResult(_ text: String, sessionID: UUID? = nil, transcriptID: UUID? = nil) {
        let final = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !final.isEmpty else {
            // Distinguish "no speech" from "no signal at all" — the latter usually means the wrong mic
            let message = recorder.peakLevel < 0.12
                ? L.t("No sound received — check the Microphone selection", "没有收到声音，请检查「麦克风」选择")
                : L.t("Nothing recognized", "未识别到内容")
            finishQuickHUD(message, success: false)
            return
        }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(final, forType: .string)
        if UserDefaults.standard.bool(forKey: "autoPaste") {
            Paster.pasteToFrontApp()
        }

        // Optional review panel: the text is already copied; the panel offers a
        // chance to fix it (re-copied + lexicon learns) without leaving the flow.
        let reviewEnabled = (UserDefaults.standard.object(forKey: "quickReview") as? Bool) ?? true
        if reviewEnabled, let sessionID, let transcriptID {
            phase = .idle
            HUDController.shared.hide()
            reviewTarget = ReviewTarget(sessionID: sessionID, transcriptID: transcriptID, originalDisplay: final)
            ReviewPanelController.shared.show()
        } else {
            finishQuickHUD(L.t("Copied (\(final.count) chars)", "已复制（\(final.count) 字）"), success: true)
        }
    }

    /// Closes the review panel; a non-nil `editedText` means the user changed the
    /// text — re-copy it, store it as the corrected version, and learn the fixes.
    func finishReview(editedText: String?) {
        defer {
            reviewTarget = nil
            ReviewPanelController.shared.hide()
        }
        guard let target = reviewTarget,
              let edited = editedText?.trimmingCharacters(in: .whitespacesAndNewlines),
              !edited.isEmpty, edited != target.originalDisplay else { return }

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(edited, forType: .string)

        store.updateTranscript(sessionID: target.sessionID, transcriptID: target.transcriptID) {
            $0.correctedText = edited
        }
        if let session = store.session(target.sessionID),
           let version = session.transcripts.first(where: { $0.id == target.transcriptID }) {
            store.learn(original: version.originalText, corrected: edited)
        }
    }

    private func finishQuickHUD(_ message: String, success: Bool) {
        liveText = ""
        phase = .done(message, success)
        Task {
            try? await Task.sleep(nanoseconds: 1_700_000_000)
            if case .done = self.phase {
                self.phase = .idle
                HUDController.shared.hide()
            }
        }
    }
}
