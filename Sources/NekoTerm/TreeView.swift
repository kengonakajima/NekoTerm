import AppKit
import SwiftTerm

let previewRows = 5
let previewCols = 40

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

class TreeView: NSOutlineView, NSOutlineViewDataSource, NSOutlineViewDelegate {
    var onSelectionChanged: ((UUID) -> Void)?
    var refreshTimer: Timer?
    var isRefreshing = false
    var projectGroups: [ProjectGroup] = []

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
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

    // MARK: - NSOutlineViewDelegate

    func outlineView(_ outlineView: NSOutlineView, heightOfRowByItem item: Any) -> CGFloat {
        if item is ProjectGroup {
            return 24
        }
        return CGFloat(previewRows * 14 + 24)
    }

    func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        if let group = item as? ProjectGroup {
            return makeGroupView(group)
        }
        if let terminalId = item as? UUID,
           let state = terminalStates.first(where: { $0.id == terminalId }) {
            let index = projectGroups.first { $0.terminalIds.contains(terminalId) }?
                .terminalIds.firstIndex(of: terminalId) ?? 0
            return makeTerminalView(state, index: index)
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

        titleLabel.stringValue = "~/\(group.name)"

        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: cellView.leadingAnchor, constant: 8),
            titleLabel.trailingAnchor.constraint(equalTo: cellView.trailingAnchor, constant: -8),
            titleLabel.centerYAnchor.constraint(equalTo: cellView.centerYAnchor)
        ])

        return cellView
    }

    func makeTerminalView(_ state: TerminalState, index: Int) -> NSView {
        let cellView = NSView()

        // タイトル
        let titleLabel = NSTextField(labelWithString: "")
        titleLabel.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        titleLabel.textColor = .white
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        cellView.addSubview(titleLabel)

        let displayTitle = state.title.isEmpty ? "Terminal" : state.title
        titleLabel.stringValue = "\(index + 1). \(displayTitle)"

        // プレビュー
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
            titleLabel.leadingAnchor.constraint(equalTo: cellView.leadingAnchor, constant: 16),
            titleLabel.trailingAnchor.constraint(equalTo: cellView.trailingAnchor, constant: -8),
            titleLabel.topAnchor.constraint(equalTo: cellView.topAnchor, constant: 4),

            previewLabel.leadingAnchor.constraint(equalTo: cellView.leadingAnchor, constant: 16),
            previewLabel.trailingAnchor.constraint(equalTo: cellView.trailingAnchor, constant: -8),
            previewLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 2),
            previewLabel.bottomAnchor.constraint(equalTo: cellView.bottomAnchor, constant: -4)
        ])

        return cellView
    }

    func getTerminalPreview(_ terminalView: LocalProcessTerminalView) -> String {
        let terminal = terminalView.getTerminal()
        let buffer = terminal.buffer
        var lines: [String] = []

        let cursorRow = buffer.y
        let startRow = max(0, cursorRow - previewRows + 1)
        let endRow = cursorRow + 1

        for row in startRow..<endRow {
            if let line = terminal.getLine(row: row) {
                var text = line.translateToString(trimRight: true)
                if text.count > previewCols {
                    text = String(text.prefix(previewCols))
                }
                lines.append(text)
            }
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
