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
        appMenu.addItem(withTitle: "Quit NekoTerm", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

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

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }

    func windowControllerDidClose(_ controller: WindowController) {
        windowControllers.removeAll { $0 === controller }
    }
}
