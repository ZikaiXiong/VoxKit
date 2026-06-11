import SwiftUI
import AppKit
import AVFoundation

struct SessionDetailView: View {
    let session: Session
    @EnvironmentObject var state: AppState

    var body: some View {
        DetailContent(session: session, state: state, store: state.store, service: state.service)
    }
}

private struct DetailContent: View {
    let session: Session
    @ObservedObject var state: AppState
    @ObservedObject var store: Store
    @ObservedObject var service: TranscriptionService

    @State private var tab: Tab = .corrected
    @State private var toast: String?

    enum Tab: Hashable { case original, corrected }

    /// Always reads the latest data from the store; the session param only locates it
    private var live: Session { store.session(session.id) ?? session }
    private var version: TranscriptVersion? { live.current }
    private var inProgress: TranscriptionService.Progress? { service.progress[session.id] }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            PlayerBar(url: store.audioURL(for: live))

            if let version {
                versionBar(version)
                suggestionBar(version)
                textTabs(version)
                footer(version)
            } else if let progress = inProgress {
                Spacer()
                VStack(spacing: 10) {
                    ProgressView()
                    Text(progress.label ?? (progress.total > 1
                         ? L.t("Transcribing chunk \(min(progress.done + 1, progress.total))/\(progress.total)…",
                               "正在转写 第 \(min(progress.done + 1, progress.total))/\(progress.total) 段…")
                         : L.t("Transcribing…", "正在转写…")))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                Spacer()
            } else {
                Spacer()
                VStack(spacing: 12) {
                    Text(L.t("This recording has no transcript yet", "这条录音还没有转写结果"))
                        .foregroundStyle(.secondary)
                    retranscribeMenu(label: L.t("Transcribe with…", "选择模型转写"))
                }
                .frame(maxWidth: .infinity)
                Spacer()
            }
        }
        .padding(18)
        .overlay(alignment: .bottom) {
            if let toast {
                Text(toast)
                    .font(.callout.weight(.medium))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Capsule().fill(.regularMaterial))
                    .padding(.bottom, 14)
                    .transition(.opacity)
            }
        }
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                TextField(L.t("Title", "标题"), text: store.titleBinding(for: session.id))
                    .textFieldStyle(.plain)
                    .font(.title2.weight(.semibold))
                Spacer()
                Button(role: .destructive) {
                    store.delete(live)
                    state.selectedSessionID = nil
                } label: {
                    Image(systemName: "trash")
                }
                .help(L.t("Delete this recording and all transcripts", "删除此录音及全部转写"))
            }
            HStack(spacing: 8) {
                TagChip(text: live.mode.label, color: live.mode == .quick ? .blue : .purple)
                Text(L.t("\(Format.shortDate(live.date)) · \(Format.mmss(live.duration)) · \(live.transcripts.count) transcript version(s)",
                         "\(Format.shortDate(live.date)) · 时长 \(Format.mmss(live.duration)) · \(live.transcripts.count) 个转写版本"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: Versions & re-transcription

    private func versionBar(_ version: TranscriptVersion) -> some View {
        HStack(spacing: 10) {
            Picker(L.t("Version", "版本"), selection: Binding(
                get: { version.id },
                set: { store.setCurrentTranscript(sessionID: session.id, transcriptID: $0) }
            )) {
                ForEach(live.transcripts) { v in
                    Text("\(Providers.by(v.providerID).displayName) · \(v.model == "on-device" ? L.t("on-device", "本机") : v.model)")
                        .tag(v.id)
                }
            }
            .fixedSize()

            if version.chunkCount > 1 {
                TagChip(text: L.t("Auto-split: \(version.chunkCount) chunks", "自动分了 \(version.chunkCount) 段"), color: .indigo)
            }
            if let note = version.note {
                TagChip(text: note, color: note.contains(L.t("failed", "失败")) ? .orange : .teal)
            }

            Spacer()

            if let progress = inProgress {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text(progress.label ?? (progress.total > 1
                         ? "\(progress.done)/\(progress.total)"
                         : L.t("Working…", "转写中")))
                        .font(.caption).foregroundStyle(.secondary)
                }
            } else {
                aiCorrectButton(version)
                retranscribeMenu(label: L.t("Redo", "重转"))
            }
        }
    }

    private func aiCorrectButton(_ version: TranscriptVersion) -> some View {
        Button {
            state.aiCorrect(sessionID: session.id, transcriptID: version.id)
        } label: {
            Label(L.t("AI Fix", "AI 修正"), systemImage: "wand.and.stars")
        }
        .help(AICorrector.isConfigured
              ? L.t("Proofread with \(AICorrector.configuredLabel) using your glossary", "用 \(AICorrector.configuredLabel) 带词库整体校对")
              : L.t("Configure under Settings → AI Correction first", "先到「设置 → AI 修正」选择模型"))
    }

    @ViewBuilder
    private func retranscribeMenu(label: String) -> some View {
        Menu {
            ForEach(Providers.all) { p in
                if p.id == "apple" {
                    Button(p.displayName) {
                        state.retranscribe(session: live, providerID: p.id, model: "on-device")
                    }
                } else {
                    let models = ProviderConfig.models(p)
                    if !models.isEmpty {
                        Menu(p.displayName) {
                            ForEach(models, id: \.self) { m in
                                Button(m) { state.retranscribe(session: live, providerID: p.id, model: m) }
                            }
                        }
                    }
                }
            }
        } label: {
            Label(label, systemImage: "arrow.triangle.2.circlepath")
        }
        .fixedSize()
        .help(L.t("Re-transcribe with another model (the audio is never lost)", "用其他模型重新转写（原录音永不丢失）"))
    }

    // MARK: Correction suggestions

    @ViewBuilder
    private func suggestionBar(_ version: TranscriptVersion) -> some View {
        let text = version.correctedText ?? version.originalText
        let suggestions = Learner.suggestions(for: text, rules: store.lexicon.rules)
        if !suggestions.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    Image(systemName: "wand.and.stars")
                        .foregroundStyle(.indigo)
                    ForEach(suggestions.prefix(8)) { s in
                        Button {
                            applyRule(s.rule, to: version)
                        } label: {
                            HStack(spacing: 4) {
                                Text(s.rule.original).strikethrough().foregroundStyle(.secondary)
                                Image(systemName: "arrow.right").font(.caption2)
                                Text(s.rule.replacement).foregroundStyle(.primary)
                                Text("×\(s.occurrences)").font(.caption2).foregroundStyle(.tertiary)
                            }
                            .font(.callout)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 4)
                            .background(Capsule().fill(Color.indigo.opacity(0.1)))
                        }
                        .buttonStyle(.plain)
                        .help(L.t("Replace all \(s.occurrences) occurrence(s)", "点击替换全部 \(s.occurrences) 处"))
                    }
                    if suggestions.count > 1 {
                        Button(L.t("Apply All", "全部应用")) {
                            var t = version.correctedText ?? version.originalText
                            for s in suggestions { t = Learner.apply(s.rule, to: t) }
                            store.updateTranscript(sessionID: session.id, transcriptID: version.id) { $0.correctedText = t }
                            tab = .corrected
                            showToast(L.t("Applied \(suggestions.count) corrections", "已应用 \(suggestions.count) 条修正"))
                        }
                        .controlSize(.small)
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    private func applyRule(_ rule: CorrectionRule, to version: TranscriptVersion) {
        let base = version.correctedText ?? version.originalText
        let applied = Learner.apply(rule, to: base)
        store.updateTranscript(sessionID: session.id, transcriptID: version.id) { $0.correctedText = applied }
        tab = .corrected
        showToast(L.t("Replaced “\(rule.original) → \(rule.replacement)”", "已替换「\(rule.original) → \(rule.replacement)」"))
    }

    // MARK: Text area

    private func textTabs(_ version: TranscriptVersion) -> some View {
        VStack(spacing: 8) {
            HStack {
                Picker("", selection: $tab) {
                    Text(L.t("Corrected", "修正稿")).tag(Tab.corrected)
                    Text(L.t("Original", "模型原文")).tag(Tab.original)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 210)

                if version.hasCorrection {
                    TagChip(text: L.t("Differs from original", "与原文不同"), color: .green)
                }
                Spacer()
            }

            Group {
                if tab == .original {
                    ScrollView {
                        Text(version.originalText.isEmpty ? L.t("(empty)", "（空）") : version.originalText)
                            .textSelection(.enabled)
                            .font(.system(size: 14))
                            .lineSpacing(5)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12)
                    }
                } else {
                    TextEditor(text: store.correctedBinding(sessionID: session.id, transcriptID: version.id))
                        .font(.system(size: 14))
                        .lineSpacing(5)
                        .scrollContentBackground(.hidden)
                        .padding(6)
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color(nsColor: .textBackgroundColor))
                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(.quaternary, lineWidth: 1))
            )
            .frame(maxHeight: .infinity)
        }
        .frame(maxHeight: .infinity)
    }

    // MARK: Footer actions

    private func footer(_ version: TranscriptVersion) -> some View {
        HStack(spacing: 10) {
            Button {
                let text = tab == .original ? version.originalText : (version.correctedText ?? version.originalText)
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(text, forType: .string)
                showToast(L.t("Copied", "已复制"))
            } label: {
                Label(L.t("Copy", "复制"), systemImage: "doc.on.doc")
            }

            Button {
                exportText(version)
            } label: {
                Label(L.t("Export .txt", "导出 .txt"), systemImage: "square.and.arrow.up")
            }

            Spacer()

            Button {
                let corrected = version.correctedText ?? version.originalText
                let learned = store.learn(original: version.originalText, corrected: corrected)
                showToast(learned > 0
                          ? L.t("Saved — learned \(learned) correction pair(s)", "已保存，学到 \(learned) 个修正词对")
                          : L.t("Corrected text saved", "已保存修正稿"))
            } label: {
                Label(L.t("Save & Learn", "保存修正并学习"), systemImage: "brain.head.profile")
            }
            .buttonStyle(.borderedProminent)
            .disabled(!version.hasCorrection)
            .help(L.t("Diffs against the original to learn your fixes for next time", "对比原文提取你改过的词，下次自动提示/修正"))
        }
    }

    private func exportText(_ version: TranscriptVersion) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = live.title + ".txt"
        panel.allowedContentTypes = [.plainText]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        var content = "# \(live.title)\n\(Format.shortDate(live.date)) · \(Format.mmss(live.duration)) · \(Providers.by(version.providerID).displayName) \(version.model)\n\n"
        content += version.displayText
        try? content.write(to: url, atomically: true, encoding: .utf8)
        showToast(L.t("Exported", "已导出"))
    }

    private func showToast(_ text: String) {
        withAnimation { toast = text }
        Task {
            try? await Task.sleep(nanoseconds: 1_800_000_000)
            withAnimation { toast = nil }
        }
    }
}

