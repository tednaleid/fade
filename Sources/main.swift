// ABOUTME: A macOS image slideshow app launched from the command line.
// ABOUTME: Displays images with cross-fade transitions, keyboard/click navigation, and pause/play.

import AppKit
import ArgumentParser

// MARK: - CLI Entry Point

@main
struct Fade: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Display images from a directory as a slideshow with fade transitions."
    )

    @Argument(help: "Directory containing images.")
    var directory: String = "."

    @Option(name: [.short, .long], help: "Seconds each image is displayed.")
    var duration: Double = 10.0

    @Option(name: [.short, .long], help: "Fade transition duration in seconds.")
    var fade: Double = 1.5

    @Flag(name: [.short, .long], help: "Shuffle image order.")
    var random: Bool = false

    @Option(name: [.short, .long], help: "Seed for shuffle (UInt64). Auto-generated if omitted.")
    var seed: UInt64?

    @Flag(name: .long, help: "Exit after showing all images once.")
    var noLoop: Bool = false

    @Flag(name: .long, help: "Use --width/--height instead of fitting window to screen.")
    var actualSize: Bool = false

    @Flag(name: .long, help: "Keep the CLI attached (don't detach to background).")
    var foreground: Bool = false

    // Hidden flag: set when re-spawned as the background GUI process
    @Flag(name: .long, help: .hidden)
    var _spawned: Bool = false

    @Option(help: "Seconds between directory rescans for new images.")
    var scan: Double = 30.0

    @Option(help: "Initial window width.")
    var width: Int = 800

    @Option(help: "Initial window height.")
    var height: Int = 1200

    mutating func run() throws {
        let resolvedDir = (directory as NSString).standardizingPath
        let dirURL: URL
        if resolvedDir.hasPrefix("/") {
            dirURL = URL(fileURLWithPath: resolvedDir, isDirectory: true)
        } else {
            dirURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent(resolvedDir, isDirectory: true)
        }

        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: dirURL.path, isDirectory: &isDir), isDir.boolValue else {
            throw ValidationError("Not a directory: \(dirURL.path)")
        }

        var paths = loadImagePaths(from: dirURL)
        guard !paths.isEmpty else {
            throw ValidationError("No images found in \(dirURL.path)")
        }

        if random {
            let usedSeed: UInt64
            if let provided = seed {
                usedSeed = provided
            } else {
                usedSeed = UInt64.random(in: 0...UInt64.max)
            }
            print("Shuffle seed: \(usedSeed)")
            var rng = SeededRNG(seed: usedSeed)
            paths.shuffle(using: &rng)
        }

        let config = SlideshowConfig(
            paths: paths,
            duration: duration,
            fadeDuration: fade,
            noLoop: noLoop,
            fitScreen: !actualSize,
            windowWidth: CGFloat(width),
            windowHeight: CGFloat(height),
            directoryURL: dirURL,
            isRandom: random,
            scanInterval: scan
        )

        // Spawn a background process so the CLI returns immediately
        if !foreground && !_spawned {
            var args = ProcessInfo.processInfo.arguments
            args.append("--_spawned")
            let argv = args.map { strdup($0) } + [nil]
            defer { argv.compactMap({ $0 }).forEach { free($0) } }

            var pid: pid_t = 0
            var fileActions: posix_spawn_file_actions_t?
            posix_spawn_file_actions_init(&fileActions)
            // Redirect stdin/stdout/stderr to /dev/null so the child is detached
            posix_spawn_file_actions_addopen(&fileActions, STDIN_FILENO, "/dev/null", O_RDONLY, 0)
            posix_spawn_file_actions_addopen(&fileActions, STDOUT_FILENO, "/dev/null", O_WRONLY, 0)
            posix_spawn_file_actions_addopen(&fileActions, STDERR_FILENO, "/dev/null", O_WRONLY, 0)

            let result = posix_spawn(&pid, args[0], &fileActions, nil, argv, environ)
            posix_spawn_file_actions_destroy(&fileActions)

            guard result == 0 else {
                throw ValidationError("Failed to spawn background process: \(result)")
            }
            return
        }

        let app = NSApplication.shared
        app.setActivationPolicy(.regular)

        let delegate = AppDelegate(config: config)
        app.delegate = delegate
        app.run()
    }
}

// MARK: - Seeded RNG

struct SeededRNG: RandomNumberGenerator {
    // Simple splitmix64 generator for reproducible shuffles.
    var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9e3779b97f4a7c15
        var z = state
        z = (z ^ (z >> 30)) &* 0xbf58476d1ce4e5b9
        z = (z ^ (z >> 27)) &* 0x94d049bb133111eb
        return z ^ (z >> 31)
    }
}

// MARK: - Image Loading

func loadImagePaths(from directory: URL) -> [String] {
    let extensions: Set<String> = ["jpg", "jpeg", "png"]
    guard let contents = try? FileManager.default.contentsOfDirectory(
        at: directory,
        includingPropertiesForKeys: nil,
        options: [.skipsHiddenFiles]
    ) else {
        return []
    }

    return contents
        .filter { extensions.contains($0.pathExtension.lowercased()) }
        .map { $0.path }
        .sorted()
}

