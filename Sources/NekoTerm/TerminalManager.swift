import AppKit
import SwiftTerm

struct TerminalState {
    let id: UUID
    let terminalView: LocalProcessTerminalView
    var currentDirectory: String?
    var title: String
    var projectName: String
    var lastActivityTime: Date = Date.distantPast  // 初期状態では灰色
    var lastContentHash: Int? = nil  // nilなら初回チェック（緑にしない）
}

func getShell() -> String {
    let bufsize = sysconf(_SC_GETPW_R_SIZE_MAX)
    guard bufsize != -1 else { return "/bin/zsh" }
    let buffer = UnsafeMutablePointer<Int8>.allocate(capacity: bufsize)
    defer { buffer.deallocate() }
    var pwd = passwd()
    var result: UnsafeMutablePointer<passwd>? = UnsafeMutablePointer<passwd>.allocate(capacity: 1)
    if getpwuid_r(getuid(), &pwd, buffer, bufsize, &result) != 0 {
        return "/bin/zsh"
    }
    return String(cString: pwd.pw_shell)
}
