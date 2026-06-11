import Foundation
import AVFoundation
import Speech

/// Apple system speech recognition (free / offline-capable / lightweight)
enum AppleSpeech {
    static func ensurePermission() async -> Bool {
        let current = SFSpeechRecognizer.authorizationStatus()
        if current == .authorized { return true }
        guard current == .notDetermined else { return false }
        return await withCheckedContinuation { cont in
            SFSpeechRecognizer.requestAuthorization { status in
                cont.resume(returning: status == .authorized)
            }
        }
    }

    static func recognizer(for lang: String) -> SFSpeechRecognizer? {
        let localeID = (lang == "en") ? "en-US" : "zh-CN"
        return SFSpeechRecognizer(locale: Locale(identifier: localeID))
    }

    static func supportsOnDevice(lang: String) -> Bool {
        recognizer(for: lang)?.supportsOnDeviceRecognition ?? false
    }

    /// Recognizes a whole audio file (pair with the chunker for long audio)
    static func transcribeFile(url: URL, language: String, preferOnDevice: Bool) async throws -> String {
        guard await ensurePermission() else {
            throw VoxError.message(L.t("未获得语音识别权限：请在「系统设置 → 隐私与安全性 → 语音识别」中允许「声记」",
                                       "Speech recognition denied: allow VoxNote under System Settings → Privacy & Security → Speech Recognition"))
        }
        guard let recognizer = recognizer(for: language), recognizer.isAvailable else {
            throw VoxError.message(L.t("本机语音识别当前不可用", "On-device speech recognition is unavailable"))
        }
        let request = SFSpeechURLRecognitionRequest(url: url)
        request.shouldReportPartialResults = true
        request.taskHint = .dictation
        if preferOnDevice && recognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        }

        final class Box: @unchecked Sendable {
            var lastText = ""
            var finished = false
            let lock = NSLock()
        }
        let box = Box()

        return try await withCheckedThrowingContinuation { cont in
            _ = recognizer.recognitionTask(with: request) { result, error in
                box.lock.lock()
                if box.finished { box.lock.unlock(); return }
                if let result {
                    box.lastText = result.bestTranscription.formattedString
                    if result.isFinal {
                        box.finished = true
                        box.lock.unlock()
                        cont.resume(returning: box.lastText)
                        return
                    }
                }
                if let error {
                    box.finished = true
                    let text = box.lastText
                    box.lock.unlock()
                    // Silent chunks often fail with "no speech detected"; keep any partial result
                    if text.isEmpty {
                        let ns = error as NSError
                        if ns.domain == "kAFAssistantErrorDomain" {
                            cont.resume(returning: "")
                        } else {
                            cont.resume(throwing: VoxError.message(L.t("本机识别失败：", "On-device recognition failed: ") + error.localizedDescription))
                        }
                    } else {
                        cont.resume(returning: text)
                    }
                    return
                }
                box.lock.unlock()
            }
        }
    }
}

/// Live streaming recognition (text appears as you speak in Quick Dictation, IME-like feel)
final class AppleLiveRecognizer: @unchecked Sendable {
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var latestText = ""
    private var finishCont: CheckedContinuation<String, Never>?
    private let lock = NSLock()

    /// Live text callback, delivered on the main thread
    var onUpdate: ((String) -> Void)?

    func start(language: String, preferOnDevice: Bool) async -> Bool {
        guard await AppleSpeech.ensurePermission() else { return false }
        guard let recognizer = AppleSpeech.recognizer(for: language), recognizer.isAvailable else { return false }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.taskHint = .dictation
        if preferOnDevice && recognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        }
        lock.withLock {
            latestText = ""
            self.request = request
        }

        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }
            if let result {
                let text = result.bestTranscription.formattedString
                self.lock.lock()
                self.latestText = text
                self.lock.unlock()
                DispatchQueue.main.async { self.onUpdate?(text) }
                if result.isFinal { self.resolveFinish() }
            }
            if error != nil { self.resolveFinish() }
        }
        return true
    }

    func append(_ buffer: AVAudioPCMBuffer) {
        request?.append(buffer)
    }

    /// Ends input and waits for the final result (up to 3s, then falls back to the latest partial)
    func finish() async -> String {
        request?.endAudio()
        let text: String = await withCheckedContinuation { cont in
            lock.lock()
            finishCont = cont
            lock.unlock()
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
                self?.resolveFinish()
            }
        }
        cleanup()
        return text
    }

    func cancel() {
        resolveFinish()
        cleanup()
    }

    private func resolveFinish() {
        lock.lock()
        let cont = finishCont
        finishCont = nil
        let text = latestText
        lock.unlock()
        cont?.resume(returning: text)
    }

    private func cleanup() {
        task?.cancel()
        task = nil
        request = nil
    }
}
