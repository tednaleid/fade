// ABOUTME: Tests for loadImagePaths directory scanning.
// ABOUTME: Verifies file extension filtering, hidden file skipping, and sort order.

import Testing
import Foundation
@testable import fade

/// Creates a temporary directory with the given filenames and returns its URL. Caller must clean up.
private func makeTempDir(files: [String]) throws -> URL {
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("fade-test-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    for name in files {
        FileManager.default.createFile(atPath: dir.appendingPathComponent(name).path, contents: Data())
    }
    return dir
}

@Test func loadsJpgAndPngOnly() throws {
    let dir = try makeTempDir(files: ["a.jpg", "b.jpeg", "c.png", "d.gif", "e.txt", "f.bmp"])
    defer { try? FileManager.default.removeItem(at: dir) }

    let paths = loadImagePaths(from: dir)
    let names = paths.map { ($0 as NSString).lastPathComponent }
    #expect(names == ["a.jpg", "b.jpeg", "c.png"])
}

@Test func caseInsensitiveExtensions() throws {
    let dir = try makeTempDir(files: ["a.JPG", "b.Png", "c.JPEG"])
    defer { try? FileManager.default.removeItem(at: dir) }

    let paths = loadImagePaths(from: dir)
    #expect(paths.count == 3)
}

@Test func skipsHiddenFiles() throws {
    let dir = try makeTempDir(files: ["visible.jpg", ".hidden.jpg"])
    defer { try? FileManager.default.removeItem(at: dir) }

    let paths = loadImagePaths(from: dir)
    let names = paths.map { ($0 as NSString).lastPathComponent }
    #expect(names == ["visible.jpg"])
}

@Test func returnsSortedPaths() throws {
    let dir = try makeTempDir(files: ["c.jpg", "a.jpg", "b.jpg"])
    defer { try? FileManager.default.removeItem(at: dir) }

    let paths = loadImagePaths(from: dir)
    let names = paths.map { ($0 as NSString).lastPathComponent }
    #expect(names == ["a.jpg", "b.jpg", "c.jpg"])
}

@Test func emptyDirectoryReturnsEmpty() throws {
    let dir = try makeTempDir(files: [])
    defer { try? FileManager.default.removeItem(at: dir) }

    let paths = loadImagePaths(from: dir)
    #expect(paths.isEmpty)
}

@Test func nonexistentDirectoryReturnsEmpty() {
    let bogus = URL(fileURLWithPath: "/tmp/fade-test-nonexistent-\(UUID().uuidString)")
    let paths = loadImagePaths(from: bogus)
    #expect(paths.isEmpty)
}
