import AppKit
import SwiftTerm

let previewRows = 5
let previewCols = 40

// ANSI 256 color palette
let ansi256Colors: [NSColor] = {
    var colors: [NSColor] = []

    // Basic 16 colors (xterm style)
    let basic: [(CGFloat, CGFloat, CGFloat)] = [
        (0, 0, 0), (205, 0, 0), (0, 205, 0), (205, 205, 0),
        (0, 0, 238), (205, 0, 205), (0, 205, 205), (229, 229, 229),
        (127, 127, 127), (255, 0, 0), (0, 255, 0), (255, 255, 0),
        (92, 92, 255), (255, 0, 255), (0, 255, 255), (255, 255, 255)
    ]
    for (r, g, b) in basic {
        colors.append(NSColor(red: r/255, green: g/255, blue: b/255, alpha: 1))
    }

    // 216 colors (6x6x6 cube)
    let v: [CGFloat] = [0, 95, 135, 175, 215, 255]
    for i in 0..<216 {
        let r = v[(i / 36) % 6]
        let g = v[(i / 6) % 6]
        let b = v[i % 6]
        colors.append(NSColor(red: r/255, green: g/255, blue: b/255, alpha: 1))
    }

    // 24 greyscales
    for i in 0..<24 {
        let c = CGFloat(8 + i * 10) / 255
        colors.append(NSColor(red: c, green: c, blue: c, alpha: 1))
    }

    return colors
}()

func mapAttributeColor(_ color: Attribute.Color, isForeground: Bool, nativeFg: NSColor, nativeBg: NSColor) -> NSColor {
    switch color {
    case .defaultColor:
        return isForeground ? nativeFg : nativeBg
    case .defaultInvertedColor:
        return isForeground ? nativeBg : nativeFg
    case .ansi256(let code):
        return ansi256Colors[Int(code) % 256]
    case .trueColor(let r, let g, let b):
        return NSColor(red: CGFloat(r)/255, green: CGFloat(g)/255, blue: CGFloat(b)/255, alpha: 1)
    }
}

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
        previewLabel.backgroundColor = NSColor(white: 0.05, alpha: 1.0)
        previewLabel.drawsBackground = true
        previewLabel.isBordered = false
        previewLabel.isEditable = false
        previewLabel.maximumNumberOfLines = previewRows
        previewLabel.lineBreakMode = .byClipping
        previewLabel.translatesAutoresizingMaskIntoConstraints = false
        cellView.addSubview(previewLabel)

        previewLabel.attributedStringValue = getTerminalPreview(state.terminalView)

        NSLayoutConstraint.activate([
            previewLabel.leadingAnchor.constraint(equalTo: cellView.leadingAnchor, constant: 16),
            previewLabel.trailingAnchor.constraint(equalTo: cellView.trailingAnchor, constant: -8),
            previewLabel.topAnchor.constraint(equalTo: cellView.topAnchor, constant: 4),
            previewLabel.bottomAnchor.constraint(equalTo: cellView.bottomAnchor, constant: -4)
        ])

        return cellView
    }

    func getTerminalPreview(_ terminalView: LocalProcessTerminalView) -> NSAttributedString {
        let terminal = terminalView.getTerminal()
        let buffer = terminal.buffer
        var lineAttrs: [NSAttributedString] = []
        let font = NSFont.monospacedSystemFont(ofSize: 9, weight: .regular)

        // TerminalViewから実際のネイティブ色を取得
        let nativeFg = terminalView.nativeForegroundColor
        let nativeBg = terminalView.nativeBackgroundColor

        // カーソル位置から上に遡って、コンテンツがある行を5行分取得
        var row = buffer.y
        while lineAttrs.count < previewRows && row >= 0 {
            if let line = terminal.getLine(row: row) {
                let text = line.translateToString(trimRight: true)
                if !text.isEmpty {
                    let attrStr = NSMutableAttributedString()
                    let cols = min(previewCols, line.count)

                    for col in 0..<cols {
                        let charData = line[col]
                        let char = charData.getCharacter()
                        if char == "\u{0}" { continue }

                        var fg = charData.attribute.fg
                        var bg = charData.attribute.bg
                        let style = charData.attribute.style

                        // Handle inverse mode
                        if style.contains(.inverse) {
                            swap(&fg, &bg)
                            if fg == .defaultColor { fg = .defaultInvertedColor }
                            if bg == .defaultColor { bg = .defaultInvertedColor }
                        }

                        let fgColor = mapAttributeColor(fg, isForeground: true, nativeFg: nativeFg, nativeBg: nativeBg)
                        let bgColor = mapAttributeColor(bg, isForeground: false, nativeFg: nativeFg, nativeBg: nativeBg)

                        let attrs: [NSAttributedString.Key: Any] = [
                            .font: font,
                            .foregroundColor: fgColor,
                            .backgroundColor: bgColor
                        ]
                        attrStr.append(NSAttributedString(string: String(char), attributes: attrs))
                    }

                    if attrStr.length > 0 {
                        lineAttrs.insert(attrStr, at: 0)
                    }
                }
            }
            row -= 1
        }

        let result = NSMutableAttributedString()
        for (i, lineAttr) in lineAttrs.enumerated() {
            result.append(lineAttr)
            if i < lineAttrs.count - 1 {
                result.append(NSAttributedString(string: "\n"))
            }
        }

        return result
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
