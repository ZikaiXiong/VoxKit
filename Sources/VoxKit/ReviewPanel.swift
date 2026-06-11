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
        // Rebuild the content so each dictation starts with fresh editor state
        let host = NSHostingView(rootView: ReviewView().environmentObject(AppState.shared))
        host.frame = NSRect(x: 0, y: 0, width: 540, height: 240)
        panel?.contentView = host
        position()
        panel?.orderFrontRegardless()
    }

    func hide() {
        panel?.orderOut(nil)
    }

    private func build() {
        let panel = KeyablePanel(
            contentRect: NSRect(x: 0, y: 0, width: 540, height: 240),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false)
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isMovableByWindowBackground = true
        panel.becomesKeyOnlyIfNeeded = true
        self.panel = panel
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
                .frame(height: 110)
                .background(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(Color(nsColor: .textBackgroundColor))
                        .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .strokeBorder(.quaternary, lineWidth: 1))
                )
                .onChange(of: editedText) { _ in countdown = nil }

            HStack {
                Text(edited
                     ? L.t("Edits are re-copied and taught to the lexicon", "修改会重新复制，并让词典学习你的改法")
                     : L.t("You can already ⌘V into your target app", "可直接去目标输入框 ⌘V 粘贴"))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
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
        .frame(width: 524)
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
}
