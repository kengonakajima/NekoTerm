import AppKit
import SwiftTerm

class AppDelegate: NSObject, NSApplicationDelegate {
    var windowControllers: [WindowController] = []
    var keyMonitor: Any? = nil

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMenu()

        // 最初のウィンドウを作成
        let wc = WindowController()
        wc.createInitialTerminal()
        wc.show()
        windowControllers.append(wc)

        NSApp.activate(ignoringOtherApps: true)

        setupKeyMonitor()
    }

    func setupKeyMonitor() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if let wc = self?.activeWindowController(),
               wc.handleKeyEvent(event) {
                return nil
            }
            return event
        }
    }

    func activeWindowController() -> WindowController? {
        guard let keyWindow = NSApp.keyWindow else { return windowControllers.first }
        return windowControllers.first { $0.window === keyWindow }
    }

    func setupMenu() {
        let mainMenu = NSMenu()

        // App menu
        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Quit Nekotty", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        // Edit menu
        let editMenuItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(pasteAsPlainText(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editMenuItem.submenu = editMenu
        mainMenu.addItem(editMenuItem)

        // Shell menu
        let shellMenuItem = NSMenuItem()
        let shellMenu = NSMenu(title: "Shell")
        shellMenu.addItem(withTitle: "New Window", action: #selector(newWindow(_:)), keyEquivalent: "n")
        shellMenu.addItem(withTitle: "New Tab", action: #selector(newTab(_:)), keyEquivalent: "t")
        shellMenu.addItem(NSMenuItem.separator())
        shellMenu.addItem(withTitle: "Close Tab", action: #selector(closeTab(_:)), keyEquivalent: "w")
        shellMenu.addItem(NSMenuItem.separator())
        shellMenu.addItem(withTitle: "Clear Buffer", action: #selector(clearBuffer(_:)), keyEquivalent: "k")
        shellMenuItem.submenu = shellMenu
        mainMenu.addItem(shellMenuItem)

        // View menu
        let viewMenuItem = NSMenuItem()
        let viewMenu = NSMenu(title: "View")
        viewMenu.addItem(withTitle: "Bigger", action: #selector(makeFontBigger(_:)), keyEquivalent: "+")
        viewMenu.addItem(withTitle: "Smaller", action: #selector(makeFontSmaller(_:)), keyEquivalent: "-")
        viewMenu.addItem(withTitle: "Reset Font Size", action: #selector(resetFontSize(_:)), keyEquivalent: "0")
        viewMenuItem.submenu = viewMenu
        mainMenu.addItem(viewMenuItem)

        NSApp.mainMenu = mainMenu
    }

    @objc func newWindow(_ sender: Any?) {
        let wc = WindowController()
        wc.createInitialTerminal()
        wc.show()
        windowControllers.append(wc)
    }

    @objc func newTab(_ sender: Any?) {
        activeWindowController()?.newTab()
    }

    @objc func closeTab(_ sender: Any?) {
        if let wc = activeWindowController() {
            wc.closeCurrentTerminal()
            // ウィンドウのターミナルが全部なくなったらウィンドウを閉じる
            if wc.terminalStates.isEmpty {
                wc.window.close()
                windowControllers.removeAll { $0 === wc }
                // ウィンドウが1個もなくなったらアプリを終了
                if windowControllers.isEmpty {
                    NSApp.terminate(nil)
                }
            }
        }
    }

    @objc func clearBuffer(_ sender: Any?) {
        activeWindowController()?.clearBuffer()
    }

    @objc func pasteAsPlainText(_ sender: Any?) {
        guard let wc = activeWindowController(),
              let state = wc.getSelectedTerminal() else { return }
        let clipboard = NSPasteboard.general

        // 画像がある場合は/tmpに保存してパスを貼り付け
        if let image = clipboard.readObjects(forClasses: [NSImage.self], options: nil)?.first as? NSImage {
            if let path = saveImageToTemp(image) {
                state.terminalView.send(txt: path)
                return
            }
        }

        // テキストの場合はプレーンテキストとして直接送信
        if let text = clipboard.string(forType: .string) {
            state.terminalView.send(txt: text)
        }
    }

    func saveImageToTemp(_ image: NSImage) -> String? {
        let timestamp = Int(Date().timeIntervalSince1970 * 1000)
        let filename = "nekoterm_paste_\(timestamp).png"
        let path = "/tmp/\(filename)"

        guard let tiffData = image.tiffRepresentation,
              let bitmapRep = NSBitmapImageRep(data: tiffData),
              let pngData = bitmapRep.representation(using: .png, properties: [:]) else {
            return nil
        }

        do {
            try pngData.write(to: URL(fileURLWithPath: path))
            return path
        } catch {
            return nil
        }
    }

    @objc func makeFontBigger(_ sender: Any?) {
        activeWindowController()?.changeFontSize(delta: 1)
    }

    @objc func makeFontSmaller(_ sender: Any?) {
        activeWindowController()?.changeFontSize(delta: -1)
    }

    @objc func resetFontSize(_ sender: Any?) {
        activeWindowController()?.resetFontSize()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }

    func windowControllerDidClose(_ controller: WindowController) {
        windowControllers.removeAll { $0 === controller }
    }
}
