import Foundation

func killChild(in file: URL) {
    if let text = try? String(contentsOf: file, encoding: .utf8),
       let pid = Int32(text.trimmingCharacters(in: .whitespacesAndNewlines)) {
        kill(pid, SIGKILL)
    }
    try? FileManager.default.removeItem(at: file)
}
