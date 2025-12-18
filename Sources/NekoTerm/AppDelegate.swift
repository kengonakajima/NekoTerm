import AppKit
import SwiftTerm

class AppDelegate: NSObject, NSApplicationDelegate, LocalProcessTerminalViewDelegate, NSSplitViewDelegate {
    var window: NSWindow!
    var splitView: NSSplitView!
    var leftPane: NSScrollView!
    var treeView: TreeView!
    var terminalContainer: NSView!

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMenu()

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

        // 左ペイン（ツリービュー）
        leftPane = NSScrollView(frame: NSRect(x: 0, y: 0, width: 200, height: contentBounds.height))
        leftPane.hasVerticalScroller = true
        leftPane.drawsBackground = true
        leftPane.backgroundColor = NSColor(white: 0.1, alpha: 1.0)

        treeView = TreeView(frame: leftPane.bounds)
        treeView.onSelectionChanged = { [weak self] id in
            selectTerminal(id: id)
            self?.showSelectedTerminal()
        }
        leftPane.documentView = treeView

        // 右ペイン（ターミナルコンテナ）
        terminalContainer = NSView(frame: NSRect(x: 0, y: 0, width: 800, height: contentBounds.height))

        // 最初のターミナルを作成
        let state = createTerminal(delegate: self)
        selectTerminal(id: state.id)
        treeView.reloadTerminals()
        showSelectedTerminal()

        splitView.addArrangedSubview(leftPane)
        splitView.addArrangedSubview(terminalContainer)

        window.contentView?.addSubview(splitView)

        splitView.setPosition(200, ofDividerAt: 0)
        splitView.adjustSubviews()

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
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
        shellMenu.addItem(withTitle: "New Tab", action: #selector(newTab(_:)), keyEquivalent: "t")
        shellMenuItem.submenu = shellMenu
        mainMenu.addItem(shellMenuItem)

        NSApp.mainMenu = mainMenu
    }

    @objc func newTab(_ sender: Any?) {
        let state = createTerminal(delegate: self)
        selectTerminal(id: state.id)
        treeView.reloadTerminals()
        showSelectedTerminal()
    }

    func showSelectedTerminal() {
        // 既存のターミナルビューを削除
        for subview in terminalContainer.subviews {
            subview.removeFromSuperview()
        }

        // 選択中のターミナルを表示
        if let state = getSelectedTerminal() {
            state.terminalView.frame = terminalContainer.bounds
            state.terminalView.autoresizingMask = [.width, .height]
            terminalContainer.addSubview(state.terminalView)
            window.makeFirstResponder(state.terminalView)
        }
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

    // MARK: - LocalProcessTerminalViewDelegate

    func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {
    }

    func setTerminalTitle(source: LocalProcessTerminalView, title: String) {
        if let state = terminalStates.first(where: { $0.terminalView === source }) {
            updateTerminalTitle(id: state.id, title: title)
            treeView.reloadTerminals()
        }
        if let selected = getSelectedTerminal(), selected.terminalView === source {
            window.title = title.isEmpty ? "NekoTerm" : title
        }
    }

    func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {
        if let state = terminalStates.first(where: { $0.terminalView === source }) {
            updateTerminalDirectory(id: state.id, directory: directory)
        }
    }

    func processTerminated(source: TerminalView, exitCode: Int32?) {
        if let state = terminalStates.first(where: { $0.terminalView === source }) {
            removeTerminal(id: state.id)
            if terminalStates.isEmpty {
                NSApp.terminate(nil)
            } else {
                treeView.reloadTerminals()
                showSelectedTerminal()
            }
        }
    }
}
