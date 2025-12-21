import AppKit
import SwiftTerm

let previewRows = 5

// プロセス名キャッシュ
var processNameCache: [UUID: (name: String?, pgid: pid_t, time: Date)] = [:]

// フォアグラウンドプロセス名を取得（キャッシュ付き）
func getForegroundProcessName(for terminalView: LocalProcessTerminalView, terminalId: UUID) -> String? {
    let shellPid = terminalView.process.shellPid
    guard shellPid > 0 else { return nil }

    // シェルのfdからフォアグラウンドプロセスグループを取得
    let fd = terminalView.process.childfd
    let foregroundPgid = tcgetpgrp(fd)
    guard foregroundPgid > 0 else { return nil }

    // キャッシュをチェック（同じpgidなら1秒間有効）
    if let cached = processNameCache[terminalId],
       cached.pgid == foregroundPgid,
       Date().timeIntervalSince(cached.time) < 1.0 {
        return cached.name
    }

    // プロセス名を取得 (psコマンドを使用)
    let pipe = Pipe()
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/ps")
    process.arguments = ["-p", "\(foregroundPgid)", "-o", "comm="]
    process.standardOutput = pipe
    process.standardError = FileHandle.nullDevice

    do {
        try process.run()
        process.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        if let name = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) {
            let shortName = (name as NSString).lastPathComponent
            processNameCache[terminalId] = (shortName, foregroundPgid, Date())
            return shortName
        }
    } catch {
        processNameCache[terminalId] = (nil, foregroundPgid, Date())
        return nil
    }
    processNameCache[terminalId] = (nil, foregroundPgid, Date())
    return nil
}
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

