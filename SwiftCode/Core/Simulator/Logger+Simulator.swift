import Foundation
import os

extension Logger {
    private static let subsystem = "com.swiftcode.simulator"

    /// Logs related to the overall discovery pipeline and stage transitions.
    public static let discovery = Logger(subsystem: subsystem, category: "discovery")

    /// Logs related to process execution, command specs, and pipe draining.
    public static let process = Logger(subsystem: subsystem, category: "process")

    /// Logs related to defensive JSON decoding, schema drift, and parsing errors.
    public static let decode = Logger(subsystem: subsystem, category: "decode")

    /// Logs related to critical subsystem faults or unhandled failures.
    public static let fault = Logger(subsystem: subsystem, category: "fault")
}
