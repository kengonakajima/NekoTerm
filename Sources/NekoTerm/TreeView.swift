import AppKit
import SwiftTerm

let previewRows = 5
let previewCols = 40

// 背景色を描画できるNSView
class BackgroundView: NSView {
    var backgroundColor: NSColor?

    override func draw(_ dirtyRect: NSRect) {
        if let color = backgroundColor {
            color.setFill()
            dirtyRect.fill()
        }
        super.draw(dirtyRect)
    }
}

// プロジェクトグループを表すクラス
class ProjectGroup {
    let name: String
    var terminalIds: [UUID] = []

    init(name: String) {
        self.name = name
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

let terminalPasteboardType = NSPasteboard.PasteboardType("com.nekoterm.terminal")
let groupPasteboardType = NSPasteboard.PasteboardType("com.nekoterm.group")

class TreeView: NSOutlineView, NSOutlineViewDataSource, NSOutlineViewDelegate {
    var onSelectionChanged: ((UUID) -> Void)?
    var refreshTimer: Timer?
    var isRefreshing = false
    var projectGroups: [ProjectGroup] = []
    var draggedTerminalId: UUID?
    var draggedGroupName: String?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    override var acceptsFirstResponder: Bool {
        return false
    }

    func setup() {
        dataSource = self
        delegate = self

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("terminal"))
        column.title = ""
        column.width = 280
        addTableColumn(column)
        outlineTableColumn = column

        headerView = nil
        backgroundColor = NSColor(white: 0.1, alpha: 1.0)
        selectionHighlightStyle = .regular
        allowsEmptySelection = false
        indentationPerLevel = 0

        // ドラッグ&ドロップ設定
        registerForDraggedTypes([terminalPasteboardType, groupPasteboardType])
        setDraggingSourceOperationMask(.move, forLocal: true)

        startRefreshTimer()
    }

    func startRefreshTimer() {
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.refreshPreview()
        }
    }

    func refreshPreview() {
        isRefreshing = true
        projectGroups = buildProjectGroups()
        reloadData()
        expandAllGroups()
        selectCurrentTerminal()
        isRefreshing = false
    }

    func reloadTerminals() {
        isRefreshing = true
        projectGroups = buildProjectGroups()
        reloadData()
        expandAllGroups()
        selectCurrentTerminal()
        isRefreshing = false
    }

    func expandAllGroups() {
        for group in projectGroups {
            expandItem(group)
        }
    }

    func selectCurrentTerminal() {
        guard let id = selectedTerminalId else { return }
        let row = self.row(forItem: id)
        if row >= 0 {
            selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        }
    }

