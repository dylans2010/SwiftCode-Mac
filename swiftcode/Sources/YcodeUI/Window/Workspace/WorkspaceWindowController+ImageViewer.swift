import AppKit
import YcodeIDECore

extension WorkspaceWindowController {
    public var imageViewer: ImageViewerController? {
        get { imageViewerBox.controller }
        set {
            imageViewerBox.controller = newValue
            imageViewerBox.pending = nil
        }
    }

    public var pendingImageViewer: ImageViewerController? { imageViewerBox.pending }

    func showImage(_ url: URL) {
        if let shown = imageViewer, OpenRequestKey.path(shown.url) == OpenRequestKey.path(url),
           editor.auxiliaryFile.map(OpenRequestKey.path) == OpenRequestKey.path(url) { return }
        if let pending = imageViewerBox.pending, OpenRequestKey.path(pending.url) == OpenRequestKey.path(url) { return }
        let c = ImageViewerController(url: url)
        c.onLoaded = { [weak self, weak c] props in
            guard let self, let c, self.imageViewer === c else { return }
            self.inspector.imageProperties = props
        }
        if c.isReady {
            swapIn(c)
            return
        }
        imageViewerBox.pending = c
        c.onReady = { [weak self, weak c] in
            guard let self, let c, self.imageViewerBox.pending === c else { return }
            self.swapIn(c)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + ImageViewerLayout.loadingDelay) { [weak self, weak c] in
            MainActor.assumeIsolated {
                guard let self, let c, self.imageViewerBox.pending === c else { return }
                self.swapIn(c)
            }
        }
    }

    private func swapIn(_ c: ImageViewerController) {
        imageViewer = c
        let url = c.url
        editor.showAuxiliary(c.view, path: jumpPath(for: url), file: url)
        editor.jumpBar.symbolTitle = "No Selection"
        inspector.imageProperties = c.properties
        inspector.show(file: url)
        debugArea.setPosition(line: 0, column: 0)
    }
}

@MainActor
final class ImageViewerBox {
    var controller: ImageViewerController?
    var pending: ImageViewerController?
}
