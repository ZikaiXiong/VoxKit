import SwiftUI
import UniformTypeIdentifiers

struct MainWindow: View {
    @EnvironmentObject var state: AppState
    @State private var dropTargeted = false

    var body: some View {
        NavigationSplitView {
            List(selection: $state.selectedPage) {
                ForEach(MainPage.allCases) { page in
                    Label(page.title, systemImage: page.icon)
                        .tag(page)
                }
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 160, ideal: 185, max: 220)
            .safeAreaInset(edge: .bottom) {
                sidebarFooter
            }
        } detail: {
            Group {
                switch state.selectedPage ?? .record {
                case .record: RecordView()
                case .speak: SpeakView()
                case .history: HistoryView()
                case .lexicon: LexiconView()
                case .settings: SettingsView()
                }
            }
        }
        .frame(minWidth: 920, minHeight: 600)
        .alert(L.t("Something went wrong", "出错了"), isPresented: errorBinding) {
            Button(L.t("OK", "好")) { state.errorMessage = nil }
        } message: {
            Text(state.errorMessage ?? "")
        }
        .onAppear { WindowPolicy.windowOpened() }
        .onDrop(of: [.fileURL], isTargeted: $dropTargeted) { providers in
            handleDrop(providers)
        }
        .overlay { dropOverlay }
    }

    // MARK: Drag & drop import

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        let group = DispatchGroup()
        let lock = NSLock()
        var urls: [URL] = []
        for provider in providers where provider.canLoadObject(ofClass: URL.self) {
            group.enter()
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                if let url {
                    lock.lock(); urls.append(url); lock.unlock()
                }
                group.leave()
            }
        }
        group.notify(queue: .main) {
            guard !urls.isEmpty else { return }
            AppState.shared.importAudioFiles(urls)
        }
        return true
    }

    @ViewBuilder
    private var dropOverlay: some View {
        if dropTargeted {
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(nsColor: .windowBackgroundColor).opacity(0.86))
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(LinearGradient.vox, style: StrokeStyle(lineWidth: 2.5, dash: [9, 6]))
                VStack(spacing: 10) {
                    Image(systemName: "square.and.arrow.down.on.square.fill")
                        .font(.system(size: 42))
                        .foregroundStyle(LinearGradient.vox)
                    Text(L.t("Drop to import audio files", "松开以导入音频文件"))
                        .font(.title3.weight(.semibold))
                    Text(L.t("Converted automatically — transcribe with any model afterwards",
                             "自动转换格式并加入历史，随后可用任意模型转写"))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(14)
            .transition(.opacity)
            .allowsHitTesting(false)
        }
    }

    private var errorBinding: Binding<Bool> {
        Binding(get: { state.errorMessage != nil },
                set: { if !$0 { state.errorMessage = nil } })
    }

    private var sidebarFooter: some View {
        VStack(spacing: 4) {
            Divider()
            HStack(spacing: 8) {
                Image(systemName: "waveform.circle.fill")
                    .foregroundStyle(LinearGradient.vox)
                VStack(alignment: .leading, spacing: 0) {
                    Text(L.appName).font(.caption.weight(.semibold))
                    Text(L.t("Hotkey", "快捷键") + " " + HotkeyPreset.current().label)
                        .font(.caption2).foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
    }
}