// MARK: - Audio player bar

struct PlayerBar: View {
    let url: URL
    @StateObject private var controller = PlayerController()

    var body: some View {
        Card {
            HStack(spacing: 12) {
                Button {
                    controller.toggle()
                } label: {
                    Image(systemName: controller.playing ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(LinearGradient.vox)
                }
                .buttonStyle(.plain)
                .disabled(!controller.ready)

                Text(Format.mmss(controller.position))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)

                Slider(value: Binding(
                    get: { controller.position },
                    set: { controller.seek(to: $0) }
                ), in: 0...max(1, controller.duration))
                .controlSize(.small)
                .disabled(!controller.ready)

                Text(Format.mmss(controller.duration))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .onAppear { controller.load(url: url) }
        .onDisappear { controller.unload() }
    }
}

@MainActor
final class PlayerController: NSObject, ObservableObject, AVAudioPlayerDelegate {
    @Published var playing = false
    @Published var position: Double = 0
    @Published var duration: Double = 0
    @Published var ready = false

    private var player: AVAudioPlayer?
    private var timer: Timer?

    func load(url: URL) {
        unload()
        guard let p = try? AVAudioPlayer(contentsOf: url) else { return }
        p.delegate = self
        p.prepareToPlay()
        player = p
        duration = p.duration
        ready = true
    }

    func toggle() {
        guard let player else { return }
        if player.isPlaying {
            player.pause()
            playing = false
            stopTimer()
        } else {
            player.play()
            playing = true
            startTimer()
        }
    }

    func seek(to t: Double) {
        player?.currentTime = t
        position = t
    }

    func unload() {
        stopTimer()
        player?.stop()
        player = nil
        playing = false
        position = 0
        duration = 0
        ready = false
    }

    private func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, let p = self.player else { return }
                self.position = p.currentTime
            }
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            self.playing = false
            self.position = 0
            self.stopTimer()
        }
    }
}
