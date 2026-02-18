// ABOUTME: Tests for the SeededRNG deterministic random number generator.
// ABOUTME: Verifies reproducibility, uniqueness across seeds, and shuffle determinism.

import XCTest
@testable import fade

final class SeededRNGTests: XCTestCase {

    func testSameSeedProducesSameSequence() {
        var rng1 = SeededRNG(seed: 42)
        var rng2 = SeededRNG(seed: 42)
        for _ in 0..<100 {
            XCTAssertEqual(rng1.next(), rng2.next())
        }
    }

    func testDifferentSeedsProduceDifferentSequences() {
        var rng1 = SeededRNG(seed: 1)
        var rng2 = SeededRNG(seed: 2)
        let seq1 = (0..<10).map { _ in rng1.next() }
        let seq2 = (0..<10).map { _ in rng2.next() }
        XCTAssertNotEqual(seq1, seq2)
    }

    func testShuffleIsDeterministic() {
        var items1 = Array(0..<20)
        var items2 = Array(0..<20)
        var rng1 = SeededRNG(seed: 99)
        var rng2 = SeededRNG(seed: 99)
        items1.shuffle(using: &rng1)
        items2.shuffle(using: &rng2)
        XCTAssertEqual(items1, items2)
    }

    func testShuffleActuallyReorders() {
        var items = Array(0..<20)
        let original = items
        var rng = SeededRNG(seed: 42)
        items.shuffle(using: &rng)
        XCTAssertNotEqual(items, original)
    }
}
