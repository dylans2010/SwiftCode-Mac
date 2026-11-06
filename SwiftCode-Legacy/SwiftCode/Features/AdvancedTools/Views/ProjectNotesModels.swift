import Foundation

public struct NoteAttachment: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public var name: String
    public var type: String // "image", "pdf", "markdown", "text", "json", "yaml", "swift", "zip", "audio", "video"
    public var relativePath: String
    public var createdAt: Date

    public init(id: UUID = UUID(), name: String, type: String, relativePath: String, createdAt: Date = Date()) {
        self.id = id
        self.name = name
        self.type = type
        self.relativePath = relativePath
        self.createdAt = createdAt
    }
}

public struct NoteVersion: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public let noteId: UUID
    public var content: String
    public var timestamp: Date

    public init(id: UUID = UUID(), noteId: UUID, content: String, timestamp: Date = Date()) {
        self.id = id
        self.noteId = noteId
        self.content = content
        self.timestamp = timestamp
    }
}

public struct SavedSearch: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public var query: String
    public var category: String
    public var createdAt: Date

    public init(id: UUID = UUID(), query: String, category: String = "General", createdAt: Date = Date()) {
        self.id = id
        self.query = query
        self.category = category
        self.createdAt = createdAt
    }
}

public struct ProjectNotebook: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public var name: String
    public var createdAt: Date

    public init(id: UUID = UUID(), name: String, createdAt: Date = Date()) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
    }
}

public struct ProjectNote: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public var title: String
    public var content: String
    public var notebookId: UUID
    public var category: String // "Architecture", "API", "Build", "Debugging", etc.
    public var tags: [String]
    public var isPinned: Bool
    public var isFavorite: Bool
    public var isArchived: Bool
    public var author: String
    public var wordCount: Int
    public var readingTime: Int // in minutes
    public var characterCount: Int
    public var createdAt: Date
    public var updatedAt: Date

    // Linking relationships
    public var linkedNoteIds: Set<UUID>
    public var linkedFiles: [String]
    public var linkedSymbols: [String]
    public var linkedGitCommits: [String]
    public var linkedBuildLogs: [String]
    public var linkedDeployments: [String]
    public var attachments: [NoteAttachment]
    public var backlinkNoteIds: Set<UUID>

    public init(
        id: UUID = UUID(),
        title: String,
        content: String,
        notebookId: UUID,
        category: String = "General",
        tags: [String] = [],
        isPinned: Bool = false,
        isFavorite: Bool = false,
        isArchived: Bool = false,
        author: String = "Developer",
        wordCount: Int = 0,
        readingTime: Int = 0,
        characterCount: Int = 0,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        linkedNoteIds: Set<UUID> = [],
        linkedFiles: [String] = [],
        linkedSymbols: [String] = [],
        linkedGitCommits: [String] = [],
        linkedBuildLogs: [String] = [],
        linkedDeployments: [String] = [],
        attachments: [NoteAttachment] = [],
        backlinkNoteIds: Set<UUID> = []
    ) {
        self.id = id
        self.title = title
        self.content = content
        self.notebookId = notebookId
        self.category = category
        self.tags = tags
        self.isPinned = isPinned
        self.isFavorite = isFavorite
        self.isArchived = isArchived
        self.author = author
        self.wordCount = wordCount
        self.readingTime = readingTime
        self.characterCount = characterCount
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.linkedNoteIds = linkedNoteIds
        self.linkedFiles = linkedFiles
        self.linkedSymbols = linkedSymbols
        self.linkedGitCommits = linkedGitCommits
        self.linkedBuildLogs = linkedBuildLogs
        self.linkedDeployments = linkedDeployments
        self.attachments = attachments
        self.backlinkNoteIds = backlinkNoteIds
    }
}

