// ABOUTME: CLI entry point for the fade image slideshow app.
// ABOUTME: Parses arguments, spawns background process, and launches the NSApplication.

@preconcurrency import AppKit
import ArgumentParser

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

    @Flag(name: .long, help: "Start with comparison slider visible.")
    var slider: Bool = false

    @Option(help: "Seconds between directory rescans for new images.")
    var scan: Double = 30.0

    @Option(help: "Initial window width.")
    var width: Int = 800

    @Option(help: "Initial window height.")
    var height: Int = 1200

    mutating func run() throws {
        let resolvedPath = (directory as NSString).standardizingPath
        let inputURL: URL
        if resolvedPath.hasPrefix("/") {
            inputURL = URL(fileURLWithPath: resolvedPath)
        } else {
            inputURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent(resolvedPath)
        }

        // Determine if argument is a file or directory
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: inputURL.path, isDirectory: &isDir) else {
            throw ValidationError("Path does not exist: \(inputURL.path)")
        }

        let dirURL: URL
        let startFile: String?
        if isDir.boolValue {
            dirURL = inputURL
            startFile = nil
        } else {
            dirURL = inputURL.deletingLastPathComponent()
            startFile = inputURL.path
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
            scanInterval: scan,
            startWithSlider: slider,
            startFile: startFile
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

        MainActor.assumeIsolated {
            let app = NSApplication.shared
            app.setActivationPolicy(.regular)

            let delegate = AppDelegate(config: config)
            app.delegate = delegate
            app.run()
        }
    }
}
