import SwiftUI

struct RecordView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        RecordContent(state: state, recorder: state.recorder, service: state.service,
                      audioDevices: AudioDeviceManager.shared)
    }
}

private struct RecordContent: View {
    @ObservedObject var state: AppState
    @ObservedObject var recorder: AudioRecorder
    @ObservedObject var service: TranscriptionService
    @ObservedObject var audioDevices: AudioDeviceManager
    @State private var pulse = false

    private var busyRecording: Bool { state.phase == .recording || state.phase == .paused }

    var body: some View {
        VStack(spacing: 0) {
            // Mode switcher
            Picker("", selection: $state.uiMode) {
                ForEach(TranscriptionMode.allCases) { mode in
                    Label(mode.label, systemImage: mode.icon).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 310)
            .padding(.top, 24)
            .disabled(busyRecording || state.phase == .processing)

            Spacer()

            VStack(spacing: 22) {
                recordButton

                Text(Format.mmss(recorder.elapsed))
                    .font(.system(size: 34, weight: .light).monospacedDigit())
                    .foregroundStyle(busyRecording ? .primary : .tertiary)

                LevelMeter(level: busyRecording && state.phase == .recording ? recorder.level : 0)

                statusLine

                if busyRecording && state.activeMode == .meeting {
                    meetingControls
                }
            }

            Spacer()

            bottomBar
        }
        .padding(.horizontal, 28)
        .padding(.bottom, 20)
    }

    // MARK: Record button

    private var recordButton: some View {
        Button {
            if busyRecording {
                Task { await state.stopAndFinish() }
            } else if state.phase == .idle {
                Task { await state.startRecording(state.uiMode) }
            }
        } label: {
            ZStack {
                Circle()
                    .fill(LinearGradient.vox)
                    .frame(width: 116, height: 116)
                    .shadow(color: Color(red: 0.25, green: 0.45, blue: 0.95).opacity(0.35), radius: pulse && state.phase == .recording ? 26 : 14)
                    .scaleEffect(pulse && state.phase == .recording ? 1.05 : 1)
                    .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: pulse)

                if state.phase == .processing {
                    ProgressView().controlSize(.large).tint(.white)
                } else {
                    Image(systemName: busyRecording ? "stop.fill" : "mic.fill")
                        .font(.system(size: 38, weight: .medium))
                        .foregroundStyle(.white)
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(state.phase == .processing)
        .onAppear { pulse = true }
    }

    @ViewBuilder
    private var statusLine: some View {
        switch state.phase {
        case .idle:
            VStack(spacing: 5) {
                Text(state.uiMode == .quick
                     ? L.t("点击开始，或在任何地方按 \(HotkeyPreset.current().label)",
                           "Click to start, or press \(HotkeyPreset.current().label) anywhere")
                     : L.t("点击开始会议录音，支持暂停、超长自动分段",
                           "Click to start a meeting recording — pausable, long audio auto-splits"))
                    .foregroundStyle(.secondary)
                if state.uiMode == .quick {
                    Text(L.t("结果自动复制到剪贴板，可直接粘贴", "Result is copied to the clipboard automatically"))
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                inFlightProgress
            }
        case .recording:
            Text(!recorder.isReceivingAudio
                 ? L.t("正在启动麦克风…", "Starting the microphone…")
                 : (state.activeMode == .quick && !state.liveText.isEmpty
                    ? state.liveText
                    : L.t("正在录音…", "Recording…")))
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .frame(maxWidth: 520)
                .multilineTextAlignment(.center)
        case .paused:
            Text(L.t("已暂停", "Paused")).foregroundStyle(.orange)
        case .processing:
            Text(state.processingDetail ?? L.t("正在转写…", "Transcribing…")).foregroundStyle(.secondary)
        case .done(let msg, let ok):
            Label(msg, systemImage: ok ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(ok ? Color.green : Color.red)
        }
    }

    /// Background transcription progress (you can keep working after a meeting ends)
    @ViewBuilder
    private var inFlightProgress: some View {
        if let (_, progress) = service.progress.first {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text(progress.label ?? (progress.total > 1
                     ? L.t("后台转写中 · 第 \(min(progress.done + 1, progress.total))/\(progress.total) 段",
                           "Transcribing in background · chunk \(min(progress.done + 1, progress.total))/\(progress.total)")
                     : L.t("后台转写中…", "Transcribing in background…")))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 6)
        }
    }

    private var meetingControls: some View {
        HStack(spacing: 14) {
            Button {
                state.pauseOrResume()
            } label: {
                Label(state.phase == .paused ? L.t("继续", "Resume") : L.t("暂停", "Pause"),
                      systemImage: state.phase == .paused ? "play.fill" : "pause.fill")
                    .frame(width: 84)
            }
            .controlSize(.large)

            Button(role: .destructive) {
                state.cancelRecording()
            } label: {
                Label(L.t("放弃", "Discard"), systemImage: "trash").frame(width: 84)
            }
            .controlSize(.large)
        }
    }

    // MARK: Bottom bar (mic / service / model / language)

    private var bottomBar: some View {
        Card {
            VStack(spacing: 10) {
                HStack(spacing: 18) {
                    // Microphone picker (prominent; hot-plug aware)
                    Picker(selection: $state.micUID) {
                        Label(L.t("系统默认", "System Default"), systemImage: "mic").tag("")
                        ForEach(audioDevices.devices) { d in
                            Text(d.name).tag(d.id)
                        }
                    } label: {
                        Label(L.t("麦克风", "Microphone"), systemImage: "mic.fill")
                    }
                    .frame(maxWidth: 320)

                    Spacer()

                    keyStatus
                }
                Divider()
                HStack(spacing: 18) {
                    Picker(L.t("服务", "Service"), selection: state.providerBinding) {
                        ForEach(Providers.all) { p in
                            Text(p.displayName).tag(p.id)
                        }
                    }
                    .fixedSize()

                    if state.provider.id != "apple" {
                        Picker(L.t("模型", "Model"), selection: state.modelBinding) {
                            ForEach(ProviderConfig.models(state.provider), id: \.self) { m in
                                Text(m).tag(m)
                            }
                            if ProviderConfig.models(state.provider).isEmpty {
                                Text(L.t("未配置", "Not set")).tag("")
                            }
                        }
                        .fixedSize()
                    }

                    Picker(L.t("语言", "Language"), selection: $state.language) {
                        ForEach(LanguageChoice.allCases) { l in
                            Text(l.label).tag(l)
                        }
                    }
                    .fixedSize()

                    Spacer()

                    if AICorrector.autoEnabled && AICorrector.isConfigured {
                        TagChip(text: L.t("AI 修正已开启", "AI correction on"), color: .indigo)
                    }
                }
            }
        }
        .disabled(busyRecording || state.phase == .processing)
    }

    @ViewBuilder
    private var keyStatus: some View {
        if state.provider.needsKey {
            if Keychain.has(account: state.provider.id) {
                TagChip(text: L.t("密钥已配置", "Key configured"), color: .green)
            } else {
                Button {
                    state.selectedPage = .settings
                } label: {
                    TagChip(text: L.t("缺少 API Key，点此配置", "No API key — click to set up"), color: .orange)
                }
                .buttonStyle(.plain)
            }
        } else {
            TagChip(text: L.t("离线 · 免费", "Offline · Free"), color: .blue)
        }
    }
}
