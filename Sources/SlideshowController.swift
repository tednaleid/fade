// ABOUTME: Core slideshow controller managing window, navigation, timers, and display.
// ABOUTME: Handles image loading, cross-fade transitions, tagging, pause/play, and keyboard/click input.

@preconcurrency import AppKit

@MainActor class SlideshowController: NSObject, NSWindowDelegate {
    let config: SlideshowConfig
    var paths: [String]
    let window: SlideshowWindow

    // Two image views for cross-fade
    let frontView: NSImageView
    let backView: NSImageView

    // Status overlays
    let statusIcon: StatusIconView
    let statusLabel: NSTextField
    var statusFadeTimer: Timer?

    // Directional arrow overlays
    let arrowLeft: DirectionalArrowView
    let arrowRight: DirectionalArrowView
    let arrowUp: DirectionalArrowView
    let arrowDown: DirectionalArrowView

    var currentIndex: Int = 0
    var isPaused: Bool = false
    var allTrashed: Bool = false
    var advanceTimer: Timer?
    var refreshTimer: Timer?
    var autoAdvanceTimer: Timer?

    // Comparison slider state
    var viewMode: ViewMode = .normal
    var wasPausedBeforeMode: Bool = false
    var sliderDivider: SliderDividerView?
    var sliderPosition: CGFloat = 1.0
    var sliderComparisonIndex: Int?

    // Triptych state
    var triptychLeftView: NSImageView?
    var triptychMiddleView: NSImageView?
    var triptychRightView: NSImageView?
    var triptychLeftIndex: Int?
    var triptychRightIndex: Int?
    var savedWindowWidth: CGFloat?

    // Titlebar labels for multi-image modes
    var titlebarLabels: [NSTextField] = []
    var titlebarAccessory: NSTitlebarAccessoryViewController?

    // Preloaded next image
    var preloadedImage: NSImage?
    var preloadedIndex: Int?

    // Desaturation filter for trash-tagged images
    let desaturateFilter: CIFilter = {
        let filter = CIFilter(name: "CIColorControls")!
        filter.setValue(0.3, forKey: kCIInputSaturationKey)
        return filter
    }()

    init(config: SlideshowConfig) {
        self.config = config
        self.paths = config.paths

        let contentRect = NSRect(x: 0, y: 0, width: config.windowWidth, height: config.windowHeight)
        window = SlideshowWindow(
            contentRect: contentRect,
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .visible
        window.isMovableByWindowBackground = true
        window.backgroundColor = .black
        window.center()

        let containerView = NSView(frame: contentRect)
        containerView.autoresizingMask = [.width, .height]

        backView = NSImageView(frame: contentRect)
        backView.imageScaling = .scaleProportionallyUpOrDown
        backView.autoresizingMask = [.width, .height]
        backView.wantsLayer = true
        backView.alphaValue = 0

        frontView = NSImageView(frame: contentRect)
        frontView.imageScaling = .scaleProportionallyUpOrDown
        frontView.autoresizingMask = [.width, .height]
        frontView.wantsLayer = true
        frontView.alphaValue = 1

        containerView.addSubview(backView)
        containerView.addSubview(frontView)

        // Status icon (centered, 80x60)
        let iconSize = NSSize(width: 80, height: 60)
        statusIcon = StatusIconView(frame: NSRect(
            x: (contentRect.width - iconSize.width) / 2,
            y: (contentRect.height - iconSize.height) / 2,
            width: iconSize.width,
            height: iconSize.height
        ))
        statusIcon.autoresizingMask = [.minXMargin, .maxXMargin, .minYMargin, .maxYMargin]
        statusIcon.alphaValue = 0
        containerView.addSubview(statusIcon)

        // Status text label (centered, hidden by default)
        statusLabel = NSTextField(labelWithString: "")
        statusLabel.font = NSFont.systemFont(ofSize: 24, weight: .light)
        statusLabel.textColor = .white
        statusLabel.backgroundColor = NSColor(white: 0, alpha: 0.6)
        statusLabel.wantsLayer = true
        statusLabel.layer?.cornerRadius = 12
        statusLabel.alignment = .center
        statusLabel.isBezeled = false
        statusLabel.isEditable = false
        statusLabel.drawsBackground = true
        statusLabel.alphaValue = 0
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(statusLabel)
        NSLayoutConstraint.activate([
            statusLabel.centerXAnchor.constraint(equalTo: containerView.centerXAnchor),
            statusLabel.centerYAnchor.constraint(equalTo: containerView.centerYAnchor),
            statusLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 200)
        ])

        // Directional arrow overlays (edges, hidden by default)
        let margin: CGFloat = 20
        let arrowLR = NSSize(width: 60, height: 80)  // tall for left/right
        let arrowUD = NSSize(width: 80, height: 60)   // wide for up/down

        arrowLeft = DirectionalArrowView(direction: .left, color: .white, frame: NSRect(
            x: margin,
            y: (contentRect.height - arrowLR.height) / 2,
            width: arrowLR.width, height: arrowLR.height))
        arrowLeft.autoresizingMask = [.maxXMargin, .minYMargin, .maxYMargin]
        arrowLeft.alphaValue = 0
        containerView.addSubview(arrowLeft)

        arrowRight = DirectionalArrowView(direction: .right, color: .white, frame: NSRect(
            x: contentRect.width - arrowLR.width - margin,
            y: (contentRect.height - arrowLR.height) / 2,
            width: arrowLR.width, height: arrowLR.height))
        arrowRight.autoresizingMask = [.minXMargin, .minYMargin, .maxYMargin]
        arrowRight.alphaValue = 0
        containerView.addSubview(arrowRight)

        arrowUp = DirectionalArrowView(direction: .up, color: .systemGreen, frame: NSRect(
            x: (contentRect.width - arrowUD.width) / 2,
            y: contentRect.height - arrowUD.height - margin,
            width: arrowUD.width, height: arrowUD.height))
        arrowUp.autoresizingMask = [.minXMargin, .maxXMargin, .minYMargin]
        arrowUp.alphaValue = 0
        containerView.addSubview(arrowUp)

        arrowDown = DirectionalArrowView(direction: .down, color: .systemRed, frame: NSRect(
            x: (contentRect.width - arrowUD.width) / 2,
            y: margin,
            width: arrowUD.width, height: arrowUD.height))
        arrowDown.autoresizingMask = [.minXMargin, .maxXMargin, .maxYMargin]
        arrowDown.alphaValue = 0
        containerView.addSubview(arrowDown)

        window.contentView = containerView

        super.init()

        window.delegate = self
        window.keyHandler = self
    }

