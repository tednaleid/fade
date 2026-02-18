// ABOUTME: Tests for Finder tag operations (tagUp, tagDown, isTrashed, isFavorited).
// ABOUTME: Uses temporary files to verify the tag cycling state machine.

import XCTest
@testable import fade

final class FinderTagTests: XCTestCase {

    /// Creates a temporary file and returns its path.
    private func makeTempFile() throws -> String {
        let dir = FileManager.default.temporaryDirectory
        let path = dir.appendingPathComponent("fade-test-\(UUID().uuidString).jpg").path
        FileManager.default.createFile(atPath: path, contents: Data())
        addTeardownBlock { try? FileManager.default.removeItem(atPath: path) }
        return path
    }

    func testNewFileHasNoTags() throws {
        let path = try makeTempFile()
        XCTAssertFalse(isTrashed(path: path))
        XCTAssertFalse(isFavorited(path: path))
        XCTAssert(getFileTags(path: path).isEmpty)
    }

    func testTagUpCyclesToFavorite() throws {
        let path = try makeTempFile()

        // Untagged → Favorite
        tagUp(path: path)
        XCTAssertTrue(isFavorited(path: path))
        XCTAssertFalse(isTrashed(path: path))

        // Favorite → still Favorite (ceiling)
        tagUp(path: path)
        XCTAssertTrue(isFavorited(path: path))
    }

    func testTagDownCyclesToTrash() throws {
        let path = try makeTempFile()

        // Untagged → Trash
        tagDown(path: path)
        XCTAssertTrue(isTrashed(path: path))
        XCTAssertFalse(isFavorited(path: path))

        // Trash → still Trash (floor)
        tagDown(path: path)
        XCTAssertTrue(isTrashed(path: path))
    }

    func testTagUpFromTrashGoesToUntagged() throws {
        let path = try makeTempFile()
        tagDown(path: path)
        XCTAssertTrue(isTrashed(path: path))

        // Trash → Untagged
        tagUp(path: path)
        XCTAssertFalse(isTrashed(path: path))
        XCTAssertFalse(isFavorited(path: path))
    }

    func testTagDownFromFavoriteGoesToUntagged() throws {
        let path = try makeTempFile()
        tagUp(path: path)
        XCTAssertTrue(isFavorited(path: path))

        // Favorite → Untagged
        tagDown(path: path)
        XCTAssertFalse(isFavorited(path: path))
        XCTAssertFalse(isTrashed(path: path))
    }

    func testFullCycleUpThenDown() throws {
        let path = try makeTempFile()

        // Untagged → Favorite → Untagged → Trash
        tagUp(path: path)
        XCTAssertTrue(isFavorited(path: path))
        tagDown(path: path)
        XCTAssertFalse(isFavorited(path: path))
        XCTAssertFalse(isTrashed(path: path))
        tagDown(path: path)
        XCTAssertTrue(isTrashed(path: path))

        // Trash → Untagged → Favorite
        tagUp(path: path)
        XCTAssertFalse(isTrashed(path: path))
        XCTAssertFalse(isFavorited(path: path))
        tagUp(path: path)
        XCTAssertTrue(isFavorited(path: path))
    }
}