public struct ProjectNoteTemplates {
    public static let builtInTemplates: [String: String] = [
        "Architecture Notes": """
# Architecture Notes: [System/Module Name]

## 1. Executive Summary
Provide a high-level summary of the subsystem or module architecture.

## 2. Design Pattern & Structure
Describe the architectural patterns used (e.g., MVVM, Clean Architecture, Actor-based isolation).

## 3. Data Flow & Communication
Detail how data flows between components.
- Class/Struct references: `MyService`, `DataStore`

## 4. Technical Debt & Trade-offs
List the compromises made during this implementation.
""",

        "API Documentation": """
# API Documentation: [API Name]

## 1. Overview
High-level description of what this API exposes and its client scope.

## 2. Authentication & Headers
```http
Authorization: Bearer <token>
Content-Type: application/json
```

## 3. Endpoint Specifications
### GET /v1/resource
- **Request Parameters:** None
- **Response Payload:**
```json
{
  "id": "uuid",
  "status": "active"
}
```

## 4. Error Codes
- `401 Unauthorized`
- `429 Rate Limited`
""",

        "Build Notes": """
# Build Notes: Release [Version]

## 1. Build Metadata
- **Target Platform:** macOS 15.0+ / iOS 18.0+
- **Build Configuration:** Release / Release.xcconfig
- **Signing Profile:** Developer Identity

## 2. Compilation Targets
Specify target modules and dependencies updated.

## 3. Critical Warnings & Suppressions
Detail any compiler warning resolutions or safe bypasses.
""",

        "Debugging Notes": """
# Debugging Notes: Bug ID [number]

## 1. Problem Description
Detailed log of the unexpected behavior or crash trace.

## 2. Reproduction Steps
1. Navigate to Settings.
2. Select offline sync mode.
3. Observe crash or freeze.

## 3. Root Cause Analysis
Explain why the crash occurred (e.g., race condition in multi-thread database write).

## 4. Verification & Testing
Steps taken to verify the fix works correctly.
""",

        "Deployment Notes": """
# Deployment Notes: [Environment]

## 1. Target Environment
- **Host:** Netlify / Supabase Cloud / Vercel
- **Database Migrations:** Yes/No

## 2. Pre-Deployment Checklist
- [ ] Run test suites.
- [ ] Verify env variables match the target profile.

## 3. Rollback Procedure
Command or steps to restore the previous stable release.
""",

        "Feature Planning": """
# Feature Planning: [Feature Title]

## 1. User Story & Goal
As a user, I want to [action] so that [benefit].

## 2. Scope & Boundaries
Define what is in-scope and out-of-scope.

## 3. Design & Architecture Sketch
Brief description of the UI components and backend stores required.
""",

        "Sprint Planning": """
# Sprint Planning: [Sprint Name]

## 1. Sprint Goal
Core objective for the upcoming development cycle.

## 2. Team Capacity
Details of developer availability and story points allocation.

## 3. Backlog Items
- [ ] Feature: Expanded search engine
- [ ] Bug: Fix window restoration offset
""",

        "Bug Investigation": """
# Bug Investigation: [Bug Title]

## 1. Symptoms & Logs
Paste relevant console traces or crash reports here.

## 2. Areas of Inquiry
Code modules that could potentially cause this symptom.

## 3. Findings & Resolution Plan
Propose steps to isolate and eliminate the bug.
""",

        "Code Reviews": """
# Code Review Plan: PR #[Number]

## 1. Review Objectives
Ensure strict concurrency guidelines are met and project registration matches conventions.

## 2. Focus Areas
- Concurrency isolation boundaries
- Force unwrap validations
- General code styling

## 3. Feedback Notes
Detailed notes for the author.
""",

        "Refactoring Plans": """
# Refactoring Plan: [Module Name]

## 1. Rationale
Why does this module need to be refactored? (e.g., massive view controller, redundant conformances)

## 2. Target Architecture
Proposed clean state structure.

## 3. Safe Migration Steps
Phase-by-phase migration plan to avoid regressions.
""",

        "Design Decisions": """
# Architectural Design Decision (ADR)

## 1. Title & Context
Title of the ADR and historical context of the problem.

## 2. Options Considered
List alternatives along with pros and cons.

## 3. Decision
Which path was chosen and why.

## 4. Consequences
Implications of this decision on future features.
""",

        "Meeting Notes": """
# Meeting Notes: [Topic]
**Date:** [Date] | **Attendees:** [List]

## 1. Agenda
Key topics scheduled for discussion.

## 2. Discussion Summary
Overview of conversation and agreements.

## 3. Action Items
- [ ] Developer A: Build persistent database schemas.
- [ ] Developer B: Polish 3-column split view.
""",

        "Release Notes": """
# Release Notes: Version [X.Y.Z]

## 1. Overview
Summary of major highlights in this release.

## 2. New Features
- **Knowledge Base:** Advanced multi-pane project note systems.

## 3. Bug Fixes & Refactoring
- Corrected thread-safety on background indexers.
""",

        "Changelog Entries": """
# Changelog - [Module]

## [Unreleased]
- Added template support to Project Notes.

## [1.0.0] - 2026-07-25
- First stable release of the workspace documentation hub.
""",

        "Security Reviews": """
# Security Review: [Module Name]

## 1. Threat Modeling
Identify potential attack vectors or injection risks.

## 2. Compliance Checklist
- [ ] API keys protected in Keychain.
- [ ] Row Level Security (RLS) active on database.

## 3. Remediation Items
Actions required to close identified security gaps.
""",

        "Database Documentation": """
# Database Schema Documentation

## 1. Table: `profiles`
- **user_id:** UUID (Primary Key, Foreign Key -> users)
- **username:** String (Nullable)

## 2. Migration Triggers
Details of cascade deletes and row automatic timestamp updates.
""",

        "AI Prompts": """
# Prompt Spec: [Prompt Action]

## 1. System Instruction Context
```text
You are an expert iOS developer...
```

## 2. Model Configuration
- **Selected Model:** meta-llama/llama-3-70b-instruct
- **Temperature:** 0.2
""",

        "Research Notes": """
# Research Notes: [Topic]

## 1. Abstract & Scope
Scope of the technical exploration.

## 2. Literature/API Review
Findings from Apple Developer documentation or open-source guides.

## 3. Prototype Implementation
Details of prototype performance and architectural viability.
""",

        "Performance Analysis": """
# Performance Analysis: [Module Name]

## 1. Benchmarking Scope
Focus areas (e.g., main thread frames, file read latency).

## 2. Observations & Metrics
- Frame Rate (FPS)
- CPU Usage (%)
- Memory Usage (MB)

## 3. Optimization Opportunities
List of bottlenecks and recommended actions.
""",

        "Testing Plans": """
# Test Plan: [Feature Name]

## 1. Testing Strategy
Unit tests, Integration tests, and automated UI checks.

## 2. Test Cases
- [ ] Case 1: Invalid key rejection
- [ ] Case 2: Autosave triggers after 3 seconds of inactivity
""",

        "User Stories": """
# User Story: [Title]

## 1. Description
As a developer, I want a collapsible 3-column workspace so that I can maximize editing space.

## 2. Acceptance Criteria
- [ ] Double-click folder to open.
- [ ] Drag handle dynamically resizes panes.
""",

        "Feature Requests": """
# Feature Request: [Proposed Feature]

## 1. Context & Requestor
Who is requesting this and why?

## 2. Expected Behavior
Description of the ideal user experience.

## 3. Impact & Priority
Strategic value and estimated story points.
""",

        "Technical Debt": """
# Technical Debt Log: [Module]

## 1. Identified Debt
Explain where code complexity exceeds standards.

## 2. Strategic Impact
How does this debt affect future velocity or robustness?

## 3. Remediation Strategy
Action plan to pay down this technical debt.
""",

        "Migration Plans": """
# Migration Plan: [Target Framework/API]

## 1. Target Tech Stack
Migrating from Combine to Swift 6 Concurrency.

## 2. Deprecation Timeline
When old code routes will be deprecated and permanently deleted.

## 3. Execution Plan
Detailed steps of the migration code changes.
""",

        "Dependency Notes": """
# Dependency Log: [Package Name]

## 1. Package Metadata
- **Source:** https://github.com/...
- **License:** MIT
- **Target Version:** Up to Next Major

## 2. Architectural Impact
Integration points inside our codebase.
"""
    ]
}
