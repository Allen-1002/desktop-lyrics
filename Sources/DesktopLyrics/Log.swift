import Foundation

/// 在终端里直接运行可执行文件时，把关键步骤打印出来，方便排查。
/// 同一处代码连续打印相同内容时只打印一次。
enum Log {
    private static var lastByCallSite: [String: String] = [:]

    static func info(_ message: String, fileID: String = #fileID, line: Int = #line) {
        let callSite = "\(fileID):\(line)"
        guard lastByCallSite[callSite] != message else { return }
        lastByCallSite[callSite] = message
        FileHandle.standardError.write(Data("[桌面歌词] \(message)\n".utf8))
    }
}
