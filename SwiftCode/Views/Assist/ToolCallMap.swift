//
//  ToolCallMap.swift
//  SwiftCode
//
//  Canonical presentation map for EVERY registered Assist tool: display title,
//  SF Symbol, and subtle tint color used by the Assist main view's native
//  tool-call UI (MuseNativeToolCard).
//
//  This replaces the hand-rolled per-tool switches that previously covered
//  only a handful of tools. Coverage is enforced by
//  SwiftCode/Backend/Assist/Tools/validate_tools.py: every tool registered in
//  AssistToolRegistry must have an entry here, and every entry must resolve
//  to a registered tool.

import SwiftUI

/// Presentation descriptor for one Assist tool in the Assist main view.
public struct ToolCallDescriptor {
    /// Short human-readable title, e.g. "Read File".
    public let title: String
    /// SF Symbol name rendered next to the title.
    public let symbolName: String
    /// Subtle tint applied to the symbol.
    public let tint: Color

    public init(title: String, symbolName: String, tint: Color) {
        self.title = title
        self.symbolName = symbolName
        self.tint = tint
    }
}

/// Single source of truth mapping Assist tool IDs to their UI presentation.
public enum ToolCallMap {
    /// Returns the descriptor for a tool ID. Lookup is case-insensitive and
    /// treats "-" and "_" as equivalent (e.g. "plan-AskUser" == "plan_askuser").
    /// Unknown IDs get a generic descriptor derived from the raw identifier so
    /// the UI never renders a blank card.
    public static func descriptor(for toolID: String) -> ToolCallDescriptor {
        let norm = toolID.lowercased().replacingOccurrences(of: "-", with: "_")
        if let entry = entries[norm] {
            return entry
        }
        let cleaned = toolID
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
        let title = cleaned.isEmpty ? "Tool Action" : cleaned.capitalized
        return ToolCallDescriptor(title: title, symbolName: "wrench.and.screwdriver.fill", tint: .gray)
    }

    /// Number of tools covered by the map.
    public static var toolCount: Int { entries.count }

    /// Every normalized tool ID covered by the map (used by tests/validators).
    public static var allToolIDs: [String] { Array(entries.keys).sorted() }

