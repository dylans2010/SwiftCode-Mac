import Foundation
import os

extension Logger {
    private static let subsystem = "com.swiftcode.simulator"

    public static let discovery = Logger(subsystem: subsystem, category: "discovery")

    public static let process = Logger(subsystem: subsystem, category: "process")

    public static let decode = Logger(subsystem: subsystem, category: "decode")

    public static let fault = Logger(subsystem: subsystem, category: "fault")
}
