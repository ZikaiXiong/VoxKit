import SwiftUI

struct LexiconView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        LexiconContent(store: state.store)
    }
}

private struct LexiconContent: View {
    @ObservedObject var store: Store
    @State private var newOriginal = ""
    @State private var newReplacement = ""
    @State private var newHotword = ""
    @State private var candidates: [(String, Int)] = []

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text(L.t("词典", "Lexicon"))
                    .font(.title2.weight(.semibold))
                Text(L.t("出现 2 次的改法自动生效，用于自动修正与热词。",
                         "A fix seen twice becomes active, powering auto-correction and hotwords."))
                    .font(.callout)
                    .foregroundStyle(.secondary)

                rulesSection
                hotwordsSection
                candidatesSection
            }
            .padding(22)
            .frame(maxWidth: 760, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .onAppear { candidates = store.frequentTokenCandidates() }
    }

    // MARK: Correction rules

    private var rulesSection: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                Label(L.t("修正规则（识别错 → 应该是）", "Correction rules (wrong → right)"), systemImage: "wand.and.stars")
                    .font(.headline)

                HStack(spacing: 8) {
                    TextField(L.t("识别成了…", "Recognized as…"), text: $newOriginal)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 160)
                    Image(systemName: "arrow.right").foregroundStyle(.secondary)
                    TextField(L.t("应该是…", "Should be…"), text: $newReplacement)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 160)
                    Button(L.t("添加", "Add")) {
                        store.addManualRule(original: newOriginal, replacement: newReplacement)
                        newOriginal = ""; newReplacement = ""
                    }
                    .disabled(newOriginal.trimmingCharacters(in: .whitespaces).isEmpty
                              || newReplacement.trimmingCharacters(in: .whitespaces).isEmpty)
                    Spacer()
                }

                if store.lexicon.rules.isEmpty {
                    Text(L.t("还没有规则——在「历史」里改完文本点「保存修正并学习」即可积累。",
                             "No rules yet — edit a transcript under History and click “Save & Learn”."))
                        .captionStyle()
                        .padding(.vertical, 8)
                } else {
                    VStack(spacing: 0) {
                        ForEach(store.lexicon.rules) { rule in
                            HStack(spacing: 10) {
                                Toggle("", isOn: Binding(
                                    get: { rule.enabled },
                                    set: { _ in store.toggleRule(rule) }
                                ))
                                .labelsHidden()
                                .toggleStyle(.switch)
                                .controlSize(.mini)

                                Text(rule.original)
                                    .strikethrough(color: .secondary)
                                    .foregroundStyle(.secondary)
                                Image(systemName: "arrow.right").font(.caption2).foregroundStyle(.tertiary)
                                Text(rule.replacement).fontWeight(.medium)

                                if rule.isManual {
                                    TagChip(text: L.t("手动", "Manual"), color: .blue)
                                } else if rule.isActive {
                                    TagChip(text: L.t("已生效 · 学习 \(rule.count) 次", "Active · learned ×\(rule.count)"), color: .green)
                                } else {
                                    TagChip(text: L.t("再出现 \(max(0, 2 - rule.count)) 次后生效", "Active after \(max(0, 2 - rule.count)) more"), color: .orange)
                                }

                                Spacer()

                                Button {
                                    store.deleteRule(rule)
                                } label: {
                                    Image(systemName: "trash").foregroundStyle(.secondary)
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(.vertical, 7)
                            Divider()
                        }
                    }
                }
            }
        }
    }

    // MARK: Hotwords

    private var hotwordsSection: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                Label(L.t("热词（专有名词、人名、术语）", "Hotwords (proper nouns, names, jargon)"), systemImage: "flame")
                    .font(.headline)
                    .help(L.t("注入转写模型与 AI 修正，让专有名词从源头拼对",
                              "Injected into transcription and AI correction so these terms come out right"))

                HStack {
                    TextField(L.t("输入热词后回车", "Type a hotword and press Return"), text: $newHotword)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 220)
                        .onSubmit { addHotword() }
                    Button(L.t("添加", "Add")) { addHotword() }
                        .disabled(newHotword.trimmingCharacters(in: .whitespaces).isEmpty)
                }

                FlowChips(items: store.lexicon.hotwords, emptyHint: L.t("暂无热词", "No hotwords yet")) { word in
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
                    Label(L.t("高频词（从你的转写里自动统计）", "Frequent words (mined from your transcripts)"), systemImage: "chart.bar.fill")
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
                          emptyHint: L.t("录音多了之后这里会出现你的高频词", "Your frequent words will appear here as you record more")) { packed in
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
