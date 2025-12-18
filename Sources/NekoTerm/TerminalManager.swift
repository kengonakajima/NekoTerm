import AppKit
import SwiftTerm

struct TerminalState {
    let id: UUID
    let terminalView: LocalProcessTerminalView
    var currentDirectory: String?
    var title: String
    var projectName: String
}

var terminalStates: [TerminalState] = []
var selectedTerminalId: UUID?
var lastSelectedInGroup: [String: UUID] = [:]  // projectName -> last selected terminal id

func createTerminal(delegate: LocalProcessTerminalViewDelegate) -> TerminalState {
    let terminalView = LocalProcessTerminalView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
    terminalView.processDelegate = delegate

    let shell = getShell()
    let shellIdiom = "-" + (shell as NSString).lastPathComponent
    FileManager.default.changeCurrentDirectoryPath(FileManager.default.homeDirectoryForCurrentUser.path)
    terminalView.startProcess(executable: shell, execName: shellIdiom)

    let state = TerminalState(
        id: UUID(),
        terminalView: terminalView,
        currentDirectory: nil,
        title: "Terminal",
        projectName: "~"
    )
    terminalStates.append(state)
    return state
}

func getShell() -> String {
    let bufsize = sysconf(_SC_GETPW_R_SIZE_MAX)
    guard bufsize != -1 else { return "/bin/zsh" }
    let buffer = UnsafeMutablePointer<Int8>.allocate(capacity: bufsize)
    defer { buffer.deallocate() }
    var pwd = passwd()
    var result: UnsafeMutablePointer<passwd>? = UnsafeMutablePointer<passwd>.allocate(capacity: 1)
    if getpwuid_r(getuid(), &pwd, buffer, bufsize, &result) != 0 {
        return "/bin/zsh"
    }
    return String(cString: pwd.pw_shell)
}

func selectTerminal(id: UUID) {
    selectedTerminalId = id
    // グループ内の最後の選択を記録
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

func getLastSelectedInGroup(groupIndex: Int) -> UUID? {
    let groups = buildProjectGroups()
    guard groupIndex < groups.count else { return nil }
    let group = groups[groupIndex]
    // このグループで最後に選択したターミナルがあればそれを返す
    if let lastId = lastSelectedInGroup[group.name],
       group.terminalIds.contains(lastId) {
        return lastId
    }
    // なければグループの最初のターミナルを返す
    return group.terminalIds.first
}
