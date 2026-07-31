import Foundation
#if canImport(Darwin)
import Darwin
#endif

public final class PreviewLiveReloadManager {
    #if canImport(Darwin)
    private var source: DispatchSourceFileSystemObject?
    private var fileDescriptor: CInt = -1
    #endif

    public var onChange: (() -> Void)?

    public init() {}

    public func startWatching(directory: URL) {
        #if canImport(Darwin)
        stopWatching()

        fileDescriptor = open(directory.path, O_EVTONLY)
        guard fileDescriptor >= 0 else { return }

        let queue = DispatchQueue(label: "swiftcode.preview.live-reload")
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fileDescriptor,
            eventMask: [.write, .extend, .rename, .delete],
            queue: queue
        )

        source.setEventHandler { [weak self] in
            self?.onChange?()
        }

        source.setCancelHandler { [weak self] in
            guard let self else { return }
            if self.fileDescriptor >= 0 {
                close(self.fileDescriptor)
                self.fileDescriptor = -1
            }
        }

        self.source = source
        source.resume()
        #else
        _ = directory
        #endif
    }

    public func stopWatching() {
        #if canImport(Darwin)
        source?.cancel()
        source = nil
        if fileDescriptor >= 0 {
            close(fileDescriptor)
            fileDescriptor = -1
        }
        #endif
    }
}
