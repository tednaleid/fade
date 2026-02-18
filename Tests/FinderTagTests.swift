// ABOUTME: Tests for Finder tag operations (tagUp, tagDown, isTrashed, isFavorited).
// ABOUTME: Uses temporary files to verify the tag cycling state machine.

import Testing
import Foundation
@testable import fade

/// Creates a temporary file and returns its path. Caller must clean up.
private func makeTempFile() throws -> String {
    let dir = FileManager.default.temporaryDirectory
    let path = dir.appendingPathComponent("fade-test-\(UUID().uuidString).jpg").path
    FileManager.default.createFile(atPath: path, contents: Data())
    return path
}

@Test func newFileHasNoTags() throws {
    let path = try makeTempFile()
    defer { try? FileManager.default.removeItem(atPath: path) }

    #expect(!isTrashed(path: path))
    #expect(!isFavorited(path: path))
    #expect(getFileTags(path: path).isEmpty)
}

@Test func tagUpCyclesToFavorite() throws {
    let path = try makeTempFile()
    defer { try? FileManager.default.removeItem(atPath: path) }

    // Untagged → Favorite
    tagUp(path: path)
    #expect(isFavorited(path: path))
    #expect(!isTrashed(path: path))

    // Favorite → still Favorite (ceiling)
    tagUp(path: path)
    #expect(isFavorited(path: path))
}

@Test func tagDownCyclesToTrash() throws {
    let path = try makeTempFile()
    defer { try? FileManager.default.removeItem(atPath: path) }

    // Untagged → Trash
    tagDown(path: path)
    #expect(isTrashed(path: path))
    #expect(!isFavorited(path: path))

    // Trash → still Trash (floor)
    tagDown(path: path)
    #expect(isTrashed(path: path))
}

@Test func tagUpFromTrashGoesToUntagged() throws {
    let path = try makeTempFile()
    defer { try? FileManager.default.removeItem(atPath: path) }

    tagDown(path: path)
    #expect(isTrashed(path: path))

    // Trash → Untagged
    tagUp(path: path)
    #expect(!isTrashed(path: path))
    #expect(!isFavorited(path: path))
}

@Test func tagDownFromFavoriteGoesToUntagged() throws {
    let path = try makeTempFile()
    defer { try? FileManager.default.removeItem(atPath: path) }

    tagUp(path: path)
    #expect(isFavorited(path: path))

    // Favorite → Untagged
    tagDown(path: path)
    #expect(!isFavorited(path: path))
    #expect(!isTrashed(path: path))
}

@Test func fullCycleUpThenDown() throws {
    let path = try makeTempFile()
    defer { try? FileManager.default.removeItem(atPath: path) }

    // Untagged → Favorite → Untagged → Trash
    tagUp(path: path)
    #expect(isFavorited(path: path))
    tagDown(path: path)
    #expect(!isFavorited(path: path))
    #expect(!isTrashed(path: path))
    tagDown(path: path)
    #expect(isTrashed(path: path))

    // Trash → Untagged → Favorite
    tagUp(path: path)
    #expect(!isTrashed(path: path))
    #expect(!isFavorited(path: path))
    tagUp(path: path)
    #expect(isFavorited(path: path))
}
