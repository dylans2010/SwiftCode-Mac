// Ported from Legacy (Dylan's own SwiftCode code, MIT-authorised direct port):
//   SwiftCode/Models/ProjectOpenError.swift
//   (Legacy main ab03f681)
//
// Destination: SwiftCodeIDECore/Model/ProjectOpenError.swift.
//
// Why a standalone type (not folded into SCProjectError):
// `SCProjectError` (SCProjectFormat.swift) is the `.scproj` package-format
// error: manifestMissing, corruptedPackage, invalidFormat,
// versionIncompatible, securityFailure, ioError. `PBXProj.LoadError`
// (SwiftCodeProject) is the damaged-`.pbxproj` error: syntax, structure.
// Neither has a typed case for the three project-open operation
// failures below, and enum cases cannot be added by extension, so the
// Legacy operation error is ported whole. Case mapping to the
// destination errors, for call sites that translate:
//   .pathNotFound            — no SCProjectError equivalent
//                              (manifestMissing is manifest-specific)
//   .bookmarkResolutionFailed — SCProjectError.securityFailure
//   .corruptedProjectFile    — SCProjectError.corruptedPackage
//   .timeout                 — no SCProjectError equivalent
//   .unsupportedProjectVersion — SCProjectError.versionIncompatible
//   .cancelled               — no SCProjectError equivalent
//   .underlyingIO            — SCProjectError.ioError
//
// Wiring hook (landing): project-open call sites that today can only
// surface SCProjectError should throw/map to ProjectOpenError where the
// operation can time out, be cancelled, or find the folder missing
// (notably the `.scproj` open path in SCProjectFormat and the recent-
// projects reopen path); no call site is changed by this file alone.

import Foundation

public enum ProjectOpenError: LocalizedError, Sendable {
    case pathNotFound
    case bookmarkResolutionFailed
    case corruptedProjectFile
    case timeout
    case unsupportedProjectVersion
    case cancelled
    case underlyingIO(Error)

    public var errorDescription: String? {
        switch self {
        case .pathNotFound:
            return "The project folder could not be found."
        case .bookmarkResolutionFailed:
            return "Failed to resolve the security-scoped bookmark for the project."
        case .corruptedProjectFile:
            return "The project metadata file (project.json) is corrupted or missing."
        case .timeout:
            return "The project took too long to load. Please try again."
        case .unsupportedProjectVersion:
            return "This project was created with an unsupported version of SwiftCode."
        case .cancelled:
            return "Project loading was cancelled."
        case .underlyingIO(let error):
            return "An I/O error occurred: \(error.localizedDescription)"
        }
    }
}
