# SWIFTCODE-MAC — COMPLETE LEGACY FEATURE MIGRATION, ARCHITECTURE VALIDATION, AND SAFE REBRANDING

## MASTER AGENTIC EXECUTION DIRECTIVE

# 0. MISSION AND NON-NEGOTIABLE OBJECTIVE

Your mission is to perform a **COMPLETE migration of the required functionality from SwiftCode-Legacy into the production SwiftCode-Mac application.**

You have three repositories with distinct responsibilities:

| Repository | Responsibility |
|---|---|
| https://github.com/dylans2010/SwiftCode-Mac | Production destination |
| https://github.com/dylans2010/SwiftCode-Legacy | Source of functionality and feature implementations |
| https://github.com/MarcoDotIO/Ycode | Original upstream architectural reference |

The objective is to restore every feature specified in this document, including its supporting infrastructure, functionality, services, tools, resources, and workflows.

However, the production application must retain its own architecture, UI design, and existing AI provider/model infrastructure.

## THE FOUR MOST IMPORTANT RULES

1. **Migrate the functionality from Legacy.** Do not omit features because they are complicated or require architectural adaptation.
2. **Rebuild migrated interfaces to match the existing SwiftCode-Mac application.** Do not copy Legacy UI unchanged.
3. **Preserve the existing SwiftCode-Mac AI provider and model-calling infrastructure.** Integrate the migrated Assist system with it instead of replacing it.
4. **Implement the correct editor experience for each file type.** Opening a supported file must automatically activate its dedicated viewer/editor when one exists. Do not force users to find specialized file viewers manually in a tools drawer.

This is an implementation assignment, not a planning assignment.
You must investigate, implement, integrate, validate, and audit the work.
Do not stop after creating a plan or migration report.

---

# 1. REPOSITORY INVESTIGATION AND SOURCE OF TRUTH

- SwiftCode-Mac (current repo) is the production destination.
- SwiftCode-Legacy (in `./SwiftCode-Legacy`) is the feature source.
- Ycode (https://github.com/MarcoDotIO/Ycode) is the upstream architectural reference.

---

# 2. COMPLETE FEATURE MIGRATION

The following features are mandatory:
1. `.xcstrings` Localization Catalog UI (auto opens on .xcstrings)
2. Info.plist Viewer and Editor (auto opens on Info.plist)
3. `.xcodeproj` Project File Viewer (auto opens on .xcodeproj)
4. Artboards
5. Integrated Terminal
6. IPA Packaging
7. Full Source Control Workspace
8. CI Visual Workflows
9. Simulators & Previews
10. Visual UI Builder
11. SF Symbols Browser
12. Device Connect
13. Virtualization
14. Database Management
15. Coding Dictionary
16. Every Template available in SwiftCode-Legacy
17. SwiftCode Project Archive

---

# 3. COMPLETE ASSIST SYSTEM MIGRATION

- Migrate System Assets (`SwiftCode-Legacy/SwiftCode/Backend/Assist/Functions/System Assets`)
- Migrate Tools (`SwiftCode-Legacy/SwiftCode/Backend/Assist`)
- Rename to Assist
- PRESERVE AI PROVIDERS AND MODEL CALLS (do not replace SwiftCode-Mac provider infrastructure)

---

# 4. CENTRALIZED TOOLS DRAWER — SCTOOLSVIEW.SWIFT

- Implement `SCToolsView.swift`
- Add dedicated Tools button in editor interface
- Launches real standalone tools
- Specialized file viewers (Info.plist, .xcstrings, .xcodeproj) are automatically routed when files open, NOT forced through drawer.

---

# 5. AUTOMATIC FILE-TYPE DETECTION AND SPECIALIZED EDITOR ROUTING

- Info.plist -> Dedicated Info.plist Viewer/Editor
- *.xcstrings -> Dedicated Localization Catalog Viewer/Editor
- *.xcodeproj -> Dedicated Xcode Project Viewer
- Fallback to standard editor for normal files.
- Operate on real files and persist real saves.

---

# 6. SAFE REBRANDING & IMPORT AUDIT

- Product identity is SwiftCode.
- DO NOT blindly rename internal modules/imports (no fake SwiftCodeUI imports).
- Generate `IMPORT_AND_MODULE_AUDIT.md`.

---

# 7. CODE COMMENT REMOVAL AND 2-LINE COMMENT RULE

- Remove all comments across repository via script.
- For new/modified code, comments strictly <= 2 lines and only if truly important.

---

# 8. REQUIRED REPORTS

1. `MIGRATION_TRACKER.md`
2. `LEGACY_FEATURE_PARITY_AUDIT.md`
3. `IMPORT_AND_MODULE_AUDIT.md`
4. `REBRANDING_AND_IMPORT_REGRESSION_AUDIT.md`
5. `ASSIST_MIGRATION_AUDIT.md`
6. `PROJECT_INTEGRATION_AUDIT.md`
7. `REGRESSION_AUDIT.md`
8. `FILE_ROUTING_AUDIT.md`
9. `TOOLS_DRAWER_AUDIT.md`
10. `FINAL_MIGRATION_REPORT.md`
