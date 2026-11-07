import AppKit

extension NavigatorAreaController {
    static let plusSize = NSSize(width: 31, height: GlassBars.height)
    static let filterInset: CGFloat = 4
    static let filterTextInset: CGFloat = 28
    static let plusToFilter: CGFloat = 5
    static let selectorPillSize = NSSize(width: 30, height: 24)

    func installGlassBars(_ root: NSView) {
        let field = filter
        NSLayoutConstraint.activate([
            selectorGlass.topAnchor.constraint(equalTo: root.safeAreaLayoutGuide.topAnchor, constant: GlassBars.topOffset),
            selectorGlass.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 6),
            selectorGlass.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -6),
            selectorGlass.heightAnchor.constraint(equalToConstant: GlassBars.height),
            plusGlass.centerXAnchor.constraint(equalTo: addBreakpointButton.centerXAnchor),
            plusGlass.centerYAnchor.constraint(equalTo: field.centerYAnchor),
            plusGlass.widthAnchor.constraint(equalToConstant: Self.plusSize.width),
            plusGlass.heightAnchor.constraint(equalToConstant: Self.plusSize.height),
            filterGlass.leadingAnchor.constraint(equalTo: field.leadingAnchor, constant: -Self.filterInset),
            filterGlass.trailingAnchor.constraint(equalTo: field.trailingAnchor, constant: Self.filterInset),
            filterGlass.centerYAnchor.constraint(equalTo: field.centerYAnchor),
            filterGlass.heightAnchor.constraint(equalToConstant: GlassBars.height),
        ])
        field.isBezeled = false
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        (field as? NavigatorFilterField)?.leadingInset = Self.filterTextInset
        underBarsScroll = [
            scrollView.topAnchor.constraint(equalTo: selectorGlass.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: filterGlass.bottomAnchor),
        ]
    }

    func setOutlineUnderBars(_ under: Bool) {
        guard GlassBars.enabled, !underBarsScroll.isEmpty else { return }
        if under {
            NSLayoutConstraint.deactivate(clippedScrollConstraints)
            NSLayoutConstraint.activate(underBarsScroll)
        } else {
            NSLayoutConstraint.deactivate(underBarsScroll)
            NSLayoutConstraint.activate(clippedScrollConstraints)
        }
        scrollClipView.clipsToBounds = !under
        updateOutlineInsets()
    }

    func updateGlassLayout() {
        guard GlassBars.enabled, isViewLoaded else { return }
        selectorPill.follow(selectorButtons.first { $0.state == .on }, size: Self.selectorPillSize)
    }

    var outlineTopPadding: CGFloat {
        let o = outlineView
        guard o.numberOfRows > 0 else { return measuredOutlineTopPadding.value }
        let pad = scrollView.contentView.convert(o.rect(ofRow: 0), from: o).minY
        measuredOutlineTopPadding.value = pad
        return pad
    }

    func updateOutlineInsets() {
        guard isViewLoaded else { return }
        let pad = outlineTopPadding
        if GlassBars.enabled, underBarsScroll.first?.isActive == true {
            let selectorBottom = selectorView.frame.height
            let scrollBottom = filterGlass.frame.minY
            let top = selectorBottom + Self.firstRowGap - pad
            let bottom = max(scrollClipView.frame.minY, filterGlass.frame.maxY + 2) - scrollBottom
            let scroller = NSEdgeInsets(top: selectorBottom + Self.scrollerBelowSelector, left: 0,
                                        bottom: filterGlass.frame.height + Self.scrollerAboveFilter, right: 0)
            setOutlineInsets(NSEdgeInsets(top: top, left: 0, bottom: bottom, right: 0), scroller: scroller)
        } else {
            setOutlineInsets(NSEdgeInsets(top: Self.clipToFirstRow - pad, left: 0, bottom: 0, right: 0))
        }
    }

    static let scrollerBelowSelector: CGFloat = 3
    static let scrollerAboveFilter: CGFloat = 11

    private func setOutlineInsets(_ insets: NSEdgeInsets, scroller: NSEdgeInsets? = nil) {
        let scroll = scrollView
        let old = scroll.contentInsets
        let scrollerInsets = scroller ?? insets
        if abs(scroll.scrollerInsets.top - scrollerInsets.top) > 0.25 || abs(scroll.scrollerInsets.bottom - scrollerInsets.bottom) > 0.25 {
            scroll.scrollerInsets = scrollerInsets
        }
        guard abs(old.top - insets.top) > 0.25 || abs(old.bottom - insets.bottom) > 0.25 else { return }
        let atTop = scroll.contentView.bounds.minY <= -old.top + 0.5
        scroll.contentInsets = insets
        if atTop {
            scroll.contentView.scroll(to: NSPoint(x: scroll.contentView.bounds.minX, y: -insets.top))
            scroll.reflectScrolledClipView(scroll.contentView)
        }
    }
}

final class OutlinePaddingBox {
    var value: CGFloat = 0
}
