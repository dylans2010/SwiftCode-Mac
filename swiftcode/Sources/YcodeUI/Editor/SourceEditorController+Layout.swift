import AppKit
import YcodeIDECore

extension SourceEditorController {
    var barInsets: NSEdgeInsets {
        let safe = view.safeAreaInsets
        return NSEdgeInsets(top: safe.top + JumpBar.height + (isShowingFindBar ? findBar.frame.height : 0), left: 0, bottom: safe.bottom, right: 0)
    }

    var scrollerLaneWidth: CGFloat {
        guard scrollView.scrollerStyle == .legacy, scrollView.hasVerticalScroller, let s = scrollView.verticalScroller, !s.isHidden else { return 0 }
        return s.frame.width
    }

    func updateEditorInsets() {
        guard isViewLoaded else { return }
        let insets = barInsets
        let old = scrollView.contentInsets
        if abs(old.top - insets.top) > 0.25 || abs(old.bottom - insets.bottom) > 0.25 {
            let atTop = scrollView.contentView.bounds.minY <= -old.top + 0.5
            scrollView.contentInsets = insets
            if atTop {
                scrollView.contentView.scroll(to: NSPoint(x: scrollView.contentView.bounds.minX, y: -insets.top))
                scrollView.reflectScrolledClipView(scrollView.contentView)
            }
        }
        let lane = scrollerLaneWidth
        if minimapTrailing.constant != -lane { minimapTrailing.constant = -lane }
        let header = -(lane + minimapWidthValue)
        if stickyHeaderTrailing.constant != header { stickyHeaderTrailing.constant = header }
        updateTextContainerWidth()
        updateMinimapViewport()
    }

    func updateTextContainerWidth() {
        guard Preferences.shared.wrapLines, let tc = textView.textContainer else { return }
        let clip = scrollView.contentView
        guard view.bounds.width > 200, clip.bounds.width > 200 else {
            tc.widthTracksTextView = true
            return
        }
        let visibleEnd = textView.convert(NSPoint(x: clip.bounds.maxX, y: 0), from: clip).x
        let end: CGFloat
        if minimapWidthValue > 0, !minimap.isHidden {
            end = textView.convert(NSPoint(x: view.bounds.maxX - scrollerLaneWidth - minimapWidthValue, y: 0), from: view).x - CGFloat(EditorMetrics.textToMinimap)
        } else {
            end = visibleEnd
        }
        let width = max(40, min(end, visibleEnd) - textView.textContainerOrigin.x)
        tc.widthTracksTextView = false
        if abs(tc.size.width - width) > 0.5 { tc.size = NSSize(width: width, height: CGFloat.greatestFiniteMagnitude) }
        let docWidth = clip.bounds.width + min(0, clip.bounds.minX)
        if abs(textView.frame.width - docWidth) > 0.5 { textView.setFrameSize(NSSize(width: docWidth, height: textView.frame.height)) }
    }

    var textContainerEnd: CGFloat {
        guard let tc = textView.textContainer else { return textView.bounds.width }
        return tc.widthTracksTextView || !Preferences.shared.wrapLines ? textView.bounds.width : textView.textContainerOrigin.x + tc.size.width
    }

    func updateMinimapViewport() {
        guard minimapWidthValue > 0 else { return }
        let clip = scrollView.contentView
        let insets = scrollView.contentInsets
        let visibleHeight = max(0, clip.bounds.height - insets.top - insets.bottom)
        let top = clip.bounds.minY + insets.top
        let docHeight = textView.frame.height
        let scrollable = max(1, docHeight - visibleHeight)
        minimap.contentTop = insets.top
        minimap.visibleTop = max(0, top)
        minimap.visibleHeight = visibleHeight
        minimap.scrollFraction = min(1, max(0, top / scrollable))
        minimap.advance = Theme.advance
    }

    func scrollMinimapTarget(_ y: CGFloat) {
        let clip = scrollView.contentView
        let insets = scrollView.contentInsets
        let visibleHeight = max(0, clip.bounds.height - insets.top - insets.bottom)
        let maxY = max(-insets.top, textView.frame.height - clip.bounds.height + insets.bottom)
        let target = min(maxY, max(-insets.top, y - visibleHeight / 2 - insets.top))
        clip.scroll(to: NSPoint(x: clip.bounds.minX, y: target))
        scrollView.reflectScrolledClipView(clip)
    }

    func updateMinimapRows() {
        guard minimapWidthValue > 0, let storage = textView.textStorage else { minimap.rows = []; return }
        let advance = max(1, Theme.advance)
        let width = textView.textContainer.map { $0.widthTracksTextView ? textView.bounds.width : $0.size.width } ?? textView.bounds.width
        let columns = width.isFinite && width < 100_000 ? Int(width / advance) : 10_000
        minimap.textTopInset = CGFloat(EditorMetrics.firstLineInset)
        let doc = syntax.document.flatMap { $0.units.count == storage.length ? $0 : nil }
        let tokens = doc.map { MinimapView.tokenInteriors($0.tokens(in: 0..<storage.length)) } ?? IndexSet()
        minimap.rows = MinimapView.rows(of: storage, columns: columns, tabWidth: Preferences.shared.tabWidth, wraps: Preferences.shared.wrapLines,
                                        tokens: tokens)
        updateMinimapViewport()
    }
}

extension SourceEditorController: NSTextContentStorageDelegate {
    public nonisolated func textContentStorage(_ textContentStorage: NSTextContentStorage, textParagraphWith range: NSRange) -> NSTextParagraph? {
        let snap = wrapSnapshot
        guard snap.wraps, snap.advance > 0, let text = textContentStorage.textStorage, NSMaxRange(range) <= text.length, range.length > 0 else { return nil }
        let para = text.attributedSubstring(from: range)
        let indent = EditorMetrics.wrappedIndent(of: Substring(para.string), tabWidth: snap.tabWidth)
        let base = (para.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle) ?? NSParagraphStyle.default
        let style = (base.mutableCopy() as? NSMutableParagraphStyle) ?? NSMutableParagraphStyle()
        style.headIndent = CGFloat(indent) * snap.advance
        let out = NSMutableAttributedString(attributedString: para)
        out.addAttribute(.paragraphStyle, value: style, range: NSRange(location: 0, length: out.length))
        return NSTextParagraph(attributedString: out)
    }
}

struct WrapSnapshot: Sendable {
    var wraps = true
    var advance: CGFloat = 8
    var tabWidth = 4
}
