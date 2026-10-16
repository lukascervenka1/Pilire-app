import SwiftUI
import UIKit

/// Keeps a focused field visible inside a native List, including when a custom
/// tab bar changes the safe area during the keyboard transition.
struct KeyboardFieldVisibility: UIViewRepresentable {
    let isFocused: Bool

    func makeUIView(context: Context) -> FieldAnchor { FieldAnchor() }
    func updateUIView(_ view: FieldAnchor, context: Context) { view.setFocused(isFocused) }
    static func dismantleUIView(_ view: FieldAnchor, coordinator: ()) { view.restoreInset() }

    final class FieldAnchor: UIView {
        private var fieldActive = false
        private var keyboardFrame: CGRect?
        private var observers: [NSObjectProtocol] = []
        private weak var adjustedScrollView: UIScrollView?
        private var addedBottomInset: CGFloat = 0
        private var queued = false

        init() {
            super.init(frame:.zero)
            isUserInteractionEnabled = false
            isAccessibilityElement = false
            for name in [UIResponder.keyboardWillShowNotification, UIResponder.keyboardWillChangeFrameNotification,
                         UIResponder.keyboardDidShowNotification, UIResponder.keyboardDidChangeFrameNotification] {
                observers.append(NotificationCenter.default.addObserver(forName:name,object:nil,queue:.main) { [weak self] notification in
                    let frame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect
                    let starting = name == UIResponder.keyboardWillShowNotification || name == UIResponder.keyboardWillChangeFrameNotification
                    Task { @MainActor [weak self] in
                        self?.keyboardFrame = frame
                        if starting { self?.reveal() } else { self?.revealAfterLayout() }
                    }
                })
            }
            observers.append(NotificationCenter.default.addObserver(forName:UIResponder.keyboardWillHideNotification,object:nil,queue:.main) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.keyboardFrame = nil
                    self?.restoreInset()
                }
            })
        }
        required init?(coder:NSCoder) { nil }
        deinit { observers.forEach(NotificationCenter.default.removeObserver) }

        func setFocused(_ value: Bool) {
            fieldActive = value
            if value { revealAfterLayout() } else { restoreInset() }
        }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            if window != nil { revealAfterLayout() } else { restoreInset() }
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            revealAfterLayout()
        }

        private func revealAfterLayout() {
            guard fieldActive, !queued else { return }
            queued = true
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.queued = false
                self.reveal()
            }
        }

        private func reveal() {
            guard fieldActive, let window, let keyboardFrame else { return }
            let keyboard = window.convert(keyboardFrame,from:nil)
            guard keyboard.height > 0, keyboard.intersects(window.bounds) else {
                restoreInset()
                return
            }
            var ancestor = superview
            while let view = ancestor, !(view is UIScrollView) { ancestor = view.superview }
            guard let scroll = ancestor as? UIScrollView else { return }
            if adjustedScrollView !== scroll { restoreInset();adjustedScrollView = scroll }
            // Normally UIKit has already inset the List. Supply only the part
            // still obscured; adding the whole keyboard height would double it.
            let viewport = scroll.convert(scroll.bounds,to:window)
            let systemBottom = scroll.adjustedContentInset.bottom - addedBottomInset
            let needed = max(0,viewport.maxY - systemBottom - keyboard.minY)
            if abs(needed-addedBottomInset) > 0.5 {
                var inset = scroll.contentInset
                inset.bottom += needed-addedBottomInset
                scroll.contentInset = inset
                addedBottomInset = needed
            }
            let field = convert(bounds,to:window)
            let visibleTop = viewport.minY + scroll.adjustedContentInset.top + 12
            let visibleBottom = min(viewport.maxY-scroll.adjustedContentInset.bottom,keyboard.minY)-12
            guard field.maxY > visibleBottom || field.minY < visibleTop else { return }
            scroll.scrollRectToVisible(convert(bounds,to:scroll).insetBy(dx:0,dy:-16),
                                       animated:!UIAccessibility.isReduceMotionEnabled)
        }

        func restoreInset() {
            guard let scroll = adjustedScrollView, addedBottomInset > 0 else { return }
            var inset = scroll.contentInset
            inset.bottom = max(0,inset.bottom-addedBottomInset)
            scroll.contentInset = inset
            addedBottomInset = 0
            adjustedScrollView = nil
        }
    }
}
