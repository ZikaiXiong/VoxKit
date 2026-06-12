import SwiftUI
import AppKit
import ServiceManagement

struct SettingsView: View {
    @EnvironmentObject var state: AppState

    @AppStorage("quickReview") private var quickReview = true
    @AppStorage("autoPaste") private var autoPaste = false
    @AppStorage("apple.lang") private var appleLang = "zh"
    @AppStorage("apple.onDevice") private var appleOnDevice = true
    @AppStorage("hotkey") private var hotkeyID = "optSpace"
    @AppStorage("showDock") private var showDock = false
    @AppStorage("launchAtLogin") private var launchAtLogin = false
    @AppStorage("models.custom") private var customModels = ""
    @AppStorage("ai.auto") private var aiAuto = false
    @AppStorage("ai.provider") private var aiProvider = AICorrector.providerID

    var body: some View {
        Form {
            generalSection
            dictationSection
            appleSection
            aiSection
            keysSection
            chunkSection
            aboutSection
        }
        .formStyle(.grouped)
    }

    // MARK: General

    private var generalSection: some View {
        Section(L.t("General", "通用")) {
            Picker(L.t("Interface Language", "界面语言"), selection: $state.uiLangPref) {
                Text(L.t("Follow System", "跟随系统")).tag("system")
                Text("English").tag("en")
                Text("简体中文").tag("zh")
                Text("Español").tag("es")
                Text("Français").tag("fr")
                Text("日本語").tag("ja")
            }
            Picker(L.t("Microphone Input", "麦克风输入源"), selection: $state.micUID) {
                Text(L.t("System Default", "系统默认")).tag("")
                ForEach(AudioDeviceManager.shared.devices) { d in
                    Text(d.name).tag(d.id)
                }
            }
            Toggle(L.t("Always show Dock icon", "在 Dock 中常驻图标"), isOn: $showDock)
                .onChange(of: showDock) { _ in WindowPolicy.applyDockPreference() }
            Toggle(L.t("Launch at login", "登录时启动"), isOn: $launchAtLogin)
                .onChange(of: launchAtLogin) { on in
                    do {
                        if on { try SMAppService.mainApp.register() }
                        else { try SMAppService.mainApp.unregister() }
                    } catch {
                        state.errorMessage = L.t("Launch-at-login failed: \(error.localizedDescription) (requires running the packaged .app)",
                                                 "设置开机启动失败：\(error.localizedDescription)（从 dist 目录运行打包后的 App 才支持）")
                    }
                }
            LabeledContent(L.t("Recordings & Data", "录音与数据")) {
                Button(L.t("Reveal in Finder", "在访达中显示")) {
                    NSWorkspace.shared.activateFileViewerSelecting([state.store.rootDir])
                }
            }
            Text(L.t("All data stays on this Mac. Keys live in the Keychain. No telemetry.",
                     "所有数据仅存本机，Key 在钥匙串，无遥测。"))
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    // MARK: Dictation

    private var dictationSection: some View {
        Section(L.t("Dictation", "听写")) {
            modeServiceRow(mode: .quick,
                           label: L.t("Quick Dictation Service", "快速听写服务"))
            modeServiceRow(mode: .meeting,
                           label: L.t("Meeting Service", "会议记录服务"))
            Picker(L.t("Dictation Language", "听写语言"), selection: $state.language) {
                ForEach(LanguageChoice.allCases) { Text($0.label).tag($0) }
            }
            Picker(L.t("Global Hotkey", "全局快捷键"), selection: $hotkeyID) {
                ForEach(HotkeyPreset.all) { Text($0.label).tag($0.id) }
            }
            .onChange(of: hotkeyID) { _ in HotKeyManager.shared.applyFromDefaults() }

            Toggle(L.t("Show a review panel after dictation", "听写完成后弹出修正窗"), isOn: $quickReview)
                .help(L.t("Text is copied first; the panel never steals focus, edits are re-copied and learned",
                          "结果仍会先复制；修正窗不抢焦点，改动会重新复制并让词典学习"))
            Toggle(L.t("Auto-paste after quick dictation", "快速听写复制后自动粘贴到当前输入框"), isOn: $autoPaste)
                .onChange(of: autoPaste) { on in
                    if on && !Paster.trusted { Paster.requestTrust() }
                }
            if autoPaste && !Paster.trusted {
                Text(L.t("Needs Accessibility permission: System Settings → Privacy & Security → Accessibility",
                         "需要辅助功能权限：系统设置 → 隐私与安全性 → 辅助功能 中勾选「声记」"))
                    .font(.caption).foregroundStyle(.orange)
            }
        }
    }

    /// Service + model pickers bound to one mode's remembered selection
    @ViewBuilder
    private func modeServiceRow(mode: TranscriptionMode, label: String) -> some View {
        let pid = AppState.storedProvider(for: mode)
        Picker(label, selection: state.providerBinding(for: mode)) {
            ForEach(Providers.all) { p in
                Text(p.displayName).tag(p.id)
            }
        }
        if pid != "apple" {
            let models = ProviderConfig.models(Providers.by(pid))
            Picker(L.t("　└ Model", "　└ 模型"), selection: state.modelBinding(for: mode)) {
                ForEach(models, id: \.self) { Text($0).tag($0) }
                if models.isEmpty { Text(L.t("Not set", "未配置")).tag("") }
            }
        }
    }

    // MARK: On-device recognition

    private var appleSection: some View {
        Section(L.t("On-Device Recognition (Apple)", "本机识别 (Apple)")) {
            Picker(L.t("Recognition Language", "识别语言"), selection: $appleLang) {
                Text("中文").tag("zh")
                Text("English").tag("en")
                Text("Español").tag("es")
                Text("Français").tag("fr")
                Text("日本語").tag("ja")
            }
            Toggle(L.t("Prefer offline recognition", "优先使用离线识别"), isOn: $appleOnDevice)
            Text(AppleSpeech.supportsOnDevice(lang: appleLang)
                 ? L.t("✓ Offline recognition available", "✓ 当前语言支持离线识别")
                 : L.t("This language uses Apple's server", "当前语言将使用 Apple 服务器"))
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    // MARK: AI correction

    private var aiSection: some View {
        Section(L.t("AI Cleanup", "AI 清理润色")) {
            Picker(L.t("Cleanup Model", "清理模型"), selection: $aiProvider) {
                Text(L.t("Apple Intelligence (on-device, free)", "Apple 智能（本机，免费）")).tag(AICorrector.appleID)
                ForEach(Providers.cloud) { p in
                    Text(p.displayName).tag(p.id)
                }
            }

            if aiProvider == AICorrector.appleID {
                if AICorrector.appleAvailable {
                    Text(L.t("✓ Apple Intelligence is available", "✓ Apple 智能可用"))
                        .font(.caption).foregroundStyle(.green)
                } else {
                    Text(L.t("Requires macOS 26+ with Apple Intelligence enabled in System Settings.",
                             "需要 macOS 26+ 并在系统设置中开启 Apple Intelligence。"))
                        .font(.caption).foregroundStyle(.orange)
                }
            } else {
                AIModelField(providerID: aiProvider)
                if !Keychain.has(account: aiProvider) {
                    Text(L.t("Add this service's key under API Keys below.", "请在下方「API 密钥」中配置该服务的 Key。"))
                        .font(.caption).foregroundStyle(.orange)
                }
            }

            Toggle(L.t("Clean up automatically after every transcription", "转写完成后自动清理润色"), isOn: $aiAuto)
                .help(L.t("Proofreads with your glossary; the original is always kept. Also available per-session in History",
                          "模型会带着你的词库校对，原文始终保留；也可在历史详情页手动触发"))
            Text(lexiconSummary)
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    /// Makes the lexicon's participation visible: every correction request includes these
    private var lexiconSummary: String {
        let hotwords = state.store.lexicon.hotwords.count
        return L.t("Every request includes your \(hotwords) lexicon word(s). Groq is the fastest cloud option.",
                   "每次修正都会带上你的 \(hotwords) 个词库词汇。Groq 是最快的云端选项。")
    }

    // MARK: API keys

    private var keysSection: some View {
        Section(L.t("API Keys (stored in macOS Keychain)", "API 密钥（保存在 macOS 钥匙串）")) {
            ForEach(Providers.cloud) { provider in
                ProviderKeyRow(provider: provider, customModels: $customModels)
            }
        }
    }

    // MARK: Chunking

    private var chunkSection: some View {
        Section(L.t("Long-Audio Chunking", "长音频分段")) {
            Text(L.t("Long audio is split at quiet points and merged with timestamps.", "超长录音在安静处切段，按时间戳合并。"))
                .font(.caption).foregroundStyle(.secondary)
            ForEach(Providers.cloud.filter { $0.id != "assemblyai" }) { provider in
                ChunkRow(provider: provider)
            }
        }
    }

    // MARK: About

    private var aboutSection: some View {
        Section(L.t("About", "关于")) {
            HStack(spacing: 12) {
                Image(systemName: "waveform.circle.fill")
                    .font(.system(size: 34))
                    .foregroundStyle(LinearGradient.vox)
                VStack(alignment: .leading, spacing: 2) {
                    Text(L.appName).font(.headline)
                    Text(L.t("Version", "版本") + " " + appVersion)
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
            }
            LabeledContent(L.t("Developer", "开发者")) {
                Text("Zikai Xiong")
            }
            LabeledContent(L.t("Built with", "开发方式")) {
                Text("Claude Fable 5")
                    .foregroundStyle(LinearGradient.vox)
                    .fontWeight(.medium)
            }
            LabeledContent(L.t("Homepage", "主页")) {
                Button {
                    if let url = URL(string: "https://zikaixiong.github.io") {
                        NSWorkspace.shared.open(url)
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text("zikaixiong.github.io")
                        Image(systemName: "arrow.up.right.square").font(.caption)
                    }
                }
                .buttonStyle(.link)
            }
        }
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.8.0"
    }
}

// MARK: - AI correction model field

private struct AIModelField: View {
    let providerID: String
    @State private var model = ""

    var body: some View {
        TextField(L.t("Model (default: \(AICorrector.defaultModel(for: providerID)))",
                      "模型名（默认：\(AICorrector.defaultModel(for: providerID))）"),
                  text: $model)
            .textFieldStyle(.roundedBorder)
            .onChange(of: model) { v in
                UserDefaults.standard.set(v, forKey: "ai.model.\(providerID)")
            }
            .onAppear {
                model = UserDefaults.standard.string(forKey: "ai.model.\(providerID)") ?? ""
            }
            .id(providerID)
    }
}

// MARK: - Provider key row

private struct ProviderKeyRow: View {
    let provider: Provider
    @Binding var customModels: String

    @State private var key = ""
    @State private var saved = false
    @State private var baseURL = ""
    @State private var diarize = true

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(provider.displayName, systemImage: provider.icon)
                    .font(.body.weight(.medium))
                Spacer()
                TagChip(text: saved ? L.t("Configured", "已配置") : L.t("Not set", "未配置"),
                        color: saved ? .green : .secondary)
            }
            HStack(spacing: 8) {
                SecureField(saved ? L.t("Saved (enter a new key to replace)", "已保存（输入新 Key 可覆盖）")
                                  : L.t("Paste API key", "粘贴 API Key"), text: $key)
                    .textFieldStyle(.roundedBorder)
                Button(L.t("Save", "保存")) {
                    if Keychain.set(key.trimmingCharacters(in: .whitespacesAndNewlines), account: provider.id) {
                        key = ""
                        saved = true
                    }
                }
                .disabled(key.trimmingCharacters(in: .whitespaces).isEmpty)
                if saved {
                    Button(L.t("Remove", "清除")) {
                        Keychain.delete(account: provider.id)
                        saved = false
                    }
                }
            }
            if provider.id == "assemblyai" {
                Toggle(L.t("Speaker diarization (outputs Speaker A/B, +$0.02/hr)",
                           "说话人分离（输出「说话人 A / B」，+$0.02/小时）"), isOn: $diarize)
                    .onChange(of: diarize) { v in
                        UserDefaults.standard.set(v, forKey: "assemblyai.diarize")
                    }
            }
            DisclosureGroup(L.t("Advanced", "高级")) {
                VStack(alignment: .leading, spacing: 6) {
                    TextField(L.t("API base URL (default: \(provider.defaultBaseURL.isEmpty ? "none" : provider.defaultBaseURL))",
                                  "API 地址（留空用默认：\(provider.defaultBaseURL.isEmpty ? "无" : provider.defaultBaseURL)）"),
                              text: $baseURL)
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: baseURL) { v in
                            UserDefaults.standard.set(v, forKey: "base.\(provider.id)")
                        }
                    if provider.id == "custom" {
                        TextField(L.t("Transcription models (comma-separated)", "转写模型名（多个用逗号分隔）"), text: $customModels)
                            .textFieldStyle(.roundedBorder)
                    }
                }
                .padding(.top, 4)
            }
            .font(.callout)
            Text(provider.hint).font(.caption).foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
        .onAppear {
            saved = Keychain.has(account: provider.id)
            baseURL = UserDefaults.standard.string(forKey: "base.\(provider.id)") ?? ""
            diarize = (UserDefaults.standard.object(forKey: "assemblyai.diarize") as? Bool) ?? true
        }
    }
}

// MARK: - Chunk length row

private struct ChunkRow: View {
    let provider: Provider
    @State private var seconds: Double = 600

    var body: some View {
        Stepper(value: $seconds, in: 60...1800, step: 60) {
            HStack {
                Text(provider.displayName)
                Spacer()
                Text(L.t("\(Int(seconds / 60)) min/chunk", "\(Int(seconds / 60)) 分钟/段"))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
        .onChange(of: seconds) { v in
            UserDefaults.standard.set(v, forKey: "chunk.\(provider.id)")
        }
        .onAppear {
            seconds = ProviderConfig.chunkSeconds(provider)
        }
    }
}