// MARK: - Finder Tags

struct TagInfo {
    let name: String       // Display name: "Favorite" / "Trash"
    let finderTag: String  // Built-in Finder color tag: "Green" / "Red"
    let dot: String        // Emoji for title bar: "🟢" / "🔴"
}

let favoriteTag = TagInfo(name: "Favorite", finderTag: "Green", dot: "🟢")
let trashTag = TagInfo(name: "Trash", finderTag: "Red", dot: "🔴")

func getFileTags(path: String) -> [String] {
    let url = NSURL(fileURLWithPath: path)
    var tags: AnyObject?
    try? url.getResourceValue(&tags, forKey: .tagNamesKey)
    return tags as? [String] ?? []
}

func setFileTags(path: String, tags: [String]) {
    let url = NSURL(fileURLWithPath: path)
    try? url.setResourceValue(tags, forKey: .tagNamesKey)
}

// Moves the file one step toward Favorite: Trash → Untagged → Favorite
func tagUp(path: String) {
    var tags = getFileTags(path: path)
    if tags.contains(trashTag.finderTag) {
        tags.removeAll { $0 == trashTag.finderTag }
    } else if !tags.contains(favoriteTag.finderTag) {
        tags.append(favoriteTag.finderTag)
    }
    setFileTags(path: path, tags: tags)
}

// Moves the file one step toward Trash: Favorite → Untagged → Trash
func tagDown(path: String) {
    var tags = getFileTags(path: path)
    if tags.contains(favoriteTag.finderTag) {
        tags.removeAll { $0 == favoriteTag.finderTag }
    } else if !tags.contains(trashTag.finderTag) {
        tags.append(trashTag.finderTag)
    }
    setFileTags(path: path, tags: tags)
}

// MARK: - Config

struct SlideshowConfig {
    let paths: [String]
    let duration: Double
    let fadeDuration: Double
    let noLoop: Bool
    let fitScreen: Bool
    let windowWidth: CGFloat
    let windowHeight: CGFloat
    let directoryURL: URL
    let isRandom: Bool
    let scanInterval: Double
}

// MARK: - App Delegate

class AppDelegate: NSObject, NSApplicationDelegate {
    let config: SlideshowConfig
    var controller: SlideshowController?

    init(config: SlideshowConfig) {
        self.config = config
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        controller = SlideshowController(config: config)
        controller?.start()
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }
}

// MARK: - Slideshow Window

class SlideshowWindow: NSWindow {
    weak var keyHandler: SlideshowController?

    override func keyDown(with event: NSEvent) {
        keyHandler?.handleKeyDown(event)
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

// MARK: - Status Icon View

class StatusIconView: NSView {
    enum Icon { case pause, play }

    var icon: Icon = .pause {
        didSet { needsDisplay = true }
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = 16
        layer?.backgroundColor = NSColor(white: 0, alpha: 0.6).cgColor
    }

    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        NSColor.white.setFill()

        let bounds = self.bounds
        let cx = bounds.midX
        let cy = bounds.midY

        switch icon {
        case .pause:
            // Two vertical bars: ❚❚
            let barW: CGFloat = 8
            let barH: CGFloat = 30
            let gap: CGFloat = 8
            let leftX = cx - gap / 2 - barW
            let rightX = cx + gap / 2
            let y = cy - barH / 2
            NSBezierPath(rect: NSRect(x: leftX, y: y, width: barW, height: barH)).fill()
            NSBezierPath(rect: NSRect(x: rightX, y: y, width: barW, height: barH)).fill()

        case .play:
            // Right-pointing triangle: ▶
            let size: CGFloat = 30
            let path = NSBezierPath()
            path.move(to: NSPoint(x: cx - size * 0.4, y: cy + size / 2))
            path.line(to: NSPoint(x: cx - size * 0.4, y: cy - size / 2))
            path.line(to: NSPoint(x: cx + size * 0.6, y: cy))
            path.close()
            path.fill()
        }
    }
}

// MARK: - Slideshow Controller

class SlideshowController: NSObject, NSWindowDelegate {
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

    var currentIndex: Int = 0
    var isPaused: Bool = false
    var allTrashed: Bool = false
    var advanceTimer: Timer?
    var refreshTimer: Timer?

    // Preloaded next image
    var preloadedImage: NSImage?
    var preloadedIndex: Int?

