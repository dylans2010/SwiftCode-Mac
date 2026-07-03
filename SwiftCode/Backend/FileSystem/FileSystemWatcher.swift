import Foundation

public class FileSystemWatcher {
    private var source: DispatchSourceFileSystemObject?
    private let url: URL
    private let onChange: () -> Void

    public init(url: URL, onChange: @escaping () -> Void) {
        self.url = url
        self.onChange = onChange
    }

    public func start() {
        let descriptor = open(url.path, O_EVTONLY)
        guard descriptor >= 0 else { return }

        source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: descriptor, eventMask: .write, queue: .main)
        source?.setEventHandler { [weak self] in
            self?.onChange()
        }
        source?.setCancelHandler {
            close(descriptor)
        }
        source?.resume()
    }

    public func stop() {
        source?.cancel()
    }
}