    // MARK: - NSOutlineViewDataSource

    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        if item == nil {
            return projectGroups.count
        }
        if let group = item as? ProjectGroup {
            return group.terminalIds.count
        }
        return 0
    }

    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        if item == nil {
            return projectGroups[index]
        }
        if let group = item as? ProjectGroup {
            return group.terminalIds[index]
        }
        return ""
    }

    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        return item is ProjectGroup
    }

    // MARK: - Drag & Drop

    func outlineView(_ outlineView: NSOutlineView, pasteboardWriterForItem item: Any) -> NSPasteboardWriting? {
        let pasteboardItem = NSPasteboardItem()

        // グループのドラッグ
        if let group = item as? ProjectGroup {
            draggedGroupName = group.name
            draggedTerminalId = nil
            pasteboardItem.setString(group.name, forType: groupPasteboardType)
            return pasteboardItem
        }

        // ターミナルのドラッグ
        if let terminalId = item as? UUID {
            draggedTerminalId = terminalId
            draggedGroupName = nil
            pasteboardItem.setString(terminalId.uuidString, forType: terminalPasteboardType)
            return pasteboardItem
        }

        return nil
    }

    func outlineView(_ outlineView: NSOutlineView, validateDrop info: NSDraggingInfo, proposedItem item: Any?, proposedChildIndex index: Int) -> NSDragOperation {
        // グループのドラッグ
        if draggedGroupName != nil {
            // ルートレベル（item == nil）へのドロップのみ許可
            if item == nil && index >= 0 {
                return .move
            }
            return []
        }

        // ターミナルのドラッグ
        if let draggedId = draggedTerminalId {
            // ドロップ先がグループの場合のみ許可
            guard let targetGroup = item as? ProjectGroup else { return [] }

            // 同じグループ内でのみ移動を許可
            guard let draggedState = terminalStates.first(where: { $0.id == draggedId }) else { return [] }
            if draggedState.projectName != targetGroup.name { return [] }

            if index >= 0 {
                return .move
            }
        }

        return []
    }

    func outlineView(_ outlineView: NSOutlineView, acceptDrop info: NSDraggingInfo, item: Any?, childIndex index: Int) -> Bool {
        // グループのドロップ
        if let draggedGroup = draggedGroupName {
            if item == nil && index >= 0 {
                let result = moveGroup(name: draggedGroup, toIndex: index)
                draggedGroupName = nil
                if result {
                    reloadTerminals()
                }
                return result
            }
            return false
        }

        // ターミナルのドロップ
        if let draggedId = draggedTerminalId,
           let targetGroup = item as? ProjectGroup,
           index >= 0 {
            let result = moveTerminal(id: draggedId, toIndex: index, inGroup: targetGroup.name)
            draggedTerminalId = nil
            if result {
                reloadTerminals()
            }
            return result
        }

        return false
    }

    func outlineView(_ outlineView: NSOutlineView, draggingSession session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        draggedTerminalId = nil
        draggedGroupName = nil
    }

    // MARK: - NSOutlineViewDelegate

    func outlineView(_ outlineView: NSOutlineView, heightOfRowByItem item: Any) -> CGFloat {
        if item is ProjectGroup {
            return 24
        }
        return CGFloat(previewRows * 12 + 8)
    }

    func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        if let group = item as? ProjectGroup {
            return makeGroupView(group)
        }
        if let terminalId = item as? UUID,
           let state = terminalStates.first(where: { $0.id == terminalId }) {
            return makeTerminalView(state)
        }
        return nil
    }

    func makeGroupView(_ group: ProjectGroup) -> NSView {
        let cellView = NSView()

        let titleLabel = NSTextField(labelWithString: "")
        titleLabel.font = NSFont.systemFont(ofSize: 12, weight: .bold)
        titleLabel.textColor = NSColor(white: 0.7, alpha: 1.0)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        cellView.addSubview(titleLabel)

        if group.name == "~" {
            titleLabel.stringValue = "~"
        } else {
            titleLabel.stringValue = "~/\(group.name)"
        }

        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: cellView.leadingAnchor, constant: 8),
            titleLabel.trailingAnchor.constraint(equalTo: cellView.trailingAnchor, constant: -8),
            titleLabel.centerYAnchor.constraint(equalTo: cellView.centerYAnchor)
        ])

        return cellView
    }

    func makeTerminalView(_ state: TerminalState) -> NSView {
        let cellView = BackgroundView()

        // 現在選択中か、グループ内で最後に選択されたターミナルか
        let isCurrentlySelected = selectedTerminalId == state.id
        let isLastSelectedInGroup = lastSelectedInGroup[state.projectName] == state.id

        if isCurrentlySelected {
            // 現在選択中: 明るい青
            cellView.backgroundColor = NSColor(red: 0.15, green: 0.25, blue: 0.4, alpha: 1.0)
        } else if isLastSelectedInGroup {
            // グループ内で最後に選択: 暗い青
            cellView.backgroundColor = NSColor(red: 0.08, green: 0.12, blue: 0.2, alpha: 1.0)
        }

        // プレビューのみ
        let previewLabel = NSTextField(labelWithString: "")
        previewLabel.font = NSFont.monospacedSystemFont(ofSize: 9, weight: .regular)
        previewLabel.textColor = NSColor(white: 0.8, alpha: 1.0)
        previewLabel.backgroundColor = NSColor(white: 0.05, alpha: 1.0)
        previewLabel.drawsBackground = true
        previewLabel.isBordered = false
        previewLabel.isEditable = false
        previewLabel.maximumNumberOfLines = previewRows
        previewLabel.lineBreakMode = .byClipping
        previewLabel.translatesAutoresizingMaskIntoConstraints = false
        cellView.addSubview(previewLabel)

        previewLabel.stringValue = getTerminalPreview(state.terminalView)

        NSLayoutConstraint.activate([
            previewLabel.leadingAnchor.constraint(equalTo: cellView.leadingAnchor, constant: 16),
            previewLabel.trailingAnchor.constraint(equalTo: cellView.trailingAnchor, constant: -8),
            previewLabel.topAnchor.constraint(equalTo: cellView.topAnchor, constant: 4),
            previewLabel.bottomAnchor.constraint(equalTo: cellView.bottomAnchor, constant: -4)
        ])

        return cellView
    }

    func getTerminalPreview(_ terminalView: LocalProcessTerminalView) -> String {
        let terminal = terminalView.getTerminal()
        let buffer = terminal.buffer
        var lines: [String] = []

        // カーソル位置から上に遡って、コンテンツがある行を5行分取得
        var row = buffer.y
        while lines.count < previewRows && row >= 0 {
            if let line = terminal.getLine(row: row) {
                var text = line.translateToString(trimRight: true)
                if !text.isEmpty {
                    if text.count > previewCols {
                        text = String(text.prefix(previewCols))
                    }
                    lines.insert(text, at: 0)
                }
            }
            row -= 1
        }

        return lines.joined(separator: "\n")
    }

    func outlineViewSelectionDidChange(_ notification: Notification) {
        guard !isRefreshing else { return }
        let row = selectedRow
        guard row >= 0 else { return }
        let item = self.item(atRow: row)
        if let terminalId = item as? UUID {
            onSelectionChanged?(terminalId)
        }
    }
}
