import SwiftUI

struct LexiconView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        LexiconContent(store: state.store)
    }
}

private struct LexiconContent: View {
    @ObservedObject var store: Store
    @State private var newHotword = ""
    @State private var candidates: [(String, Int)] = []

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text(L.t("Lexicon", "词典"))
                    .font(.title2.weight(.semibold))
                Text(L.t("Your vocabulary — injected into transcription and AI correction. Words you type while correcting transcripts are added automatically.",
                         "你的词库——注入转写与 AI 修正。修正文本时改出的新词会自动加入。"))
                    .font(.callout)
                    .foregroundStyle(.secondary)

                hotwordsSection
                candidatesSection
            }
            .padding(22)
            .frame(maxWidth: 760, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .onAppear { candidates = store.frequentTokenCandidates() }
    }

    // MARK: Hotwords

    private var hotwordsSection: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                Label(L.t("Hotwords (proper nouns, names, jargon)", "热词（专有名词、人名、术语）"), systemImage: "flame")
                    .font(.headline)
                    .help(L.t("Injected into transcription and AI correction so these terms come out right",
                              "注入转写模型与 AI 修正，让专有名词从源头拼对"))

                HStack {
                    TextField(L.t("Type a hotword and press Return", "输入热词后回车"), text: $newHotword)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 220)
                        .onSubmit { addHotword() }
                    Button(L.t("Add", "添加")) { addHotword() }
                        .disabled(newHotword.trimmingCharacters(in: .whitespaces).isEmpty)
                }

                FlowChips(items: store.lexicon.hotwords, emptyHint: L.t("No hotwords yet", "暂无热词")) { word in
                    HStack(spacing: 4) {
                        Text(word)
                        Button {
                            store.removeHotword(word)
                        } label: {
                            Image(systemName: "xmark").font(.system(size: 8, weight: .bold))
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                    }
                    .font(.callout)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Color.orange.opacity(0.12)))
                }
            }
        }
    }

    private func addHotword() {
        store.addHotword(newHotword)
        newHotword = ""
    }

    // MARK: Frequent-word candidates

    private var candidatesSection: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label(L.t("Frequent words (mined from your transcripts)", "高频词（从你的转写里自动统计）"), systemImage: "chart.bar.fill")
                        .font(.headline)
                    Spacer()
                    Button {
                        candidates = store.frequentTokenCandidates()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.borderless)
                }
                FlowChips(items: candidates.map { "\($0.0)|\($0.1)" },
                          emptyHint: L.t("Your frequent words will appear here as you record more", "录音多了之后这里会出现你的高频词")) { packed in
                    let parts = packed.split(separator: "|")
                    let word = String(parts.first ?? "")
                    let count = parts.count > 1 ? String(parts[1]) : ""
                    return HStack(spacing: 5) {
                        Text(word)
                        Text("×\(count)").font(.caption2).foregroundStyle(.tertiary)
                        Button {
                            store.addHotword(word)
                            candidates.removeAll { $0.0 == word }
                        } label: {
                            Image(systemName: "plus.circle.fill").foregroundStyle(.indigo)
                        }
                        .buttonStyle(.plain)
                    }
                    .font(.callout)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Color.indigo.opacity(0.08)))
                }
            }
        }
    }
}

/// Simple flow layout of chips that wraps by row
struct FlowChips<Content: View>: View {
    let items: [String]
    let emptyHint: String
    @ViewBuilder let chip: (String) -> Content

    var body: some View {
        if items.isEmpty {
            Text(emptyHint).captionStyle().padding(.vertical, 6)
        } else {
            FlowLayout(spacing: 8) {
                ForEach(items, id: \.self) { item in
                    chip(item)
                }
            }
        }
    }
}

/// Minimal Layout-protocol flow layout (macOS 13+)
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 600
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > width, x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: width, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
