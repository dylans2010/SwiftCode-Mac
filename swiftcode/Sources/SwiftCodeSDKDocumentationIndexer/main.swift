import Foundation
import SwiftCodeSDK

// `documentation-indexer`: print the Markdown inventory of the SDK docs
// (Legacy SwiftCode/SDK/Sources/Tools/DocumentationIndexer).
// Thin wrapper over SwiftCodeSDK (`DocumentationIndexerMain`).
exit(DocumentationIndexerMain.run(arguments: Array(CommandLine.arguments.dropFirst())))
