import Foundation

/// 在终端里直接运行可执行文件时，把关键步骤打印出来，方便排查。
/// 同一条消息连续出现时只打印一次。
enum Log {
    private static var last: String?

    static func info(_ message: String) {
        guard message != last else { return }
        last = message
        FileHandle.standardError.write(Data("[桌面歌词] \(message)\n".utf8))
    }
}
