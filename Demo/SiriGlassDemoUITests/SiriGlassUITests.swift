//
//  SiriGlassUITests.swift
//  SiriGlassDemoUITests
//
//  End to end on iPhone: launches the demo, summons Siri with a real tap,
//  and watches what the user would: the drop pouring out of the island,
//  the light swelling when the voice is loud and settling when it is quiet,
//  then Siri thinking and leaving on its own once the talking stops; the
//  picker moving it between the orb and the home screen; a tap sending it
//  away, even a tap right on the drop.
//
//  Stubbed at the boundary: the microphone. The voice comes from a file
//  (TEST_RUNNER_SIRI_VOICE; make it with `Scripts/voice.py out.wav
//  --lead 5`, so its first five seconds are silent) that the app runs
//  through the same analyser the microphone feeds, from the moment of the
//  tap, via the package's public `SiriGlassAudio.file(_:muted:)`. Muted, so
//  a test run doesn't talk out of the Mac. Screenshots land in
//  TEST_RUNNER_SIRI_OUT when it is set.
//

import XCTest

final class SiriGlassUITests: XCTestCase {

    private var voice: String? { ProcessInfo.processInfo.environment["SIRI_VOICE"] }
    private var outDir: String? { ProcessInfo.processInfo.environment["SIRI_OUT"] }

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func launch(stage: String? = nil) throws -> XCUIApplication {
        let voice = try XCTUnwrap(voice, "set TEST_RUNNER_SIRI_VOICE to a voice file")
        let app = XCUIApplication()
        app.launchEnvironment["SIRIGLASS_AUDIO"] = voice
        app.launchEnvironment["SIRIGLASS_MUTE"] = "1"
        app.launchEnvironment["SIRIGLASS_PROBE"] = "1"
        if let stage { app.launchEnvironment["SIRIGLASS_STAGE"] = stage }
        app.launch()
        return app
    }

