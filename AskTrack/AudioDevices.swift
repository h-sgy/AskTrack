import AudioToolbox
import CoreAudio

struct InputDevice: Identifiable, Hashable, Sendable {
    let id: AudioDeviceID
    let uid: String   // 再起動しても変わらない識別子（設定に保存する）
    let name: String
}

/// Core Audio の入力デバイス
enum AudioDevices {
    static func inputs() -> [InputDevice] {
        deviceIDs().compactMap { id in
            guard inputChannelCount(id) > 0,
                  let uid = string(id, kAudioDevicePropertyDeviceUID),
                  let name = string(id, kAudioObjectPropertyName) else { return nil }
            return InputDevice(id: id, uid: uid, name: name)
        }
    }

    /// システムの既定の入力
    static func defaultInput() -> InputDevice? {
        var id = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = globalAddress(kAudioHardwarePropertyDefaultInputDevice)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &id) == noErr
        else { return nil }
        return inputs().first { $0.id == id }
    }

    private static func deviceIDs() -> [AudioDeviceID] {
        var address = globalAddress(kAudioHardwarePropertyDevices)
        var size: UInt32 = 0
        let system = AudioObjectID(kAudioObjectSystemObject)
        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr else { return [] }
        var ids = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(system, &address, 0, nil, &size, &ids) == noErr else { return [] }
        return ids
    }

    private static func inputChannelCount(_ id: AudioDeviceID) -> Int {
        var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreamConfiguration,
                                                 mScope: kAudioDevicePropertyScopeInput,
                                                 mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(id, &address, 0, nil, &size) == noErr, size > 0 else { return 0 }
        let raw = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { raw.deallocate() }
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, raw) == noErr else { return 0 }
        let buffers = UnsafeMutableAudioBufferListPointer(raw.assumingMemoryBound(to: AudioBufferList.self))
        return buffers.reduce(0) { $0 + Int($1.mNumberChannels) }
    }

    private static func string(_ id: AudioDeviceID, _ selector: AudioObjectPropertySelector) -> String? {
        var address = globalAddress(selector)
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let status = withUnsafeMutablePointer(to: &value) { AudioObjectGetPropertyData(id, &address, 0, nil, &size, $0) }
        guard status == noErr, let value else { return nil }
        return value.takeRetainedValue() as String
    }

    fileprivate static func globalAddress(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal,
                                   mElement: kAudioObjectPropertyElementMain)
    }
}

/// 既定の入力やデバイス一覧が変わったら知らせる（メインスレッドで呼ぶ）。保持している間だけ有効
final class AudioDeviceObserver {
    private let block: AudioObjectPropertyListenerBlock
    private var addresses = [AudioDevices.globalAddress(kAudioHardwarePropertyDefaultInputDevice),
                             AudioDevices.globalAddress(kAudioHardwarePropertyDevices)]

    init(onChange: @escaping () -> Void) {
        block = { _, _ in onChange() }
        for index in addresses.indices {
            AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &addresses[index], .main, block)
        }
    }

    isolated deinit {
        for index in addresses.indices {
            AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &addresses[index], .main, block)
        }
    }
}
