// ABOUTME: Tests for loadImagePaths directory scanning.
// ABOUTME: Verifies file extension filtering, hidden file skipping, and sort order.

import XCTest
@testable import fade

final class ImagePathTests: XCTestCase {

    /// Creates a temporary directory with the given filenames and returns its URL.
    private func makeTempDir(files: [String]) throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("fade-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        for name in files {
            FileManager.default.createFile(atPath: dir.appendingPathComponent(name).path, contents: Data())
        }
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        return dir
    }

    func testLoadsJpgAndPngOnly() throws {
        let dir = try makeTempDir(files: ["a.jpg", "b.jpeg", "c.png", "d.gif", "e.txt", "f.bmp"])
        let paths = loadImagePaths(from: dir)
        let names = paths.map { ($0 as NSString).lastPathComponent }
        XCTAssertEqual(names, ["a.jpg", "b.jpeg", "c.png"])
    }

    func testCaseInsensitiveExtensions() throws {
        let dir = try makeTempDir(files: ["a.JPG", "b.Png", "c.JPEG"])
        let paths = loadImagePaths(from: dir)
        XCTAssertEqual(paths.count, 3)
    }

    func testSkipsHiddenFiles() throws {
        let dir = try makeTempDir(files: ["visible.jpg", ".hidden.jpg"])
        let paths = loadImagePaths(from: dir)
        let names = paths.map { ($0 as NSString).lastPathComponent }
        XCTAssertEqual(names, ["visible.jpg"])
    }

    func testReturnsSortedPaths() throws {
        let dir = try makeTempDir(files: ["c.jpg", "a.jpg", "b.jpg"])
        let paths = loadImagePaths(from: dir)
        let names = paths.map { ($0 as NSString).lastPathComponent }
        XCTAssertEqual(names, ["a.jpg", "b.jpg", "c.jpg"])
    }

    func testEmptyDirectoryReturnsEmpty() throws {
        let dir = try makeTempDir(files: [])
        let paths = loadImagePaths(from: dir)
        XCTAssert(paths.isEmpty)
    }

    func testNonexistentDirectoryReturnsEmpty() {
        let bogus = URL(fileURLWithPath: "/tmp/fade-test-nonexistent-\(UUID().uuidString)")
        let paths = loadImagePaths(from: bogus)
        XCTAssert(paths.isEmpty)
    }
}
