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

    var body: some View {
        HStack(spacing: 14) {
            statusIcon

            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text(titleLine)
                        .font(.callout.weight(.semibold))
                        .lineLimit(1)
                    Spacer()
                    if state.phase == .recording {
                        // Live mic level — instantly shows whether sound is being picked up
                        LevelMeter(level: recorder.level, barCount: 9, barWidth: 2.5,
                                   spacing: 2, maxBarHeight: 12, minBarHeight: 2.5)
                    }
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
        case .recording: return L.t("Dictating · ", "正在听写 · ") + state.activeProvider.displayName
        case .paused: return L.t("Paused", "已暂停")
        case .processing: return state.processingDetail ?? L.t("Transcribing…", "正在转写…")
        case .done(let msg, _): return msg
        case .idle: return L.appName
        }
    }

    @ViewBuilder
    private var subtitle: some View {
        switch state.phase {
        case .recording, .paused:
            Text(!recorder.isReceivingAudio && state.phase == .recording
                 ? L.t("Starting the microphone…", "正在启动麦克风…")
                 : (state.liveText.isEmpty
                    ? L.t("Speak… (press \(HotkeyPreset.current().label) again to finish & copy)",
                          "请讲话…（再按 \(HotkeyPreset.current().label) 完成并复制）")
                    : state.liveText))
                .font(.callout)
                .foregroundStyle(state.liveText.isEmpty ? .secondary : .primary)
                .lineLimit(2)
                .truncationMode(.head)
        case .processing:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text(state.processingDetail ?? L.t("Recognizing…", "识别内容生成中…"))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        case .done(_, let success):
            Text(success
                 ? L.t("Press ⌘V to paste", "可直接 ⌘V 粘贴")
                 : L.t("Retry with another model from History", "可到主窗口「历史」中重试其他模型"))
                .font(.callout)
                .foregroundStyle(.secondary)
        case .idle:
            EmptyView()
        }
    }

    private var statusIcon: some View {
        ZStack {
            // Outer ring breathes with the mic level while recording
            Circle()
                .stroke(LinearGradient.vox, lineWidth: 2)
                .frame(width: 46, height: 46)
                .scaleEffect(state.phase == .recording ? 1 + CGFloat(min(recorder.level, 1)) * 0.45 : 1)
                .opacity(state.phase == .recording ? Double(0.7 - min(recorder.level, 1) * 0.5) : 0)
                .animation(.easeOut(duration: 0.12), value: recorder.level)
            Circle()
                .fill(LinearGradient.vox)
                .frame(width: 46, height: 46)
                .scaleEffect(state.phase == .recording ? 1 + CGFloat(min(recorder.level, 1)) * 0.18 : 1)
                .animation(.easeOut(duration: 0.1), value: recorder.level)
            Image(systemName: iconName)
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(.white)
        }
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
                .help(L.t("Cancel", "取消"))

                Button {
                    Task { await state.stopAndFinish() }
                } label: {
                    Image(systemName: "checkmark")
                        .font(.system(size: 13, weight: .bold))
                        .frame(width: 30, height: 30)
                }
                .buttonStyle(.borderedProminent)
                .clipShape(Circle())
                .help(L.t("Finish & copy", "完成并复制"))
            }
        }
    }
}
