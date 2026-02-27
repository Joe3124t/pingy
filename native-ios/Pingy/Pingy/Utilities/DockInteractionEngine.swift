import SwiftUI

@MainActor
final class DockInteractionEngine: ObservableObject {
    @Published private(set) var horizontalTilt: CGFloat = 0
    @Published private(set) var reflectionShift: CGFloat = 0
    @Published private(set) var highlightX: CGFloat = 0
    @Published private(set) var isDragging = false

    func updateDrag(translationX: CGFloat, locationX: CGFloat, width: CGFloat) {
        let normalized = max(-1, min(1, translationX / 90))
        horizontalTilt = normalized
        reflectionShift = normalized * 26
        highlightX = min(max(0, locationX), max(width, 1))
        isDragging = true
    }

    func endDrag(snapTo targetX: CGFloat) {
        withAnimation(.spring(response: 0.36, dampingFraction: 0.82)) {
            horizontalTilt = 0
            reflectionShift = 0
            highlightX = targetX
            isDragging = false
        }
    }

    func setRestingHighlightX(_ value: CGFloat) {
        guard !isDragging else { return }
        withAnimation(.spring(response: 0.3, dampingFraction: 0.84)) {
            highlightX = value
        }
    }
}
