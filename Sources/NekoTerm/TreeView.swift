import AppKit

class TreeView: NSTableView, NSTableViewDataSource, NSTableViewDelegate {
    var onSelectionChanged: ((UUID) -> Void)?

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
        column.width = 180
        addTableColumn(column)

        headerView = nil
        backgroundColor = NSColor(white: 0.1, alpha: 1.0)
        rowHeight = 30
        selectionHighlightStyle = .regular
        allowsEmptySelection = false
    }

    func reloadTerminals() {
        reloadData()
        if let id = selectedTerminalId,
           let index = terminalStates.firstIndex(where: { $0.id == id }) {
            selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
        }
    }

    // MARK: - NSTableViewDataSource

    func numberOfRows(in tableView: NSTableView) -> Int {
        return terminalStates.count
    }

    // MARK: - NSTableViewDelegate

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let state = terminalStates[row]

        let cellView = NSTableCellView()
        cellView.identifier = NSUserInterfaceItemIdentifier("cell")

        let textField = NSTextField(labelWithString: "")
        textField.font = NSFont.systemFont(ofSize: 12)
        textField.textColor = .white
        textField.lineBreakMode = .byTruncatingTail
        textField.translatesAutoresizingMaskIntoConstraints = false
        cellView.addSubview(textField)
        cellView.textField = textField

        NSLayoutConstraint.activate([
            textField.leadingAnchor.constraint(equalTo: cellView.leadingAnchor, constant: 8),
            textField.trailingAnchor.constraint(equalTo: cellView.trailingAnchor, constant: -8),
            textField.centerYAnchor.constraint(equalTo: cellView.centerYAnchor)
        ])

        let displayTitle = state.title.isEmpty ? "Terminal" : state.title
        textField.stringValue = "\(row + 1). \(displayTitle)"

        return cellView
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        let row = selectedRow
        guard row >= 0, row < terminalStates.count else { return }
        let state = terminalStates[row]
        onSelectionChanged?(state.id)
    }
}
