//
//  VoiceTests.swift
//  SiriGlassTests
//
//  The voice analysis on its own: synthetic audio in, levels out. The drop
//  itself is checked end to end by the demo's UI tests.
//

import XCTest
@testable import SiriGlass

final class VoiceAnalyzerTests: XCTestCase {
    private let rate = 48_000.0

    private func tone(_ hz: Double, amplitude: Float, count: Int = VoiceAnalyzer.windowSize) -> [Float] {
        (0..<count).map { amplitude * Float(sin(2 * .pi * hz * Double($0) / rate)) }
    }

    private func measure(_ analyzer: VoiceAnalyzer, _ samples: [Float]) -> SiriGlassLevels {
        samples.withUnsafeBufferPointer { analyzer.measure($0, sampleRate: rate, elapsed: 0.1) }
    }

    func testSilenceIsCalm() {
        let levels = measure(VoiceAnalyzer(), [Float](repeating: 0, count: VoiceAnalyzer.windowSize))
        XCTAssertEqual(levels.loudness, 0)
        XCTAssertEqual(levels.low, 0)
        XCTAssertEqual(levels.high, 0)
    }

    func testAQuietRoomStaysCalm() {
        // About -60 dBFS of hum: below the gate.
        let levels = measure(VoiceAnalyzer(), tone(120, amplitude: 0.001))
        XCTAssertEqual(levels.loudness, 0, accuracy: 0.001)
    }

    func testASpeakingVoiceLightsItUp() {
        let levels = measure(VoiceAnalyzer(), tone(220, amplitude: 0.3))
        XCTAssertGreaterThan(levels.loudness, 0.9)
    }

    func testVowelsAndConsonantsLandInTheirBands() {
        let vowel = measure(VoiceAnalyzer(), tone(220, amplitude: 0.3))
        XCTAssertGreaterThan(vowel.low, vowel.high)
        let hiss = measure(VoiceAnalyzer(), tone(3_500, amplitude: 0.3))
        XCTAssertGreaterThan(hiss.high, hiss.low)
    }

    func testOneBadSampleDoesNotPoisonWhatFollows() {
        let analyzer = VoiceAnalyzer()
        var broken = tone(220, amplitude: 0.3)
        broken[10] = .nan
        XCTAssertEqual(measure(analyzer, broken).loudness, 0)
        XCTAssertGreaterThan(measure(analyzer, tone(220, amplitude: 0.3)).loudness, 0.9)
    }
}

final class SiriGlassLevelsTests: XCTestCase {
    func testLevelsStayBetweenZeroAndOne() {
        let levels = SiriGlassLevels(loudness: 2, low: -1, mid: .nan, high: .infinity)
        XCTAssertEqual(levels.loudness, 1)
        XCTAssertEqual(levels.low, 0)
        XCTAssertEqual(levels.mid, 0)
        XCTAssertEqual(levels.high, 0)
    }

    func testBandsFollowTheLoudnessWhenLeftOut() {
        let levels = SiriGlassLevels(loudness: 0.8)
        XCTAssertEqual(levels.low, 0.8, accuracy: 0.0001)
        XCTAssertLessThan(levels.high, levels.mid)
        XCTAssertLessThan(levels.mid, levels.low)
    }
}

final class VoiceDriveTests: XCTestCase {
    func testTheStrandsRunFasterWhileSomeoneSpeaks() {
        var quiet = VoiceDrive(), speaking = VoiceDrive()
        for _ in 0..<60 {
            quiet.advance(toward: SiriGlassLevels(), dt: 1.0 / 60)
            speaking.advance(toward: SiriGlassLevels(loudness: 1), dt: 1.0 / 60)
        }
        let start = VoiceDrive().phases
        XCTAssertGreaterThan(abs(speaking.phases.x - start.x), abs(quiet.phases.x - start.x) * 2)
    }

    func testLevelsRiseQuicklyAndFallSlowly() {
        var drive = VoiceDrive()
        for _ in 0..<6 { drive.advance(toward: SiriGlassLevels(loudness: 1), dt: 1.0 / 60) }
        XCTAssertGreaterThan(drive.levels.loudness, 0.9)
        for _ in 0..<6 { drive.advance(toward: SiriGlassLevels(), dt: 1.0 / 60) }
        XCTAssertGreaterThan(drive.levels.loudness, 0.45)
    }
}
