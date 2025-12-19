import AppKit
import SwiftTerm

class NekoTerminalView: LocalProcessTerminalView {
    static let urlPattern = try! NSRegularExpression(
        pattern: "https?://[^\\s<>\"'\\]\\)]+",
        options: .caseInsensitive
    )

    var urlUnderlineLayer: CAShapeLayer?
    var commandKeyDown = false
    var currentUrlRange: (row: Int, range: NSRange)?
    var lastMouseLocation: NSPoint?
    var isOverUrl = false

    override func cursorUpdate(with event: NSEvent) {
        if commandKeyDown && isOverUrl {
            NSCursor.pointingHand.set()
        } else {
            NSCursor.iBeam.set()
        }
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: commandKeyDown && isOverUrl ? .pointingHand : .iBeam)
    }

    override func mouseUp(with event: NSEvent) {
        // Cmd+クリックでURLを開く
        if event.modifierFlags.contains(.command) {
            if let url = detectUrlAtClick(event: event) {
                NSWorkspace.shared.open(url)
                return
            }
        }
        super.mouseUp(with: event)
    }

    override func flagsChanged(with event: NSEvent) {
        super.flagsChanged(with: event)
        if event.modifierFlags.contains(.command) {
            commandKeyDown = true
            if let location = lastMouseLocation {
                updateUrlUnderlineAtPoint(location)
            }
        } else {
            commandKeyDown = false
            isOverUrl = false
            removeUrlUnderline()
            window?.invalidateCursorRects(for: self)
        }
    }

    override func mouseMoved(with event: NSEvent) {
        lastMouseLocation = convert(event.locationInWindow, from: nil)
        super.mouseMoved(with: event)
        if commandKeyDown {
            updateUrlUnderlineAtPoint(lastMouseLocation!)
        }
    }

    func updateUrlUnderlineAtPoint(_ point: NSPoint) {
        let hit = calculateMouseHit(at: point)
        let row = hit.grid.row
        let col = hit.grid.col

        let buffer = terminal.buffer
        let absRow = buffer.yDisp + row
        guard let line = terminal.getLine(row: absRow) else {
            removeUrlUnderline()
            NSCursor.iBeam.set()
            return
        }

        let lineText = line.translateToString(trimRight: true)
        let nsLineText = lineText as NSString

        let matches = NekoTerminalView.urlPattern.matches(
            in: lineText,
            options: [],
            range: NSRange(location: 0, length: nsLineText.length)
        )

        // クリック位置を含むURLを探す
        for match in matches {
            let range = match.range
            if col >= range.location && col < range.location + range.length {
                drawUrlUnderline(row: row, range: range)
                isOverUrl = true
                window?.invalidateCursorRects(for: self)
                return
            }
        }

        removeUrlUnderline()
        isOverUrl = false
        window?.invalidateCursorRects(for: self)
    }

    func drawUrlUnderline(row: Int, range: NSRange) {
        // 同じURLなら再描画しない
        if let current = currentUrlRange, current.row == row, current.range == range {
            return
        }
        currentUrlRange = (row, range)

        removeUrlUnderline()

        let layer = CAShapeLayer()
        let cellWidth = cellDimension.width
        let cellHeight = cellDimension.height

        print("DEBUG: row=\(row), range.location=\(range.location), range.length=\(range.length)")
        print("DEBUG: cellWidth=\(cellWidth), cellHeight=\(cellHeight)")
        print("DEBUG: frame.height=\(frame.height)")

        let x = CGFloat(range.location) * cellWidth
        let y = frame.height - CGFloat(row + 1) * cellHeight
        let width = CGFloat(range.length) * cellWidth
        let underlineY = y + 2

        print("DEBUG: x=\(x), y=\(y), width=\(width), underlineY=\(underlineY)")

        let path = CGMutablePath()
        path.move(to: CGPoint(x: x, y: underlineY))
        path.addLine(to: CGPoint(x: x + width, y: underlineY))

        layer.path = path
        layer.strokeColor = NSColor(white: 0.7, alpha: 1.0).cgColor
        layer.lineWidth = 1.0

        self.wantsLayer = true
        self.layer?.addSublayer(layer)
        urlUnderlineLayer = layer
    }

    func removeUrlUnderline() {
        urlUnderlineLayer?.removeFromSuperlayer()
        urlUnderlineLayer = nil
        currentUrlRange = nil
    }

    func detectUrlAtClick(event: NSEvent) -> URL? {
        let point = convert(event.locationInWindow, from: nil)
        let hit = calculateMouseHit(at: point)
        let row = hit.grid.row
        let col = hit.grid.col

        let buffer = terminal.buffer
        let absRow = buffer.yDisp + row
        guard let line = terminal.getLine(row: absRow) else { return nil }

        let lineText = line.translateToString(trimRight: true)
        let nsLineText = lineText as NSString

        let matches = NekoTerminalView.urlPattern.matches(
            in: lineText,
            options: [],
            range: NSRange(location: 0, length: nsLineText.length)
        )

        for match in matches {
            let range = match.range
            if col >= range.location && col < range.location + range.length {
                let urlString = nsLineText.substring(with: range)
                return URL(string: urlString)
            }
        }

        return nil
    }
}
