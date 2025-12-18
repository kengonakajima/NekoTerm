import AppKit
import SwiftTerm

class WindowController: NSObject, LocalProcessTerminalViewDelegate, NSSplitViewDelegate {
    var window: NSWindow!
    var splitView: NSSplitView!
    var leftPane: NSScrollView!
    var treeView: TreeView!
    var terminalContainer: NSView!

    // ウィンドウ固有のターミナル状態
    var terminalStates: [TerminalState] = []
    var selectedTerminalId: UUID?
    var lastSelectedInGroup: [String: UUID] = [:]

    // 2ストローク選択用
    var pendingGroupIndex: Int? = nil
    var pendingTimer: Timer? = nil

    override init() {
        super.init()
        setupWindow()
    }

    func setupWindow() {
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
        treeView.windowController = self
        treeView.onSelectionChanged = { [weak self] id in
            self?.selectTerminal(id: id)
            self?.showSelectedTerminal()
        }
        leftPane.documentView = treeView

        // 右ペイン（ターミナルコンテナ）
        terminalContainer = NSView(frame: NSRect(x: 0, y: 0, width: 800, height: contentBounds.height))

        splitView.addArrangedSubview(leftPane)
        splitView.addArrangedSubview(terminalContainer)

        window.contentView?.addSubview(splitView)

        splitView.setPosition(200, ofDividerAt: 0)
        splitView.adjustSubviews()
    }

    func createInitialTerminal() {
        let state = createTerminal(directory: nil)
        selectTerminal(id: state.id)
        treeView.reloadTerminals()
        showSelectedTerminal()
    }

    func show() {
        window.makeKeyAndOrderFront(nil)
    }

    // MARK: - Terminal Management

    func createTerminal(directory: String? = nil) -> TerminalState {
        let terminalView = LocalProcessTerminalView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        terminalView.processDelegate = self

        // 見やすい色に設定
        terminalView.nativeForegroundColor = NSColor(white: 0.9, alpha: 1.0)
        terminalView.nativeBackgroundColor = NSColor(white: 0.05, alpha: 1.0)

        let shell = getShell()
        let shellIdiom = "-" + (shell as NSString).lastPathComponent

        var startDir: String? = nil
        if let dir = directory, FileManager.default.fileExists(atPath: dir) {
            startDir = dir
        }

        if let dir = startDir {
            FileManager.default.changeCurrentDirectoryPath(dir)
        } else {
            FileManager.default.changeCurrentDirectoryPath(FileManager.default.homeDirectoryForCurrentUser.path)
        }
        terminalView.startProcess(executable: shell, execName: shellIdiom)

        let state = TerminalState(
            id: UUID(),
            terminalView: terminalView,
            currentDirectory: startDir,
            title: "Terminal",
            projectName: extractProjectName(from: startDir)
        )
        terminalStates.append(state)
        return state
    }

    func selectTerminal(id: UUID) {
        selectedTerminalId = id
        if let state = terminalStates.first(where: { $0.id == id }) {
            lastSelectedInGroup[state.projectName] = id
        }
    }

    func getSelectedTerminal() -> TerminalState? {
        guard let id = selectedTerminalId else { return terminalStates.first }
        return terminalStates.first { $0.id == id }
    }

    func removeTerminal(id: UUID) {
        terminalStates.removeAll { $0.id == id }
        if selectedTerminalId == id {
            selectedTerminalId = terminalStates.first?.id
        }
    }

    func updateTerminalDirectory(id: UUID, directory: String?) {
        if let index = terminalStates.firstIndex(where: { $0.id == id }) {
            terminalStates[index].currentDirectory = directory
            terminalStates[index].projectName = extractProjectName(from: directory)
        }
    }

    func updateTerminalTitle(id: UUID, title: String) {
        if let index = terminalStates.firstIndex(where: { $0.id == id }) {
            terminalStates[index].title = title
        }
    }

