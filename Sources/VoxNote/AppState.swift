import SwiftUI
import AVFoundation
import AppKit

enum MainPage: String, CaseIterable, Identifiable {
    case record, history, lexicon, settings
    var id: String { rawValue }
    var title: String {
        switch self {
        case .record: return L.t("听写", "Dictate")
        case .history: return L.t("历史", "History")
        case .lexicon: return L.t("词典", "Lexicon")
        case .settings: return L.t("设置", "Settings")
        }
    }
    var icon: String {
        switch self {
        case .record: return "mic.fill"
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
    @Published var uiMode: TranscriptionMode = .quick
    @Published var liveText = ""
    @Published var selectedPage: MainPage? = .record
    @Published var selectedSessionID: UUID?
    @Published var errorMessage: String?
    /// Fine-grained status text while processing ("Transcribing…" / "AI correcting…")
    @Published var processingDetail: String?

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

    var isRecording: Bool { phase == .recording || phase == .paused }

    private init() {
        let defaults = UserDefaults.standard
        let pid = defaults.string(forKey: "providerID") ?? "apple"
        providerID = Providers.all.contains(where: { $0.id == pid }) ? pid : "apple"
        model = ""
        language = LanguageChoice(rawValue: defaults.string(forKey: "language") ?? "auto") ?? .auto
        uiLangPref = defaults.string(forKey: "uiLang") ?? "system"
        micUID = defaults.string(forKey: "micUID") ?? ""
        L.apply(uiLangPref)
        live.onUpdate = { [weak self] text in
            Task { @MainActor in self?.liveText = text }
        }
        restoreModel()
    }

    var provider: Provider { Providers.by(providerID) }

    // MARK: Model selection

    func selectProvider(_ id: String) {
        providerID = id
        UserDefaults.standard.set(id, forKey: "providerID")
        restoreModel()
    }

    func selectModel(_ m: String) {
        model = m
        UserDefaults.standard.set(m, forKey: "model.\(providerID)")
    }

    private func restoreModel() {
        let models = ProviderConfig.models(provider)
        let saved = UserDefaults.standard.string(forKey: "model.\(providerID)")
        if let saved, models.contains(saved) {
            model = saved
        } else {
            model = models.first ?? ""
        }
    }

    var providerBinding: Binding<String> {
        Binding(get: { self.providerID }, set: { self.selectProvider($0) })
    }
    var modelBinding: Binding<String> {
        Binding(get: { self.model }, set: { self.selectModel($0) })
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
                errorMessage = L.t("正在进行会议录音，请先在主窗口结束。",
                                   "A meeting recording is in progress. Stop it from the main window first.")
            }
        case .processing:
            break
        }
    }

