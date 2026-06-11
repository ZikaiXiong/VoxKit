import SwiftUI
import AppKit
import AVFoundation

struct SpeakView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        SpeakContent(state: state, store: state.store)
    }
}

private struct SpeakContent: View {
    @ObservedObject var state: AppState
    @ObservedObject var store: Store

    @State private var text = ""
    @State private var isGenerating = false
    @State private var toast: String?
    @StateObject private var player = PlayerController()
    @State private var playingItemID: UUID?

    @AppStorage("tts.provider") private var providerID = TTSEngine.systemID
    @AppStorage("tts.speed") private var speed = 1.0
    @AppStorage("tts.autoSpeak") private var autoSpeak = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            inputCard
            optionsCard
            historyList
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 18)
        .overlay(alignment: .bottom) {
            if let toast {
                Text(toast)
                    .font(.callout.weight(.medium))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Capsule().fill(.regularMaterial))
                    .padding(.bottom, 12)
                    .transition(.opacity)
            }
        }
        .onDisappear { stopPlayback() }
    }

    // MARK: Input

    private var inputCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                TextEditor(text: $text)
                    .font(.system(size: 14))
                    .lineSpacing(4)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 110, maxHeight: 180)
                    .overlay(alignment: .topLeading) {
                        if text.isEmpty {
                            Text(L.t("Type the text to turn into speech… (Chinese or English)",
                                     "输入要转成语音的文字…（中英文皆可）"))
                                .foregroundStyle(.tertiary)
                                .padding(.top, 8)
                                .padding(.leading, 5)
                                .allowsHitTesting(false)
                        }
                    }
                HStack {
                    Text(L.t("\(text.count) chars", "\(text.count) 字"))
                        .font(.caption)
                        .foregroundStyle(text.count > TTSEngine.maxInputLength && providerID != TTSEngine.systemID
                                         ? AnyShapeStyle(.orange) : AnyShapeStyle(.tertiary))
                    Spacer()
                    if !text.isEmpty {
                        Button(L.t("Clear", "清空")) { text = "" }
                            .controlSize(.small)
                    }
                }
            }
        }
    }

    // MARK: Options

    private var optionsCard: some View {
        Card {
            VStack(spacing: 10) {
                HStack(spacing: 16) {
                    Picker(L.t("Service", "服务"), selection: $providerID) {
                        ForEach(TTSEngine.providerIDs, id: \.self) { id in
                            Text(TTSEngine.name(id)).tag(id)
                        }
                    }
                    .fixedSize()

                    voiceControl

                    ModelGuideButton(kind: .tts)

                    Spacer()

                    keyStatus
                }
                Divider()
                HStack(spacing: 16) {
                    modelControl

                    HStack(spacing: 6) {
                        Text(L.t("Speed", "语速")).foregroundStyle(.secondary)
                        Slider(value: $speed, in: 0.5...2.0, step: 0.1)
                            .frame(width: 130)
                        Text(String(format: "%.1f×", speed))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }

                    Toggle(L.t("Speak after generating", "生成后自动朗读"), isOn: $autoSpeak)

                    Spacer()

                    generateButton
                }
            }
        }
    }

    @ViewBuilder
    private var voiceControl: some View {
        if providerID == TTSEngine.systemID {
            Picker(L.t("Voice", "音色"), selection: voiceBinding) {
                Text(L.t("Default", "默认")).tag("")
                ForEach(TTSEngine.systemVoices(), id: \.identifier) { v in
                    Text("\(v.name) (\(v.language))").tag(v.identifier)
                }
            }
            .frame(maxWidth: 300)
        } else if providerID == "openai" {
            Picker(L.t("Voice", "音色"), selection: voiceBinding) {
                ForEach(TTSEngine.openAIVoices, id: \.self) { Text($0).tag($0) }
            }
            .fixedSize()
        } else {
            HStack(spacing: 6) {
                Text(L.t("Voice", "音色")).foregroundStyle(.secondary)
                TextField(TTSEngine.defaultVoice(providerID), text: voiceBinding)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 220)
            }
        }
    }

    @ViewBuilder
    private var modelControl: some View {
        if providerID != TTSEngine.systemID {
            HStack(spacing: 6) {
                Text(L.t("Model", "模型")).foregroundStyle(.secondary)
                TextField(TTSEngine.defaultModel(providerID), text: modelBinding)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 200)
            }
        }
    }

    private var voiceBinding: Binding<String> {
        Binding(get: { UserDefaults.standard.string(forKey: "tts.voice.\(providerID)") ?? TTSEngine.defaultVoice(providerID) },
                set: { UserDefaults.standard.set($0, forKey: "tts.voice.\(providerID)") })
    }

    private var modelBinding: Binding<String> {
        Binding(get: { UserDefaults.standard.string(forKey: "tts.model.\(providerID)") ?? "" },
                set: { UserDefaults.standard.set($0, forKey: "tts.model.\(providerID)") })
    }

    @ViewBuilder
    private var keyStatus: some View {
        if TTSEngine.needsKey(providerID) {
            if Keychain.has(account: providerID) {
                TagChip(text: L.t("Key configured", "密钥已配置"), color: .green)
            } else {
                Button {
                    state.selectedPage = .settings
                } label: {
                    TagChip(text: L.t("No API key — click to set up", "缺少 API Key，点此配置"), color: .orange)
                }
                .buttonStyle(.plain)
            }
        } else {
            TagChip(text: L.t("Offline · Free", "离线 · 免费"), color: .blue)
        }
    }

    private var generateButton: some View {
        Button {
            generate()
        } label: {
            HStack(spacing: 6) {
                if isGenerating {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "waveform.badge.plus")
                }
                Text(isGenerating ? L.t("Generating…", "生成中…") : L.t("Generate", "生成语音"))
                    .fontWeight(.medium)
            }
            .frame(minWidth: 110)
        }
        .buttonStyle(.borderedProminent)
        .tint(Color(red: 0.32, green: 0.36, blue: 0.95))
        .disabled(isGenerating || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    private func generate() {
        let input = text
        isGenerating = true
        Task {
            defer { isGenerating = false }
            do {
                let item = try await TTSEngine.generate(text: input, providerID: providerID,
                                                        speed: speed, into: store.speechDir)
                store.addSpeech(item)
                showToast(L.t("Generated & saved (\(Format.mmss(item.duration)))", "已生成并保存（\(Format.mmss(item.duration))）"))
                if autoSpeak { play(item) }
            } catch {
                state.errorMessage = L.t("Speech generation failed: ", "语音生成失败：") + error.localizedDescription
            }
        }
    }

    // MARK: History

    private var historyList: some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label(L.t("Generated audio", "生成记录"), systemImage: "music.note.list")
                        .font(.headline)
                    Spacer()
                    if !store.speechItems.isEmpty {
                        Button {
                            NSWorkspace.shared.activateFileViewerSelecting([store.speechDir])
                        } label: {
                            Image(systemName: "folder")
                        }
                        .buttonStyle(.borderless)
                        .help(L.t("Reveal all audio in Finder", "在访达中显示全部音频"))
                    }
                }

                if store.speechItems.isEmpty {
                    Text(L.t("Generated audio is saved here for replay or export.", "生成的语音会保存在这里，随时重听或导出。"))
                        .captionStyle()
                        .padding(.vertical, 10)
                } else {
                    ScrollView {
                        VStack(spacing: 0) {
                            ForEach(store.speechItems) { item in
                                speechRow(item)
                                Divider()
                            }
                        }
                    }
                }
            }
        }
        .frame(maxHeight: .infinity)
    }

    private func speechRow(_ item: SpeechItem) -> some View {
        HStack(spacing: 12) {
            Button {
                if playingItemID == item.id, player.playing {
                    player.toggle()
                } else {
                    play(item)
                }
            } label: {
                Image(systemName: playingItemID == item.id && player.playing ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 26))
                    .foregroundStyle(LinearGradient.vox)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 3) {
                Text(item.preview)
                    .font(.callout)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    TagChip(text: TTSEngine.name(item.providerID))
                    if !item.voice.isEmpty { TagChip(text: item.voice, color: .purple) }
                    Text("\(Format.shortDate(item.date)) · \(Format.mmss(item.duration))")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer()

            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(item.text, forType: .string)
                showToast(L.t("Text copied", "文本已复制"))
            } label: {
                Image(systemName: "doc.on.doc")
            }
            .buttonStyle(.borderless)
            .help(L.t("Copy text", "复制原文"))

            Button {
                exportSpeech(item)
            } label: {
                Image(systemName: "square.and.arrow.up")
            }
            .buttonStyle(.borderless)
            .help(L.t("Export audio", "导出音频"))

            Button {
                if playingItemID == item.id { stopPlayback() }
                store.deleteSpeech(item)
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 7)
    }

    private func play(_ item: SpeechItem) {
        player.load(url: store.speechURL(for: item))
        playingItemID = item.id
        player.toggle()
    }

    private func stopPlayback() {
        player.unload()
        playingItemID = nil
    }

    private func exportSpeech(_ item: SpeechItem) {
        let panel = NSSavePanel()
        let ext = (item.fileName as NSString).pathExtension
        panel.nameFieldStringValue = item.preview.prefix(24).replacingOccurrences(of: "/", with: "-") + ".\(ext)"
        guard panel.runModal() == .OK, let dest = panel.url else { return }
        try? FileManager.default.removeItem(at: dest)
        do {
            try FileManager.default.copyItem(at: store.speechURL(for: item), to: dest)
            showToast(L.t("Exported", "已导出"))
        } catch {
            state.errorMessage = L.t("Export failed: ", "导出失败：") + error.localizedDescription
        }
    }

    private func showToast(_ message: String) {
        withAnimation { toast = message }
        Task {
            try? await Task.sleep(nanoseconds: 1_800_000_000)
            withAnimation { toast = nil }
        }
    }
}