    func buildProjectGroups() -> [ProjectGroup] {
        var groupMap: [String: ProjectGroup] = [:]
        var orderedNames: [String] = []

        for state in terminalStates {
            let projectName = state.projectName
            if groupMap[projectName] == nil {
                groupMap[projectName] = ProjectGroup(name: projectName)
                orderedNames.append(projectName)
            }
            groupMap[projectName]!.terminalIds.append(state.id)
        }

        return orderedNames.compactMap { groupMap[$0] }
    }

    func getLastSelectedInGroup(groupIndex: Int) -> UUID? {
        let groups = buildProjectGroups()
        guard groupIndex < groups.count else { return nil }
        let group = groups[groupIndex]
        if let lastId = lastSelectedInGroup[group.name],
           group.terminalIds.contains(lastId) {
            return lastId
        }
        return group.terminalIds.first
    }

    func moveTerminal(id: UUID, toIndex targetIndex: Int, inGroup groupName: String) -> Bool {
        let groupTerminals = terminalStates.enumerated().filter { $0.element.projectName == groupName }
        guard let sourceEntry = groupTerminals.first(where: { $0.element.id == id }) else { return false }

        let sourceGlobalIndex = sourceEntry.offset

        var targetGlobalIndex: Int
        if targetIndex >= groupTerminals.count {
            if let lastInGroup = groupTerminals.last {
                targetGlobalIndex = lastInGroup.offset
            } else {
                return false
            }
        } else if targetIndex <= 0 {
            if let firstInGroup = groupTerminals.first {
                targetGlobalIndex = firstInGroup.offset
            } else {
                return false
            }
        } else {
            targetGlobalIndex = groupTerminals[targetIndex].offset
        }

        if sourceGlobalIndex == targetGlobalIndex { return false }

        let state = terminalStates.remove(at: sourceGlobalIndex)
        let adjustedTarget = sourceGlobalIndex < targetGlobalIndex ? targetGlobalIndex - 1 : targetGlobalIndex
        terminalStates.insert(state, at: adjustedTarget)

        return true
    }

    func moveGroup(name: String, toIndex targetIndex: Int) -> Bool {
        let groups = buildProjectGroups()
        guard let sourceIndex = groups.firstIndex(where: { $0.name == name }) else { return false }
        if sourceIndex == targetIndex || sourceIndex == targetIndex - 1 { return false }

        let groupTerminals = terminalStates.filter { $0.projectName == name }
        if groupTerminals.isEmpty { return false }

        terminalStates.removeAll { $0.projectName == name }

        var insertIndex: Int
        if targetIndex <= 0 {
            insertIndex = 0
        } else if targetIndex >= groups.count {
            insertIndex = terminalStates.count
        } else {
            let targetGroupName = groups[targetIndex].name
            if let firstOfTarget = terminalStates.firstIndex(where: { $0.projectName == targetGroupName }) {
                insertIndex = firstOfTarget
            } else {
                insertIndex = terminalStates.count
            }
        }

        for (i, terminal) in groupTerminals.enumerated() {
            terminalStates.insert(terminal, at: insertIndex + i)
        }

        return true
    }

    // MARK: - UI

    func showSelectedTerminal() {
        for subview in terminalContainer.subviews {
            subview.removeFromSuperview()
        }

        if let state = getSelectedTerminal() {
            state.terminalView.frame = terminalContainer.bounds
            state.terminalView.autoresizingMask = [.width, .height]
            terminalContainer.addSubview(state.terminalView)
            window.makeFirstResponder(state.terminalView)
        }
    }

    func newTab() {
        let currentDir = getSelectedTerminal()?.currentDirectory
        let state = createTerminal(directory: currentDir)
        selectTerminal(id: state.id)
        treeView.reloadTerminals()
        showSelectedTerminal()
    }

    func closeCurrentTerminal() {
        guard let id = selectedTerminalId else { return }
        removeTerminal(id: id)
        if !terminalStates.isEmpty {
            treeView.reloadTerminals()
            showSelectedTerminal()
        }
    }

    // MARK: - Key Handling

