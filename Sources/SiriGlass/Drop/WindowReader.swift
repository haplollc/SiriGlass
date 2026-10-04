//
//  WindowReader.swift
//  SiriGlass
//
//  Reads the window's size and top safe area straight from UIKit. SwiftUI's
//  own safe area can't be trusted here: a parent that ignores the safe area
//  (as a full-screen root usually does) hides it from everything inside.
//

import SwiftUI
import UIKit

struct WindowReader: UIViewRepresentable {
    let onChange: @MainActor (WindowMetrics) -> Void

    func makeUIView(context: Context) -> ProbeView {
        let view = ProbeView()
        view.isUserInteractionEnabled = false
        view.isAccessibilityElement = false
        view.onChange = onChange
        return view
    }

    func updateUIView(_ view: ProbeView, context: Context) {
        view.onChange = onChange
    }

    final class ProbeView: UIView {
        var onChange: (@MainActor (WindowMetrics) -> Void)?
        private var last: WindowMetrics?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            report()
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            report()
        }

        override func safeAreaInsetsDidChange() {
            super.safeAreaInsetsDidChange()
            report()
        }

        private func report() {
            guard let window else { return }
            let metrics = WindowMetrics(size: window.bounds.size, safeAreaTop: window.safeAreaInsets.top,
                                        isPhone: traitCollection.userInterfaceIdiom == .phone)
            guard metrics != last else { return }
            last = metrics
            let onChange = onChange
            // Not during the layout pass that brought us here.
            DispatchQueue.main.async { onChange?(metrics) }
        }
    }
}
