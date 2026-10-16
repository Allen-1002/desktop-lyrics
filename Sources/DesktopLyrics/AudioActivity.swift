import CoreAudio

/// 查询某个应用此刻是否正在输出声音（macOS 14.2 起系统提供每个进程的音频状态）。
enum AudioActivity {
    /// 返回 nil 表示系统不支持或读取失败，判断不了。
    static func isOutputting(bundleID: String) -> Bool? {
        guard #available(macOS 14.2, *) else { return nil }
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyProcessObjectList,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let system = AudioObjectID(kAudioObjectSystemObject)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr else { return nil }
        var processes = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard !processes.isEmpty else { return false }
        guard AudioObjectGetPropertyData(system, &address, 0, nil, &size, &processes) == noErr else { return nil }

        for process in processes {
            // 有的应用用子进程放声音，子进程的 bundle id 一般以主程序的开头
            guard let id = bundleIdentifier(of: process), id == bundleID || id.hasPrefix(bundleID + ".") else {
                continue
            }
            if isRunningOutput(process) {
                return true
            }
        }
        return false
    }

    @available(macOS 14.2, *)
    private static func bundleIdentifier(of process: AudioObjectID) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioProcessPropertyBundleID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let status = withUnsafeMutablePointer(to: &value) {
            AudioObjectGetPropertyData(process, &address, 0, nil, &size, $0)
        }
        guard status == noErr, let value else { return nil }
        return value.takeRetainedValue() as String
    }

    @available(macOS 14.2, *)
    private static func isRunningOutput(_ process: AudioObjectID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioProcessPropertyIsRunningOutput,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var running: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(process, &address, 0, nil, &size, &running) == noErr else { return false }
        return running != 0
    }
}
