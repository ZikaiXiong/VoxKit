import SwiftUI
import AppKit

struct MenuBarView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        MenuBarContent(state: state, recorder: state.recorder, store: state.store, service: state.service)
    }
}

private struct MenuBarContent: View {
    @ObservedObject var state: AppState
    @ObservedObject var recorder: AudioRecorder
    @ObservedObject var store: Store
    @ObservedObject var service: TranscriptionService
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "waveform.circle.fill")
                    .font(.title3)
                    .foregroundStyle(LinearGradient.vox)
                Text(L.appName).font(.headline)
                Spacer()
                statusText
            }

            primaryButton

            if state.phase == .recording || state.phase == .paused {
                HStack(spacing: 8) {
                    if state.activeMode == .meeting {
                        Button(state.phase == .paused ? L.t("继续", "Resume") : L.t("暂停", "Pause")) {
                            state.pauseOrResume()
                        }
                    }
                    Button(L.t("取消", "Cancel"), role: .destructive) { state.cancelRecording() }
                    Spacer()
                    Text(Format.mmss(recorder.elapsed))
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                .controlSize(.small)
            }

            if !store.sessions.isEmpty {
                Divider()
                VStack(alignment: .leading, spacing: 2) {
                    Text(L.t("最近", "Recent")).font(.caption).foregroundStyle(.secondary)
                    ForEach(store.sessions.prefix(3)) { session in
                        Button {
                            state.selectedPage = .history
                            state.selectedSessionID = session.id
                            openMain()
                        } label: {
                            HStack {
                                Image(systemName: session.mode.icon)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .frame(width: 14)
                                Text(session.title).lineLimit(1)
                                Spacer()
                                if service.progress[session.id] != nil {
                                    ProgressView().controlSize(.mini)
                                } else {
                                    Text(Format.mmss(session.duration))
                                        .font(.caption2).foregroundStyle(.tertiary)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .padding(.vertical, 3)
                    }
                }
            }

            Divider()

            HStack {
                Button(L.t("打开主窗口", "Open Main Window")) { openMain() }
                Spacer()
                Button {
                    state.selectedPage = .settings
                    openMain()
                } label: {
                    Image(systemName: "gearshape")
                }
                .buttonStyle(.borderless)
                Button {
                    NSApp.terminate(nil)
                } label: {
                    Image(systemName: "power")
                }
                .buttonStyle(.borderless)
                .help(L.t("退出声记", "Quit VoxKit"))
            }
            .controlSize(.small)
        }
        .padding(12)
        .frame(width: 300)
    }

    @ViewBuilder
    private var statusText: some View {
        switch state.phase {
        case .recording:
            TagChip(text: L.t("录音中", "Recording") + " " + Format.mmss(recorder.elapsed), color: .red)
        case .paused:
            TagChip(text: L.t("已暂停", "Paused"), color: .orange)
        case .processing:
            TagChip(text: state.processingDetail ?? L.t("转写中", "Working"), color: .indigo)
        default:
            if service.isBusy {
                TagChip(text: L.t("后台转写中", "Transcribing"), color: .indigo)
            } else {
                TagChip(text: L.t("待命", "Ready") + " " + HotkeyPreset.current().label, color: .secondary)
            }
        }
    }

    private var primaryButton: some View {
        Button {
            state.toggleQuick()
        } label: {
            HStack {
                Image(systemName: state.phase == .recording && state.activeMode == .quick ? "checkmark.circle.fill" : "mic.fill")
                Text(state.phase == .recording && state.activeMode == .quick
                     ? L.t("完成并复制", "Finish & Copy")
                     : L.t("开始快速听写", "Start Quick Dictation"))
                    .fontWeight(.medium)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
        }
        .buttonStyle(.borderedProminent)
        .tint(Color(red: 0.32, green: 0.36, blue: 0.95))
        .disabled(state.phase == .processing || (state.isRecording && state.activeMode == .meeting))
    }

    private func openMain() {
        WindowPolicy.windowOpened()
        openWindow(id: "main")
        NSApp.activate(ignoringOtherApps: true)
    }
}
