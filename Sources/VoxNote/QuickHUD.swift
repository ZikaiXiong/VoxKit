import SwiftUI
import AppKit

/// Quick Dictation floating panel: top-center of the screen, never steals focus (the target text field keeps it)
@MainActor
final class HUDController {
    static let shared = HUDController()
    private var panel: NSPanel?

    func show() {
        if panel == nil { build() }
        position()
        panel?.orderFrontRegardless()
    }

    func hide() {
        panel?.orderOut(nil)
    }

    private func build() {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 116),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false)
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isMovableByWindowBackground = true
        panel.becomesKeyOnlyIfNeeded = true

        let host = NSHostingView(rootView: QuickHUDView().environmentObject(AppState.shared))
        host.frame = NSRect(x: 0, y: 0, width: 480, height: 116)
        panel.contentView = host
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

struct QuickHUDView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        HUDContent(state: state, recorder: state.recorder)
    }
}

private struct HUDContent: View {
    @ObservedObject var state: AppState
    @ObservedObject var recorder: AudioRecorder
    @State private var pulse = false

    var body: some View {
        HStack(spacing: 14) {
            statusIcon

            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text(titleLine)
                        .font(.callout.weight(.semibold))
                        .lineLimit(1)
                    Spacer()
                    if state.phase == .recording || state.phase == .paused {
                        Text(Format.mmss(recorder.elapsed))
                            .font(.callout.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
                subtitle
            }

            controls
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .frame(width: 464)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.regularMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(.quaternary, lineWidth: 1)
                )
        )
        .padding(8)
    }

    private var titleLine: String {
        switch state.phase {
        case .recording: return L.t("正在听写 · ", "Dictating · ") + state.provider.displayName
        case .paused: return L.t("已暂停", "Paused")
        case .processing: return state.processingDetail ?? L.t("正在转写…", "Transcribing…")
        case .done(let msg, _): return msg
        case .idle: return L.appName
        }
    }

    @ViewBuilder
    private var subtitle: some View {
        switch state.phase {
        case .recording, .paused:
            Text(state.liveText.isEmpty
                 ? L.t("请讲话…（再按 \(HotkeyPreset.current().label) 完成并复制）",
                       "Speak… (press \(HotkeyPreset.current().label) again to finish & copy)")
                 : state.liveText)
                .font(.callout)
                .foregroundStyle(state.liveText.isEmpty ? .secondary : .primary)
                .lineLimit(2)
                .truncationMode(.head)
        case .processing:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text(state.processingDetail ?? L.t("识别内容生成中…", "Recognizing…"))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        case .done(_, let success):
            Text(success
                 ? L.t("可直接 ⌘V 粘贴", "Press ⌘V to paste")
                 : L.t("可到主窗口「历史」中重试其他模型", "Retry with another model from History"))
                .font(.callout)
                .foregroundStyle(.secondary)
        case .idle:
            EmptyView()
        }
    }

    private var statusIcon: some View {
        ZStack {
            Circle()
                .fill(LinearGradient.vox)
                .frame(width: 46, height: 46)
                .scaleEffect(pulse && state.phase == .recording ? 1.08 : 1)
                .animation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true), value: pulse)
            Image(systemName: iconName)
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(.white)
        }
        .onAppear { pulse = true }
    }

    private var iconName: String {
        switch state.phase {
        case .recording: return "waveform"
        case .paused: return "pause.fill"
        case .processing: return "ellipsis"
        case .done(_, let ok): return ok ? "checkmark" : "xmark"
        case .idle: return "mic.fill"
        }
    }

    @ViewBuilder
    private var controls: some View {
        if state.phase == .recording || state.phase == .paused {
            HStack(spacing: 10) {
                Button {
                    state.cancelRecording()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .bold))
                        .frame(width: 30, height: 30)
                }
                .buttonStyle(.bordered)
                .clipShape(Circle())
                .help(L.t("取消", "Cancel"))

                Button {
                    Task { await state.stopAndFinish() }
                } label: {
                    Image(systemName: "checkmark")
                        .font(.system(size: 13, weight: .bold))
                        .frame(width: 30, height: 30)
                }
                .buttonStyle(.borderedProminent)
                .clipShape(Circle())
                .help(L.t("完成并复制", "Finish & copy"))
            }
        }
    }
}
