import AppKit
import SwiftTerm

class AppDelegate: NSObject, NSApplicationDelegate, LocalProcessTerminalViewDelegate, NSSplitViewDelegate {
    var window: NSWindow!
    var splitView: NSSplitView!
    var leftPane: NSScrollView!
    var treeView: TreeView!
    var terminalContainer: NSView!

    // 2ストローク選択用
    var pendingGroupIndex: Int? = nil
    var pendingTimer: Timer? = nil
    var keyMonitor: Any? = nil

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

        // 保存されたターミナルを復元、なければ新規作成
        let savedDirs = loadSavedTerminalDirectories()
        print("Restoring \(savedDirs.count) terminals")
        if savedDirs.isEmpty {
            print("No saved terminals, creating new one")
            let state = createTerminal(delegate: self)
            selectTerminal(id: state.id)
        } else {
            for dir in savedDirs {
                print("Creating terminal for directory: \(dir)")
                let state = createTerminal(delegate: self, directory: dir)
                if terminalStates.count == 1 {
                    selectTerminal(id: state.id)
                }
            }
        }
        treeView.reloadTerminals()
        showSelectedTerminal()

        splitView.addArrangedSubview(leftPane)
        splitView.addArrangedSubview(terminalContainer)

        window.contentView?.addSubview(splitView)

        splitView.setPosition(200, ofDividerAt: 0)
        splitView.adjustSubviews()

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        setupKeyMonitor()
    }

    func setupKeyMonitor() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            print("Key event: \(event.charactersIgnoringModifiers ?? "nil"), modifiers: \(event.modifierFlags.rawValue)")
            if self?.handleKeyEvent(event) == true {
                return nil  // イベントを消費
            }
            return event
        }
    }

    func handleKeyEvent(_ event: NSEvent) -> Bool {
        // Cmd+数字の検出
        guard event.modifierFlags.contains(.command) else {
            print("No command key")
            return false
        }

        guard let number = numberFromEvent(event) else {
            print("Not a number")
            return false
        }

        print("Number: \(number), pending: \(String(describing: pendingGroupIndex))")

        // 2ストローク目（pending中に数字が押された）
        if let pending = pendingGroupIndex {
            print("Second stroke: group=\(pending), terminal=\(number - 1)")
            selectTerminalInGroup(groupIndex: pending, terminalIndex: number - 1)
            cancelPendingSelection()
            return true
        }

        // 1ストローク目（グループ選択モードに入る）
        print("First stroke: setting pending to \(number - 1)")
        pendingGroupIndex = number - 1
        pendingTimer?.invalidate()
        pendingTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { [weak self] _ in
            print("Timeout, selecting last in group")
            self?.selectLastInPendingGroup()
        }
        return true
    }

    func numberFromEvent(_ event: NSEvent) -> Int? {
        guard let chars = event.charactersIgnoringModifiers,
              let char = chars.first,
              let number = Int(String(char)),
              number >= 1 && number <= 9 else {
            return nil
        }
        return number
    }

    func selectTerminalInGroup(groupIndex: Int, terminalIndex: Int) {
        let groups = buildProjectGroups()
        guard groupIndex < groups.count else { return }
        let group = groups[groupIndex]
        guard terminalIndex < group.terminalIds.count else { return }
        let terminalId = group.terminalIds[terminalIndex]

        selectTerminal(id: terminalId)
        treeView.reloadTerminals()
        showSelectedTerminal()
    }

    func cancelPendingSelection() {
        pendingGroupIndex = nil
        pendingTimer?.invalidate()
        pendingTimer = nil
    }

    func selectLastInPendingGroup() {
        if let groupIndex = pendingGroupIndex,
           let terminalId = getLastSelectedInGroup(groupIndex: groupIndex) {
            selectTerminal(id: terminalId)
            treeView.reloadTerminals()
            showSelectedTerminal()
        }
        cancelPendingSelection()
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

    func applicationWillTerminate(_ notification: Notification) {
        saveTerminalStates()
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
            // URL形式の場合はパスに変換
            var path = directory
            if let dir = directory, let url = URL(string: dir) {
                path = url.path
            }
            updateTerminalDirectory(id: state.id, directory: path)
            saveTerminalStates()
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
