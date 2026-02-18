// ABOUTME: NSView and NSWindow subclasses for the slideshow UI.
// ABOUTME: Includes AppDelegate, custom window, status icon, directional arrows, and slider divider.

import AppKit

// MARK: - App Delegate

@MainActor class AppDelegate: NSObject, NSApplicationDelegate {
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

@MainActor class SlideshowWindow: NSWindow {
    weak var keyHandler: SlideshowController?

    override func keyDown(with event: NSEvent) {
        keyHandler?.handleKeyDown(event)
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

// MARK: - Status Icon View

@MainActor class StatusIconView: NSView {
    enum Icon { case pause, play, neutral }

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

        case .neutral:
            // Horizontal dash: —
            let barW: CGFloat = 30
            let barH: CGFloat = 8
            NSBezierPath(rect: NSRect(x: cx - barW / 2, y: cy - barH / 2, width: barW, height: barH)).fill()
        }
    }
}

// MARK: - Directional Arrow View

@MainActor class DirectionalArrowView: NSView {
    enum Direction { case left, right, up, down }

    let direction: Direction
    let originalColor: NSColor
    var color: NSColor { didSet { needsDisplay = true } }
    var drawDash: Bool = false { didSet { needsDisplay = true } }
    var fadeTimer: Timer?

    init(direction: Direction, color: NSColor, frame: NSRect) {
        self.direction = direction
        self.originalColor = color
        self.color = color
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = 16
        layer?.backgroundColor = NSColor(white: 0, alpha: 0.6).cgColor
    }

    required init?(coder: NSCoder) { fatalError() }

    func flash() {
        drawDash = false
        color = originalColor
        flashAndFade()
    }

    func flashDash(withColor dashColor: NSColor) {
        drawDash = true
        color = dashColor
        flashAndFade()
    }

    private func flashAndFade() {
        fadeTimer?.invalidate()
        alphaValue = 1
        fadeTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.3
                    self?.animator().alphaValue = 0
                }
            }
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        color.setFill()

        let bounds = self.bounds
        let cx = bounds.midX
        let cy = bounds.midY
        let size: CGFloat = 30

        if drawDash {
            // Horizontal dash: —
            let barW: CGFloat = 30
            let barH: CGFloat = 8
            NSBezierPath(rect: NSRect(x: cx - barW / 2, y: cy - barH / 2, width: barW, height: barH)).fill()
            return
        }

        let path = NSBezierPath()
        switch direction {
        case .right:
            path.move(to: NSPoint(x: cx - size * 0.4, y: cy + size / 2))
            path.line(to: NSPoint(x: cx - size * 0.4, y: cy - size / 2))
            path.line(to: NSPoint(x: cx + size * 0.6, y: cy))
        case .left:
            path.move(to: NSPoint(x: cx + size * 0.4, y: cy + size / 2))
            path.line(to: NSPoint(x: cx + size * 0.4, y: cy - size / 2))
            path.line(to: NSPoint(x: cx - size * 0.6, y: cy))
        case .up:
            path.move(to: NSPoint(x: cx - size / 2, y: cy - size * 0.4))
            path.line(to: NSPoint(x: cx + size / 2, y: cy - size * 0.4))
            path.line(to: NSPoint(x: cx, y: cy + size * 0.6))
        case .down:
            path.move(to: NSPoint(x: cx - size / 2, y: cy + size * 0.4))
            path.line(to: NSPoint(x: cx + size / 2, y: cy + size * 0.4))
            path.line(to: NSPoint(x: cx, y: cy - size * 0.6))
        }
        path.close()
        path.fill()
    }
}

// MARK: - Slider Divider View

@MainActor class SliderDividerView: NSView {
    var onDrag: ((CGFloat) -> Void)?
    private var isDragging = false

    // The full-height line width and the handle dimensions
    private let lineWidth: CGFloat = 2
    private let handleWidth: CGFloat = 24
    private let handleHeight: CGFloat = 48

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
    }

    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let bounds = self.bounds
        let cx = bounds.midX
        let cy = bounds.midY

        // Vertical line
        NSColor.white.withAlphaComponent(0.8).setFill()
        NSBezierPath(rect: NSRect(x: cx - lineWidth / 2, y: 0, width: lineWidth, height: bounds.height)).fill()

        // Handle pill
        let handleRect = NSRect(
            x: cx - handleWidth / 2,
            y: cy - handleHeight / 2,
            width: handleWidth,
            height: handleHeight)
        let pill = NSBezierPath(roundedRect: handleRect, xRadius: handleWidth / 2, yRadius: handleWidth / 2)
        NSColor(white: 0.2, alpha: 0.9).setFill()
        pill.fill()
        NSColor.white.withAlphaComponent(0.8).setStroke()
        pill.lineWidth = 1.5
        pill.stroke()

        // Grip lines on handle
        NSColor.white.withAlphaComponent(0.6).setStroke()
        for offset: CGFloat in [-4, 0, 4] {
            let gripPath = NSBezierPath()
            gripPath.move(to: NSPoint(x: cx - 5, y: cy + offset))
            gripPath.line(to: NSPoint(x: cx + 5, y: cy + offset))
            gripPath.lineWidth = 1
            gripPath.stroke()
        }
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .resizeLeftRight)
    }

    override func mouseDown(with event: NSEvent) {
        isDragging = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard isDragging, let parentView = superview else { return }
        let parentLocation = parentView.convert(event.locationInWindow, from: nil)
        onDrag?(parentLocation.x)
    }

    override func mouseUp(with event: NSEvent) {
        isDragging = false
    }
}