    private static let entries: [String: ToolCallDescriptor] = [
        // MARK: - access
        "access_level_audit": ToolCallDescriptor(title: "Access Level Audit", symbolName: "checkmark.shield.fill", tint: .teal),
        // MARK: - accessibility
        "accessibility_audit": ToolCallDescriptor(title: "Accessibility Audit", symbolName: "checkmark.shield.fill", tint: .teal),
        "accessibility_audit_scanner": ToolCallDescriptor(title: "Accessibility Audit Scanner", symbolName: "checkmark.shield.fill", tint: .teal),
        // MARK: - api
        "api_docs_coverage": ToolCallDescriptor(title: "API Docs Coverage", symbolName: "book.fill", tint: .brown),
        "api_endpoint_audit": ToolCallDescriptor(title: "API Endpoint Audit", symbolName: "checkmark.shield.fill", tint: .teal),
        "api_surface_extract": ToolCallDescriptor(title: "API Surface", symbolName: "network", tint: .teal),
        // MARK: - artboard
        "artboard_compile": ToolCallDescriptor(title: "Compile Artboard Preview", symbolName: "rectangle.dashed", tint: .pink),
        "artboard_create": ToolCallDescriptor(title: "Create Artboard", symbolName: "rectangle.dashed", tint: .pink),
        "artboard_delete": ToolCallDescriptor(title: "Delete Artboard", symbolName: "rectangle.dashed", tint: .pink),
        "artboard_get": ToolCallDescriptor(title: "Get Artboard Details", symbolName: "rectangle.dashed", tint: .pink),
        "artboard_list": ToolCallDescriptor(title: "List Artboards", symbolName: "rectangle.dashed", tint: .pink),
        "artboard_run_app": ToolCallDescriptor(title: "Run Full App", symbolName: "rectangle.dashed", tint: .pink),
        "artboard_update": ToolCallDescriptor(title: "Update Artboard", symbolName: "rectangle.dashed", tint: .pink),
        // MARK: - asset
        "asset_catalog_list": ToolCallDescriptor(title: "List Asset Catalog", symbolName: "photo.stack.fill", tint: .pink),
        "asset_catalog_manager": ToolCallDescriptor(title: "Asset Catalog Manager", symbolName: "photo.stack.fill", tint: .pink),
        "asset_image_add": ToolCallDescriptor(title: "Add Asset Image", symbolName: "photo.stack.fill", tint: .pink),
        // MARK: - automated
        "automated_repair_engine": ToolCallDescriptor(title: "Automated Repair Engine", symbolName: "wand.and.stars", tint: .purple),
        // MARK: - autonomous
        "autonomous_review_engine": ToolCallDescriptor(title: "Autonomous Review Engine", symbolName: "eyeglasses", tint: .indigo),
        // MARK: - batch
        "batch_rename_files": ToolCallDescriptor(title: "Batch Rename Files", symbolName: "pencil", tint: .blue),
        // MARK: - binary
        "binary_plist_converter": ToolCallDescriptor(title: "Binary Plist Converter", symbolName: "tablecells", tint: .teal),
        "binary_size_report": ToolCallDescriptor(title: "Binary Size Report", symbolName: "chart.bar.fill", tint: .green),
        // MARK: - build
        "build_configuration_list": ToolCallDescriptor(title: "Build Configuration List", symbolName: "hammer.fill", tint: .orange),
        "build_log_analyze": ToolCallDescriptor(title: "Build Log Analyze", symbolName: "hammer.fill", tint: .orange),
        "build_phase_scripts_list": ToolCallDescriptor(title: "Build Phase Scripts List", symbolName: "hammer.fill", tint: .orange),
        "build_settings_diff": ToolCallDescriptor(title: "Build Settings Diff", symbolName: "hammer.fill", tint: .orange),
        "build_system_detect": ToolCallDescriptor(title: "Build System Detect", symbolName: "hammer.fill", tint: .orange),
        // MARK: - bundle
        "bundle_resource_auditor": ToolCallDescriptor(title: "Bundle Resource Auditor", symbolName: "checkmark.shield.fill", tint: .teal),
        // MARK: - call
        "call_hierarchy": ToolCallDescriptor(title: "Call Hierarchy", symbolName: "point.3.connected.trianglepath", tint: .indigo),
        // MARK: - carthage
        "carthage_cartfile_inspector": ToolCallDescriptor(title: "Carthage Cartfile Inspector", symbolName: "checkmark.shield.fill", tint: .teal),
        // MARK: - change
        "change_impact_estimate": ToolCallDescriptor(title: "Change Impact Estimate", symbolName: "chart.bar.fill", tint: .orange),
        // MARK: - clipboard
        "clipboard_manager_tool": ToolCallDescriptor(title: "Clipboard Manager", symbolName: "clipboard.fill", tint: .gray),
        // MARK: - code
        "code_comment_extract": ToolCallDescriptor(title: "Code Comment Extract", symbolName: "chevron.left.forwardslash.chevron.right", tint: .orange),
        "code_format": ToolCallDescriptor(title: "Format Code", symbolName: "wand.and.stars", tint: .purple),
        "code_generate": ToolCallDescriptor(title: "Generate File", symbolName: "sparkles", tint: .purple),
        "code_insert": ToolCallDescriptor(title: "Insert Code Block", symbolName: "character.cursor.ibeam", tint: .orange),
        "code_lint": ToolCallDescriptor(title: "Lint Code", symbolName: "checkmark.shield.fill", tint: .green),
        "code_metrics_analyzer": ToolCallDescriptor(title: "Code Metrics Analyzer", symbolName: "chevron.left.forwardslash.chevron.right", tint: .orange),
        "code_multi_edit": ToolCallDescriptor(title: "Multi-File Edit", symbolName: "chevron.left.forwardslash.chevron.right", tint: .orange),
        "code_mutation_engine": ToolCallDescriptor(title: "Controlled Mutation Engine", symbolName: "chevron.left.forwardslash.chevron.right", tint: .orange),
        "code_refactor": ToolCallDescriptor(title: "Refactor", symbolName: "wand.and.stars", tint: .orange),
        "code_replace": ToolCallDescriptor(title: "Replace in File", symbolName: "text.badge.checkmark", tint: .orange),
        "code_review": ToolCallDescriptor(title: "Code Review Validation", symbolName: "eyeglasses", tint: .indigo),
        "code_signing_diagnose": ToolCallDescriptor(title: "Code Signing Diagnose", symbolName: "chevron.left.forwardslash.chevron.right", tint: .orange),
        "code_snippet_manager": ToolCallDescriptor(title: "Code Snippet & Architecture Template Manager", symbolName: "chevron.left.forwardslash.chevron.right", tint: .orange),
        "code_summary": ToolCallDescriptor(title: "Code Summary", symbolName: "chevron.left.forwardslash.chevron.right", tint: .orange),
        // MARK: - color
        "color_usage_audit": ToolCallDescriptor(title: "Color Usage Audit", symbolName: "checkmark.shield.fill", tint: .teal),
        // MARK: - colorset
        "colorset_builder": ToolCallDescriptor(title: "Color Set Builder", symbolName: "hammer.fill", tint: .orange),
        // MARK: - comment
        "comment_density_report": ToolCallDescriptor(title: "Comment Density Report", symbolName: "chart.bar.fill", tint: .green),
        // MARK: - compiler
        "compiler_diagnostics_engine": ToolCallDescriptor(title: "Compiler Diagnostics Engine", symbolName: "stethoscope", tint: .teal),
        // MARK: - complexity
        "complexity_analysis": ToolCallDescriptor(title: "Complexity Analysis", symbolName: "chart.bar.fill", tint: .green),
        // MARK: - concurrency
        "concurrency_audit": ToolCallDescriptor(title: "Concurrency Audit", symbolName: "checkmark.shield.fill", tint: .teal),
        // MARK: - conflict
        "conflict_marker_scan": ToolCallDescriptor(title: "Conflict Marker Scan", symbolName: "checkmark.shield.fill", tint: .teal),
        // MARK: - context
        "context_persistence_store": ToolCallDescriptor(title: "Persistent Context Store", symbolName: "archivebox.fill", tint: .purple),
        // MARK: - conversation
        "conversation_context_manager": ToolCallDescriptor(title: "Conversation Context Manager", symbolName: "bubble.left.and.bubble.right.fill", tint: .blue),
        // MARK: - core
        "core_data_model_inspector": ToolCallDescriptor(title: "Core Data Model Inspector", symbolName: "checkmark.shield.fill", tint: .teal),
        // MARK: - count
        "count_file_lines": ToolCallDescriptor(title: "Count File Lines and Code Metrics", symbolName: "list.number", tint: .blue),
        // MARK: - crash
        "crash_log_parse": ToolCallDescriptor(title: "Crash Log Parse", symbolName: "stethoscope", tint: .teal),
        // MARK: - create
        "create_artifact": ToolCallDescriptor(title: "Create Artifact", symbolName: "cube.fill", tint: .purple),
        "create_new_app": ToolCallDescriptor(title: "Create New App", symbolName: "plus.circle.fill", tint: .green),
        // MARK: - csv
        "csv_to_json": ToolCallDescriptor(title: "Convert CSV to JSON", symbolName: "tablecells", tint: .teal),
        // MARK: - dead
        "dead_code_eliminator": ToolCallDescriptor(title: "Dead Code Eliminator", symbolName: "trash.fill", tint: .red),
        "dead_code_scan": ToolCallDescriptor(title: "Dead Code Scan", symbolName: "checkmark.shield.fill", tint: .teal),
        // MARK: - delete
        "delete_artifact": ToolCallDescriptor(title: "Delete Artifact", symbolName: "cube.fill", tint: .red),
        // MARK: - dependency
        "dependency_graph": ToolCallDescriptor(title: "Dependency Graph", symbolName: "shippingbox.fill", tint: .orange),
        "dependency_licenses": ToolCallDescriptor(title: "Dependency Licenses", symbolName: "shippingbox.fill", tint: .orange),
        "dependency_resolution_engine": ToolCallDescriptor(title: "Dependency Resolution Engine", symbolName: "shippingbox.fill", tint: .orange),
        // MARK: - deprecation
        "deprecation_usage_scan": ToolCallDescriptor(title: "Deprecation Usage Scan", symbolName: "checkmark.shield.fill", tint: .teal),
        // MARK: - derived
        "derived_data_locate": ToolCallDescriptor(title: "DerivedData Locate", symbolName: "magnifyingglass", tint: .gray),
        // MARK: - device
        "device_list": ToolCallDescriptor(title: "List Devices", symbolName: "iphone", tint: .gray),
        // MARK: - dir
        "dir_cd": ToolCallDescriptor(title: "Change Directory", symbolName: "folder.fill", tint: .blue),
        "dir_create": ToolCallDescriptor(title: "Create Directory", symbolName: "folder.badge.plus", tint: .green),
        "dir_delete": ToolCallDescriptor(title: "Delete Directory", symbolName: "folder.fill.badge.minus", tint: .red),
        "dir_pwd": ToolCallDescriptor(title: "Print Working Directory", symbolName: "folder.fill", tint: .blue),
        "dir_read": ToolCallDescriptor(title: "Read Directory", symbolName: "folder.fill", tint: .blue),
        "dir_size_report": ToolCallDescriptor(title: "Directory Size Report", symbolName: "folder.fill", tint: .blue),
        // MARK: - disk
        "disk_space_analyzer": ToolCallDescriptor(title: "Disk Space Analyzer", symbolName: "internaldrive.fill", tint: .gray),
        // MARK: - docc
        "docc_build": ToolCallDescriptor(title: "Build DocC Docs", symbolName: "hammer.fill", tint: .orange),
        // MARK: - docs
        "docs_generate": ToolCallDescriptor(title: "Generate Docs", symbolName: "book.fill", tint: .brown),
        "docs_index_build": ToolCallDescriptor(title: "Docs Index Build", symbolName: "hammer.fill", tint: .orange),
        // MARK: - docstring
        "docstring_generator": ToolCallDescriptor(title: "DocC Documentation Generator", symbolName: "book.fill", tint: .brown),
        // MARK: - duplicate
        "duplicate_code_scan": ToolCallDescriptor(title: "Duplicate Code Scan", symbolName: "checkmark.shield.fill", tint: .teal),
        // MARK: - empty
        "empty_dirs_find": ToolCallDescriptor(title: "Find Empty Directories", symbolName: "folder.fill", tint: .blue),
        // MARK: - entitlements
        "entitlements_diff": ToolCallDescriptor(title: "Entitlements Diff", symbolName: "key.fill", tint: .yellow),
        "entitlements_manager": ToolCallDescriptor(title: "Entitlements Manager", symbolName: "key.fill", tint: .yellow),
        // MARK: - entry
        "entry_points_discover": ToolCallDescriptor(title: "Discover Entry Points", symbolName: "flag.fill", tint: .indigo),
        // MARK: - env
        "env_capture_logs": ToolCallDescriptor(title: "Capture Logs", symbolName: "terminal.fill", tint: .gray),
        "env_info": ToolCallDescriptor(title: "Environment Info", symbolName: "info.circle.fill", tint: .gray),
        // MARK: - environment
        "environment_variable_manager": ToolCallDescriptor(title: "Environment Variable Manager", symbolName: "gearshape.fill", tint: .gray),
        // MARK: - executable
        "executable_files_scan": ToolCallDescriptor(title: "Executable Files Scan", symbolName: "checkmark.shield.fill", tint: .teal),
        // MARK: - execution
        "execution_plan": ToolCallDescriptor(title: "Generate Execution Plan", symbolName: "list.bullet.clipboard.fill", tint: .orange),
        // MARK: - external
        "external_resource_gateway": ToolCallDescriptor(title: "External Resource Gateway", symbolName: "app.connected.to.app.below.fill", tint: .teal),
        // MARK: - extract
        "extract_code_symbols": ToolCallDescriptor(title: "Extract Code Symbols", symbolName: "magnifyingglass", tint: .indigo),
        // MARK: - fetch
        "fetch_documentation": ToolCallDescriptor(title: "Fetch Apple Documentation", symbolName: "book.fill", tint: .brown),
        // MARK: - file
        "file_append": ToolCallDescriptor(title: "Append to File", symbolName: "doc.badge.plus", tint: .teal),
        "file_backup": ToolCallDescriptor(title: "File Backup", symbolName: "clock.arrow.circlepath", tint: .blue),
        "file_checksum_verifier": ToolCallDescriptor(title: "File Checksum Verifier", symbolName: "doc.text.fill", tint: .blue),
        "file_compare_diff": ToolCallDescriptor(title: "Compare Two Files and Generate Diff", symbolName: "doc.text.below.ecg", tint: .orange),
        "file_copy": ToolCallDescriptor(title: "Copy File", symbolName: "doc.on.doc.fill", tint: .blue),
        "file_create": ToolCallDescriptor(title: "Create File", symbolName: "doc.badge.plus", tint: .green),
        "file_delete": ToolCallDescriptor(title: "Delete File", symbolName: "trash.fill", tint: .red),
        "file_hash_verify": ToolCallDescriptor(title: "Verify File Hash", symbolName: "doc.text.fill", tint: .blue),
        "file_head_preview": ToolCallDescriptor(title: "File Head Preview", symbolName: "doc.text.fill", tint: .blue),
        "file_metadata": ToolCallDescriptor(title: "File Metadata", symbolName: "doc.text.fill", tint: .blue),
        "file_move": ToolCallDescriptor(title: "Move File", symbolName: "doc.on.doc.fill", tint: .indigo),
        "file_read": ToolCallDescriptor(title: "Read File", symbolName: "doc.text.magnifyingglass", tint: .blue),
        "file_rename": ToolCallDescriptor(title: "Rename File", symbolName: "pencil", tint: .blue),
        "file_type_breakdown": ToolCallDescriptor(title: "File Type Breakdown", symbolName: "doc.text.fill", tint: .blue),
        "file_write": ToolCallDescriptor(title: "Write File", symbolName: "doc.badge.plus", tint: .blue),
        // MARK: - find
        "find_duplicate_files": ToolCallDescriptor(title: "Find Duplicate Files", symbolName: "doc.on.doc.fill", tint: .blue),
        // MARK: - fix
        "fix_artboards": ToolCallDescriptor(title: "Fix Artboards and Visual UI Builder Errors", symbolName: "paintbrush.fill", tint: .pink),
        // MARK: - force
        "force_unwrap_scan": ToolCallDescriptor(title: "Force Unwrap Scan", symbolName: "checkmark.shield.fill", tint: .teal),
        // MARK: - format
        "format_json_file": ToolCallDescriptor(title: "Format and Validate JSON File", symbolName: "paintbrush.fill", tint: .purple),
        // MARK: - framework
        "framework_linker_auditor": ToolCallDescriptor(title: "Framework Linker Auditor", symbolName: "checkmark.shield.fill", tint: .teal),
        // MARK: - function
        "function_size_report": ToolCallDescriptor(title: "Function Size Report", symbolName: "chart.bar.fill", tint: .green),
        // MARK: - generate
        "generate_file_checksum": ToolCallDescriptor(title: "Generate File Cryptographic Checksum", symbolName: "plus.circle.fill", tint: .green),
        "generate_xcodeproj": ToolCallDescriptor(title: "Generate Xcode Project", symbolName: "hammer.fill", tint: .orange),
        // MARK: - git
        "git_bisect": ToolCallDescriptor(title: "Git Bisect", symbolName: "arrow.triangle.branch", tint: .orange),
        "git_blame_inspector": ToolCallDescriptor(title: "Git Blame Inspector", symbolName: "arrow.triangle.branch", tint: .orange),
        "git_branch_compare": ToolCallDescriptor(title: "Compare Branches", symbolName: "arrow.triangle.branch", tint: .orange),
        "git_branch_manager": ToolCallDescriptor(title: "Git Branch Manager", symbolName: "arrow.triangle.branch", tint: .orange),
        "git_cherry_pick": ToolCallDescriptor(title: "Git Cherry-Pick", symbolName: "arrow.triangle.branch", tint: .orange),
        "git_conflict_resolver": ToolCallDescriptor(title: "Git Conflict Resolver", symbolName: "arrow.triangle.branch", tint: .orange),
        "git_log_viewer": ToolCallDescriptor(title: "Git Log Viewer", symbolName: "arrow.triangle.branch", tint: .orange),
        "git_pr_summary": ToolCallDescriptor(title: "PR Summary", symbolName: "arrow.triangle.branch", tint: .orange),
        "git_stash_operator": ToolCallDescriptor(title: "Git Stash Operator", symbolName: "arrow.triangle.branch", tint: .orange),
        // MARK: - github
        "github_repo": ToolCallDescriptor(title: "GitHub Repository Inspector", symbolName: "chevron.left.forwardslash.chevron.right", tint: .gray),
        // MARK: - gzip
        "gzip_compress_file": ToolCallDescriptor(title: "gzip Compress File", symbolName: "archivebox.fill", tint: .gray),
        "gzip_decompress_file": ToolCallDescriptor(title: "gzip Decompress File", symbolName: "archivebox.fill", tint: .gray),
        // MARK: - icon
        "icon_generator_tool": ToolCallDescriptor(title: "App Icon Generator & Validator", symbolName: "photo.fill", tint: .pink),
        // MARK: - image
        "image_asset_size_report": ToolCallDescriptor(title: "Image Asset Size Report", symbolName: "photo.fill", tint: .pink),
        "image_convert_format": ToolCallDescriptor(title: "Convert Image Format", symbolName: "photo.fill", tint: .pink),
        "image_decode_base64": ToolCallDescriptor(title: "Decode Base64 to Image", symbolName: "photo.fill", tint: .pink),
        "image_encode_base64": ToolCallDescriptor(title: "Encode Image to Base64", symbolName: "photo.fill", tint: .pink),
        "image_extract_metadata": ToolCallDescriptor(title: "Extract Image Metadata", symbolName: "photo.fill", tint: .pink),
        "image_generate_thumbnail": ToolCallDescriptor(title: "Generate Image Thumbnail", symbolName: "photo.fill", tint: .pink),
        "image_get_dimensions": ToolCallDescriptor(title: "Get Image Dimensions and Specs", symbolName: "photo.fill", tint: .pink),
        // MARK: - import
        "import_cleanup": ToolCallDescriptor(title: "Import Cleanup", symbolName: "wand.and.stars", tint: .purple),
        "import_graph": ToolCallDescriptor(title: "Import Graph", symbolName: "point.3.connected.trianglepath", tint: .indigo),
        // MARK: - info
        "info_plist_audit": ToolCallDescriptor(title: "Info.plist Audit", symbolName: "checkmark.shield.fill", tint: .teal),
        // MARK: - intel
        "intel_autofix": ToolCallDescriptor(title: "Auto-Fix Errors", symbolName: "wand.and.sparkles", tint: .purple),
        "intel_breakdown_task": ToolCallDescriptor(title: "Breakdown Task", symbolName: "list.bullet.indent", tint: .purple),
        "intel_explain_code": ToolCallDescriptor(title: "Explain Code", symbolName: "sparkles", tint: .purple),
        "intel_generate_tests": ToolCallDescriptor(title: "Generate Tests", symbolName: "sparkles", tint: .purple),
        "intel_plan_task": ToolCallDescriptor(title: "Plan Task", symbolName: "list.bullet.clipboard.fill", tint: .purple),
        // MARK: - interface
        "interface_simulator": ToolCallDescriptor(title: "Interface Simulator & Accessibility Auditor", symbolName: "rectangle.3.offgrid.fill", tint: .pink),
        // MARK: - json
        "json_to_csv": ToolCallDescriptor(title: "Convert JSON to CSV", symbolName: "tablecells", tint: .teal),
        "json_to_plist": ToolCallDescriptor(title: "Convert JSON to Plist", symbolName: "tablecells", tint: .teal),
        "json_validate": ToolCallDescriptor(title: "Validate JSON", symbolName: "tablecells", tint: .teal),
        "json_validator_tool": ToolCallDescriptor(title: "JSON Validator & Formatter", symbolName: "tablecells", tint: .teal),
        // MARK: - license
        "license_header_check": ToolCallDescriptor(title: "License Header Check", symbolName: "doc.text.fill", tint: .brown),
        // MARK: - list
        "list_artifacts": ToolCallDescriptor(title: "List Artifacts", symbolName: "cube.fill", tint: .purple),
        // MARK: - localization
        "localization_audit": ToolCallDescriptor(title: "Localization Audit", symbolName: "translate", tint: .blue),
        "localization_manager": ToolCallDescriptor(title: "Localization Manager", symbolName: "translate", tint: .blue),
        // MARK: - localize
        "localize_app": ToolCallDescriptor(title: "Localization", symbolName: "translate", tint: .blue),
        // MARK: - mach
        "mach_o_binary_analyzer": ToolCallDescriptor(title: "Mach-O Binary Analyzer", symbolName: "cpu.fill", tint: .gray),
        // MARK: - manage
        "manage_memory": ToolCallDescriptor(title: "Manage Memory", symbolName: "brain", tint: .purple),
        // MARK: - markdown
        "markdown_link_check": ToolCallDescriptor(title: "Markdown Link Check", symbolName: "book.fill", tint: .brown),
        "markdown_toc_generate": ToolCallDescriptor(title: "Markdown Toc Generate", symbolName: "book.fill", tint: .brown),
        // MARK: - mem
        "mem_clear": ToolCallDescriptor(title: "Clear Memory", symbolName: "brain", tint: .purple),
        "mem_context_snapshot": ToolCallDescriptor(title: "Context Snapshot", symbolName: "brain", tint: .purple),
        "mem_retrieve": ToolCallDescriptor(title: "Retrieve Memory", symbolName: "brain", tint: .purple),
        "mem_store": ToolCallDescriptor(title: "Store Memory", symbolName: "brain", tint: .purple),
        // MARK: - memory
        "memory_leak_detector": ToolCallDescriptor(title: "Memory Leak Detector", symbolName: "brain", tint: .purple),
        // MARK: - network
        "network_security_auditor": ToolCallDescriptor(title: "Network Security & ATS Auditor", symbolName: "checkmark.shield.fill", tint: .teal),
        // MARK: - open
        "open_in_finder": ToolCallDescriptor(title: "Open in Finder", symbolName: "folder.fill", tint: .blue),
        // MARK: - package
        "package_dependency_add": ToolCallDescriptor(title: "Add Package Dependency", symbolName: "shippingbox.fill", tint: .orange),
        "package_dependency_audit": ToolCallDescriptor(title: "Audit Package Dependencies", symbolName: "checkmark.shield.fill", tint: .teal),
        "package_dependency_update": ToolCallDescriptor(title: "Update Package Dependencies", symbolName: "shippingbox.fill", tint: .orange),
        "package_manifest_read": ToolCallDescriptor(title: "Read Package Manifest", symbolName: "shippingbox.fill", tint: .orange),
        "package_manifest_validate": ToolCallDescriptor(title: "Validate Package Manifest", symbolName: "shippingbox.fill", tint: .orange),
        // MARK: - patch
        "patch_application_engine": ToolCallDescriptor(title: "Patch Application Engine", symbolName: "gearshape.fill", tint: .gray),
        // MARK: - pbxproj
        "pbxproj_lint": ToolCallDescriptor(title: "pbxproj Lint", symbolName: "hammer.fill", tint: .orange),
        // MARK: - performance
        "performance_benchmark": ToolCallDescriptor(title: "Performance Benchmark", symbolName: "chart.bar.fill", tint: .green),
        // MARK: - permissions
        "permissions_audit": ToolCallDescriptor(title: "Permissions Audit", symbolName: "checkmark.shield.fill", tint: .teal),
        // MARK: - plan
        "plan_askuser": ToolCallDescriptor(title: "Ask User for Decision", symbolName: "questionmark.bubble.fill", tint: .orange),
        // MARK: - plist
        "plist_edit": ToolCallDescriptor(title: "Edit Plist", symbolName: "tablecells", tint: .teal),
        "plist_editor": ToolCallDescriptor(title: "Property List Editor", symbolName: "tablecells", tint: .teal),
        "plist_to_json": ToolCallDescriptor(title: "Convert Plist to JSON", symbolName: "tablecells", tint: .teal),
        // MARK: - podfile
        "podfile_inspector": ToolCallDescriptor(title: "Podfile & CocoaPods Inspector", symbolName: "checkmark.shield.fill", tint: .teal),
        // MARK: - preflight
        "preflight_checks": ToolCallDescriptor(title: "Preflight Checks", symbolName: "airplane", tint: .blue),
        // MARK: - privacy
        "privacy_manifest_auditor": ToolCallDescriptor(title: "Privacy Manifest Auditor", symbolName: "checkmark.shield.fill", tint: .teal),
        // MARK: - process
        "process_monitor_tool": ToolCallDescriptor(title: "Process Monitor", symbolName: "terminal.fill", tint: .gray),
        // MARK: - project
        "project_archive": ToolCallDescriptor(title: "Archive Project", symbolName: "folder.badge.gearshape", tint: .gray),
        "project_build": ToolCallDescriptor(title: "Build Project", symbolName: "hammer.fill", tint: .orange),
        "project_build_settings": ToolCallDescriptor(title: "Build Settings", symbolName: "hammer.fill", tint: .orange),
        "project_capabilities": ToolCallDescriptor(title: "Capabilities", symbolName: "folder.badge.gearshape", tint: .gray),
        "project_changelog": ToolCallDescriptor(title: "View Changelog", symbolName: "folder.badge.gearshape", tint: .gray),
        "project_clean": ToolCallDescriptor(title: "Clean Project", symbolName: "trash.fill", tint: .orange),
        "project_diff": ToolCallDescriptor(title: "Diff Project", symbolName: "folder.badge.gearshape", tint: .gray),
        "project_entitlements": ToolCallDescriptor(title: "Entitlements", symbolName: "key.fill", tint: .yellow),
        "project_info_plist": ToolCallDescriptor(title: "Info.Plist Editor", symbolName: "folder.badge.gearshape", tint: .gray),
        "project_mutation_controller": ToolCallDescriptor(title: "Xcode Project Mutation Controller", symbolName: "chevron.left.forwardslash.chevron.right", tint: .orange),
        "project_restore": ToolCallDescriptor(title: "Restore Snapshot", symbolName: "clock.arrow.circlepath", tint: .blue),
        "project_scheme_list": ToolCallDescriptor(title: "List Schemes", symbolName: "hammer.fill", tint: .orange),
        "project_signing": ToolCallDescriptor(title: "Signing Check", symbolName: "key.fill", tint: .yellow),
        "project_snapshot": ToolCallDescriptor(title: "Snapshot Project", symbolName: "camera.fill", tint: .blue),
        "project_structure_map": ToolCallDescriptor(title: "Project Structure Map", symbolName: "folder.badge.gearshape", tint: .gray),
        "project_target_add": ToolCallDescriptor(title: "Add Target", symbolName: "hammer.fill", tint: .orange),
        "project_target_list": ToolCallDescriptor(title: "List Targets", symbolName: "hammer.fill", tint: .orange),
        "project_test": ToolCallDescriptor(title: "Run Tests", symbolName: "play.circle.fill", tint: .green),
        // MARK: - protocol
        "protocol_conformance_list": ToolCallDescriptor(title: "Protocol Conformance List", symbolName: "list.bullet", tint: .indigo),
        // MARK: - provisioning
        "provisioning_check": ToolCallDescriptor(title: "Provisioning Check", symbolName: "key.fill", tint: .yellow),
        "provisioning_profile_reader": ToolCallDescriptor(title: "Provisioning Profile Reader", symbolName: "key.fill", tint: .yellow),
        // MARK: - read
        "read_artifact": ToolCallDescriptor(title: "Read Artifact", symbolName: "cube.fill", tint: .purple),
        // MARK: - readme
        "readme_generate": ToolCallDescriptor(title: "README Generate", symbolName: "book.fill", tint: .brown),
        "readme_locate": ToolCallDescriptor(title: "Locate README", symbolName: "book.fill", tint: .brown),
        // MARK: - recent
        "recent_changes": ToolCallDescriptor(title: "Recent Changes", symbolName: "doc.text.fill", tint: .blue),
        // MARK: - regex
        "regex_replace_in_files": ToolCallDescriptor(title: "Regex Replace in Files", symbolName: "text.magnifyingglass", tint: .orange),
        // MARK: - repo
        "repo_overview": ToolCallDescriptor(title: "Repository Overview", symbolName: "text.bubble.fill", tint: .indigo),
        // MARK: - report
        "report_to_user": ToolCallDescriptor(title: "Report Task Completion to User", symbolName: "bubble.left.and.exclamationmark.bubble.right.fill", tint: .green),
        // MARK: - reveal
        "reveal_in_finder": ToolCallDescriptor(title: "Reveal in Finder", symbolName: "folder.fill", tint: .blue),
        // MARK: - reverse
        "reverse_analyze": ToolCallDescriptor(title: "Reverse Analyze", symbolName: "arrow.counterclockwise", tint: .teal),
        // MARK: - runtime
        "runtime_diagnostics_engine": ToolCallDescriptor(title: "Runtime Diagnostics Engine", symbolName: "stethoscope", tint: .teal),
        // MARK: - safe
        "safe_undo": ToolCallDescriptor(title: "Undo Last Action", symbolName: "arrow.uturn.backward.circle.fill", tint: .blue),
        "safe_validate_changes": ToolCallDescriptor(title: "Validate Changes", symbolName: "checkmark.shield.fill", tint: .green),
        // MARK: - save
        "save_to_memory": ToolCallDescriptor(title: "Save to Memory", symbolName: "tray.and.arrow.down.fill", tint: .purple),
        // MARK: - scheme
        "scheme_test_plan_list": ToolCallDescriptor(title: "Scheme Test Plan List", symbolName: "hammer.fill", tint: .orange),
        // MARK: - search
        "search_regex": ToolCallDescriptor(title: "Regex Search", symbolName: "magnifyingglass", tint: .indigo),
        "search_skills": ToolCallDescriptor(title: "Search Agent Skills", symbolName: "magnifyingglass", tint: .indigo),
        "search_symbol": ToolCallDescriptor(title: "Symbol Search", symbolName: "curlybraces", tint: .indigo),
        "search_text": ToolCallDescriptor(title: "Search Text", symbolName: "magnifyingglass", tint: .indigo),
        // MARK: - secrets
        "secrets_scan": ToolCallDescriptor(title: "Secrets Scan", symbolName: "checkmark.shield.fill", tint: .teal),
        // MARK: - security
        "security_audit_scanner": ToolCallDescriptor(title: "Security Audit Scanner", symbolName: "checkmark.shield.fill", tint: .teal),
        // MARK: - semantic
        "semantic_query_engine": ToolCallDescriptor(title: "Semantic Source Query Engine", symbolName: "magnifyingglass.circle.fill", tint: .indigo),
        // MARK: - session
        "session_export": ToolCallDescriptor(title: "Export Session", symbolName: "square.and.arrow.up.fill", tint: .blue),
        "session_progress_report": ToolCallDescriptor(title: "Session Progress Report", symbolName: "chart.bar.fill", tint: .blue),
        // MARK: - signing
        "signing_certificate_inspector": ToolCallDescriptor(title: "Code Signing Certificate Inspector", symbolName: "checkmark.shield.fill", tint: .teal),
        // MARK: - simulator
        "simulator_boot": ToolCallDescriptor(title: "Boot Simulator", symbolName: "iphone", tint: .gray),
        "simulator_controller": ToolCallDescriptor(title: "Simulator Controller", symbolName: "iphone", tint: .gray),
        "simulator_list": ToolCallDescriptor(title: "List Simulators", symbolName: "iphone", tint: .gray),
        // MARK: - source
        "source_graph_builder": ToolCallDescriptor(title: "Source Graph Builder", symbolName: "hammer.fill", tint: .orange),
        // MARK: - spm
        "spm_dependency_tree": ToolCallDescriptor(title: "SPM Dependency Tree", symbolName: "shippingbox.fill", tint: .orange),
        // MARK: - stale
        "stale_files_report": ToolCallDescriptor(title: "Stale Files Report", symbolName: "chart.bar.fill", tint: .green),
        // MARK: - string
        "string_catalog_migrator": ToolCallDescriptor(title: "String Catalog Migrator", symbolName: "translate", tint: .blue),
        "string_literal_audit": ToolCallDescriptor(title: "String Literal Audit", symbolName: "checkmark.shield.fill", tint: .teal),
        // MARK: - strings
        "strings_file_validate": ToolCallDescriptor(title: "Strings File Validate", symbolName: "translate", tint: .blue),
        "strings_localization": ToolCallDescriptor(title: "Localization Strings", symbolName: "translate", tint: .blue),
        // MARK: - svg
        "svg_to_png": ToolCallDescriptor(title: "Convert SVG to PNG", symbolName: "photo.fill", tint: .pink),
        // MARK: - swift
        "swift_ast_inspector": ToolCallDescriptor(title: "Swift AST Inspector", symbolName: "checkmark.shield.fill", tint: .teal),
        "swift_concurrency_analyzer": ToolCallDescriptor(title: "Swift Concurrency Analyzer", symbolName: "arrow.triangle.2.circlepath", tint: .orange),
        "swift_data_schema_auditor": ToolCallDescriptor(title: "SwiftData Schema Auditor", symbolName: "checkmark.shield.fill", tint: .teal),
        "swift_format_lint": ToolCallDescriptor(title: "Swift Format Linter", symbolName: "paintbrush.fill", tint: .purple),
        "swift_migration_advisor": ToolCallDescriptor(title: "Swift 6 Migration Advisor", symbolName: "arrow.left.arrow.right", tint: .teal),
        "swift_package_manager": ToolCallDescriptor(title: "Swift Package Manager", symbolName: "shippingbox.fill", tint: .orange),
        // MARK: - symbol
        "symbol_move_file": ToolCallDescriptor(title: "Move Symbol Across Files", symbolName: "magnifyingglass", tint: .indigo),
        "symbol_reference_graph": ToolCallDescriptor(title: "Symbol Reference Graph", symbolName: "magnifyingglass", tint: .indigo),
        "symbol_rename_project": ToolCallDescriptor(title: "Rename Symbol Project-Wide", symbolName: "magnifyingglass", tint: .indigo),
        // MARK: - symlink
        "symlink_audit": ToolCallDescriptor(title: "Symlink Audit", symbolName: "checkmark.shield.fill", tint: .teal),
        // MARK: - system
        "system_notification_tool": ToolCallDescriptor(title: "Post macOS System Notification", symbolName: "bell.fill", tint: .orange),
        // MARK: - take
        "take_screenrecord": ToolCallDescriptor(title: "Take Screenrecord", symbolName: "record.circle.fill", tint: .red),
        "take_screenshot": ToolCallDescriptor(title: "Take Screenshot", symbolName: "camera.fill", tint: .gray),
        // MARK: - tar
        "tar_archive_create": ToolCallDescriptor(title: "Create tar Archive", symbolName: "archivebox.fill", tint: .gray),
        "tar_archive_extract": ToolCallDescriptor(title: "Extract tar Archive", symbolName: "archivebox.fill", tint: .gray),
        // MARK: - target
        "target_dependencies_list": ToolCallDescriptor(title: "Target Dependencies List", symbolName: "hammer.fill", tint: .orange),
        "target_source_list": ToolCallDescriptor(title: "Target Source List", symbolName: "hammer.fill", tint: .orange),
        // MARK: - task
        "task_runner": ToolCallDescriptor(title: "Run Task", symbolName: "checklist", tint: .orange),
        // MARK: - test
        "test_coverage_report": ToolCallDescriptor(title: "Test Coverage Report", symbolName: "checkmark.circle.fill", tint: .green),
        "test_coverage_reporter": ToolCallDescriptor(title: "Test Coverage Reporter", symbolName: "checkmark.circle.fill", tint: .green),
        "test_data_factory": ToolCallDescriptor(title: "Test Data Factory", symbolName: "checkmark.circle.fill", tint: .green),
        "test_flaky_detect": ToolCallDescriptor(title: "Flaky Test Detection", symbolName: "checkmark.circle.fill", tint: .green),
        "test_log_parse": ToolCallDescriptor(title: "Parse Test Log", symbolName: "checkmark.circle.fill", tint: .green),
        "test_run_single": ToolCallDescriptor(title: "Run Single Test", symbolName: "checkmark.circle.fill", tint: .green),
        "test_snapshot_manage": ToolCallDescriptor(title: "Manage Test Snapshots", symbolName: "checkmark.circle.fill", tint: .green),
        "test_target_add": ToolCallDescriptor(title: "Add Test Target", symbolName: "checkmark.circle.fill", tint: .green),
        // MARK: - todo
        "todo_fixme_scanner": ToolCallDescriptor(title: "TODO & FIXME Scanner", symbolName: "checkmark.shield.fill", tint: .teal),
        "todo_scan": ToolCallDescriptor(title: "TODO Scan", symbolName: "checkmark.shield.fill", tint: .teal),
        // MARK: - tool
        "tool_capability_lookup": ToolCallDescriptor(title: "Tool Capability Lookup", symbolName: "magnifyingglass.circle.fill", tint: .indigo),
        // MARK: - tree
        "tree_view": ToolCallDescriptor(title: "Tree View", symbolName: "list.bullet.indent", tint: .indigo),
        // MARK: - type
        "type_hierarchy": ToolCallDescriptor(title: "Type Hierarchy", symbolName: "point.3.connected.trianglepath", tint: .indigo),
        // MARK: - ui
        "ui_test_scaffold": ToolCallDescriptor(title: "UI Test Scaffold", symbolName: "plus.circle.fill", tint: .green),
        // MARK: - unused
        "unused_imports_detector": ToolCallDescriptor(title: "Unused Imports Detector", symbolName: "trash.fill", tint: .red),
        // MARK: - unzip
        "unzip_file": ToolCallDescriptor(title: "Unzip Archive", symbolName: "archivebox.fill", tint: .gray),
        // MARK: - use
        "use_app": ToolCallDescriptor(title: "Use App", symbolName: "app.fill", tint: .blue),
        "use_composio": ToolCallDescriptor(title: "Execute Composio Tool", symbolName: "app.connected.to.app.below.fill", tint: .teal),
        "use_mcp": ToolCallDescriptor(title: "Execute MCP Tool", symbolName: "network", tint: .teal),
        "use_system": ToolCallDescriptor(title: "System Diagnostics", symbolName: "cpu.fill", tint: .gray),
        "use_terminal": ToolCallDescriptor(title: "Use Terminal", symbolName: "terminal.fill", tint: .purple),
        "use_workers": ToolCallDescriptor(title: "Create and Coordinate Assist Workers", symbolName: "person.3.sequence.fill", tint: .blue),
        // MARK: - version
        "version_control_operator": ToolCallDescriptor(title: "Version Control Operator", symbolName: "arrow.triangle.branch", tint: .orange),
        // MARK: - view
        "view_memory": ToolCallDescriptor(title: "View Memory", symbolName: "brain", tint: .purple),
        // MARK: - workspace
        "workspace_settings_read": ToolCallDescriptor(title: "Workspace Settings Read", symbolName: "gearshape.fill", tint: .gray),
        // MARK: - xcode
        "xcode_build_settings_inspector": ToolCallDescriptor(title: "Xcode Build Settings Inspector", symbolName: "checkmark.shield.fill", tint: .teal),
        "xcode_device_destination_finder": ToolCallDescriptor(title: "Xcode Device Destination Finder", symbolName: "hammer.fill", tint: .orange),
        "xcode_scheme_manager": ToolCallDescriptor(title: "Xcode Scheme & Build Configuration Manager", symbolName: "hammer.fill", tint: .orange),
        "xcode_toolchain_info": ToolCallDescriptor(title: "Xcode Toolchain Info", symbolName: "hammer.fill", tint: .orange),
        // MARK: - xcresult
        "xcresult_parser": ToolCallDescriptor(title: "XCResult Bundle Parser", symbolName: "doc.text.below.ecg", tint: .green),
        // MARK: - xctest
        "xctest_discovery": ToolCallDescriptor(title: "XCTest Discovery", symbolName: "checkmark.circle.fill", tint: .green),
        // MARK: - yaml
        "yaml_parser_tool": ToolCallDescriptor(title: "YAML Parser & Validator", symbolName: "tablecells", tint: .teal),
        "yaml_validate": ToolCallDescriptor(title: "Validate YAML", symbolName: "tablecells", tint: .teal),
        // MARK: - zip
        "zip_file": ToolCallDescriptor(title: "Zip File or Directory", symbolName: "archivebox.fill", tint: .gray),
    ]
}
