//
//  Logging.swift
//  beemed
//

import os

extension Logger {
    private static let subsystem = "name.danmackinlay.beemed"

    static let sync = Logger(subsystem: subsystem, category: "sync")
    static let persistence = Logger(subsystem: subsystem, category: "persistence")
    static let auth = Logger(subsystem: subsystem, category: "auth")
    static let watch = Logger(subsystem: subsystem, category: "watch")
}
