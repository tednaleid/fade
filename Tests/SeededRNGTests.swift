// ABOUTME: Tests for the SeededRNG deterministic random number generator.
// ABOUTME: Verifies reproducibility, uniqueness across seeds, and shuffle determinism.

import Testing
@testable import fade

@Test func sameSeedProducesSameSequence() {
    var rng1 = SeededRNG(seed: 42)
    var rng2 = SeededRNG(seed: 42)
    for _ in 0..<100 {
        #expect(rng1.next() == rng2.next())
    }
}

@Test func differentSeedsProduceDifferentSequences() {
    var rng1 = SeededRNG(seed: 1)
    var rng2 = SeededRNG(seed: 2)
    let seq1 = (0..<10).map { _ in rng1.next() }
    let seq2 = (0..<10).map { _ in rng2.next() }
    #expect(seq1 != seq2)
}

@Test func shuffleIsDeterministic() {
    var items1 = Array(0..<20)
    var items2 = Array(0..<20)
    var rng1 = SeededRNG(seed: 99)
    var rng2 = SeededRNG(seed: 99)
    items1.shuffle(using: &rng1)
    items2.shuffle(using: &rng2)
    #expect(items1 == items2)
}

@Test func shuffleActuallyReorders() {
    var items = Array(0..<20)
    let original = items
    var rng = SeededRNG(seed: 42)
    items.shuffle(using: &rng)
    #expect(items != original)
}
