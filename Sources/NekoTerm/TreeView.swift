import AppKit
import SwiftTerm

let previewRows = 5
let previewCols = 40

class TreeView: NSTableView, NSTableViewDataSource, NSTableViewDelegate {
    var onSelectionChanged: ((UUID) -> Void)?
    var refreshTimer: Timer?
    var isRefreshing = false

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

        headerView = nil
        backgroundColor = NSColor(white: 0.1, alpha: 1.0)
        rowHeight = CGFloat(previewRows * 14 + 24)
        selectionHighlightStyle = .regular
        allowsEmptySelection = false

        startRefreshTimer()
    }

    func startRefreshTimer() {
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.refreshPreview()
        }
    }

    func refreshPreview() {
        isRefreshing = true
        reloadData()
        if let id = selectedTerminalId,
           let index = terminalStates.firstIndex(where: { $0.id == id }) {
            selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
        }
        isRefreshing = false
    }

    func reloadTerminals() {
        isRefreshing = true
        reloadData()
        if let id = selectedTerminalId,
           let index = terminalStates.firstIndex(where: { $0.id == id }) {
            selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
        }
        isRefreshing = false
    }

    // MARK: - NSTableViewDataSource

    func numberOfRows(in tableView: NSTableView) -> Int {
        return terminalStates.count
    }

    // MARK: - NSTableViewDelegate

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let state = terminalStates[row]

        let cellView = NSView()

        // タイトル
        let titleLabel = NSTextField(labelWithString: "")
        titleLabel.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        titleLabel.textColor = .white
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        cellView.addSubview(titleLabel)

        let displayTitle = state.title.isEmpty ? "Terminal" : state.title
        titleLabel.stringValue = "\(row + 1). \(displayTitle)"

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
            titleLabel.leadingAnchor.constraint(equalTo: cellView.leadingAnchor, constant: 8),
            titleLabel.trailingAnchor.constraint(equalTo: cellView.trailingAnchor, constant: -8),
            titleLabel.topAnchor.constraint(equalTo: cellView.topAnchor, constant: 4),

            previewLabel.leadingAnchor.constraint(equalTo: cellView.leadingAnchor, constant: 8),
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

        // カーソル位置（最終行）とその上の4行を表示
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

    func tableViewSelectionDidChange(_ notification: Notification) {
        guard !isRefreshing else { return }
        let row = selectedRow
        guard row >= 0, row < terminalStates.count else { return }
        let state = terminalStates[row]
        onSelectionChanged?(state.id)
    }
}
