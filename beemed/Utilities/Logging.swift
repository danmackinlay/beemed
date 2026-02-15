//
//  Logging.swift
//  beemed
//

import os

extension Logger {
    nonisolated private static let subsystem = "name.danmackinlay.beemed"

    nonisolated static let sync = Logger(subsystem: subsystem, category: "sync")
    nonisolated static let persistence = Logger(subsystem: subsystem, category: "persistence")
    nonisolated static let auth = Logger(subsystem: subsystem, category: "auth")
    nonisolated static let watch = Logger(subsystem: subsystem, category: "watch")
}
