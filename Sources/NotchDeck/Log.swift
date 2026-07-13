import Foundation
import os

// inputs {category}, does {structured logging: unified log + stdout mirror in one format}, returns {namespace}
enum Log {
    private static let logger = Logger(subsystem: "dev.notchdeck.app", category: "app")

    // inputs {message}, does {logs info-level event}, returns {}
    static func info(_ message: String) {
        logger.info("\(message, privacy: .public)")
        print("[NotchDeck] \(message)")
        fflush(stdout)
    }
}
