import SwiftUI
import AppKit

/// In-app model guide: prices and scenario recommendations, one click away from
/// the model pickers. Prices are ballpark figures (verified 2026-06) — vendors change them.
struct ModelGuideView: View {
    enum Kind { case transcription, tts }
    let kind: Kind

    private struct Entry: Identifiable {
        let id = UUID()
        let service: String
        let model: String
        let price: String
        let note: String
        var recommended = false
        var url: String? = nil
    }

    private var entries: [Entry] {
        switch kind {
        case .transcription:
            return [
                Entry(service: L.t("本机识别 (Apple)", "On-Device (Apple)"), model: L.t("系统识别", "system"),
                      price: L.t("免费 · 离线", "Free · offline"),
                      note: L.t("快速听写首选：零成本、实时出字、隐私好；长会议准确率一般。",
                                "Best for quick dictation: free, live text, private. Average accuracy on long meetings."),
                      recommended: true),
                Entry(service: "Groq", model: "whisper-large-v3-turbo",
                      price: L.t("≈ $0.04/小时", "≈ $0.04/hr"),
                      note: L.t("性价比之王：极快极便宜，中英文都不错，日常云端转写推荐。",
                                "Best value: blazing fast and dirt cheap, solid for Chinese & English."),
                      recommended: true,
                      url: "https://groq.com/pricing"),
                Entry(service: "OpenAI", model: "gpt-4o-mini-transcribe",
                      price: L.t("≈ $0.18/小时", "≈ $0.18/hr"),
                      note: L.t("准确率高、口语顺滑；但对“对话式”语音偶发自由发挥。",
                                "High accuracy and fluent output; occasionally improvises on conversational audio."),
                      url: "https://platform.openai.com/docs/pricing"),
                Entry(service: "OpenAI", model: "whisper-1 / gpt-4o-transcribe",
                      price: L.t("≈ $0.36/小时", "≈ $0.36/hr"),
                      note: L.t("whisper-1 老实稳定；gpt-4o-transcribe 准确率最高。",
                                "whisper-1 is faithful and steady; gpt-4o-transcribe tops accuracy."),
                      url: "https://platform.openai.com/docs/pricing"),
                Entry(service: L.t("硅基流动", "SiliconFlow"), model: "SenseVoiceSmall",
                      price: L.t("极低 · 国内直连", "Very low cost"),
                      note: L.t("中文识别强，国内网络友好。", "Strong Chinese recognition; great connectivity in China."),
                      url: "https://siliconflow.cn"),
                Entry(service: "AssemblyAI", model: "universal-3-pro",
                      price: L.t("$0.21/小时（说话人分离 +$0.02）", "$0.21/hr (+$0.02 diarization)"),
                      note: L.t("多人会议/采访首选：输出「说话人 A/B」分段稿，长音频免分段。直接支持英西葡法德意，其他语言（含中文）自动回退 universal-2。注册送 $50 额度。",
                                "Best for meetings/interviews: Speaker A/B segmented output, no chunking. Native EN/ES/PT/FR/DE/IT; other languages (incl. Chinese) auto-fall back to universal-2. $50 free signup credit."),
                      recommended: true,
                      url: "https://www.assemblyai.com/pricing"),
                Entry(service: "AssemblyAI", model: "universal-2",
                      price: L.t("$0.15/小时", "$0.15/hr"),
                      note: L.t("99 种语言（含中文），同样支持说话人分离。", "99 languages incl. Chinese, also supports diarization."),
                      url: "https://www.assemblyai.com/pricing"),
            ]
        case .tts:
            return [
                Entry(service: L.t("系统语音 (Apple)", "System Voice (Apple)"), model: L.t("系统音色", "system voices"),
                      price: L.t("免费 · 离线", "Free · offline"),
                      note: L.t("零成本即用，中英文系统音色；机械感稍强。",
                                "Zero-cost, offline, Chinese & English system voices; somewhat robotic."),
                      recommended: true),
                Entry(service: "OpenAI", model: "gpt-4o-mini-tts",
                      price: L.t("≈ $0.015/分钟音频", "≈ $0.015/min of audio"),
                      note: L.t("自然度高、10 种音色，中英文皆佳——云端首选。",
                                "Very natural, 10 voices, great in Chinese & English — top cloud pick."),
                      recommended: true,
                      url: "https://platform.openai.com/docs/pricing"),
                Entry(service: L.t("硅基流动", "SiliconFlow"), model: "CosyVoice2-0.5B",
                      price: L.t("极低 · 国内直连", "Very low cost"),
                      note: L.t("中文自然度好，价格便宜。", "Natural Chinese output at a low price."),
                      url: "https://siliconflow.cn"),
                Entry(service: "Groq", model: "playai-tts",
                      price: L.t("低价 · 极快", "Low cost · very fast"),
                      note: L.t("英文为主，生成速度快。", "English-focused, very fast generation."),
                      url: "https://groq.com/pricing"),
            ]
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(kind == .transcription
                  ? L.t("转写模型怎么选？", "Which transcription model?")
                  : L.t("语音模型怎么选？", "Which voice model?"),
                  systemImage: "lightbulb.fill")
                .font(.headline)

            ForEach(entries) { entry in
                HStack(alignment: .top, spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(entry.service).font(.callout.weight(.semibold))
                            Text(entry.model).font(.caption.monospaced()).foregroundStyle(.secondary)
                            if entry.recommended {
                                TagChip(text: L.t("推荐", "Pick"), color: .green)
                            }
                        }
                        Text(entry.note)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 3) {
                        Text(entry.price)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.indigo)
                        if let urlString = entry.url, let url = URL(string: urlString) {
                            Button {
                                NSWorkspace.shared.open(url)
                            } label: {
                                HStack(spacing: 2) {
                                    Text(L.t("官网", "Site"))
                                    Image(systemName: "arrow.up.right")
                                }
                                .font(.caption2)
                            }
                            .buttonStyle(.link)
                            .help(urlString)
                        }
                    }
                    .frame(width: 130, alignment: .trailing)
                }
                .padding(.vertical, 3)
                if entry.id != entries.last?.id { Divider() }
            }

            Text(L.t("价格为约数（2026-06 核对），以各服务官网为准。",
                     "Prices are approximate (checked 2026-06); see each vendor's site."))
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(16)
        .frame(width: 460)
    }
}

/// The little ⓘ that opens the guide
struct ModelGuideButton: View {
    let kind: ModelGuideView.Kind
    @State private var showing = false

    var body: some View {
        Button {
            showing.toggle()
        } label: {
            Image(systemName: "info.circle")
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.borderless)
        .help(L.t("模型价格与场景推荐", "Model prices & recommendations"))
        .popover(isPresented: $showing, arrowEdge: .bottom) {
            ModelGuideView(kind: kind)
        }
    }
}
