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
                Entry(service: L.t("On-Device (Apple)", "本机识别 (Apple)"), model: L.t("system", "系统识别"),
                      price: L.t("Free · offline", "免费 · 离线"),
                      note: L.t("Best for quick dictation: free, live text, private. Average accuracy on long meetings.",
                                "快速听写首选：零成本、实时出字、隐私好；长会议准确率一般。"),
                      recommended: true),
                Entry(service: "Groq", model: "whisper-large-v3-turbo",
                      price: L.t("≈ $0.04/hr", "≈ $0.04/小时"),
                      note: L.t("Best value: blazing fast and dirt cheap, solid for Chinese & English.",
                                "性价比之王：极快极便宜，中英文都不错，日常云端转写推荐。"),
                      recommended: true,
                      url: "https://groq.com/pricing"),
                Entry(service: "OpenAI", model: "gpt-4o-mini-transcribe",
                      price: L.t("≈ $0.18/hr", "≈ $0.18/小时"),
                      note: L.t("High accuracy and fluent output; occasionally improvises on conversational audio.",
                                "准确率高、口语顺滑；但对“对话式”语音偶发自由发挥。"),
                      url: "https://platform.openai.com/docs/pricing"),
                Entry(service: "OpenAI", model: "whisper-1 / gpt-4o-transcribe",
                      price: L.t("≈ $0.36/hr", "≈ $0.36/小时"),
                      note: L.t("whisper-1 is faithful and steady; gpt-4o-transcribe tops accuracy.",
                                "whisper-1 老实稳定；gpt-4o-transcribe 准确率最高。"),
                      url: "https://platform.openai.com/docs/pricing"),
                Entry(service: L.t("SiliconFlow", "硅基流动"), model: "SenseVoiceSmall",
                      price: L.t("Very low cost", "极低 · 国内直连"),
                      note: L.t("Strong Chinese recognition; great connectivity in China.", "中文识别强，国内网络友好。"),
                      url: "https://siliconflow.cn"),
                Entry(service: "AssemblyAI", model: "universal-3-pro",
                      price: L.t("$0.21/hr (+$0.02 diarization)", "$0.21/小时（说话人分离 +$0.02）"),
                      note: L.t("Best for English meetings: diarization + no chunking, so speaker labels stay stable for hours. Chinese falls back to universal-2 and code-switching is weak — prefer OpenAI diarize for mixed meetings. $50 free credit.",
                                "英文会议首选：说话人分离 + 长音频免分段（说话人编号全程稳定）。中文回退 universal-2、中英混较弱——混合会议建议用 OpenAI diarize。注册送 $50。"),
                      recommended: true,
                      url: "https://www.assemblyai.com/pricing"),
                Entry(service: "Deepgram", model: "nova-3",
                      price: L.t("≈ $0.26/小时", "≈ $0.26/hr"),
                      note: L.t("英文准确率顶级、速度极快；注册送 $200 额度。", "Top English accuracy, very fast; $200 free signup credit."),
                      url: "https://deepgram.com/pricing"),
                Entry(service: "ElevenLabs", model: "scribe_v2",
                      price: L.t("≈ $0.40/小时", "≈ $0.40/hr"),
                      note: L.t("多语种识别准确，长音频支持好。", "Accurate multilingual recognition with long-audio support."),
                      url: "https://elevenlabs.io/pricing"),
                Entry(service: L.t("智谱 GLM", "Zhipu GLM"), model: "glm-asr-2512",
                      price: L.t("低价 · 国内直连", "Low cost"),
                      note: L.t("中文识别强，国内网络友好。", "Strong Chinese recognition; great connectivity in China."),
                      url: "https://open.bigmodel.cn"),
                Entry(service: "AssemblyAI", model: "universal-2",
                      price: L.t("$0.15/hr", "$0.15/小时"),
                      note: L.t("99 languages incl. Chinese, also supports diarization.", "99 种语言（含中文），同样支持说话人分离。"),
                      url: "https://www.assemblyai.com/pricing"),
            ]
        case .tts:
            return [
                Entry(service: L.t("System Voice (Apple)", "系统语音 (Apple)"), model: L.t("system voices", "系统音色"),
                      price: L.t("Free · offline", "免费 · 离线"),
                      note: L.t("Zero-cost, offline, Chinese & English system voices; somewhat robotic.",
                                "零成本即用，中英文系统音色；机械感稍强。"),
                      recommended: true),
                Entry(service: "OpenAI", model: "gpt-4o-mini-tts",
                      price: L.t("≈ $0.015/min of audio", "≈ $0.015/分钟音频"),
                      note: L.t("Very natural, 10 voices, great in Chinese & English — top cloud pick.",
                                "自然度高、10 种音色，中英文皆佳——云端首选。"),
                      recommended: true,
                      url: "https://platform.openai.com/docs/pricing"),
                Entry(service: L.t("SiliconFlow", "硅基流动"), model: "CosyVoice2-0.5B",
                      price: L.t("Very low cost", "极低 · 国内直连"),
                      note: L.t("Natural Chinese output at a low price.", "中文自然度好，价格便宜。"),
                      url: "https://siliconflow.cn"),
                Entry(service: "ElevenLabs", model: "eleven_multilingual_v2",
                      price: L.t("≈ $0.18/千字符", "≈ $0.18/1k chars"),
                      note: L.t("公认最自然的音色，多语种俱佳。", "Widely considered the most natural voices, excellent across languages."),
                      recommended: true,
                      url: "https://elevenlabs.io/pricing"),
                Entry(service: "Groq", model: "playai-tts",
                      price: L.t("Low cost · very fast", "低价 · 极快"),
                      note: L.t("English-focused, very fast generation.", "英文为主，生成速度快。"),
                      url: "https://groq.com/pricing"),
            ]
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(kind == .transcription
                  ? L.t("Which transcription model?", "转写模型怎么选？")
                  : L.t("Which voice model?", "语音模型怎么选？"),
                  systemImage: "lightbulb.fill")
                .font(.headline)

            ForEach(entries) { entry in
                HStack(alignment: .top, spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(entry.service).font(.callout.weight(.semibold))
                            Text(entry.model).font(.caption.monospaced()).foregroundStyle(.secondary)
                            if entry.recommended {
                                TagChip(text: L.t("Pick", "推荐"), color: .green)
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
                                    Text(L.t("Site", "官网"))
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

            Text(L.t("Prices are approximate (checked 2026-06); see each vendor's site.",
                     "价格为约数（2026-06 核对），以各服务官网为准。"))
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
        .help(L.t("Model prices & recommendations", "模型价格与场景推荐"))
        .popover(isPresented: $showing, arrowEdge: .bottom) {
            ModelGuideView(kind: kind)
        }
    }
}
