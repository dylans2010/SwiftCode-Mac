import Foundation

public struct WorkflowTemplates {
    public static var templates: [DeveloperWorkflow] {
        [
            DeveloperWorkflow(
                name: "Morning Startup",
                description: "Sync your local project repository, update dependencies, boot your simulator, and prepare your coding workspace.",
                icon: "sun.max.fill",
                category: "Startup",
                steps: [
                    WorkflowStep(name: "Pull Latest Changes", description: "Fetch and pull commits from remote origin.", icon: "arrow.down.doc.fill", category: "Git", estimatedDuration: 2.0, inputs: ["rebase": "true"]),
                    WorkflowStep(name: "Resolve Swift Packages", description: "Resolve and download SPM package dependencies.", icon: "shippingbox.fill", category: "Swift", estimatedDuration: 5.0),
                    WorkflowStep(name: "Launch Simulator", description: "Boot selected macOS or iOS simulator platform.", icon: "iphone", category: "Xcode", estimatedDuration: 3.0, inputs: ["device": "iPhone 16 Pro"]),
                    WorkflowStep(name: "Build Project", description: "Perform an initial standard workspace compilation.", icon: "hammer.fill", category: "Swift", estimatedDuration: 10.0, inputs: ["configuration": "Debug"])
                ]
            ),
            DeveloperWorkflow(
                name: "Pre-Commit & Validate",
                description: "Clean artifacts, format your Swift style rules, execute unit tests, and prepare clean code for git push.",
                icon: "checkmark.shield.fill",
                category: "Quality",
                steps: [
                    WorkflowStep(name: "Format Code", description: "Run formatting linter tool on all active sources.", icon: "wand.and.stars", category: "Swift", estimatedDuration: 1.5, inputs: ["tool": "swift-format"]),
                    WorkflowStep(name: "Clean Build", description: "Purge local DerivedData and package build caches.", icon: "trash.fill", category: "Swift", estimatedDuration: 4.0),
                    WorkflowStep(name: "Run Unit Tests", description: "Execute test suite against active target configuration.", icon: "play.square.fill", category: "Swift", estimatedDuration: 12.0, inputs: ["scheme": "SwiftCodeTests"]),
                    WorkflowStep(name: "Stage & Commit", description: "Auto-stage changes and record localized commits.", icon: "doc.badge.plus", category: "Git", estimatedDuration: 1.0, inputs: ["message": "Pre-commit auto validation checks passed."])
                ]
            ),
            DeveloperWorkflow(
                name: "Release Candidate Builder",
                description: "Increment versioning details, compile final App archives, generate changelog notes, tag releases, and push.",
                icon: "shippingbox.fill",
                category: "Release",
                steps: [
                    WorkflowStep(name: "Increment Version", description: "Update active build or release version index.", icon: "plus.circle.fill", category: "Xcode", estimatedDuration: 1.0, inputs: ["type": "patch"]),
                    WorkflowStep(name: "Generate Changelog", description: "Extract commit messages since last tag to compile notes.", icon: "doc.text.fill", category: "Documentation", estimatedDuration: 2.0),
                    WorkflowStep(name: "Archive App Bundle", description: "Generate release-optimized archive of the main target.", icon: "archivebox.fill", category: "Xcode", estimatedDuration: 25.0, inputs: ["configuration": "Release"]),
                    WorkflowStep(name: "Create Git Tag", description: "Tag current commit in preparation for production launch.", icon: "tag.fill", category: "Git", estimatedDuration: 1.0, inputs: ["name": "v1.0.0-rc"]),
                    WorkflowStep(name: "Publish GitHub Release", description: "Upload app binaries and assets directly to GitHub.", icon: "cloud.and.arrow.up.fill", category: "GitHub", estimatedDuration: 6.0)
                ]
            ),
            DeveloperWorkflow(
                name: "Dependency Maintenance",
                description: "Sync repository main, run package updates, compile, and commit changes.",
                icon: "arrow.triangle.2.circlepath.circle.fill",
                category: "Maintenance",
                steps: [
                    WorkflowStep(name: "Sync Repository", description: "Perform deep fetch and hard pull synchronization.", icon: "arrow.clockwise", category: "Git", estimatedDuration: 3.0),
                    WorkflowStep(name: "Update Packages", description: "Update all packages to their latest minor versions.", icon: "arrow.up.circle.fill", category: "Swift", estimatedDuration: 15.0),
                    WorkflowStep(name: "Verify Project Build", description: "Verify compilation status post dependency updates.", icon: "hammer.fill", category: "Swift", estimatedDuration: 8.0)
                ]
            )
        ]
    }
}
