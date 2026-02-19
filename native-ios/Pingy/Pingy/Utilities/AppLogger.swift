import Foundation
import OSLog

enum AppLogger {
    private static let logger = Logger(subsystem: "com.pingy.messenger", category: "app")

    static func info(_ message: String) {
        #if DEBUG
            logger.info("\(message, privacy: .public)")
        #endif
    }

    static func debug(_ message: String) {
        #if DEBUG
            logger.debug("\(message, privacy: .public)")
        #endif
    }

    static func error(_ message: String) {
        #if DEBUG
            logger.error("\(message, privacy: .public)")
        #endif
    }
}
