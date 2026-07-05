# SwiftCode Feature Map (from dylans2010/SwiftCode)

This document maps the features integrated from the remote repository, excluding Agent and Assist related functionalities.

## 1. Project & File Management
- **Project Model**: Defines project structure, folders, and file nodes (Models/Project.swift, Models/ProjectFolder.swift).
- **Project Transfer**: Peer-to-peer project transfer (Backend/Projects/ProjectTransferManager.swift).
- **Collaboration**: Branch-based collaboration and conflict resolution (Backend/Projects/Collaboration/).

## 2. Code Editor
- **Syntax Highlighting**: Service for code highlighting (Services/SyntaxHighlighter.swift).
- **Code Formatter**: Swift/JSON formatting (Services/CodeFormatter.swift).
- **Editor Views**: Comprehensive editor with minimap and line numbers (Views/Editor/).

## 3. Build & Deployment
- **Local Building**: Bonjour-based build service (Backend/Local Building/).
- **CI Building**: GitHub Actions build integration (Backend/CI Building/).
- **Deployment**: Managers for Netlify, Vercel, and GitHub Pages (Backend/Deployments/).

## 4. GitHub Integration
- **Git Service**: Full Git operations support (Services/GitHubService.swift).
- **GitHub UI**: Views for commits, issues, pull requests, and gists (Views/GitHub/, Views/Gists/).

## 5. Developer & Debugging Tools
- **Inspectors**: File system, database, and memory inspectors (Views/Developer/).
- **Crash Analyzer**: Tools for analyzing crash logs (Features/AdvancedTools/Views/CrashLogAnalyzerView.swift).
- **Performance**: Real-time metrics dashboard (Views/Developer/RealtimeMetricsDashboardView.swift).

## 6. Local Simulation
- **SwiftUI Preview**: Local simulation and preview engine (Backend/Local Simulation/).

## 7. Extensions & Themes
- **Extension Manager**: System for managing IDE extensions (Services/ExtensionManager.swift).
- **Theme System**: Gallery and editor for IDE themes (Views/Settings/ThemeGalleryView.swift).

## 8. Onboarding & UI
- **Modern UI**: Custom styles and UI utilities (UI/Styles/, UI/Utilities/).
- **Onboarding**: Splash and welcome workflows (Views/Onboarding/).
