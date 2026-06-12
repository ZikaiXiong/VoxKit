import SwiftUI
import AppKit

/// Post-dictation review: the text is already on the clipboard, but this floating
/// editor gives you a chance to fix it before pasting — edits are re-copied and
/// fed to the lexicon learner. It never steals focus from the app you're typing in
/// until you click into it.
@MainActor
final class ReviewPanelController {
    static let shared = ReviewPanelController()
    private var panel: NSPanel?

    private final class KeyablePanel: NSPanel {
        override var canBecomeKey: Bool { true }
    }

    func show() {
        if panel == nil { build() }
        guard let panel else { return }
        // Restore the size the user last resized to
        let defaults = UserDefaults.standard
        let width = defaults.double(forKey: "review.width")
        let height = defaults.double(forKey: "review.height")
        panel.setContentSize(NSSize(width: width > 0 ? width : 560, height: height > 0 ? height : 250))
        // Rebuild the content so each dictation starts with fresh editor state
        let host = NSHostingView(rootView: ReviewView().environmentObject(AppState.shared))
        host.frame = panel.contentLayoutRect
        host.autoresizingMask = [.width, .height]
        panel.contentView = host
        position()
        panel.orderFrontRegardless()
    }

    func hide() {
        panel?.orderOut(nil)
        panel?.contentView = NSView()   // release the hosting view and its timer
    }

    private func build() {
        // A titled-but-chromeless panel: .borderless windows never get the system's
        // edge-resize behavior, so use a real titled window and hide all its chrome.
        let panel = KeyablePanel(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 250),
            styleMask: [.titled, .fullSizeContentView, .nonactivatingPanel, .resizable],
            backing: .buffered, defer: false)
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        panel.contentMinSize = NSSize(width: 460, height: 210)
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isMovableByWindowBackground = true
        panel.becomesKeyOnlyIfNeeded = true
        self.panel = panel

        // Remember the user's size for the next dictation
        NotificationCenter.default.addObserver(
            forName: NSWindow.didEndLiveResizeNotification, object: panel, queue: .main
        ) { note in
            guard let window = note.object as? NSWindow else { return }
            MainActor.assumeIsolated {
                UserDefaults.standard.set(Double(window.frame.width), forKey: "review.width")
                UserDefaults.standard.set(Double(window.frame.height), forKey: "review.height")
            }
        }
    }

    private func position() {
        guard let panel, let screen = NSScreen.main else { return }
        let frame = screen.visibleFrame
        let x = frame.midX - panel.frame.width / 2
        let y = frame.maxY - panel.frame.height - 24
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }
}

struct ReviewView: View {
    @EnvironmentObject var state: AppState
    @State private var editedText = ""
    @State private var countdown: Int? = 12
    @State private var didSeedText = false
    @State private var aiRunning = false
    @State private var aiStatus: String?
    private let tick = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private var original: String { state.reviewTarget?.originalDisplay ?? "" }
    private var edited: Bool { editedText != original }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                Text(L.t("Copied — want to touch it up?", "已复制 — 需要修改吗？"))
                    .font(.callout.weight(.semibold))
                Spacer()
                Text(L.t("\(editedText.count) chars", "\(editedText.count) 字"))
                    .font(.caption2).foregroundStyle(.tertiary)
            }

            TextEditor(text: $editedText)
                .font(.system(size: 13.5))
                .lineSpacing(3)
                .scrollContentBackground(.hidden)
                .padding(6)
                .frame(minHeight: 90, maxHeight: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(Color(nsColor: .textBackgroundColor))
                        .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .strokeBorder(.quaternary, lineWidth: 1))
                )
                .onChange(of: editedText) { _ in
                    if didSeedText { countdown = nil } else { didSeedText = true }
                }

            HStack(spacing: 10) {
                aiFixButton

                Text(aiStatus ?? (edited
                     ? L.t("Edits are re-copied and taught to the lexicon", "修改会重新复制，并让词典学习你的改法")
                     : L.t("You can already ⌘V into your target app", "可直接去目标输入框 ⌘V 粘贴")))
                    .font(.caption)
                    .foregroundStyle(aiStatus == nil ? .tertiary : .secondary)
                    .lineLimit(1)
                Spacer()
                Button(L.t("Dismiss", "放弃")) {
                    state.finishReview(editedText: nil)
                }
                .keyboardShortcut(.cancelAction)

                Button {
                    state.finishReview(editedText: edited ? editedText : nil)
                } label: {
                    Text(buttonTitle).fontWeight(.medium)
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.return, modifiers: .command)
            }
        }
        .padding(16)
        .frame(minWidth: 444, maxWidth: .infinity, minHeight: 194, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.regularMaterial)
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(.quaternary, lineWidth: 1))
        )
        .padding(8)
        .onAppear { editedText = original }
        .onHover { hovering in if hovering { countdown = nil } }
        .onReceive(tick) { _ in
            guard let c = countdown else { return }
            if c <= 1 {
                countdown = nil
                state.finishReview(editedText: nil)
            } else {
                countdown = c - 1
            }
        }
    }

    private var buttonTitle: String {
        let base = edited
            ? L.t("Copy edits & learn", "复制修改并学习")
            : L.t("Done", "完成")
        if let c = countdown, !edited {
            return base + " (\(c))"
        }
        return base
    }

    /// One-click AI proofread of the current text, using the user's lexicon
    private var aiFixButton: some View {
        Button {
            runAIFix()
        } label: {
            HStack(spacing: 4) {
                if aiRunning {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "wand.and.stars")
                }
                Text(L.t("Clean Up", "清理润色"))
            }
        }
        .disabled(aiRunning || editedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        .keyboardShortcut("j", modifiers: .command)
        .help(AICorrector.isConfigured
              ? L.t("Proofread with \(AICorrector.configuredLabel) using your lexicon (⌘J)",
                    "用 \(AICorrector.configuredLabel) 修正，会参考你的词库（⌘J）")
              : L.t("Set up under Settings → AI Correction first", "先到「设置 → AI 修正」选择模型"))
    }

    private func runAIFix() {
        countdown = nil
        guard AICorrector.isConfigured else {
            aiStatus = L.t("Not configured — see Settings → AI Correction", "未配置 — 见 设置 → AI 修正")
            return
        }
        aiRunning = true
        aiStatus = nil
        let text = editedText
        let language = state.reviewTarget.flatMap { state.store.session($0.sessionID)?.language } ?? "auto"
        Task {
            defer { aiRunning = false }
            do {
                let outcome = try await AICorrector.correct(text: text, language: language, lexicon: state.store.lexicon)
                if outcome.hasChange {
                    editedText = outcome.text
                    aiStatus = nil
                } else if outcome.skippedChunks > 0 {
                    aiStatus = L.t("AI output drifted too far — kept your text", "AI 结果偏离过大，已保留原文")
                } else {
                    aiStatus = L.t("Nothing to fix", "没有需要修正的地方")
                }
            } catch {
                aiStatus = error.localizedDescription
            }
        }
    }
}
