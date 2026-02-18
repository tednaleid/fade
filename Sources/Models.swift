// ABOUTME: Data types and utility functions shared across the app.
// ABOUTME: Includes config, RNG, Finder tag operations, and image path discovery.

import AppKit

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

func isTrashed(path: String) -> Bool {
    getFileTags(path: path).contains(trashTag.finderTag)
}

func isFavorited(path: String) -> Bool {
    getFileTags(path: path).contains(favoriteTag.finderTag)
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

// MARK: - Key Codes

enum KeyCode: UInt16 {
    case space = 49
    case rightArrow = 124
    case leftArrow = 123
    case upArrow = 126
    case downArrow = 125
    case sKey = 1
    case tKey = 17
    case escape = 53
    case qKey = 12
}

// MARK: - View Mode

enum ViewMode {
    case normal
    case slider
    case triptych
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
    let startWithSlider: Bool
    let startWithTriptych: Bool
    let startFile: String?  // If set, start on this file instead of first untrashed
}
