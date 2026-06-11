import Foundation
import AVFoundation
import AudioToolbox

/// Microphone recorder: writes a standard 16kHz / mono / 16-bit WAV (the most
/// size-efficient format cloud models accept).
///
/// Robustness: AVAudioEngine occasionally "starts" without ever delivering input
/// buffers (stale hardware format, device handoff, another app holding the mic).
/// The tap therefore uses the bus's live format (format: nil), the converter is
/// created lazily from the first real buffer, and a watchdog rebuilds the engine
/// automatically if no audio arrives shortly after start.
final class AudioRecorder: ObservableObject {
    @Published private(set) var level: Float = 0
    @Published private(set) var elapsed: TimeInterval = 0
    /// True once the first buffer actually arrived — drives the "starting mic…" UI state
    @Published private(set) var isReceivingAudio = false
    /// Highest level seen in this recording — near-zero means the mic captured no sound
    private(set) var peakLevel: Float = 0

    private var engine: AVAudioEngine?
    private var file: AVAudioFile?
    private var converter: AVAudioConverter?
    private var lastInputFormat: AVAudioFormat?
    private(set) var fileURL: URL?
    private var writtenFrames: Int64 = 0
    private var lastUIUpdate: CFAbsoluteTime = 0
    private var gotAudio = false
    private var watchdog: DispatchWorkItem?

    /// Raw-format buffer callback (feeds Apple live recognition)
    var bufferHandler: ((AVAudioPCMBuffer) -> Void)?
    /// Called on the main queue when the engine failed to deliver audio after retries
    var onStartupFailure: (() -> Void)?

    private let outFormat = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16000, channels: 1, interleaved: true)!

    var isRunning: Bool { engine?.isRunning ?? false }

    static func ensurePermission() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: return true
        case .notDetermined: return await AVCaptureDevice.requestAccess(for: .audio)
        default: return false
        }
    }

    func start(to url: URL, device: AudioDeviceID? = nil) throws {
        try startEngine(to: url, device: device)
        armWatchdog(device: device, retriesLeft: 2)
    }

    private func startEngine(to url: URL, device: AudioDeviceID?) throws {
        teardownEngine()
        let engine = AVAudioEngine()
        let input = engine.inputNode
        // Pin the input source (nil = follow the system default)
        if var deviceID = device, let audioUnit = input.audioUnit {
            AudioUnitSetProperty(audioUnit,
                                 kAudioOutputUnitProperty_CurrentDevice,
                                 kAudioUnitScope_Global, 0,
                                 &deviceID, UInt32(MemoryLayout<AudioDeviceID>.size))
        }
        let inFormat = input.outputFormat(forBus: 0)
        guard inFormat.sampleRate > 0, inFormat.channelCount > 0 else {
            throw VoxError.message(L.t("没有检测到可用的麦克风输入设备", "No usable microphone input found"))
        }
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 16000.0,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
        ]
        file = try AVAudioFile(forWriting: url, settings: settings, commonFormat: .pcmFormatInt16, interleaved: true)
        converter = nil          // built lazily from the first buffer's real format
        lastInputFormat = nil
        fileURL = url
        writtenFrames = 0
        gotAudio = false

        // format: nil — follow whatever the hardware actually delivers. Passing a
        // pre-read format can silently kill the tap when the device wakes up at a
        // different sample rate.
        input.installTap(onBus: 0, bufferSize: 4096, format: nil) { [weak self] buffer, _ in
            self?.handle(buffer)
        }
        engine.prepare()
        try engine.start()
        self.engine = engine
        peakLevel = 0
        DispatchQueue.main.async {
            self.level = 0
            self.elapsed = 0
            self.isReceivingAudio = false
        }
    }

    /// If no buffer arrives shortly after start, rebuild the engine (the silent-start
    /// failure is transient — a fresh engine almost always recovers it).
    private func armWatchdog(device: AudioDeviceID?, retriesLeft: Int) {
        watchdog?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.engine != nil, !self.gotAudio else { return }
            if retriesLeft > 0, let url = self.fileURL {
                if (try? self.startEngine(to: url, device: device)) != nil {
                    self.armWatchdog(device: device, retriesLeft: retriesLeft - 1)
                } else {
                    self.failStartup()
                }
            } else {
                self.failStartup()
            }
        }
        watchdog = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9, execute: work)
    }

    private func failStartup() {
        teardownEngine()
        DispatchQueue.main.async { self.onStartupFailure?() }
    }

    func pause() { engine?.pause() }

    func resume() { try? engine?.start() }

    /// Stops recording and finalizes the file; returns the audio URL
    @discardableResult
    func stop() -> URL? {
        let url = fileURL
        teardownEngine()
        return url
    }

    /// Cancels and deletes the file
    func cancel() {
        let url = fileURL
        teardownEngine()
        if let url { try? FileManager.default.removeItem(at: url) }
        fileURL = nil
    }

    private func teardownEngine() {
        watchdog?.cancel()
        watchdog = nil
        engine?.inputNode.removeTap(onBus: 0)
        engine?.stop()
        engine = nil
        file = nil       // releasing finalizes the WAV header
        converter = nil
        lastInputFormat = nil
    }

    // Audio-capture thread
    private func handle(_ buffer: AVAudioPCMBuffer) {
        if !gotAudio {
            gotAudio = true
            DispatchQueue.main.async { self.isReceivingAudio = true }
        }
        bufferHandler?(buffer)

        var rms: Float = 0
        if let ch = buffer.floatChannelData?[0] {
            let n = Int(buffer.frameLength)
            if n > 0 {
                var sum: Float = 0
                var count = 0
                var i = 0
                while i < n { sum += ch[i] * ch[i]; count += 1; i += 8 }
                rms = sqrtf(sum / Float(max(1, count)))
            }
        }

        if converter == nil || lastInputFormat != buffer.format {
            converter = AVAudioConverter(from: buffer.format, to: outFormat)
            lastInputFormat = buffer.format
        }
        if let converter, let file {
            let ratio = outFormat.sampleRate / buffer.format.sampleRate
            let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 64
            if let out = AVAudioPCMBuffer(pcmFormat: outFormat, frameCapacity: capacity) {
                var fed = false
                var convError: NSError?
                let status = converter.convert(to: out, error: &convError) { _, inputStatus in
                    if fed { inputStatus.pointee = .noDataNow; return nil }
                    fed = true
                    inputStatus.pointee = .haveData
                    return buffer
                }
                if status != .error, out.frameLength > 0 {
                    try? file.write(from: out)
                    writtenFrames += Int64(out.frameLength)
                }
            }
        }

        let seconds = Double(writtenFrames) / 16000.0
        let now = CFAbsoluteTimeGetCurrent()
        if now - lastUIUpdate > 0.06 {
            lastUIUpdate = now
            let lv = min(1, rms * 5)
            DispatchQueue.main.async {
                self.level = lv
                self.peakLevel = max(self.peakLevel, lv)
                self.elapsed = seconds
            }
        }
    }
}
