// ABOUTME: Triptych mode for three-image side-by-side viewing.
// ABOUTME: Extends SlideshowController with triptych entry/exit, navigation, layout, and tagging.

import AppKit

// MARK: - Triptych Mode

extension SlideshowController {

    private static let triptychGap: CGFloat = 2

    func handleTriptychKey(_ key: KeyCode) {
        switch key {
        case .rightArrow: triptychNavigate(forward: true)
        case .leftArrow:  triptychNavigate(forward: false)
        case .upArrow:    triptychTagCurrent(direction: .up)
        case .downArrow:  triptychTagCurrent(direction: .down)
        case .tKey:       exitTriptychMode()
        case .sKey:       exitTriptychMode(); enterSliderMode()
        default:          break
        }
    }

    func enterTriptychMode() {
        if viewMode == .slider { exitSliderMode() }

        viewMode = .triptych
        wasPausedBeforeMode = isPaused
        if !isPaused { togglePause() }

        // Save window width and triple it (clamped to screen)
        let currentWidth = window.frame.width
        savedWindowWidth = currentWidth
        var tripleWidth = currentWidth * 3
        if let screen = NSScreen.main {
            tripleWidth = min(tripleWidth, screen.visibleFrame.width)
        }
        let newFrame = NSRect(
            x: window.frame.origin.x,
            y: window.frame.origin.y,
            width: tripleWidth,
            height: window.frame.height)
        window.setFrame(newFrame, display: true)
        window.center()

        // Hide normal views
        frontView.alphaValue = 0
        backView.alphaValue = 0

        // Create three image views
        guard let contentView = window.contentView else { return }
        let bounds = contentView.bounds

        let leftView = NSImageView(frame: bounds)
        leftView.imageScaling = .scaleProportionallyUpOrDown
        leftView.wantsLayer = true

        let middleView = NSImageView(frame: bounds)
        middleView.imageScaling = .scaleProportionallyUpOrDown
        middleView.wantsLayer = true

        let rightView = NSImageView(frame: bounds)
        rightView.imageScaling = .scaleProportionallyUpOrDown
        rightView.wantsLayer = true

        // Insert below overlay views (statusIcon, arrows, etc.) so they remain visible
        contentView.addSubview(leftView, positioned: .below, relativeTo: statusIcon)
        contentView.addSubview(middleView, positioned: .below, relativeTo: statusIcon)
        contentView.addSubview(rightView, positioned: .below, relativeTo: statusIcon)

        triptychLeftView = leftView
        triptychMiddleView = middleView
        triptychRightView = rightView

        triptychLayout()
        triptychLoadPanels()
    }

    func exitTriptychMode() {
        viewMode = .normal

        // Remove triptych views
        triptychLeftView?.removeFromSuperview()
        triptychMiddleView?.removeFromSuperview()
        triptychRightView?.removeFromSuperview()
        triptychLeftView = nil
        triptychMiddleView = nil
        triptychRightView = nil
        triptychLeftIndex = nil
        triptychRightIndex = nil

        // Restore normal view
        frontView.alphaValue = 1
        if let image = loadImage(at: currentIndex) {
            frontView.image = image
        }
        updateDisplayState()

        // Restore window width
        if let savedWidth = savedWindowWidth {
            let newFrame = NSRect(
                x: window.frame.origin.x,
                y: window.frame.origin.y,
                width: savedWidth,
                height: window.frame.height)
            window.setFrame(newFrame, display: true)
            window.center()
            savedWindowWidth = nil
        }

        if !wasPausedBeforeMode {
            togglePause()
        }
        preloadNext()
        if !isPaused {
            scheduleAdvance()
        }
    }

    func triptychLayout() {
        guard let contentView = window.contentView else { return }
        let bounds = contentView.bounds
        let gap = Self.triptychGap
        let panelWidth = (bounds.width - 2 * gap) / 3

        triptychLeftView?.frame = NSRect(
            x: 0, y: 0,
            width: panelWidth, height: bounds.height)
        triptychMiddleView?.frame = NSRect(
            x: panelWidth + gap, y: 0,
            width: panelWidth, height: bounds.height)
        triptychRightView?.frame = NSRect(
            x: 2 * (panelWidth + gap), y: 0,
            width: panelWidth, height: bounds.height)
    }

    func triptychComputeSides() {
        triptychLeftIndex = previousIndex()
        triptychRightIndex = nextUntrashedIndex() ?? currentIndex
    }

    func triptychLoadPanels() {
        triptychComputeSides()

        if let leftIdx = triptychLeftIndex, let img = loadImage(at: leftIdx) {
            triptychLeftView?.image = img
            triptychLeftView?.contentFilters = isTrashed(path: paths[leftIdx]) ? [desaturateFilter] : []
        }

        if let img = loadImage(at: currentIndex) {
            triptychMiddleView?.image = img
            triptychMiddleView?.contentFilters = isTrashed(path: paths[currentIndex]) ? [desaturateFilter] : []
        }

        if let rightIdx = triptychRightIndex, let img = loadImage(at: rightIdx) {
            triptychRightView?.image = img
            triptychRightView?.contentFilters = isTrashed(path: paths[rightIdx]) ? [desaturateFilter] : []
        }

        updateDisplayState()
    }

    func triptychNavigate(forward: Bool) {
        if forward {
            guard let rightIdx = triptychRightIndex else { return }
            currentIndex = rightIdx
            flashArrow(.right)
        } else {
            guard let leftIdx = triptychLeftIndex else { return }
            currentIndex = leftIdx
            flashArrow(.left)
        }
        triptychLoadPanels()
    }

    func triptychTagCurrent(direction: DirectionalArrowView.Direction) {
        if direction == .up {
            tagUp(path: paths[currentIndex])
        } else {
            tagDown(path: paths[currentIndex])
        }
        updateDisplayState()

        // Update middle panel's desaturation immediately
        let path = paths[currentIndex]
        triptychMiddleView?.contentFilters = isTrashed(path: path) ? [desaturateFilter] : []

        // Check if un-trashing recovered from all-trashed state
        if direction == .up && allTrashed && !checkAllTrashed() {
            allTrashed = false
        }

        reactToTagChange(at: currentIndex, direction: direction, advanceDelay: 0.5) { [weak self] in
            guard let self else { return }
            if let nextIdx = self.nextUntrashedIndex() {
                self.currentIndex = nextIdx
            }
            self.triptychLoadPanels()
        }
    }
}
