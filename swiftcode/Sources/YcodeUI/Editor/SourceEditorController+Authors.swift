import AppKit
import YcodeIDECore

extension SourceEditorController {
    public var showsAuthors: Bool {
        get { gutter.showsAuthors }
        set {
            guard newValue != gutter.showsAuthors else { return }
            gutter.showsAuthors = newValue
            refreshBlame()
        }
    }

    public var authorBlocks: [GitBlame.Block] { gutter.authorBlocks }

    func refreshBlame() {
        blameGeneration += 1
        guard gutter.showsAuthors, let url = fileURL, let load = blameLoader else {
            blameLoading = nil
            gutter.authorBlocks = []
            return
        }
        let generation = blameGeneration
        let contents = isDirty ? textView.string : nil
        blameLoading = Task { [weak self] in
            let commits = await load(url, contents)
            guard let self, generation == self.blameGeneration else { return }
            self.blameLoading = nil
            guard self.fileURL == url else { return }
            self.gutter.authorBlocks = commits.map(GitBlame.blocks) ?? []
        }
    }

    public func authorsIdle() async {
        while let t = blameLoading { await t.value }
    }
}