    // Desaturation filter for trash-tagged images
    let desaturateFilter: CIFilter = {
        let f = CIFilter(name: "CIColorControls")!
        f.setValue(0.3, forKey: kCIInputSaturationKey)
        return f
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
            statusLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 200),
        ])

        window.contentView = containerView

        super.init()

        window.delegate = self
        window.keyHandler = self
    }

    func start() {
        guard !paths.isEmpty else { return }

        // Find the first untrashed image to display
        guard let startIndex = firstUntrashedIndex() else {
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
    }

    // MARK: - Display State

    // Updates title bar and desaturation filter to reflect current image's tag state.
    func updateDisplayState() {
        let path = paths[currentIndex]
        let tags = getFileTags(path: path)

        var title = (path as NSString).lastPathComponent
        for info in [favoriteTag, trashTag] where tags.contains(info.finderTag) {
            title += "  \(info.dot) \(info.name)"
        }
        window.title = title

        let isTrash = tags.contains(trashTag.finderTag)
        frontView.contentFilters = isTrash ? [desaturateFilter] : []
    }

    // MARK: - All-Trashed State

    func checkAllTrashed() -> Bool {
        return paths.allSatisfy { getFileTags(path: $0).contains(trashTag.finderTag) }
    }

    // Returns the index of the first untrashed image, or nil if all are trashed.
    func firstUntrashedIndex() -> Int? {
        return paths.firstIndex { !getFileTags(path: $0).contains(trashTag.finderTag) }
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
        let nextIdx = nextUntrashedIndex()
        guard nextIdx != nil else {
            preloadedImage = nil
            preloadedIndex = nil
            return
        }
        let idx = nextIdx!
        preloadedIndex = idx
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let image = self?.loadImage(at: idx)
            DispatchQueue.main.async {
                guard let self = self, self.preloadedIndex == idx else { return }
                self.preloadedImage = image
            }
        }
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
            let tags = getFileTags(path: paths[candidate])
            if !tags.contains(trashTag.finderTag) {
                return candidate
            }
        }
        return nil
    }

    func scheduleAdvance() {
        advanceTimer?.invalidate()
        guard !isPaused else { return }
        advanceTimer = Timer.scheduledTimer(withTimeInterval: config.duration, repeats: false) { [weak self] _ in
            self?.advanceWithFade()
        }
    }

    func advanceWithFade() {
        guard let nextIdx = nextUntrashedIndex() else {
            if config.noLoop {
                NSApplication.shared.terminate(nil)
                return
            }
            // Check if the current image is the sole untrashed one
            let currentIsTrashed = getFileTags(path: paths[currentIndex]).contains(trashTag.finderTag)
            if currentIsTrashed {
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

        let nextIsTrash = getFileTags(path: paths[nextIdx]).contains(trashTag.finderTag)
        crossFade(to: image, isTrash: nextIsTrash)
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
            guard let self = self else { return }
            // Swap: front becomes back, back becomes front
            self.frontView.alphaValue = 1
            self.frontView.image = self.backView.image
            self.backView.alphaValue = 0
            self.backView.image = nil
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
            let currentIsTrashed = getFileTags(path: paths[currentIndex]).contains(trashTag.finderTag)
            if currentIsTrashed && !allTrashed {
                enterAllTrashedState()
            } else if !currentIsTrashed {
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
        statusIcon.icon = icon
        statusIcon.alphaValue = 1

        statusFadeTimer = Timer.scheduledTimer(withTimeInterval: 0.8, repeats: false) { [weak self] _ in
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.3
                self?.statusIcon.animator().alphaValue = 0
            }
        }
    }

    func showStatusMessage(_ text: String) {
        statusFadeTimer?.invalidate()
        statusLabel.stringValue = "  \(text)  "
        statusLabel.alphaValue = 1

        statusFadeTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: false) { [weak self] _ in
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.5
                self?.statusLabel.animator().alphaValue = 0
            }
        }
    }

    // MARK: - Keyboard

    func handleKeyDown(_ event: NSEvent) {
        switch event.keyCode {
        case 49:  // Space
            togglePause()
        case 124: // Right arrow
            goNext()
        case 123: // Left arrow
            goPrevious()
        case 126: // Up arrow — move toward Favorite
            tagUp(path: paths[currentIndex])
            updateDisplayState()
            if allTrashed && !checkAllTrashed() {
                allTrashed = false
                if !isPaused {
                    scheduleAdvance()
                }
            }
        case 125: // Down arrow — move toward Trash
            tagDown(path: paths[currentIndex])
            updateDisplayState()
        case 53:  // Escape
            NSApplication.shared.terminate(nil)
        case 12:  // Q
            NSApplication.shared.terminate(nil)
        default:
            break
        }
    }

    // MARK: - Click Handling

    @objc func handleClick(_ recognizer: NSClickGestureRecognizer) {
        guard let contentView = window.contentView else { return }
        let location = recognizer.location(in: contentView)
        let width = contentView.bounds.width

        let leftZone = width * 0.10
        let rightZone = width * 0.90

        if location.x < leftZone {
            goPrevious()
        } else if location.x > rightZone {
            goNext()
        } else {
            togglePause()
        }
    }

    // MARK: - Directory Refresh

    func startRefreshTimer() {
        refreshTimer = Timer.scheduledTimer(withTimeInterval: config.scanInterval, repeats: true) { [weak self] _ in
            self?.refreshDirectory()
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
    }

    // MARK: - NSWindowDelegate

    func windowWillClose(_ notification: Notification) {
        advanceTimer?.invalidate()
        statusFadeTimer?.invalidate()
        refreshTimer?.invalidate()
    }
}
