Migrate missing features from SwiftCode-Legacy into the production codebase using the new application UI, align the Assist system with legacy tools and system training assets, unconditionally remove all existing code comments via a script, harden experimental features to production readiness, and implement the Version 2 roadmap features with 100% real functionality.

Working directory: /Users/dylan/Downloads/SwiftCode
Integrity mode: development

## Requirements

### R1. Code Comment Removal and Commenting Policy
Create and execute a script that removes all code comments unconditionally from every file across the repository. For all newly written or edited code, do not add comments unless truly important, and keep any such comment strictly to a maximum of 2 lines.

### R2. SwiftCode-Legacy Feature Audit and Production Migration
Generate a temporary `inventory.md` file tracking all features present in `SwiftCode-Legacy`. Compare this inventory against the production codebase (the entire repository outside `SwiftCode-Legacy/`). For any feature missing from production, implement it by porting the necessary `.swift` source files into the production codebase and adapting them to ensure the feature is fully usable and uses the UI from the new app rather than the legacy app UI.

### R3. Assist System Realignment
Rename the Assistant system to Assist, maintaining the existing model powering infrastructure. Configure Assist to support the tools located in `SwiftCode-Legacy/SwiftCode/Backend/Assist` and pull training data from `SwiftCode-Legacy/SwiftCode/Backend/Assist/Functions/System Assets`. If Assist is integrated via MCP, configure it so these are strictly the only tools and system training the assistant receives.

### R4. Experimental Features Hardening
Update all experimental features across the codebase so they are fully production ready.

### R5. Version 2 Roadmap Features
Implement the next set of features listed in README.md under "Version 2: Xcode 27.2 parity and Further out". All implemented features must be 100% real implementations with zero fake data or simulated behaviors.

## Acceptance Criteria

### Comment Removal & Cleanliness
- [ ] A script removes all code comments from every file across the repository.
- [ ] No code comments exceeding 2 lines exist in newly authored or modified files.

### Legacy Parity & Migration
- [ ] Temporary file `inventory.md` catalogs all features from `SwiftCode-Legacy` and their status in the production codebase.
- [ ] All missing features identified from `SwiftCode-Legacy` are implemented in the production codebase outside `SwiftCode-Legacy/`.
- [ ] Migrated features render and operate using the new app UI rather than legacy UI.

### Assist System
- [ ] The Assistant system is renamed to Assist.
- [ ] Assist supports the tools from `SwiftCode-Legacy/SwiftCode/Backend/Assist`.
- [ ] Assist training data is sourced from `SwiftCode-Legacy/SwiftCode/Backend/Assist/Functions/System Assets`.
- [ ] Assist receives exclusively the specified tools and training data (including across MCP integration if applicable).
- [ ] The model powering mechanism for Assist remains intact.

### Production Hardening & V2 Parity
- [ ] All experimental features across the codebase are updated to production-ready status.
- [ ] Features listed under "Version 2: Xcode 27.2 parity and Further out" in README.md are implemented with real functionality, without fake data or simulated behaviors.
- [ ] Existing project test suites (`swift test`) and build verification commands succeed.