// 更新からの経過時間に応じてヒントの色を計算（20秒以内なら緑、それ以降は灰色）
func getHintColor(elapsedTime: TimeInterval) -> NSColor {
    let activeDuration: TimeInterval = 20
    if elapsedTime < activeDuration {
        // 20秒以内: 明るい緑
        return NSColor(red: 0.2, green: 0.8, blue: 0.2, alpha: 1.0)
    } else {
        // 20秒以上経過: 灰色
        return NSColor(white: 0.5, alpha: 1.0)
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

let terminalPasteboardType = NSPasteboard.PasteboardType("com.nekoterm.terminal")
let groupPasteboardType = NSPasteboard.PasteboardType("com.nekoterm.group")

class TreeView: NSOutlineView, NSOutlineViewDataSource, NSOutlineViewDelegate {
    var onSelectionChanged: ((UUID) -> Void)?
    var refreshTimer: Timer?
    var isRefreshing = false
    var projectGroups: [ProjectGroup] = []
    var draggedTerminalId: UUID?
    var draggedGroupName: String?
    weak var windowController: WindowController?

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
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.refreshPreview()
        }
    }

    func refreshPreview() {
        guard let wc = windowController else { return }

        // グループ構成が変わった場合のみフルリロード
        let newGroups = wc.buildProjectGroups()
        let needsFullReload = projectGroups.count != newGroups.count ||
            zip(projectGroups, newGroups).contains { $0.name != $1.name || $0.terminalIds != $1.terminalIds }

        if needsFullReload {
            isRefreshing = true
            projectGroups = newGroups
            reloadData()
            expandAllGroups()
            selectCurrentTerminal()
            isRefreshing = false
        } else {
            // 表示中の行だけ更新
            let visibleRows = rows(in: visibleRect)
            reloadData(forRowIndexes: IndexSet(integersIn: visibleRows.location..<visibleRows.location + visibleRows.length),
                       columnIndexes: IndexSet(integer: 0))
        }
    }

    func reloadTerminals() {
        guard let wc = windowController else { return }
        isRefreshing = true
        projectGroups = wc.buildProjectGroups()
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
        guard let id = windowController?.selectedTerminalId else { return }
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
            guard let wc = windowController,
                  let draggedState = wc.terminalStates.first(where: { $0.id == draggedId }) else { return [] }
            if draggedState.projectName != targetGroup.name { return [] }

            if index >= 0 {
                return .move
            }
        }

        return []
    }

    func outlineView(_ outlineView: NSOutlineView, acceptDrop info: NSDraggingInfo, item: Any?, childIndex index: Int) -> Bool {
        guard let wc = windowController else { return false }

        // グループのドロップ
        if let draggedGroup = draggedGroupName {
            if item == nil && index >= 0 {
                let result = wc.moveGroup(name: draggedGroup, toIndex: index)
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
            let result = wc.moveTerminal(id: draggedId, toIndex: index, inGroup: targetGroup.name)
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
            let groupIndex = projectGroups.firstIndex(where: { $0.name == group.name }) ?? 0
            return makeGroupView(group, index: groupIndex)
        }
        if let terminalId = item as? UUID,
           let wc = windowController,
           let state = wc.terminalStates.first(where: { $0.id == terminalId }) {
            // グループ内でのインデックスを取得
            if let group = projectGroups.first(where: { $0.terminalIds.contains(terminalId) }),
               let terminalIndex = group.terminalIds.firstIndex(of: terminalId) {
                return makeTerminalView(state, index: terminalIndex)
            }
            return makeTerminalView(state, index: 0)
        }
        return nil
    }

    func makeGroupView(_ group: ProjectGroup, index: Int) -> NSView {
        let cellView = NSTableCellView()

        // タイトル（左側）
        let titleText: String
        if group.name == "~" {
            titleText = "~"
        } else {
            titleText = "~/\(group.name)"
        }

        let titleLabel = NSTextField(labelWithString: titleText)
        titleLabel.font = NSFont.systemFont(ofSize: 12, weight: .bold)
        titleLabel.textColor = NSColor(white: 0.7, alpha: 1.0)
        titleLabel.drawsBackground = false
        titleLabel.isBordered = false
        titleLabel.isEditable = false
        titleLabel.isSelectable = false
        titleLabel.frame = NSRect(x: 8, y: 0, width: 150, height: 24)
        cellView.addSubview(titleLabel)

        // ヒント（右端に表示）
        if index < 9 {
            let hintLabel = NSTextField(labelWithString: "⌘\(index + 1)")
            hintLabel.font = NSFont.systemFont(ofSize: 10)
            hintLabel.textColor = NSColor(white: 0.5, alpha: 1.0)
            hintLabel.drawsBackground = false
            hintLabel.isBordered = false
            hintLabel.isEditable = false
            hintLabel.isSelectable = false
            hintLabel.alignment = .right
            hintLabel.sizeToFit()
            // 列幅を取得して右端に配置
            let columnWidth = outlineTableColumn?.width ?? 280
            hintLabel.frame = NSRect(x: columnWidth - hintLabel.frame.width - 80, y: 4, width: hintLabel.frame.width, height: 16)
            cellView.addSubview(hintLabel)
        }

        return cellView
    }

    func makeTerminalView(_ state: TerminalState, index: Int) -> NSView {
        let cellView = BackgroundView()
        let cellHeight = CGFloat(previewRows * 12 + 8)

        // 現在選択中か、グループ内で最後に選択されたターミナルか
        let isCurrentlySelected = windowController?.selectedTerminalId == state.id
        let isLastSelectedInGroup = windowController?.lastSelectedInGroup[state.projectName] == state.id

        if isCurrentlySelected {
            // 現在選択中: 明るい青
            cellView.backgroundColor = NSColor(red: 0.15, green: 0.25, blue: 0.4, alpha: 1.0)
        } else if isLastSelectedInGroup {
            // グループ内で最後に選択: 暗い青
            cellView.backgroundColor = NSColor(red: 0.08, green: 0.12, blue: 0.2, alpha: 1.0)
        }

        // プレビュー
        let previewLabel = NSTextField(labelWithString: "")
        previewLabel.backgroundColor = NSColor(white: 0.05, alpha: 1.0)
        previewLabel.drawsBackground = true
        previewLabel.isBordered = false
        previewLabel.isEditable = false
        previewLabel.maximumNumberOfLines = previewRows
        previewLabel.lineBreakMode = .byClipping
        previewLabel.frame = NSRect(x: 4, y: 4, width: 240, height: cellHeight - 8)
        previewLabel.autoresizingMask = [.width]
        cellView.addSubview(previewLabel)

        // 内容ハッシュを計算してlastActivityTimeを更新
        let processName = getForegroundProcessName(for: state.terminalView, terminalId: state.id)
        var hintColor: NSColor = NSColor(white: 0.5, alpha: 1.0)

        if let wc = windowController, let idx = wc.terminalStates.firstIndex(where: { $0.id == state.id }) {
            // 一時的にプレビューを取得してハッシュを計算
            let tempPreview = getTerminalPreview(state.terminalView, hintIndex: nil, processName: nil)
            let currentHash = tempPreview.string.hashValue
            let isSelected = wc.selectedTerminalId == state.id

            if let lastHash = wc.terminalStates[idx].lastContentHash {
                // 前回のハッシュがある場合: 変化があり、かつ選択中でなければ更新時刻を記録
                if lastHash != currentHash {
                    wc.terminalStates[idx].lastContentHash = currentHash
                    if !isSelected {
                        wc.terminalStates[idx].lastActivityTime = Date()
                    }
                }
            } else {
                // 初回チェック: ハッシュを記録するだけ（緑にしない）
                wc.terminalStates[idx].lastContentHash = currentHash
            }

            // 経過時間に応じてヒントの色を計算（選択中でなければ）
            if !isSelected {
                let elapsed = Date().timeIntervalSince(wc.terminalStates[idx].lastActivityTime)
                hintColor = getHintColor(elapsedTime: elapsed)
            }
        }

        // プレビュー内容を設定（プロセス名とヒント番号を1行目に）
        let preview = getTerminalPreview(state.terminalView, hintIndex: index < 9 ? index + 1 : nil, processName: processName, hintColor: hintColor)
        previewLabel.attributedStringValue = preview

        return cellView
    }

    func getTerminalPreview(_ terminalView: LocalProcessTerminalView, hintIndex: Int? = nil, processName: String? = nil, hintColor: NSColor? = nil) -> NSAttributedString {
        let terminal = terminalView.getTerminal()
        let buffer = terminal.buffer
        var lineAttrs: [NSAttributedString] = []
        let font = NSFont.monospacedSystemFont(ofSize: 9, weight: .regular)

        // ヘッダー行がある場合は1行少なく取得
        let hasHeader = processName != nil || hintIndex != nil
        let maxContentRows = hasHeader ? previewRows - 1 : previewRows

        // TerminalViewから実際のネイティブ色を取得
        let nativeFg = terminalView.nativeForegroundColor
        let nativeBg = terminalView.nativeBackgroundColor

        // 画面の最終行から上に遡って、最初にコンテンツがある行を見つける
        var lastContentRow = buffer.yDisp + terminal.rows - 1
        while lastContentRow >= buffer.yDisp {
            if let line = terminal.getLine(row: lastContentRow) {
                // 空白以外の表示可能な文字があるかチェック
                var hasContent = false
                for col in 0..<line.count {
                    let char = line[col].getCharacter()
                    if char != " " && char != "\u{0}" && !char.isWhitespace {
                        hasContent = true
                        break
                    }
                }
                if hasContent {
                    break
                }
            }
            lastContentRow -= 1
        }

        // コンテンツがある行から上にmaxContentRows行分を取得
        var row = lastContentRow
        while lineAttrs.count < maxContentRows && row >= buffer.yDisp {
            if let line = terminal.getLine(row: row) {
                // 空白以外の表示可能な文字があるかチェック
                var hasContent = false
                for col in 0..<line.count {
                    let char = line[col].getCharacter()
                    if char != " " && char != "\u{0}" && !char.isWhitespace {
                        hasContent = true
                        break
                    }
                }
                if hasContent {
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

        // 1行目: プロセス名（左）とヒント番号（右）
        if processName != nil || hintIndex != nil {
            let procName = processName ?? ""
            let hintStr = hintIndex != nil ? "[\(hintIndex!)]" : ""

            // プロセス名とヒントの間をスペースで埋める
            let totalLen = procName.count + hintStr.count
            let paddingCount = max(1, previewCols - totalLen - 5)
            let padding = String(repeating: " ", count: paddingCount)

            let headerLine = NSMutableAttributedString()
            // プロセス名（灰色）
            headerLine.append(NSAttributedString(
                string: procName + padding,
                attributes: [
                    .font: font,
                    .foregroundColor: NSColor(white: 0.5, alpha: 1.0)
                ]
            ))
            // ヒント番号（色は経過時間に応じて変化）
            if !hintStr.isEmpty {
                headerLine.append(NSAttributedString(
                    string: hintStr,
                    attributes: [
                        .font: font,
                        .foregroundColor: hintColor ?? NSColor(white: 0.5, alpha: 1.0)
                    ]
                ))
            }
            lineAttrs.insert(headerLine, at: 0)
        }

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
