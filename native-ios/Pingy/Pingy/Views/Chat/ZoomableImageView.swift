import SwiftUI

struct ZoomableImageView: View {
    let image: Image
    var maxScale: CGFloat = 4

    @State private var baseScale: CGFloat = 1
    @State private var pinchScale: CGFloat = 1
    @State private var accumulatedOffset: CGSize = .zero
    @GestureState private var liveDragOffset: CGSize = .zero

    private var currentScale: CGFloat {
        min(max(1, baseScale * pinchScale), maxScale)
    }

    var body: some View {
        GeometryReader { geometry in
            image
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .scaleEffect(currentScale)
                .offset(
                    x: accumulatedOffset.width + liveDragOffset.width,
                    y: accumulatedOffset.height + liveDragOffset.height
                )
                .contentShape(Rectangle())
                .gesture(magnificationGesture)
                .simultaneousGesture(dragGesture(for: geometry.size))
                .onTapGesture(count: 2) {
                    toggleZoom()
                }
                .animation(.spring(response: 0.24, dampingFraction: 0.84), value: currentScale)
                .animation(.spring(response: 0.24, dampingFraction: 0.84), value: accumulatedOffset)
        }
    }

    private var magnificationGesture: some Gesture {
        MagnificationGesture()
            .onChanged { value in
                pinchScale = value
            }
            .onEnded { value in
                baseScale = min(max(1, baseScale * value), maxScale)
                pinchScale = 1
                if baseScale <= 1.01 {
                    resetZoom()
                }
            }
    }

    private func dragGesture(for containerSize: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .updating($liveDragOffset) { value, state, _ in
                guard currentScale > 1.01 else {
                    state = .zero
                    return
                }
                state = value.translation
            }
            .onEnded { value in
                guard currentScale > 1.01 else { return }
                let candidate = CGSize(
                    width: accumulatedOffset.width + value.translation.width,
                    height: accumulatedOffset.height + value.translation.height
                )
                accumulatedOffset = clampedOffset(candidate, for: containerSize, scale: currentScale)
            }
    }

    private func toggleZoom() {
        if currentScale > 1.01 {
            resetZoom()
            return
        }

        baseScale = min(maxScale, 2)
        pinchScale = 1
    }

    private func resetZoom() {
        baseScale = 1
        pinchScale = 1
        accumulatedOffset = .zero
    }

    private func clampedOffset(_ offset: CGSize, for container: CGSize, scale: CGFloat) -> CGSize {
        let halfExtraWidth = max(0, (container.width * scale - container.width) / 2)
        let halfExtraHeight = max(0, (container.height * scale - container.height) / 2)

        return CGSize(
            width: min(max(offset.width, -halfExtraWidth), halfExtraWidth),
            height: min(max(offset.height, -halfExtraHeight), halfExtraHeight)
        )
    }
}
