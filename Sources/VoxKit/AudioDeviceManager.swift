import Foundation
import CoreAudio
import AVFoundation

/// Microphone input management: enumerates input devices via CoreAudio and refreshes live on hot-plug events.
final class AudioDeviceManager: ObservableObject {
    static let shared = AudioDeviceManager()

    struct Device: Identifiable, Hashable {
        let id: String          // device UID (persistent)
        let name: String
        let audioID: AudioDeviceID
    }

    @Published private(set) var devices: [Device] = []

    private init() {
        refresh()
        startListening()
    }

    func refresh() {
        let list = Self.inputDevices()
        DispatchQueue.main.async { self.devices = list }
    }

    /// UID → current AudioDeviceID; nil when the device is unplugged (fall back to system default)
    func resolve(uid: String) -> AudioDeviceID? {
        guard !uid.isEmpty else { return nil }
        return Self.inputDevices().first { $0.id == uid }?.audioID
    }

    func name(forUID uid: String) -> String? {
        devices.first { $0.id == uid }?.name
    }

    // MARK: CoreAudio

    private static func inputDevices() -> [Device] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        let system = AudioObjectID(kAudioObjectSystemObject)
        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr, size > 0 else { return [] }

        let count = Int(size) / MemoryLayout<AudioDeviceID>.size
        var ids = [AudioDeviceID](repeating: 0, count: count)
        guard AudioObjectGetPropertyData(system, &address, 0, nil, &size, &ids) == noErr else { return [] }

        return ids.compactMap { deviceID in
            guard hasInputStreams(deviceID) else { return nil }
            guard let name = stringProperty(deviceID, selector: kAudioObjectPropertyName, scope: kAudioObjectPropertyScopeGlobal),
                  let uid = stringProperty(deviceID, selector: kAudioDevicePropertyDeviceUID, scope: kAudioObjectPropertyScopeGlobal),
                  !name.isEmpty else { return nil }
            return Device(id: uid, name: name, audioID: deviceID)
        }
    }

    private static func hasInputStreams(_ deviceID: AudioDeviceID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreams,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        let status = AudioObjectGetPropertyDataSize(deviceID, &address, 0, nil, &size)
        return status == noErr && size > 0
    }

    private static func stringProperty(_ deviceID: AudioDeviceID, selector: AudioObjectPropertySelector, scope: AudioObjectPropertyScope) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector, mScope: scope,
            mElement: kAudioObjectPropertyElementMain)
        var cfString: CFString? = nil
        var size = UInt32(MemoryLayout<CFString?>.size)
        let status = withUnsafeMutablePointer(to: &cfString) { ptr in
            AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, ptr)
        }
        guard status == noErr, let cf = cfString else { return nil }
        return cf as String
    }

    // MARK: Hot-plug listener

    private func startListening() {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject), &address, DispatchQueue.main
        ) { [weak self] _, _ in
            self?.refresh()
        }
    }
}
