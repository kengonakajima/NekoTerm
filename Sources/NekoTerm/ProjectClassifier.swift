import Foundation

func extractProjectName(from directory: String?) -> String {
    guard let dir = directory else { return "Unknown" }

    // file:// URL形式の場合
    if dir.hasPrefix("file://") {
        guard let url = URL(string: dir) else { return "Unknown" }
        return extractProjectNameFromPath(url.path)
    }

    // 通常のパス
    return extractProjectNameFromPath(dir)
}

func extractProjectNameFromPath(_ path: String) -> String {
    let home = FileManager.default.homeDirectoryForCurrentUser.path

    // ホームディレクトリ自体の場合
    if path == home {
        return "~"
    }

    // ホームディレクトリ配下の場合
    if path.hasPrefix(home + "/") {
        let relativePath = String(path.dropFirst(home.count + 1))
        let components = relativePath.split(separator: "/")
        if let first = components.first {
            return String(first)
        }
        return "~"
    }

    // ルート直下の場合
    if path.hasPrefix("/") {
        let components = path.split(separator: "/")
        if let first = components.first {
            return "/" + String(first)
        }
    }

    return "Unknown"
}