    /// The drop over the home screen, reacting to a voice: `.siriGlass`.
    @MainActor
    func testSiriListensReactsThinksAndLeaves() throws {
        let app = try launch(stage: "iPhone")
        let stage = app.descendants(matching: .any)["siriGlass.stage"]
        XCTAssertTrue(stage.waitForExistence(timeout: 60), "the home screen never appeared")
        XCTAssertEqual(stage.value as? String, "Asleep")
        // Let the first frames (and the shader's pipeline) draw.
        Thread.sleep(forTimeInterval: 2)
        let asleep = shot("0-asleep")

        stage.tap()
        XCTAssertTrue(wait(for: stage, value: "Listening", timeout: 5), "a tap didn't summon Siri")

        // The test voice is silent for its first 5 s: the light should be calm.
        let probe = app.staticTexts["siriGlass.level"]
        XCTAssertTrue(probe.waitForExistence(timeout: 5))
        Thread.sleep(forTimeInterval: 1.2)
        let calm = level(probe)
        let quiet = shot("1-listening-quiet")
        print("[siri-e2e] level before the voice: \(calm)")
        XCTAssertLessThan(calm, 0.1, "the drop reacted before anyone spoke")

        // Then the voice: wait until it is loud and catch that frame.
        var loudLevel: Float = 0
        let deadline = Date().addingTimeInterval(14)
        while Date() < deadline {
            loudLevel = level(probe)
            if loudLevel > 0.6 { break }
        }
        let loud = shot("2-listening-loud")
        print("[siri-e2e] level during the voice: \(loudLevel)")
        XCTAssertGreaterThan(loudLevel, 0.6, "the voice never registered")

        // What a person sees: just wallpaper under the island while asleep;
        // once summoned, the drop's dark ink there and a thin line of light
        // while it listens to silence; more light while the voice is loud.
        let ink = CGRect(x: 150, y: 54, width: 140, height: 12)        // below the island, above the line
        let light = CGRect(x: 145, y: 60, width: 150, height: 34)
        let before = band(asleep, ink), calmInk = band(quiet, ink)
        let calmLight = band(quiet, light), loudLight = band(loud, light)
        print("[siri-e2e] under the island (bright, dark px): asleep \(before), listening \(calmInk)")
        print("[siri-e2e] where the light lives: quiet \(calmLight), loud \(loudLight)")
        XCTAssertLessThan(before.dark, before.total / 20, "something dark was over the home screen before Siri")
        XCTAssertGreaterThan(calmInk.dark, calmInk.total / 2, "no dark drop once Siri was summoned")
        XCTAssertGreaterThan(calmLight.bright, 0, "no line of light while listening")
        XCTAssertGreaterThan(Double(loudLight.bright), Double(calmLight.bright) * 1.5, "the light didn't swell with the voice")

        // Siri stops listening a beat after the talking stops, thinks, and
        // (the demo answering after a second) slips back into the island.
        // Thinking is short, which a busy machine's checks can step over, so
        // any move on from listening counts, then it has to end up gone.
        let movedOn = NSPredicate(format: "value != %@", "Listening")
        let stopped = XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: movedOn, object: stage)], timeout: 25) == .completed
        XCTAssertTrue(stopped, "Siri never stopped listening")
        print("[siri-e2e] after the voice: \(stage.value as? String ?? "?")")
        shot("3-thinking")
        XCTAssertTrue(wait(for: stage, value: "Asleep", timeout: 8), "Siri never left")
        Thread.sleep(forTimeInterval: 1.0)
        let gone = shot("4-gone")
        XCTAssertLessThan(band(gone, ink).dark, band(gone, ink).total / 20, "the drop didn't go back into the island")
    }

    /// The picker moves Siri between the orb (`SiriGlassOrb`, in the
    /// middle of a white screen) and the iPhone (`.siriGlass`, under the
    /// island); either way it comes back out listening.
    @MainActor
    func testStagePickerMovesSiriBetweenOrbAndIPhone() throws {
        let app = try launch()
        let stage = app.descendants(matching: .any)["siriGlass.stage"]
        XCTAssertTrue(stage.waitForExistence(timeout: 60))
        Thread.sleep(forTimeInterval: 2)
        let empty = shot("5-orb-asleep")
        stage.tap()
        XCTAssertTrue(wait(for: stage, value: "Listening", timeout: 5))
        Thread.sleep(forTimeInterval: 1.0)
        let orb = shot("6-orb")
        let middle = CGRect(x: 150, y: 330, width: 140, height: 40)    // the orb's ink, mid-screen
        let underIsland = CGRect(x: 150, y: 54, width: 140, height: 12)
        print("[siri-e2e] middle of the screen (bright, dark px): asleep \(band(empty, middle)), orb \(band(orb, middle))")
        XCTAssertLessThan(band(empty, middle).dark, band(empty, middle).total / 20, "something dark in the middle before Siri")
        XCTAssertGreaterThan(band(orb, middle).dark, band(orb, middle).total / 2, "no orb in the middle of the screen")
        XCTAssertLessThan(band(orb, underIsland).dark, band(orb, underIsland).total / 10, "the orb wasn't on its own")

        app.descendants(matching: .any)["siriGlass.stage.iPhone"].tap()
        // It leaves, the home screen comes in, and it drips out of the island.
        Thread.sleep(forTimeInterval: 0.3)
        XCTAssertTrue(wait(for: stage, value: "Listening", timeout: 5), "Siri didn't come back out on the iPhone")
        Thread.sleep(forTimeInterval: 1.0)
        let phone = shot("7-iphone")
        print("[siri-e2e] iPhone: under the island \(band(phone, underIsland)), middle \(band(phone, middle))")
        XCTAssertGreaterThan(band(phone, underIsland).dark, band(phone, underIsland).total / 2, "no drop under the island")
        XCTAssertLessThan(band(phone, middle).dark, band(phone, middle).total / 10, "the orb was still in the middle")

        app.descendants(matching: .any)["siriGlass.stage.orb"].tap()
        Thread.sleep(forTimeInterval: 0.3)
        XCTAssertTrue(wait(for: stage, value: "Listening", timeout: 5), "Siri didn't come back out as the orb")
        Thread.sleep(forTimeInterval: 1.2)
        let back = shot("8-orb-again")
        XCTAssertGreaterThan(band(back, middle).dark, band(back, middle).total / 2, "the orb didn't come back to the middle")
    }

    /// A second tap sends Siri away, and the drop never swallows a tap:
    /// tapping right on it reaches the screen beneath.
    @MainActor
    func testTapSendsSiriAwayEvenOnTheDrop() throws {
        let app = try launch(stage: "iPhone")
        let stage = app.descendants(matching: .any)["siriGlass.stage"]
        XCTAssertTrue(stage.waitForExistence(timeout: 60))
        stage.tap()
        XCTAssertTrue(wait(for: stage, value: "Listening", timeout: 5))
        stage.tap()
        XCTAssertTrue(wait(for: stage, value: "Asleep", timeout: 3), "a second tap didn't send Siri away")

        stage.tap()
        XCTAssertTrue(wait(for: stage, value: "Listening", timeout: 5))
        Thread.sleep(forTimeInterval: 1.0)
        // Right on the hanging drop, below the island.
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.0)).withOffset(CGVector(dx: 0, dy: 100)).tap()
        XCTAssertTrue(wait(for: stage, value: "Asleep", timeout: 3), "the drop swallowed a tap on it")
    }

    // MARK: - Helpers

    private func wait(for element: XCUIElement, value: String, timeout: TimeInterval) -> Bool {
        let predicate = NSPredicate(format: "value == %@", value)
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        return XCTWaiter().wait(for: [expectation], timeout: timeout) == .completed
    }

    private func level(_ probe: XCUIElement) -> Float {
        Float(probe.label) ?? -1
    }

    @discardableResult
    private func shot(_ name: String) -> XCUIScreenshot {
        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        if let outDir {
            try? screenshot.pngRepresentation.write(to: URL(fileURLWithPath: outDir).appendingPathComponent("\(name).png"))
        }
        return screenshot
    }

    /// Bright and dark pixels in a rectangle of the screen (points).
    private func band(_ screenshot: XCUIScreenshot, _ area: CGRect) -> (bright: Int, dark: Int, total: Int) {
        guard let image = screenshot.image.cgImage else { return (0, 0, 0) }
        let scale = Double(image.width) / screenshot.image.size.width
        let rect = CGRect(x: area.minX * scale, y: area.minY * scale, width: area.width * scale, height: area.height * scale).integral
        guard let crop = image.cropping(to: rect),
              let data = crop.dataProvider?.data, let bytes = CFDataGetBytePtr(data) else { return (0, 0, 0) }
        let perRow = crop.bytesPerRow, step = crop.bitsPerPixel / 8
        var bright = 0, dark = 0
        for y in 0..<crop.height {
            for x in 0..<crop.width {
                let p = bytes + y * perRow + x * step
                // Channel order varies (RGBA or BGRA); a plain mean doesn't care.
                let value = (Int(p[0]) + Int(p[1]) + Int(p[2])) / 3
                if value > 200 { bright += 1 }
                if value < 80 { dark += 1 }
            }
        }
        return (bright, dark, crop.width * crop.height)
    }
}