    func start() {
        guard !paths.isEmpty else { return }

        // Find the starting image: use startFile if provided, otherwise first untrashed
        let startIndex: Int?
        if let startFile = config.startFile, let idx = paths.firstIndex(of: startFile) {
            startIndex = idx
        } else {
            startIndex = firstUntrashedIndex()
        }
        guard let startIndex else {
            // All images are trashed
            window.makeKeyAndOrderFront(nil)
            let clickRecognizer = NSClickGestureRecognizer(target: self, action: #selector(handleClick(_:)))
            window.contentView?.addGestureRecognizer(clickRecognizer)
            enterAllTrashedState()
            startRefreshTimer()
            return
        }

        if let image = loadImage(at: startIndex) {
            frontView.image = image
            frontView.alphaValue = 1
            backView.alphaValue = 0
            currentIndex = startIndex
            updateDisplayState()

            if config.fitScreen, let screen = NSScreen.main {
                let imageSize = image.size
                let visibleFrame = screen.visibleFrame
                let imageRatio = imageSize.width / imageSize.height
                let screenRatio = visibleFrame.width / visibleFrame.height

                let newSize: NSSize
                if imageRatio > screenRatio {
                    // Image is wider than screen — fit to screen width
                    newSize = NSSize(width: visibleFrame.width, height: visibleFrame.width / imageRatio)
                } else {
                    // Image is taller than screen — fit to screen height
                    newSize = NSSize(width: visibleFrame.height * imageRatio, height: visibleFrame.height)
                }
                window.setContentSize(newSize)
                window.center()
            }
        }

        window.makeKeyAndOrderFront(nil)

        // Install click handler
        let clickRecognizer = NSClickGestureRecognizer(target: self, action: #selector(handleClick(_:)))
        window.contentView?.addGestureRecognizer(clickRecognizer)

        // Preload next and start timers
        preloadNext()
        scheduleAdvance()
        startRefreshTimer()

        if config.startWithSlider {
            enterSliderMode()
        } else if config.startWithTriptych {
            enterTriptychMode()
        }
    }

    // MARK: - Display State

    // Builds a display title for a single image path (filename + tag dots).
    func titleForPath(_ path: String) -> String {
        let tags = getFileTags(path: path)
        var title = (path as NSString).lastPathComponent
        for info in [favoriteTag, trashTag] where tags.contains(info.finderTag) {
            title += "  \(info.dot) \(info.name)"
        }
        return title
    }

    // Updates title bar and desaturation filter to reflect current image's tag state.
    func updateDisplayState() {
        let path = paths[currentIndex]

        switch viewMode {
        case .slider:
            if titlebarLabels.count >= 2 {
                titlebarLabels[0].stringValue = titleForPath(path)
                if let compIdx = sliderComparisonIndex {
                    titlebarLabels[1].stringValue = titleForPath(paths[compIdx])
                }
            }
        case .triptych:
            if titlebarLabels.count >= 3 {
                titlebarLabels[0].stringValue = triptychLeftIndex.map { titleForPath(paths[$0]) } ?? ""
                titlebarLabels[1].stringValue = titleForPath(path)
                titlebarLabels[2].stringValue = triptychRightIndex.map { titleForPath(paths[$0]) } ?? ""
            }
        case .normal:
            window.title = titleForPath(path)
        }

        frontView.contentFilters = isTrashed(path: path) ? [desaturateFilter] : []
    }

    // MARK: - Titlebar Labels

    func installTitlebarLabels() {
        removeTitlebarLabels()

        let count: Int
        switch viewMode {
        case .slider: count = 2
        case .triptych: count = 3
        case .normal: return
        }

        let height: CGFloat = 20
        let containerView = NSView(frame: NSRect(x: 0, y: 0, width: 0, height: height))

        let shadow = NSShadow()
        shadow.shadowColor = NSColor(white: 0, alpha: 0.8)
        shadow.shadowOffset = NSSize(width: 0, height: -1)
        shadow.shadowBlurRadius = 3

        var labels: [NSTextField] = []
        for _ in 0..<count {
            let label = NSTextField(labelWithString: "")
            label.font = NSFont.systemFont(ofSize: 12, weight: .regular)
            label.textColor = NSColor(white: 1, alpha: 0.85)
            label.backgroundColor = .clear
            label.drawsBackground = false
            label.alignment = .center
            label.lineBreakMode = .byTruncatingMiddle
            label.shadow = shadow
            containerView.addSubview(label)
            labels.append(label)
        }

        titlebarLabels = labels

        let vc = NSTitlebarAccessoryViewController()
        vc.view = containerView
        vc.layoutAttribute = .bottom
        window.addTitlebarAccessoryViewController(vc)
        titlebarAccessory = vc

        window.title = ""
        layoutTitlebarLabels()
    }

    func removeTitlebarLabels() {
        if let accessory = titlebarAccessory,
           let idx = window.titlebarAccessoryViewControllers.firstIndex(of: accessory) {
            window.removeTitlebarAccessoryViewController(at: idx)
        }
        titlebarAccessory = nil
        titlebarLabels = []
    }

    func layoutTitlebarLabels() {
        guard !titlebarLabels.isEmpty else { return }
        let width = window.contentView?.bounds.width ?? window.frame.width
        let height: CGFloat = 20

        switch viewMode {
        case .slider:
            guard titlebarLabels.count == 2 else { return }
            // Reference label centered in left half, comparison starts at slider position
            titlebarLabels[0].alignment = .center
            titlebarLabels[0].frame = NSRect(x: 0, y: 0, width: width * sliderPosition, height: height)
            titlebarLabels[1].alignment = .center
            let compX = width * sliderPosition
            titlebarLabels[1].frame = NSRect(x: compX, y: 0, width: width - compX, height: height)
        case .triptych:
            guard titlebarLabels.count == 3 else { return }
            let gap = Self.triptychGap
            let panelWidth = (width - 2 * gap) / 3
            titlebarLabels[0].frame = NSRect(x: 0, y: 0, width: panelWidth, height: height)
            titlebarLabels[1].frame = NSRect(x: panelWidth + gap, y: 0, width: panelWidth, height: height)
            titlebarLabels[2].frame = NSRect(x: 2 * (panelWidth + gap), y: 0, width: panelWidth, height: height)
        case .normal:
            break
        }
    }

    // MARK: - All-Trashed State

    func checkAllTrashed() -> Bool {
        return paths.allSatisfy { isTrashed(path: $0) }
    }

    // Returns the index of the first untrashed image, or nil if all are trashed.
    func firstUntrashedIndex() -> Int? {
        return paths.firstIndex { !isTrashed(path: $0) }
    }

    func enterAllTrashedState() {
        allTrashed = true
        advanceTimer?.invalidate()
        frontView.image = makeMessageImage("No untrashed images")
        frontView.contentFilters = []
        backView.alphaValue = 0
        window.title = "No untrashed images"
    }

    func makeMessageImage(_ text: String) -> NSImage {
        let size = window.contentView?.bounds.size ?? NSSize(width: 800, height: 200)
        let image = NSImage(size: size)
        image.lockFocus()
        NSColor.black.setFill()
        NSBezierPath.fill(NSRect(origin: .zero, size: size))
        let attrs: [NSAttributedString.Key: Any] = [
            .foregroundColor: NSColor.gray,
            .font: NSFont.systemFont(ofSize: 36, weight: .light)
        ]
        let attrStr = NSAttributedString(string: text, attributes: attrs)
        let strSize = attrStr.size()
        let point = NSPoint(x: (size.width - strSize.width) / 2, y: (size.height - strSize.height) / 2)
        attrStr.draw(at: point)
        image.unlockFocus()
        return image
    }

    // MARK: - Image Loading

    func loadImage(at index: Int) -> NSImage? {
        guard index >= 0 && index < paths.count else { return nil }
        let path = paths[index]
        guard let image = NSImage(contentsOfFile: path) else { return nil }
        // Force decode by requesting a CGImage
        if let tiff = image.tiffRepresentation,
           let bitmap = NSBitmapImageRep(data: tiff) {
            _ = bitmap.cgImage
        }
        return image
    }

    func preloadNext() {
        guard let idx = nextUntrashedIndex() else {
            preloadedImage = nil
            preloadedIndex = nil
            return
        }
        preloadedIndex = idx
        let path = paths[idx]
        Task.detached {
            let image = SlideshowController.loadImageFromDisk(path: path)
            await MainActor.run { [weak self] in
                guard let self, self.preloadedIndex == idx else { return }
                self.preloadedImage = image
            }
        }
    }

    nonisolated private static func loadImageFromDisk(path: String) -> NSImage? {
        guard let image = NSImage(contentsOfFile: path) else { return nil }
        // Force decode by requesting a CGImage
        if let tiff = image.tiffRepresentation,
           let bitmap = NSBitmapImageRep(data: tiff) {
            _ = bitmap.cgImage
        }
        return image
    }

    // MARK: - Navigation

    func nextIndex() -> Int? {
        let next = currentIndex + 1
        if next < paths.count {
            return next
        } else if config.noLoop {
            return nil
        } else {
            return 0
        }
    }

    func previousIndex() -> Int {
        let prev = currentIndex - 1
        if prev >= 0 {
            return prev
        } else {
            return paths.count - 1
        }
    }

    // Returns the next index that is not tagged as trash, or nil if all are trash
    // (or no-loop mode and we've reached the end).
    func nextUntrashedIndex() -> Int? {
        let count = paths.count
        guard count > 0 else { return nil }

        var candidate = currentIndex
        for _ in 0..<count {
            candidate += 1
            if candidate >= count {
                if config.noLoop {
                    return nil
                }
                candidate = 0
            }
            if candidate == currentIndex {
                return nil
            }
            if !isTrashed(path: paths[candidate]) {
                return candidate
            }
        }
        return nil
    }

    func scheduleAdvance() {
        advanceTimer?.invalidate()
        guard !isPaused else { return }
        advanceTimer = Timer.scheduledTimer(withTimeInterval: config.duration, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.advanceWithFade() }
        }
    }

    func advanceWithFade() {
        guard let nextIdx = nextUntrashedIndex() else {
            if config.noLoop {
                NSApplication.shared.terminate(nil)
                return
            }
            // Check if the current image is the sole untrashed one
            if isTrashed(path: paths[currentIndex]) {
                enterAllTrashedState()
            } else {
                showStatusMessage("1 untrashed image")
                scheduleAdvance()
            }
            return
        }

        let nextImage: NSImage?
        if preloadedIndex == nextIdx, let preloaded = preloadedImage {
            nextImage = preloaded
        } else {
            nextImage = loadImage(at: nextIdx)
        }
        guard let image = nextImage else {
            // Skip unloadable images
            currentIndex = nextIdx
            updateDisplayState()
            preloadNext()
            scheduleAdvance()
            return
        }

        crossFade(to: image, isTrash: isTrashed(path: paths[nextIdx]))
        currentIndex = nextIdx
        updateDisplayState()
        preloadedImage = nil
        preloadedIndex = nil
        preloadNext()
        scheduleAdvance()
    }

    func crossFade(to image: NSImage, isTrash: Bool = false) {
        // Back view gets the new image, starts invisible
        backView.image = image
        backView.contentFilters = isTrash ? [desaturateFilter] : []
        backView.alphaValue = 0

        NSAnimationContext.runAnimationGroup({ context in
            context.duration = config.fadeDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            frontView.animator().alphaValue = 0
            backView.animator().alphaValue = 1
        }, completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                // Swap: front becomes back, back becomes front
                self.frontView.alphaValue = 1
                self.frontView.image = self.backView.image
                self.backView.alphaValue = 0
                self.backView.image = nil
            }
        })
    }

    func jumpTo(index: Int) {
        guard let image = loadImage(at: index) else { return }
        advanceTimer?.invalidate()
        // Instant swap, no fade
        frontView.image = image
        frontView.alphaValue = 1
        backView.alphaValue = 0
        currentIndex = index
        updateDisplayState()
        preloadedImage = nil
        preloadedIndex = nil
        preloadNext()
        if !isPaused {
            scheduleAdvance()
        }
    }

    func goNext() {
        guard let idx = nextUntrashedIndex() else {
            if config.noLoop {
                NSApplication.shared.terminate(nil)
                return
            }
            if isTrashed(path: paths[currentIndex]) && !allTrashed {
                enterAllTrashedState()
            } else if !isTrashed(path: paths[currentIndex]) {
                showStatusMessage("1 untrashed image")
            }
            return
        }
        allTrashed = false
        jumpTo(index: idx)
    }

    func goPrevious() {
        allTrashed = false
        jumpTo(index: previousIndex())
    }

    // MARK: - Pause/Play

    func togglePause() {
        isPaused = !isPaused
        if isPaused {
            advanceTimer?.invalidate()
            showStatusIcon(.pause)
        } else {
            showStatusIcon(.play)
            scheduleAdvance()
        }
    }

    func showStatusIcon(_ icon: StatusIconView.Icon) {
        statusFadeTimer?.invalidate()
        statusLabel.alphaValue = 0
        statusIcon.icon = icon
        statusIcon.alphaValue = 1

        statusFadeTimer = Timer.scheduledTimer(withTimeInterval: 0.8, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.3
                    self?.statusIcon.animator().alphaValue = 0
                }
            }
        }
    }

    func showStatusMessage(_ text: String) {
        statusFadeTimer?.invalidate()
        statusIcon.alphaValue = 0
        statusLabel.stringValue = "  \(text)  "
        statusLabel.alphaValue = 1

        statusFadeTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.5
                    self?.statusLabel.animator().alphaValue = 0
                }
            }
        }
    }

    func flashArrow(_ direction: DirectionalArrowView.Direction) {
        switch direction {
        case .left: arrowLeft.flash()
        case .right: arrowRight.flash()
        case .up: arrowUp.flash()
        case .down: arrowDown.flash()
        }
    }

    // After tagging, check if image reached Favorite/Trash (auto-advance) or Untagged (neutral icon).
    func handleTagResult(direction: DirectionalArrowView.Direction) {
        reactToTagChange(at: currentIndex, direction: direction, advanceDelay: 0.5) { [weak self] in
            guard let self = self else { return }
            self.goNext()
            self.flashArrow(.right)
        }
    }

    // Shared tag feedback: flash arrow + auto-advance if tagged, or show dash if untagged.
    // Returns true if the image was tagged (Favorite or Trash) and auto-advance was scheduled.
    @discardableResult
    func reactToTagChange(at index: Int, direction: DirectionalArrowView.Direction,
                          advanceDelay: Double, advanceAction: @escaping @MainActor @Sendable () -> Void) -> Bool {
        autoAdvanceTimer?.invalidate()
        let path = paths[index]

        if isFavorited(path: path) || isTrashed(path: path) {
            flashArrow(direction)
            autoAdvanceTimer = Timer.scheduledTimer(withTimeInterval: advanceDelay, repeats: false) { _ in
                MainActor.assumeIsolated { advanceAction() }
            }
            return true
        } else {
            let arrowView = direction == .up ? arrowUp : arrowDown
            let dashColor = direction == .up ? NSColor.systemRed : NSColor.systemGreen
            arrowView.flashDash(withColor: dashColor)
            return false
        }
    }

    // MARK: - Keyboard

    func handleKeyDown(_ event: NSEvent) {
        guard let key = KeyCode(rawValue: event.keyCode) else { return }

        // Escape/Q always quit, regardless of mode
        if key == .escape || key == .qKey {
            NSApplication.shared.terminate(nil)
            return
        }

        switch viewMode {
        case .slider:
            handleSliderKey(key)
        case .triptych:
            handleTriptychKey(key)
        case .normal:
            switch key {
            case .space:
                togglePause()
            case .rightArrow:
                goNext()
                flashArrow(.right)
            case .leftArrow:
                goPrevious()
                flashArrow(.left)
            case .upArrow:
                tagUp(path: paths[currentIndex])
                updateDisplayState()
                if allTrashed && !checkAllTrashed() {
                    allTrashed = false
                    if !isPaused {
                        scheduleAdvance()
                    }
                }
                handleTagResult(direction: .up)
            case .downArrow:
                tagDown(path: paths[currentIndex])
                updateDisplayState()
                handleTagResult(direction: .down)
            case .sKey:
                enterSliderMode()
            case .tKey:
                enterTriptychMode()
            default:
                break
            }
        }
    }

    // MARK: - Click Handling

    @objc func handleClick(_ recognizer: NSClickGestureRecognizer) {
        guard viewMode != .slider else { return }
        guard let contentView = window.contentView else { return }
        let location = recognizer.location(in: contentView)
        let width = contentView.bounds.width

        if viewMode == .triptych {
            // Left panel + left 10% of middle = go left
            // Right panel + right 10% of middle = go right
            let panelWidth = width / 3.0
            let leftZone = panelWidth + panelWidth * 0.10
            let rightZone = 2 * panelWidth - panelWidth * 0.10
            if location.x < leftZone {
                triptychNavigate(forward: false)
            } else if location.x > rightZone {
                triptychNavigate(forward: true)
            }
            return
        }

        let leftZone = width * 0.10
        let rightZone = width * 0.90

        if location.x < leftZone {
            goPrevious()
            flashArrow(.left)
        } else if location.x > rightZone {
            goNext()
            flashArrow(.right)
        } else {
            togglePause()
        }
    }

    // MARK: - Directory Refresh

    func startRefreshTimer() {
        refreshTimer = Timer.scheduledTimer(withTimeInterval: config.scanInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshDirectory() }
        }
    }

    func refreshDirectory() {
        let currentPath = paths.isEmpty ? nil : paths[currentIndex]

        var newPaths = loadImagePaths(from: config.directoryURL)
        guard !newPaths.isEmpty else { return }

        if config.isRandom {
            let newSeed = UInt64.random(in: 0...UInt64.max)
            var rng = SeededRNG(seed: newSeed)
            newPaths.shuffle(using: &rng)
        }

        paths = newPaths

        if let currentPath = currentPath, let newIndex = paths.firstIndex(of: currentPath) {
            currentIndex = newIndex
        } else {
            currentIndex = min(currentIndex, paths.count - 1)
        }

        preloadedImage = nil
        preloadedIndex = nil
        preloadNext()

        if allTrashed && !checkAllTrashed() {
            allTrashed = false
            updateDisplayState()
            if !isPaused {
                scheduleAdvance()
            }
        } else if !allTrashed && checkAllTrashed() {
            enterAllTrashedState()
        }

        if viewMode == .triptych {
            triptychLoadPanels()
        }
    }

    // MARK: - NSWindowDelegate

    func windowDidResize(_ notification: Notification) {
        switch viewMode {
        case .slider:
            updateSliderMask()
            repositionDivider()
            layoutTitlebarLabels()
        case .triptych:
            triptychLayout()
            layoutTitlebarLabels()
        case .normal:
            break
        }
    }

    func windowWillClose(_ notification: Notification) {
        advanceTimer?.invalidate()
        statusFadeTimer?.invalidate()
        refreshTimer?.invalidate()
        autoAdvanceTimer?.invalidate()
        arrowLeft.fadeTimer?.invalidate()
        arrowRight.fadeTimer?.invalidate()
        arrowUp.fadeTimer?.invalidate()
        arrowDown.fadeTimer?.invalidate()
    }
}
