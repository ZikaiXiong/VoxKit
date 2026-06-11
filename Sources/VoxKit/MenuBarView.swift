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
                        Button(state.phase == .paused ? L.t("Resume", "继续") : L.t("Pause", "暂停")) {
                            state.pauseOrResume()
                        }
                    }
                    Button(L.t("Cancel", "取消"), role: .destructive) { state.cancelRecording() }
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
                    Text(L.t("Recent", "最近")).font(.caption).foregroundStyle(.secondary)
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
                Button(L.t("Open Main Window", "打开主窗口")) { openMain() }
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
                .help(L.t("Quit VoxKit", "退出声记"))
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
            TagChip(text: L.t("Recording", "录音中") + " " + Format.mmss(recorder.elapsed), color: .red)
        case .paused:
            TagChip(text: L.t("Paused", "已暂停"), color: .orange)
        case .processing:
            TagChip(text: state.processingDetail ?? L.t("Working", "转写中"), color: .indigo)
        default:
            if service.isBusy {
                TagChip(text: L.t("Transcribing", "后台转写中"), color: .indigo)
            } else {
                TagChip(text: L.t("Ready", "待命") + " " + HotkeyPreset.current().label, color: .secondary)
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
                     ? L.t("Finish & Copy", "完成并复制")
                     : L.t("Start Quick Dictation", "开始快速听写"))
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
