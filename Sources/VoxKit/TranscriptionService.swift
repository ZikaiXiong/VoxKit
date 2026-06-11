import Foundation

/// Transcription orchestration: auto-split → per-chunk transcription (with retry) → timestamped merge → optional AI proofread
@MainActor
final class TranscriptionService: ObservableObject {
    struct Progress: Equatable {
        var done: Int
        var total: Int
        var label: String? = nil   // shown instead of counts when non-nil (e.g. "AI correcting…")
    }

    @Published var progress: [UUID: Progress] = [:]

    var isBusy: Bool { !progress.isEmpty }

    static func effectiveAppleLang(_ language: LanguageChoice) -> String {
        language == .auto
            ? (UserDefaults.standard.string(forKey: "apple.lang") ?? "zh")
            : language.rawValue
    }

    @discardableResult
    func transcribe(session: Session, provider: Provider, model: String,
                    language: LanguageChoice, store: Store) async -> TranscriptVersion? {
        let audioURL = store.audioURL(for: session)
        progress[session.id] = Progress(done: 0, total: 0)
        defer { progress[session.id] = nil }

        do {
            // 1. Determine chunk length (duration/size limits vary by model)
            var chunkSeconds = ProviderConfig.chunkSeconds(provider)
            let preferOnDevice = (UserDefaults.standard.object(forKey: "apple.onDevice") as? Bool) ?? true
            if provider.id == "apple" {
                let lang = Self.effectiveAppleLang(language)
                let onDevice = preferOnDevice && AppleSpeech.supportsOnDevice(lang: lang)
                chunkSeconds = onDevice ? 600 : 55   // server-side recognition caps at ~1 minute per request
            }

            // 2. Split (file IO on a background thread)
            let chunks = try await Task.detached(priority: .userInitiated) {
                try AudioChunker.prepareChunks(source: audioURL, maxChunkSeconds: chunkSeconds)
            }.value
            progress[session.id] = Progress(done: 0, total: chunks.count)

            // Whisper-style models follow the script/style of the prompt text, so a
            // Simplified-Chinese prompt steers Chinese output away from Traditional.
            var promptParts: [String] = []
            if provider.supportsPrompt {
                // Only for Chinese (or auto, where Chinese is the primary use case)
                if language == .zh || language == .auto { promptParts.append("以下是普通话的句子，请使用简体中文转写。") }
                if let hotwords = Learner.hotwordPrompt(store.lexicon) { promptParts.append(hotwords) }
            }
            let prompt = promptParts.isEmpty ? nil : promptParts.joined(separator: " ")
            let appleLang = Self.effectiveAppleLang(language)

            // 3. Transcribe chunk by chunk, retrying each failed chunk once
            var pieces: [String] = []
            var failures = 0
            for (index, chunk) in chunks.enumerated() {
                if provider.needsKey, provider.maxUploadMB.isFinite {
                    let size = (try? FileManager.default.attributesOfItem(atPath: chunk.url.path)[.size] as? Int) ?? 0
                    let mb = Double(size) / 1_048_576
                    if mb > provider.maxUploadMB {
                        throw VoxError.message(L.t(
                            "Chunk is \(String(format: "%.1f", mb))MB, over \(provider.displayName)'s \(Int(provider.maxUploadMB))MB limit. Reduce chunk length in Settings.",
                            "分段文件 \(String(format: "%.1f", mb))MB 超过 \(provider.displayName) 的 \(Int(provider.maxUploadMB))MB 上限，请在「设置 → 分段长度」中调小"))
                    }
                }
                var text = ""
                var lastError: Error?
                for attempt in 0..<2 {
                    do {
                        if provider.id == "apple" {
                            text = try await AppleSpeech.transcribeFile(url: chunk.url, language: appleLang, preferOnDevice: preferOnDevice)
                        } else if provider.id == "assemblyai" {
                            let diarize = (UserDefaults.standard.object(forKey: "assemblyai.diarize") as? Bool) ?? true
                            text = try await AssemblyAITranscriber.transcribe(fileURL: chunk.url, provider: provider, model: model,
                                                                              language: language.apiCode, diarize: diarize)
                        } else {
                            text = try await CloudTranscriber.transcribe(fileURL: chunk.url, provider: provider, model: model,
                                                                          language: language.apiCode, prompt: prompt)
                        }
                        lastError = nil
                        break
                    } catch {
                        lastError = error
                        if attempt == 0 { try? await Task.sleep(nanoseconds: 1_200_000_000) }
                    }
                }
                if let lastError {
                    failures += 1
                    text = L.t("[Chunk failed: \(lastError.localizedDescription)]",
                               "〔本段转写失败：\(lastError.localizedDescription)〕")
                }
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                if chunks.count > 1 {
                    pieces.append("[\(Format.mmss(chunk.start))] \(trimmed)")
                } else {
                    pieces.append(trimmed)
                }
                progress[session.id] = Progress(done: index + 1, total: chunks.count)
            }
            AudioChunker.cleanup(chunks)

            let joined = pieces.joined(separator: chunks.count > 1 ? "\n\n" : "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)

            // 4. Create the version and attach the version (original text preserved)
            var version = TranscriptVersion(
                providerID: provider.id, model: model, language: language.rawValue,
                originalText: joined, chunkCount: chunks.count,
                note: failures > 0 ? L.t("\(failures)/\(chunks.count) chunks failed", "\(failures)/\(chunks.count) 段失败") : nil)

            // 5. Optional: AI grammar correction (holistic proofread using the user glossary)
            if AICorrector.autoEnabled && AICorrector.isConfigured && failures == 0 {
                progress[session.id] = Progress(done: chunks.count, total: chunks.count,
                                                label: L.t("AI correcting…", "AI 修正中…"))
                do {
                    let outcome = try await AICorrector.correct(
                        text: version.displayText, language: version.language, lexicon: store.lexicon)
                    if outcome.hasChange {
                        version.correctedText = outcome.text
                        var tag = L.t("AI corrected", "AI 修正")
                        if outcome.skippedChunks > 0 {
                            tag += L.t(" (\(outcome.skippedChunks) chunk(s) skipped)", "（\(outcome.skippedChunks) 段跳过）")
                        }
                        version.note = version.note.map { $0 + " · " + tag } ?? tag
                    } else if outcome.skippedChunks > 0 {
                        let tag = L.t("AI correction skipped", "AI 修正被跳过")
                        version.note = version.note.map { $0 + " · " + tag } ?? tag
                    }
                } catch {
                    let tag = L.t("AI correction failed", "AI 修正失败")
                    version.note = version.note.map { $0 + " · " + tag } ?? tag
                }
            }

            store.appendTranscript(version, to: session.id)
            return version
        } catch {
            AppState.shared.errorMessage = L.t("Transcription failed for “\(session.title)”: ", "「\(session.title)」转写失败：")
                + error.localizedDescription
            return nil
        }
    }
}
