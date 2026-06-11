import Foundation
import AVFoundation
import AudioToolbox

/// Microphone recording: always written as 16kHz / mono / 16-bit WAV (smallest format cloud models accept).
/// @Published properties update on the main thread; audio callbacks run on the capture thread.
final class AudioRecorder: ObservableObject {
    @Published private(set) var level: Float = 0
    @Published private(set) var elapsed: TimeInterval = 0
    /// Highest level seen in this recording — near-zero means the mic captured no sound
    private(set) var peakLevel: Float = 0

    private var engine: AVAudioEngine?
    private var file: AVAudioFile?
    private var converter: AVAudioConverter?
    private(set) var fileURL: URL?
    private var writtenFrames: Int64 = 0
    private var lastUIUpdate: CFAbsoluteTime = 0

    /// Raw-format audio buffer callback (fed to Apple live recognition)
    var bufferHandler: ((AVAudioPCMBuffer) -> Void)?

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
        teardownEngine()
        let engine = AVAudioEngine()
        let input = engine.inputNode
        // Select the input device (nil = follow system default)
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
        converter = AVAudioConverter(from: inFormat, to: outFormat)
        fileURL = url
        writtenFrames = 0

        input.installTap(onBus: 0, bufferSize: 4096, format: inFormat) { [weak self] buffer, _ in
            self?.handle(buffer)
        }
        engine.prepare()
        try engine.start()
        self.engine = engine
        peakLevel = 0
        DispatchQueue.main.async { self.level = 0; self.elapsed = 0 }
    }

    func pause() { engine?.pause() }

    func resume() { try? engine?.start() }

    /// Stops recording, flushes to disk, and returns the audio file
    @discardableResult
    func stop() -> URL? {
        let url = fileURL
        teardownEngine()
        return url
    }

    /// Cancels recording and deletes the file
    func cancel() {
        let url = fileURL
        teardownEngine()
        if let url { try? FileManager.default.removeItem(at: url) }
        fileURL = nil
    }

    private func teardownEngine() {
        engine?.inputNode.removeTap(onBus: 0)
        engine?.stop()
        engine = nil
        file = nil       // releasing it finalizes the WAV header
        converter = nil
    }

    // Capture thread
    private func handle(_ buffer: AVAudioPCMBuffer) {
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
