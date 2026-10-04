//
//  SiriGlassDemoApp.swift
//  SiriGlassDemo
//
//  The demo: the drop as an orb on white, or pouring out of the Dynamic
//  Island over a home screen. See DemoConfig for the launch switches the
//  UI tests and recording scripts use.
//

import SwiftUI
@_spi(Recording) import SiriGlass

@main
struct SiriGlassDemoApp: App {
    private let config: DemoConfig
    private let take: SiriGlassTake?

    init() {
        let config = DemoConfig()
        self.config = config
        if config.scripted {
            let take = SiriGlassTake(pace: config.pace, hold: config.hold, freeze: config.freeze, voice: config.voice)
            take.showsOnlyGlass = config.glassOnly
            self.take = take
        } else {
            take = nil
        }
    }

    var body: some Scene {
        WindowGroup {
            DemoView(config: config, take: take)
        }
    }
}
