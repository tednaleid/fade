// ABOUTME: Comparison slider mode for side-by-side image viewing.
// ABOUTME: Extends SlideshowController with slider entry/exit, navigation, and tagging.

import AppKit

// MARK: - Comparison Slider

extension SlideshowController {

    func handleSliderKey(_ key: KeyCode) {
        switch key {
        case .rightArrow: sliderAdvanceComparison(forward: true)
        case .leftArrow:  sliderAdvanceComparison(forward: false)
        case .upArrow:    sliderTagComparison(direction: .up)
        case .downArrow:  sliderTagComparison(direction: .down)
        case .sKey:       exitSliderMode()
        case .tKey:       exitSliderMode(); enterTriptychMode()
        default:          break
        }
    }

    func enterSliderMode() {
        guard let nextIdx = nextIndex(), let nextImage = loadImage(at: nextIdx) else {
            showStatusMessage("No next image to compare")
            return
        }

        viewMode = .slider
        wasPausedBeforeMode = isPaused
        sliderComparisonIndex = nextIdx
        if !isPaused { togglePause() }

        // Show next image in backView
        backView.image = nextImage
        backView.contentFilters = isTrashed(path: paths[nextIdx]) ? [desaturateFilter] : []
        backView.alphaValue = 1

        // Start with divider at right edge (current image fully visible)
        sliderPosition = 1.0
        updateSliderMask()

        // Create and position divider
        guard let contentView = window.contentView else { return }
        let dividerWidth: CGFloat = 32
        let divider = SliderDividerView(frame: NSRect(
            x: contentView.bounds.width - dividerWidth / 2,
            y: 0,
            width: dividerWidth,
            height: contentView.bounds.height))
        divider.autoresizingMask = [.height]
        divider.onDrag = { [weak self] dragX in
            guard let self = self, let contentView = self.window.contentView else { return }
            let clamped = max(0, min(dragX, contentView.bounds.width))
            self.sliderPosition = clamped / contentView.bounds.width
            self.updateSliderMask()
            self.repositionDivider()
            self.layoutTitlebarLabels()
        }
        contentView.addSubview(divider)
        sliderDivider = divider
        installTitlebarLabels()
        updateDisplayState()
    }

    func exitSliderMode() {
        viewMode = .normal
        sliderComparisonIndex = nil
        sliderDivider?.removeFromSuperview()
        sliderDivider = nil
        frontView.layer?.mask = nil
        backView.alphaValue = 0
        backView.image = nil
        removeTitlebarLabels()
        updateDisplayState()

        if !wasPausedBeforeMode {
            togglePause()
        }
    }

    func updateSliderMask() {
        guard viewMode == .slider else {
            frontView.layer?.mask = nil
            return
        }
        let bounds = frontView.bounds
        let maskLayer = CALayer()
        maskLayer.frame = bounds
        let visibleRect = CALayer()
        visibleRect.frame = CGRect(x: 0, y: 0, width: bounds.width * sliderPosition, height: bounds.height)
        visibleRect.backgroundColor = NSColor.white.cgColor
        maskLayer.addSublayer(visibleRect)
        frontView.layer?.mask = maskLayer
    }

    func repositionDivider() {
        guard let divider = sliderDivider, let contentView = window.contentView else { return }
        let dividerX = contentView.bounds.width * sliderPosition
        divider.frame.origin.x = dividerX - divider.frame.width / 2
    }

    // Change the comparison (right) image, keeping the reference (left) image fixed.
    func sliderAdvanceComparison(forward: Bool) {
        guard let compIdx = sliderComparisonIndex else { return }
        let newIdx: Int?
        if forward {
            newIdx = nextComparisonIndex(after: compIdx)
        } else {
            newIdx = previousComparisonIndex(before: compIdx)
        }
        guard let idx = newIdx else { return }
        sliderLoadComparison(at: idx)
        flashArrow(forward ? .right : .left)
    }

    // Find the next untrashed image after a given index, skipping currentIndex.
    func nextComparisonIndex(after startIndex: Int) -> Int? {
        let count = paths.count
        guard count > 0 else { return nil }

        var candidate = startIndex
        for _ in 0..<count {
            candidate += 1
            if candidate >= count {
                if config.noLoop { return nil }
                candidate = 0
            }
            if candidate == startIndex { return nil }
            if candidate == currentIndex { continue }
            if !isTrashed(path: paths[candidate]) {
                return candidate
            }
        }
        return nil
    }

    // Find the previous image before a given index (including trashed), skipping currentIndex.
    func previousComparisonIndex(before startIndex: Int) -> Int? {
        let count = paths.count
        guard count > 0 else { return nil }

        var candidate = startIndex
        for _ in 0..<count {
            candidate -= 1
            if candidate < 0 {
                if config.noLoop { return nil }
                candidate = count - 1
            }
            if candidate == startIndex { return nil }
            if candidate == currentIndex { continue }
            return candidate
        }
        return nil
    }

    // Load an image into the comparison (right) side of the slider.
    func sliderLoadComparison(at index: Int) {
        guard let image = loadImage(at: index) else { return }
        sliderComparisonIndex = index
        backView.image = image
        backView.contentFilters = isTrashed(path: paths[index]) ? [desaturateFilter] : []
        updateSliderMask()
        repositionDivider()
        updateDisplayState()
    }

    // Tag the comparison image and auto-advance or show dash.
    func sliderTagComparison(direction: DirectionalArrowView.Direction) {
        guard let compIdx = sliderComparisonIndex else { return }

        if direction == .up {
            tagUp(path: paths[compIdx])
        } else {
            tagDown(path: paths[compIdx])
        }

        let didAdvance = reactToTagChange(at: compIdx, direction: direction, advanceDelay: 0.05) { [weak self] in
            guard let self = self else { return }
            if let nextIdx = self.nextComparisonIndex(after: compIdx) {
                self.sliderLoadComparison(at: nextIdx)
            } else {
                self.exitSliderMode()
                self.showStatusMessage("1 untrashed image")
            }
        }
        if !didAdvance {
            // Untagged — also clear desaturation on comparison image
            backView.contentFilters = []
        }
    }
}
