import Foundation
#if canImport(Darwin)
import Darwin
#endif

final class LiveReloadManager {
    #if canImport(Darwin)
    private var source: DispatchSourceFileSystemObject?
    private var fileDescriptor: CInt = -1
    #endif

    var onChange: (() -> Void)?

    func startWatching(directory: URL) {
        #if canImport(Darwin)
        stopWatching()

        fileDescriptor = open(directory.path, O_EVTONLY)
        guard fileDescriptor >= 0 else { return }

        let queue = DispatchQueue(label: "swiftcode.local-simulation.live-reload")
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

    func stopWatching() {
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