    func startRecording(_ mode: TranscriptionMode) async {
        guard phase == .idle || isDonePhase else { return }
        guard await AudioRecorder.ensurePermission() else {
            errorMessage = L.t("未获得麦克风权限：请在「系统设置 → 隐私与安全性 → 麦克风」中允许「声记」。",
                               "Microphone access denied: allow VoxNote under System Settings → Privacy & Security → Microphone.")
            return
        }
        if provider.needsKey && !Keychain.has(account: provider.id) {
            errorMessage = L.t("\(provider.displayName) 还没有配置 API Key，请到「设置」中填写，或切换到「本机识别」。",
                               "\(provider.displayName) has no API key yet. Add one in Settings, or switch to On-Device.")
            selectedPage = .settings
            return
        }

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
            errorMessage = L.t("录音启动失败：", "Failed to start recording: ") + error.localizedDescription
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

        guard let url = recorder.stop(), duration > 0.4 else {
            live.cancel()
            usingLive = false
            try? FileManager.default.removeItem(at: recorder.fileURL ?? URL(fileURLWithPath: "/dev/null"))
            finishQuickHUD(L.t("录音太短，已取消", "Too short, cancelled"), success: false)
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
                    if (UserDefaults.standard.object(forKey: "autoApplyRules") as? Bool) ?? true {
                        let (fixed, n) = Learner.applyActiveRules(store.lexicon.rules, to: trimmed)
                        if n > 0, fixed != trimmed {
                            version.correctedText = fixed
                            version.note = L.t("自动修正 \(n) 处", "Auto-fixed \(n) spots")
                        }
                    }
                    // Optional: AI grammar correction (with glossary)
                    if AICorrector.autoEnabled && AICorrector.isConfigured {
                        processingDetail = L.t("AI 修正中…", "AI correcting…")
                        if let outcome = try? await AICorrector.correct(
                            text: version.displayText, language: version.language, lexicon: store.lexicon),
                           outcome.hasChange {
                            version.correctedText = outcome.text
                            let tag = L.t("AI 修正", "AI corrected")
                            version.note = version.note.map { $0 + "；" + tag } ?? tag
                        }
                        processingDetail = nil
                    }
                    store.appendTranscript(version, to: session.id)
                    deliverQuickResult(version.displayText)
                    delivered = true
                }
            }
            usingLive = false
            if !delivered {
                // Cloud providers, or fallback to file transcription when live recognition produced nothing
                let version = await service.transcribe(session: session, provider: provider, model: model,
                                                       language: language, store: store)
                if let version {
                    deliverQuickResult(version.displayText)
                } else {
                    finishQuickHUD(L.t("转写失败，录音已保存到历史", "Failed — audio saved to History"), success: false)
                }
            }
        } else {
            usingLive = false
            phase = .idle
            selectedSessionID = session.id
            selectedPage = .history
            let p = provider, m = model, lang = language
            Task { await self.service.transcribe(session: session, provider: p, model: m, language: lang, store: self.store) }
        }
    }

    func retranscribe(session: Session, providerID: String, model: String) {
        let p = Providers.by(providerID)
        if p.needsKey && !Keychain.has(account: p.id) {
            errorMessage = L.t("\(p.displayName) 还没有配置 API Key，请到「设置」中填写。",
                               "\(p.displayName) has no API key yet. Add one in Settings.")
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
                    errorMessage = L.t("不支持的格式：\(url.lastPathComponent)（支持 wav / mp3 / m4a / aac / flac / aiff / caf）",
                                       "Unsupported format: \(url.lastPathComponent) (wav / mp3 / m4a / aac / flac / aiff / caf)")
                    continue
                }
                importingCount += 1
                defer { importingCount -= 1 }
                do {
                    let session = try await store.importAudio(from: url)
                    selectedPage = .history
                    selectedSessionID = session.id
                } catch {
                    errorMessage = L.t("导入失败：", "Import failed: ") + error.localizedDescription
                }
            }
        }
    }

    /// Manually triggers AI correction (button on the detail page)
    func aiCorrect(sessionID: UUID, transcriptID: UUID) {
        guard AICorrector.isConfigured else {
            errorMessage = L.t("AI 修正还没有配置，请到「设置 → AI 修正」选择模型。",
                               "AI correction is not configured. See Settings → AI Correction.")
            selectedPage = .settings
            return
        }
        guard service.progress[sessionID] == nil else { return }
        Task {
            guard let session = store.session(sessionID),
                  let version = session.transcripts.first(where: { $0.id == transcriptID }) else { return }
            service.progress[sessionID] = .init(done: 1, total: 1, label: L.t("AI 修正中…", "AI correcting…"))
            defer { service.progress[sessionID] = nil }
            do {
                let outcome = try await AICorrector.correct(
                    text: version.displayText, language: version.language, lexicon: store.lexicon)
                if outcome.hasChange {
                    var tag = L.t("AI 修正", "AI corrected")
                    if outcome.skippedChunks > 0 {
                        tag += L.t("（\(outcome.skippedChunks) 段跳过）", " (\(outcome.skippedChunks) chunk(s) skipped)")
                    }
                    let finalTag = tag
                    store.updateTranscript(sessionID: sessionID, transcriptID: transcriptID) {
                        $0.correctedText = outcome.text
                        $0.note = $0.note.map { n in n.contains(finalTag) ? n : n + "；" + finalTag } ?? finalTag
                    }
                } else if outcome.skippedChunks > 0 {
                    errorMessage = L.t("AI 修正结果与原文偏离过大或被安全护栏拦截，已保留原文。可重试或在设置中换一个修正模型。",
                                       "The AI output drifted too far from the original or was blocked by guardrails; the original text was kept. Retry, or switch the correction model in Settings.")
                } else {
                    errorMessage = L.t("AI 检查完毕，没有发现需要修正的地方。", "AI found nothing to fix.")
                }
            } catch {
                errorMessage = L.t("AI 修正失败：", "AI correction failed: ") + error.localizedDescription
            }
        }
    }

    // MARK: Quick Dictation wrap-up

    private func deliverQuickResult(_ text: String) {
        let final = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !final.isEmpty else {
            // Distinguish "no speech" from "no signal at all" — the latter usually means the wrong mic
            let message = recorder.peakLevel < 0.03
                ? L.t("没有收到声音，请检查「麦克风」选择", "No sound received — check the Microphone selection")
                : L.t("未识别到内容", "Nothing recognized")
            finishQuickHUD(message, success: false)
            return
        }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(final, forType: .string)
        if UserDefaults.standard.bool(forKey: "autoPaste") {
            Paster.pasteToFrontApp()
        }
        finishQuickHUD(L.t("已复制（\(final.count) 字）", "Copied (\(final.count) chars)"), success: true)
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
