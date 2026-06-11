import Foundation
import AVFoundation

struct AudioChunk {
    let url: URL
    let start: TimeInterval
    let duration: TimeInterval
    let isTemporary: Bool
}

/// Automatic splitting of long audio: cuts at the quietest spot near each target boundary to avoid slicing mid-sentence.
/// Chunks are normalized to 16kHz mono WAV, which any model accepts.
enum AudioChunker {
    private static let probe: Double = 0.2   // RMS sampling window (seconds)

    static func prepareChunks(source: URL, maxChunkSeconds: Double) throws -> [AudioChunk] {
        let src = try AVAudioFile(forReading: source)
        let sr = src.processingFormat.sampleRate
        guard sr > 0, src.length > 0 else { throw VoxError.message(L.t("Audio file is unreadable or empty", "音频文件无法读取或为空")) }
        let total = Double(src.length) / sr

        // Short enough: use the original file as-is
        if total <= maxChunkSeconds * 1.15 {
            return [AudioChunk(url: source, start: 0, duration: total, isTemporary: false)]
        }

        // 1. Scan the loudness profile of the whole file
        let profile = try loudnessProfile(of: src)

        // 2. Pick cut points: the quietest spot within ±10s of each target
        var cuts: [Double] = [0]
        var target = maxChunkSeconds
        while target < total - 5 {
            let lastCut = cuts.last ?? 0
            let lo = max(Int((target - 10) / probe), Int((lastCut + 10) / probe))
            let hi = min(Int((target + 10) / probe), profile.count - 1)
            var best = min(max(lo, 0), profile.count - 1)
            if lo <= hi && lo >= 0 {
                for i in lo...hi where profile[i] < profile[best] { best = i }
            }
            let cut = Double(best) * probe
            guard cut > lastCut + 1 else { break }
            cuts.append(cut)
            target = cut + maxChunkSeconds
        }
        cuts.append(total)

        // 3. Write out the chunk files
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("voxkit-chunks-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)

        var chunks: [AudioChunk] = []
        for k in 0..<(cuts.count - 1) {
            let s = cuts[k], e = cuts[k + 1]
            guard e - s > 0.3 else { continue }
            let url = tmpDir.appendingPathComponent(String(format: "chunk-%03d.wav", k))
            try writeSegment(of: src, from: s, to: e, into: url)
            chunks.append(AudioChunk(url: url, start: s, duration: e - s, isTemporary: true))
        }
        guard !chunks.isEmpty else { throw VoxError.message(L.t("Audio splitting failed", "音频切割失败")) }
        return chunks
    }

    static func cleanup(_ chunks: [AudioChunk]) {
        guard let first = chunks.first(where: { $0.isTemporary }) else { return }
        try? FileManager.default.removeItem(at: first.url.deletingLastPathComponent())
    }

    /// Transcodes any AVFoundation-readable audio (mp3/m4a/flac/aiff/...) into the
    /// library's standard 16kHz mono 16-bit WAV. Returns the duration in seconds.
    static func transcodeToStandardWAV(from source: URL, to dest: URL) throws -> TimeInterval {
        let src = try AVAudioFile(forReading: source)
        let sampleRate = src.processingFormat.sampleRate
        guard sampleRate > 0, src.length > 0 else {
            throw VoxError.message(L.t("Audio file is unreadable or empty", "音频文件无法读取或为空"))
        }
        let total = Double(src.length) / sampleRate
        try writeSegment(of: src, from: 0, to: total, into: dest)
        return total
    }

    // MARK: - Internals

    private static func loudnessProfile(of file: AVAudioFile) throws -> [Float] {
        let sr = file.processingFormat.sampleRate
        let block = AVAudioFrameCount(sr * probe)
        guard let buf = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: block) else {
            throw VoxError.message(L.t("Audio buffer allocation failed", "音频缓冲分配失败"))
        }
        var profile: [Float] = []
        file.framePosition = 0
        while file.framePosition < file.length {
            buf.frameLength = 0
            try file.read(into: buf, frameCount: block)
            if buf.frameLength == 0 { break }
            profile.append(rms(of: buf))
        }
        return profile
    }

    private static func rms(of buffer: AVAudioPCMBuffer) -> Float {
        guard let ch = buffer.floatChannelData?[0] else { return 0 }
        let n = Int(buffer.frameLength)
        guard n > 0 else { return 0 }
        var sum: Float = 0
        var count = 0
        var i = 0
        while i < n { sum += ch[i] * ch[i]; count += 1; i += 4 }
        return sqrtf(sum / Float(max(1, count)))
    }

    private static func writeSegment(of src: AVAudioFile, from start: Double, to end: Double, into url: URL) throws {
        let sr = src.processingFormat.sampleRate
        let outFormat = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16000, channels: 1, interleaved: true)!
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 16000.0,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
        ]
        let outFile = try AVAudioFile(forWriting: url, settings: settings, commonFormat: .pcmFormatInt16, interleaved: true)
        guard let converter = AVAudioConverter(from: src.processingFormat, to: outFormat) else {
            throw VoxError.message(L.t("Could not create the audio converter", "音频格式转换器创建失败"))
        }
        let startFrame = AVAudioFramePosition(start * sr)
        var remaining = AVAudioFrameCount(max(0, (end - start) * sr))
        src.framePosition = startFrame

        let blockFrames: AVAudioFrameCount = 32768
        guard let inBuf = AVAudioPCMBuffer(pcmFormat: src.processingFormat, frameCapacity: blockFrames) else {
            throw VoxError.message(L.t("Audio buffer allocation failed", "音频缓冲分配失败"))
        }
        let ratio = 16000.0 / sr
        while remaining > 0 {
            let toRead = min(blockFrames, remaining)
            inBuf.frameLength = 0
            try src.read(into: inBuf, frameCount: toRead)
            if inBuf.frameLength == 0 { break }
            remaining -= inBuf.frameLength

            let capacity = AVAudioFrameCount(Double(inBuf.frameLength) * ratio) + 64
            guard let outBuf = AVAudioPCMBuffer(pcmFormat: outFormat, frameCapacity: capacity) else { break }
            var fed = false
            var convError: NSError?
            let status = converter.convert(to: outBuf, error: &convError) { _, inputStatus in
                if fed { inputStatus.pointee = .noDataNow; return nil }
                fed = true
                inputStatus.pointee = .haveData
                return inBuf
            }
            if status == .error { throw convError ?? VoxError.message(L.t("Audio conversion failed", "音频转换失败")) }
            if outBuf.frameLength > 0 { try outFile.write(from: outBuf) }
        }
    }
}
