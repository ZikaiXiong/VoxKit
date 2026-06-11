import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct HistoryView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        HistoryContent(state: state, store: state.store, service: state.service)
    }
}

private struct HistoryContent: View {
    @ObservedObject var state: AppState
    @ObservedObject var store: Store
    @ObservedObject var service: TranscriptionService
    @State private var search = ""

    private var filtered: [Session] {
        guard !search.isEmpty else { return store.sessions }
        let q = search.lowercased()
        return store.sessions.filter { s in
            s.title.lowercased().contains(q)
                || s.transcripts.contains { $0.displayText.lowercased().contains(q) }
        }
    }

    var body: some View {
        HSplitView {
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField(L.t("Search titles or content", "搜索标题或内容"), text: $search)
                        .textFieldStyle(.plain)
                    if !search.isEmpty {
                        Button { search = "" } label: {
                            Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary)
                        }
                        .buttonStyle(.plain)
                    }
                    if state.importingCount > 0 {
                        ProgressView().controlSize(.small)
                            .help(L.t("Importing audio…", "正在导入音频…"))
                    }
                    Button {
                        importAudio()
                    } label: {
                        Image(systemName: "square.and.arrow.down")
                    }
                    .buttonStyle(.borderless)
                    .help(L.t("Import audio files (or just drop them on the window)", "导入音频文件转写（也可以直接拖进窗口）"))
                }
                .padding(10)

                Divider()

                List(selection: $state.selectedSessionID) {
                    ForEach(filtered) { session in
                        SessionRow(session: session, progress: service.progress[session.id])
                            .contextMenu {
                                Button(role: .destructive) {
                                    store.delete(session)
                                    if state.selectedSessionID == session.id { state.selectedSessionID = nil }
                                } label: {
                                    Label(L.t("Delete", "删除"), systemImage: "trash")
                                }
                            }
                    }
                }
                .listStyle(.inset)

                if store.sessions.isEmpty {
                    Spacer()
                }
            }
            .frame(minWidth: 270, idealWidth: 310, maxWidth: 400)

            Group {
                if let session = store.session(state.selectedSessionID) {
                    SessionDetailView(session: session)
                        .id(session.id)
                } else {
                    VStack(spacing: 12) {
                        Image(systemName: "tray")
                            .font(.system(size: 42))
                            .foregroundStyle(.quaternary)
                        Text(store.sessions.isEmpty
                             ? L.t("No recordings yet — start from the Dictate page", "还没有录音，去「听写」页开始吧")
                             : L.t("Select a recording on the left", "选择左侧一条记录查看详情"))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(minWidth: 460, maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func importAudio() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.wav, .mp3, .mpeg4Audio, .aiff, UTType(filenameExtension: "flac") ?? .audio]
        panel.allowsMultipleSelection = true
        panel.message = L.t("Choose audio files to transcribe (converted and added to the library)",
                            "选择要转写的音频文件（自动转换格式并加入资料库）")
        guard panel.runModal() == .OK, !panel.urls.isEmpty else { return }
        state.importAudioFiles(panel.urls)
    }
}

private struct SessionRow: View {
    let session: Session
    let progress: TranscriptionService.Progress?

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(session.title)
                    .font(.callout.weight(.medium))
                    .lineLimit(1)
                Spacer()
                if let progress {
                    HStack(spacing: 4) {
                        ProgressView().controlSize(.mini)
                        if let label = progress.label {
                            Text(label).font(.caption2).foregroundStyle(.secondary)
                        } else if progress.total > 1 {
                            Text("\(progress.done)/\(progress.total)").font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            HStack(spacing: 6) {
                TagChip(text: session.mode.label, color: session.mode == .quick ? .blue : .purple)
                if let v = session.current {
                    TagChip(text: v.model == "on-device" ? L.t("On-device", "本机") : v.model)
                    if v.hasCorrection { TagChip(text: L.t("Corrected", "已修正"), color: .green) }
                }
                Spacer()
                Text("\(Format.shortDate(session.date)) · \(Format.mmss(session.duration))")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 3)
    }
}
