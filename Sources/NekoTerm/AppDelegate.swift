import AppKit
import SwiftTerm

class AppDelegate: NSObject, NSApplicationDelegate, LocalProcessTerminalViewDelegate, NSSplitViewDelegate {
    var window: NSWindow!
    var splitView: NSSplitView!
    var leftPane: NSScrollView!
    var terminal: LocalProcessTerminalView!

    func applicationDidFinishLaunching(_ notification: Notification) {
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1000, height: 600),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "NekoTerm"
        window.center()

        let contentBounds = window.contentView!.bounds

        splitView = NSSplitView(frame: contentBounds)
        splitView.isVertical = true
        splitView.dividerStyle = .thin
        splitView.autoresizingMask = [.width, .height]
        splitView.delegate = self

        // 左ペイン（ツリービュー用プレースホルダー）
        leftPane = NSScrollView(frame: NSRect(x: 0, y: 0, width: 200, height: contentBounds.height))
        leftPane.hasVerticalScroller = true
        leftPane.drawsBackground = true
        leftPane.backgroundColor = NSColor(white: 0.1, alpha: 1.0)

        // 右ペイン（ターミナル）
        terminal = LocalProcessTerminalView(frame: NSRect(x: 0, y: 0, width: 800, height: contentBounds.height))
        terminal.processDelegate = self

        let shell = getShell()
        let shellIdiom = "-" + (shell as NSString).lastPathComponent
        FileManager.default.changeCurrentDirectoryPath(FileManager.default.homeDirectoryForCurrentUser.path)
        terminal.startProcess(executable: shell, execName: shellIdiom)

        splitView.addArrangedSubview(leftPane)
        splitView.addArrangedSubview(terminal)

        window.contentView?.addSubview(splitView)

        splitView.setPosition(200, ofDividerAt: 0)
        splitView.adjustSubviews()

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - NSSplitViewDelegate

    func splitView(_ splitView: NSSplitView, constrainMinCoordinate proposedMinimumPosition: CGFloat, ofSubviewAt dividerIndex: Int) -> CGFloat {
        return 150
    }

    func splitView(_ splitView: NSSplitView, constrainMaxCoordinate proposedMaximumPosition: CGFloat, ofSubviewAt dividerIndex: Int) -> CGFloat {
        return splitView.bounds.width - 400
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
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

    // MARK: - LocalProcessTerminalViewDelegate

    func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {
    }

    func setTerminalTitle(source: LocalProcessTerminalView, title: String) {
        window.title = title.isEmpty ? "NekoTerm" : title
    }

    func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {
    }

    func processTerminated(source: TerminalView, exitCode: Int32?) {
        NSApp.terminate(nil)
    }
}