    func handleKeyEvent(_ event: NSEvent) -> Bool {
        guard event.modifierFlags.contains(.command) else {
            return false
        }

        // Cmd+Shift+上下矢印: グループ間移動
        if event.modifierFlags.contains(.shift) {
            if event.keyCode == 126 { // Up
                selectPreviousGroup()
                return true
            } else if event.keyCode == 125 { // Down
                selectNextGroup()
                return true
            }
        }

        // Cmd+上下矢印: ターミナル間移動
        if event.keyCode == 126 { // Up
            selectPreviousTerminal()
            return true
        } else if event.keyCode == 125 { // Down
            selectNextTerminal()
            return true
        }

        // Cmd+数字: 2ストローク選択
        guard let number = numberFromEvent(event) else {
            return false
        }

        if let pending = pendingGroupIndex {
            selectTerminalInGroup(groupIndex: pending, terminalIndex: number - 1)
            cancelPendingSelection()
            return true
        }

        pendingGroupIndex = number - 1
        pendingTimer?.invalidate()
        pendingTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { [weak self] _ in
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

    func selectPreviousTerminal() {
        guard let currentId = selectedTerminalId,
              let currentIndex = terminalStates.firstIndex(where: { $0.id == currentId }) else { return }
        let newIndex = currentIndex > 0 ? currentIndex - 1 : terminalStates.count - 1
        selectTerminal(id: terminalStates[newIndex].id)
        treeView.reloadTerminals()
        showSelectedTerminal()
    }

    func selectNextTerminal() {
        guard let currentId = selectedTerminalId,
              let currentIndex = terminalStates.firstIndex(where: { $0.id == currentId }) else { return }
        let newIndex = (currentIndex + 1) % terminalStates.count
        selectTerminal(id: terminalStates[newIndex].id)
        treeView.reloadTerminals()
        showSelectedTerminal()
    }

    func selectPreviousGroup() {
        let groups = buildProjectGroups()
        guard groups.count > 1 else { return }
        guard let currentId = selectedTerminalId else { return }

        var currentGroupIndex = 0
        for (i, group) in groups.enumerated() {
            if group.terminalIds.contains(currentId) {
                currentGroupIndex = i
                break
            }
        }

        let newGroupIndex = currentGroupIndex > 0 ? currentGroupIndex - 1 : groups.count - 1
        if let terminalId = getLastSelectedInGroup(groupIndex: newGroupIndex) {
            selectTerminal(id: terminalId)
            treeView.reloadTerminals()
            showSelectedTerminal()
        }
    }

    func selectNextGroup() {
        let groups = buildProjectGroups()
        guard groups.count > 1 else { return }
        guard let currentId = selectedTerminalId else { return }

        var currentGroupIndex = 0
        for (i, group) in groups.enumerated() {
            if group.terminalIds.contains(currentId) {
                currentGroupIndex = i
                break
            }
        }

        let newGroupIndex = (currentGroupIndex + 1) % groups.count
        if let terminalId = getLastSelectedInGroup(groupIndex: newGroupIndex) {
            selectTerminal(id: terminalId)
            treeView.reloadTerminals()
            showSelectedTerminal()
        }
    }

    // MARK: - NSSplitViewDelegate

    func splitView(_ splitView: NSSplitView, constrainMinCoordinate proposedMinimumPosition: CGFloat, ofSubviewAt dividerIndex: Int) -> CGFloat {
        return 150
    }

    func splitView(_ splitView: NSSplitView, constrainMaxCoordinate proposedMaximumPosition: CGFloat, ofSubviewAt dividerIndex: Int) -> CGFloat {
        return splitView.bounds.width - 400
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
            var path = directory
            if let dir = directory, let url = URL(string: dir) {
                path = url.path
            }
            updateTerminalDirectory(id: state.id, directory: path)
        }
    }

    func processTerminated(source: TerminalView, exitCode: Int32?) {
        if let state = terminalStates.first(where: { $0.terminalView === source }) {
            removeTerminal(id: state.id)
            if terminalStates.isEmpty {
                window.close()
            } else {
                treeView.reloadTerminals()
                showSelectedTerminal()
            }
        }
    }
}
