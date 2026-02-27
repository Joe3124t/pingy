import QuartzCore
import SwiftUI

@MainActor
final class LiquidScrollBlurManager: ObservableObject {
    @Published private(set) var blurRadius: CGFloat = 20
    @Published private(set) var opacityScale: CGFloat = 1.0
    @Published private(set) var isFastMotion = false
    @Published private(set) var velocityPointsPerSecond: CGFloat = 0

    private var lastOffset: CGFloat?
    private var lastTimestamp: CFTimeInterval?
    private var restoreTask: Task<Void, Never>?

    private let fastVelocityThreshold: CGFloat = 620

    func sample(offset: CGFloat, timestamp: CFTimeInterval = CACurrentMediaTime()) {
        defer {
            lastOffset = offset
            lastTimestamp = timestamp
        }

        guard let previousOffset = lastOffset, let previousTimestamp = lastTimestamp else {
            return
        }

        let deltaTime = max(0.016, timestamp - previousTimestamp)
        let velocity = abs(offset - previousOffset) / deltaTime
        velocityPointsPerSecond = velocity

        if velocity >= fastVelocityThreshold {
            applyFastMotion()
        } else {
            scheduleRestore()
        }
    }

    func reset() {
        restoreTask?.cancel()
        restoreTask = nil
        withAnimation(.easeOut(duration: 0.18)) {
            blurRadius = 20
            opacityScale = 1.0
            isFastMotion = false
        }
        velocityPointsPerSecond = 0
        lastOffset = nil
        lastTimestamp = nil
    }

    private func applyFastMotion() {
        restoreTask?.cancel()
        restoreTask = nil
        guard !isFastMotion else { return }

        withAnimation(.easeOut(duration: 0.2)) {
            blurRadius = 8
            opacityScale = 0.85
            isFastMotion = true
        }
    }

    private func scheduleRestore() {
        restoreTask?.cancel()
        restoreTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 220_000_000)
            guard let self else { return }
            if Task.isCancelled { return }
            await MainActor.run {
                withAnimation(.easeOut(duration: 0.2)) {
                    self.blurRadius = 20
                    self.opacityScale = 1.0
                    self.isFastMotion = false
                }
            }
        }
    }
}
