import SwiftUI
import AppKit
import ServiceManagement

struct SettingsView: View {
    @EnvironmentObject var state: AppState

    @AppStorage("autoApplyRules") private var autoApplyRules = true
    @AppStorage("autoPaste") private var autoPaste = false
    @AppStorage("apple.lang") private var appleLang = "zh"
    @AppStorage("apple.onDevice") private var appleOnDevice = true
    @AppStorage("hotkey") private var hotkeyID = "optSpace"
    @AppStorage("showDock") private var showDock = false
    @AppStorage("launchAtLogin") private var launchAtLogin = false
    @AppStorage("models.custom") private var customModels = ""
    @AppStorage("ai.auto") private var aiAuto = false
    @AppStorage("ai.provider") private var aiProvider = AICorrector.appleID

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
        Section(L.t("通用", "General")) {
            Picker(L.t("界面语言", "Interface Language"), selection: $state.uiLangPref) {
                Text(L.t("跟随系统", "Follow System")).tag("system")
                Text("中文").tag("zh")
                Text("English").tag("en")
            }
            Picker(L.t("麦克风输入源", "Microphone Input"), selection: $state.micUID) {
                Text(L.t("系统默认", "System Default")).tag("")
                ForEach(AudioDeviceManager.shared.devices) { d in
                    Text(d.name).tag(d.id)
                }
            }
            Text(L.t("新麦克风自动出现，拔出后回退系统默认。",
                     "New mics appear automatically; unplugged ones fall back to default."))
                .font(.caption).foregroundStyle(.secondary)
            Toggle(L.t("在 Dock 中常驻图标", "Always show Dock icon"), isOn: $showDock)
                .onChange(of: showDock) { _ in WindowPolicy.applyDockPreference() }
            Toggle(L.t("登录时启动", "Launch at login"), isOn: $launchAtLogin)
                .onChange(of: launchAtLogin) { on in
                    do {
                        if on { try SMAppService.mainApp.register() }
                        else { try SMAppService.mainApp.unregister() }
                    } catch {
                        state.errorMessage = L.t("设置开机启动失败：\(error.localizedDescription)（从 dist 目录运行打包后的 App 才支持）",
                                                 "Launch-at-login failed: \(error.localizedDescription) (requires running the packaged .app)")
                    }
                }
            LabeledContent(L.t("录音与数据", "Recordings & Data")) {
                Button(L.t("在访达中显示", "Reveal in Finder")) {
                    NSWorkspace.shared.activateFileViewerSelecting([state.store.rootDir])
                }
            }
        }
    }

    // MARK: Dictation

    private var dictationSection: some View {
        Section(L.t("听写", "Dictation")) {
            Picker(L.t("默认服务", "Default Service"), selection: state.providerBinding) {
                ForEach(Providers.all) { p in
                    Text(p.displayName).tag(p.id)
                }
            }
            if state.provider.id != "apple" {
                Picker(L.t("默认模型", "Default Model"), selection: state.modelBinding) {
                    ForEach(ProviderConfig.models(state.provider), id: \.self) { Text($0).tag($0) }
                    if ProviderConfig.models(state.provider).isEmpty { Text(L.t("未配置", "Not set")).tag("") }
                }
            }
            Picker(L.t("听写语言", "Dictation Language"), selection: $state.language) {
                ForEach(LanguageChoice.allCases) { Text($0.label).tag($0) }
            }
            Picker(L.t("全局快捷键", "Global Hotkey"), selection: $hotkeyID) {
                ForEach(HotkeyPreset.all) { Text($0.label).tag($0.id) }
            }
            .onChange(of: hotkeyID) { _ in HotKeyManager.shared.applyFromDefaults() }

            Toggle(L.t("新转写自动应用已学会的修正规则", "Auto-apply learned correction rules"), isOn: $autoApplyRules)
            Toggle(L.t("快速听写复制后自动粘贴到当前输入框", "Auto-paste after quick dictation"), isOn: $autoPaste)
                .onChange(of: autoPaste) { on in
                    if on && !Paster.trusted { Paster.requestTrust() }
                }
            if autoPaste && !Paster.trusted {
                Text(L.t("需要辅助功能权限：系统设置 → 隐私与安全性 → 辅助功能 中勾选「声记」",
                         "Needs Accessibility permission: System Settings → Privacy & Security → Accessibility"))
                    .font(.caption).foregroundStyle(.orange)
            }
        }
    }

    // MARK: On-device recognition

    private var appleSection: some View {
        Section(L.t("本机识别 (Apple)", "On-Device Recognition (Apple)")) {
            Picker(L.t("识别语言", "Recognition Language"), selection: $appleLang) {
                Text("中文").tag("zh")
                Text("English").tag("en")
            }
            Toggle(L.t("优先使用离线识别", "Prefer offline recognition"), isOn: $appleOnDevice)
            Text(AppleSpeech.supportsOnDevice(lang: appleLang)
                 ? L.t("当前语言支持离线识别：免费、隐私、长录音也无需分段。",
                       "Offline recognition available: free, private, no chunking needed.")
                 : L.t("当前语言暂不支持离线识别，将使用 Apple 服务器（单段约 1 分钟，长音频会自动切割）。",
                       "Offline unavailable for this language; Apple's server will be used (~1 min per chunk, auto-split)."))
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    // MARK: AI correction

    private var aiSection: some View {
        Section(L.t("AI 修正（语法与错词校对）", "AI Correction (grammar & wording)")) {
            Text(L.t("语言模型会带着你的词库整体校对转写文本，原文始终保留。",
                     "A language model proofreads transcripts with your glossary in mind. The original is always kept."))
                .font(.caption).foregroundStyle(.secondary)

            Picker(L.t("修正模型", "Correction Model"), selection: $aiProvider) {
                Text(L.t("Apple 智能（本机，免费）", "Apple Intelligence (on-device, free)")).tag(AICorrector.appleID)
                ForEach(Providers.cloud) { p in
                    Text(p.displayName).tag(p.id)
                }
            }

            if aiProvider == AICorrector.appleID {
                if AICorrector.appleAvailable {
                    Text(L.t("✓ Apple 智能可用", "✓ Apple Intelligence is available"))
                        .font(.caption).foregroundStyle(.green)
                } else {
                    Text(L.t("需要 macOS 26+ 并在系统设置中开启 Apple Intelligence。",
                             "Requires macOS 26+ with Apple Intelligence enabled in System Settings."))
                        .font(.caption).foregroundStyle(.orange)
                }
            } else {
                AIModelField(providerID: aiProvider)
                if !Keychain.has(account: aiProvider) {
                    Text(L.t("该服务还没有 API Key，请在下方「API 密钥」中配置（与转写共用）。",
                             "No API key for this service yet — add one under API Keys below (shared with transcription)."))
                        .font(.caption).foregroundStyle(.orange)
                }
            }

            Toggle(L.t("转写完成后自动进行 AI 修正", "Auto-correct after every transcription"), isOn: $aiAuto)
            Text(L.t("不开启时可在历史详情页手动触发。", "You can always trigger it manually from a session's detail page."))
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    // MARK: API keys

    private var keysSection: some View {
        Section(L.t("API 密钥（保存在 macOS 钥匙串）", "API Keys (stored in macOS Keychain)")) {
            ForEach(Providers.cloud) { provider in
                ProviderKeyRow(provider: provider, customModels: $customModels)
            }
        }
    }

    // MARK: Chunking

    private var chunkSection: some View {
        Section(L.t("长音频分段", "Long-Audio Chunking")) {
            Text(L.t("超长录音在安静处自动切段、逐段转写后按时间戳合并。",
                     "Long recordings are split at quiet points and merged back with timestamps."))
                .font(.caption).foregroundStyle(.secondary)
            ForEach(Providers.cloud) { provider in
                ChunkRow(provider: provider)
            }
        }
    }

    // MARK: About

    private var aboutSection: some View {
        Section(L.t("关于", "About")) {
            HStack(spacing: 12) {
                Image(systemName: "waveform.circle.fill")
                    .font(.system(size: 34))
                    .foregroundStyle(LinearGradient.vox)
                VStack(alignment: .leading, spacing: 2) {
                    Text(L.appName).font(.headline)
                    Text(L.t("版本", "Version") + " " + appVersion)
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
            }
            LabeledContent(L.t("开发者", "Developer")) {
                Text("Zikai Xiong")
            }
            LabeledContent(L.t("主页", "Homepage")) {
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
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.1.0"
    }
}

// MARK: - AI correction model field

private struct AIModelField: View {
    let providerID: String
    @State private var model = ""

    var body: some View {
        TextField(L.t("模型名（默认：\(AICorrector.defaultModel(for: providerID))）",
                      "Model (default: \(AICorrector.defaultModel(for: providerID)))"),
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

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(provider.displayName, systemImage: provider.icon)
                    .font(.body.weight(.medium))
                Spacer()
                TagChip(text: saved ? L.t("已配置", "Configured") : L.t("未配置", "Not set"),
                        color: saved ? .green : .secondary)
            }
            HStack(spacing: 8) {
                SecureField(saved ? L.t("已保存（输入新 Key 可覆盖）", "Saved (enter a new key to replace)")
                                  : L.t("粘贴 API Key", "Paste API key"), text: $key)
                    .textFieldStyle(.roundedBorder)
                Button(L.t("保存", "Save")) {
                    Keychain.set(key.trimmingCharacters(in: .whitespacesAndNewlines), account: provider.id)
                    key = ""
                    saved = true
                }
                .disabled(key.trimmingCharacters(in: .whitespaces).isEmpty)
                if saved {
                    Button(L.t("清除", "Remove")) {
                        Keychain.delete(account: provider.id)
                        saved = false
                    }
                }
            }
            DisclosureGroup(L.t("高级", "Advanced")) {
                VStack(alignment: .leading, spacing: 6) {
                    TextField(L.t("API 地址（留空用默认：\(provider.defaultBaseURL.isEmpty ? "无" : provider.defaultBaseURL)）",
                                  "API base URL (default: \(provider.defaultBaseURL.isEmpty ? "none" : provider.defaultBaseURL))"),
                              text: $baseURL)
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: baseURL) { v in
                            UserDefaults.standard.set(v, forKey: "base.\(provider.id)")
                        }
                    if provider.id == "custom" {
                        TextField(L.t("转写模型名（多个用逗号分隔）", "Transcription models (comma-separated)"), text: $customModels)
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
                Text(L.t("\(Int(seconds / 60)) 分钟/段", "\(Int(seconds / 60)) min/chunk"))
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
