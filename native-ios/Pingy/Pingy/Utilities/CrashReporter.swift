import Foundation
import UIKit

final class CrashReporter {
    static let shared = CrashReporter()

    private let defaults = UserDefaults.standard
    private let lastCrashKey = "pingy.crash.lastReport"
    private var installed = false

    private init() {}

    func install() {
        guard !installed else { return }
        installed = true

        if let previous = defaults.string(forKey: lastCrashKey), !previous.isEmpty {
            AppLogger.error("Recovered previous crash report: \(previous)")
            defaults.removeObject(forKey: lastCrashKey)
        }

        NSSetUncaughtExceptionHandler { exception in
            let report = "Uncaught exception: \(exception.name.rawValue) | \(exception.reason ?? "no reason")"
            UserDefaults.standard.set(report, forKey: "pingy.crash.lastReport")
        }

        NotificationCenter.default.addObserver(
            forName: UIApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.defaults.removeObject(forKey: self?.lastCrashKey ?? "pingy.crash.lastReport")
        }
    }
}
