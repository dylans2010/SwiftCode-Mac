# SwiftCode macOS View Rules

This section defines the permanent native macOS desktop UI specification for SwiftCode. Every SwiftUI view inside SwiftCode must satisfy these criteria.

### 1. Layout
- **Desktop-First Design:** Optimize layout architectures primarily for large horizontal monitors and advanced keyboard-centric productivity. Do not use iOS-specific layout abstractions.
- **Window Resizing & Sizing Constraints:** Views must cleanly scale horizontally and vertically when the host window is resized. Define appropriate `.frame(minWidth: ..., minHeight: ..., maxWidth: ..., maxHeight: ...)` constraints where needed.
- **Adaptive Layouts:** Support flexible adaptive grid structures and flow layouts that dynamically arrange content based on window metrics.
- **Split View Compatibility:** Use native `HSplitView` and `VSplitView` rather than nested `NavigationSplitView` setups to prevent visual layout loops or UI freezing.
- **Geometry Awareness:** Utilize `GeometryReader` specifically to calculate dynamic panel sizes, while managing safety bounds so that geometry recalculations do not cause layout loops.
- **Multi-Monitor & Scale Support:** Ensure visual assets, rendering paths, and text layouts scale cleanly across standard and Retina Displays (@1x, @2x, @3x, multi-monitor dragging).
- **Control Alignment & Spacing:** Use consistent native spacing (typically 8pt, 12pt, or 16pt). Align items perfectly to avoid clipped text or overlapping controls. No hidden or out-of-bounds controls.
- **Safe Area Correctness:** Avoid overriding macOS safe area boundaries unless implementing true edge-to-edge content.
- **Sidebars & Inspectors:** Sidebars must use a standard native sidebar list style (`.listStyle(.sidebar)`), respect system accent colors, and remain collapse-resistant in primary configurations. Detailed view panels should be cleanly structured inside inspectors or right detail sheets.

### 2. Navigation
- **Native Sidebar Navigation:** Use `.listStyle(.sidebar)` for top-level navigation lists. Selection states must be preserved and high-visibility marked.
- **Toolbar Design:** Keep toolbars clean and standard macOS style. Do not use iOS-specific placements (e.g., `.topBarTrailing`, `.navigationBarTrailing`). Standardize placement to `.primaryAction` or `.secondaryAction`.
- **Navigation Split View & Stack Best Practices:** Use standard `NavigationStack` for detail drilling. Selection states must be fully persisted.
- **Keyboard Navigation:** Support navigation between lists, menus, and sidebars via arrow keys, Tab keys, and standard shortcuts.
- **Navigation & Selection Persistence:** User's selected tab, target, list selection, and scroll positions must survive view switches and tab changes via persistent coordinators.
- **Breadcrumbs:** Provide path breadcrumbs for multi-level or file-based navigation tree drilling.

### 3. Visual Design
- **Native macOS Appearance:** Mimic Apple's native design aesthetics, utilizing system colors (`.secondary`, `.tertiary`, `.background`) and vibrancy.
- **Liquid Glass Integration:** Implement glassmorphism and subtle gradient materials using native materials (`.ultraThinMaterial`, `.regularMaterial`) with fallback behaviors for older macOS versions.
- **Corner Radii & Shadows:** Use native Apple corner radii (typically 4pt to 8pt for smaller controls, 10pt to 12pt for panels) and standard soft shadow drop layers (`.shadow(color: Color.black.opacity(0.1), radius: 5, x: 0, y: 2)`).
- **Typography Hierarchy:** Establish clean visual weight hierarchies (bold titles, regular subheadlines, monospaced captions). Adjust font sizes appropriately for desktop viewing (typically 11pt-13pt body size).
- **Accent Color Consistency:** Use system accent colors for interactive highlights, active buttons, or primary selection checks.
- **Interaction States:** Make hover, pressed, disabled, and active selection states highly visible. Apply subtle `.hoverEffect` or transition animations.
- **Empty, Loading, Success, & Error States:** Use standard `ContentUnavailableView` or structured placeholders with symbolic iconography (SF Symbols) and descriptive headers for zero-state, loading progress, and error recoveries.
- **SF Symbol Conventions:** Always choose modern, descriptive, and correct SF Symbols matching Apple’s guidelines.

### 4. Lists
- **Native Row Heights & Spacing:** Use compact row heights appropriate for desktop lists (typically 20pt to 28pt) and ensure stable identity for rendering performance.
- **Native Selection & Highlights:** Support multi-selection where appropriate and standard context-highlight selection styles.
- **Scrolling Mechanics:** Ensure smooth scrolling under heavy list item numbers. Implement virtualized/lazy cells where appropriate.
- **Context & Right-click Menus:** Every critical list row should support right-click `.contextMenu` actions.
- **Drag and Drop:** Support standard native file/folder or item reordering through standard SwiftUI Drag & Drop bindings (`.onDrag`, `.onDrop`).

### 5. Forms
- **Native Alignment & Styling:** Use macOS-native `.formStyle(.grouped)` or `.formStyle(.columns)` architectures. Align labels and fields cleanly.
- **Validation & Focus Handling:** Display inline validation error messages dynamically. Keep focus rings active for standard input fields and support Tab-key navigation between inputs.
- **Submit/Cancel Actions:** Ensure standard keyboard triggers (e.g., Return to submit, Escape to cancel) are supported in dialog forms.

### 6. Buttons
- **Style Consistency:** Match button styles to action intent (e.g., `.buttonStyle(.borderedProminent)` for primary, `.buttonStyle(.bordered)` or `.buttonStyle(.plain)` for secondary/contextual).
- **Target Sizes & Keyboard Shortcuts:** Buttons should support standard mouse hit-targets (min 20x20 for toolbars) and register keyboard shortcuts where applicable (e.g., Command+S to save).

### 7. Windows & Modals
- **Escape & Close Behaviors:** Sheets and popovers must support pressing the Escape key to close.
- **Sheet/Popover/Inspector Sizing:** Explicitly set minimum/ideal bounds for modals. Popovers should track standard anchor nodes.
- **State & Dimension Restoration:** Window sizes and view structures must be saved/restored across sessions where appropriate.

### 8. Performance
- **Lazy Rendering & Redraw Minimization:** Use `LazyVStack`, `LazyHStack`, or `List` for scrollable arrays. Prevent continuous view redraw loops.
- **State Isolation:** Ensure business logic is outside views. Use `@Observable` with `@MainActor` isolation. Separately offload background computations.
- **Decomposition:** Keep views decomposed into smaller, modular subviews to avoid compiler slowdowns and unnecessary recalculation of large view bodies.

### 9. Accessibility
- **VoiceOver & Accessibility Elements:** Ensure every non-text interface has proper `.accessibilityLabel` and `.accessibilityHint` declarations.
- **Keyboard Traversal & Focus Flow:** Focus order must follow standard logical column-by-row patterns.
- **Contrast Compliance:** Ensure visual designs maintain AA or AAA color contrast ratios against background layers.

### 10. macOS Specific Behaviors
- **Context Menus:** Support context-sensitive actions upon right-click.
- **Double-click Actions:** Standardize double-click triggers on file/folder lists (e.g., double-click to rename or open in workflow).
- **Pointer & Hover Interactions:** Trigger subtle color or highlight changes when the cursor hovers over buttons, cards, or list entries.
- **Command Menus:** Ensure application commands map to system menu bar shortcuts.

### 11. Code Quality & State Management
- **View Isolation:** Keep SwiftUI views presentation-only. Do not mix business logic, file I/O, or remote API logic inside view bodies.
- **Observable State:** Use central, MainActor-isolated `@Observable` models for state. Avoid legacy `ObservableObject` and `@Published` inside views where possible.
- **Single Source of Truth:** No duplicated state variables. Inject dependencies via environment objects or standard bindings.

---

# SwiftCode View Mapping

| Relative Path | View Name | Directory | Parent Folder |
| --- | --- | --- | --- |
| `SwiftCode/Views/AI/AI New/AICodeReviewView.swift` | `AICodeReviewView` | `AI New` | `AI` |
| `SwiftCode/Views/AI/AI New/AICodeReviewView.swift` | `AICodeReviewIssueRowView` | `AI New` | `AI` |
| `SwiftCode/Views/AI/AI New/AICodeReviewView.swift` | `AICodeReviewIssueDetailSheet` | `AI New` | `AI` |
| `SwiftCode/Views/AI/AI New/AICoreView.swift` | `AICoreView` | `AI New` | `AI` |
| `SwiftCode/Views/AI/AI New/AICoreView.swift` | `TraditionalAgentView` | `AI New` | `AI` |
| `SwiftCode/Views/AI/AI New/AgentModeView.swift` | `AgentModeView` | `AI New` | `AI` |
| `SwiftCode/Views/AI/AI New/AgentToolbar.swift` | `AgentToolbar` | `AI New` | `AI` |
| `SwiftCode/Views/AI/AI New/ChatAIInterfaceView.swift` | `ChatAIInterfaceView` | `AI New` | `AI` |
| `SwiftCode/Views/AI/AI New/CodeChangesView.swift` | `CodeChangesView` | `AI New` | `AI` |
| `SwiftCode/Views/AI/AI New/Codex UIs/CodexAPIKeyView.swift` | `CodexAPIKeyView` | `Codex UIs` | `AI New` |
| `SwiftCode/Views/AI/AI New/Codex UIs/CodexDiffViewer.swift` | `CodexDiffViewer` | `Codex UIs` | `AI New` |
| `SwiftCode/Views/AI/AI New/Codex UIs/CodexErrorView.swift` | `CodexErrorView` | `Codex UIs` | `AI New` |
| `SwiftCode/Views/AI/AI New/Codex UIs/CodexFileHistoryView.swift` | `CodexFileHistoryView` | `Codex UIs` | `AI New` |
| `SwiftCode/Views/AI/AI New/Codex UIs/CodexMainView.swift` | `CodexMainView` | `Codex UIs` | `AI New` |
| `SwiftCode/Views/AI/AI New/Codex UIs/CodexPullRequestView.swift` | `CodexPullRequestView` | `Codex UIs` | `AI New` |
| `SwiftCode/Views/AI/AI New/Codex UIs/CodexRerunView.swift` | `CodexRerunView` | `Codex UIs` | `AI New` |
| `SwiftCode/Views/AI/AI New/Codex UIs/CodexUndoRedoView.swift` | `CodexUndoRedoView` | `Codex UIs` | `AI New` |
| `SwiftCode/Views/AI/AI New/Codex UIs/CodexUsageView.swift` | `CodexUsageView` | `Codex UIs` | `AI New` |
| `SwiftCode/Views/AI/AI New/ToolExecutionView.swift` | `ToolExecutionView` | `AI New` | `AI` |
| `SwiftCode/Views/AI/ChatUIComponents.swift` | `AssistantSectionHeader` | `AI` | `Views` |
| `SwiftCode/Views/AI/ChatUIComponents.swift` | `ChatMessageBubble` | `AI` | `Views` |
| `SwiftCode/Views/AI/ChatUIComponents.swift` | `TypingIndicatorBubble` | `AI` | `Views` |
| `SwiftCode/Views/AI/ChatUIComponents.swift` | `SlashCommandList` | `AI` | `Views` |
| `SwiftCode/Views/AI/CodeReviewView.swift` | `CodeReviewView` | `AI` | `Views` |
| `SwiftCode/Views/AI/CodeReviewView.swift` | `IssueRowView` | `AI` | `Views` |
| `SwiftCode/Views/AI/CodeReviewView.swift` | `IssueDetailSheet` | `AI` | `Views` |
| `SwiftCode/Views/AI/ComplexityAnalyzerView.swift` | `ComplexityAnalyzerView` | `AI` | `Views` |
| `SwiftCode/Views/AI/OnDeviceAIView.swift` | `OnDeviceAIView` | `AI` | `Views` |
| `SwiftCode/Views/AIAssistantPanelView.swift` | `AIAssistantPanelView` | `Views` | `SwiftCode` |
| `SwiftCode/Views/AIChatInputView.swift` | `AIChatInputView` | `Views` | `SwiftCode` |
| `SwiftCode/Views/AIChatMessageListView.swift` | `AIChatMessageListView` | `Views` | `SwiftCode` |
| `SwiftCode/Views/AIModelPickerView.swift` | `AIModelPickerView` | `Views` | `SwiftCode` |
| `SwiftCode/Views/AISuggestionActionBar.swift` | `AISuggestionActionBar` | `Views` | `SwiftCode` |
| `SwiftCode/Views/Agent/AgentAttachmentChipView.swift` | `AgentAttachmentChipView` | `Agent` | `Views` |
| `SwiftCode/Views/Agent/AgentAttachmentPickerView.swift` | `AgentAttachmentPickerView` | `Agent` | `Views` |
| `SwiftCode/Views/Agent/AgentChatView.swift` | `AgentChatView` | `Agent` | `Views` |
| `SwiftCode/Views/Agent/AgentChecklistView.swift` | `AgentChecklistView` | `Agent` | `Views` |
| `SwiftCode/Views/Agent/AgentInputBarView.swift` | `AgentInputBarView` | `Agent` | `Views` |
| `SwiftCode/Views/Agent/AgentMessageBubbleView.swift` | `AgentMessageBubbleView` | `Agent` | `Views` |
| `SwiftCode/Views/Agent/AgentMessageListView.swift` | `AgentMessageListView` | `Agent` | `Views` |
| `SwiftCode/Views/Agent/AgentToolCallSummaryView.swift` | `AgentToolCallSummaryView` | `Agent` | `Views` |
| `SwiftCode/Views/Agent/AskUserPromptView.swift` | `AskUserPromptView` | `Agent` | `Views` |
| `SwiftCode/Views/Agent/QuestionsHandleView.swift` | `QuestionsHandleView` | `Agent` | `Views` |
| `SwiftCode/Views/Agent/Skills/SkillsEditorView.swift` | `SkillsEditorView` | `Skills` | `Agent` |
| `SwiftCode/Views/Agent/Skills/SkillsLibraryView.swift` | `SkillsLibraryView` | `Skills` | `Agent` |
| `SwiftCode/Views/Agent/Skills/SkillsManagerView.swift` | `SkillsManagerView` | `Skills` | `Agent` |
| `SwiftCode/Views/Agent/Skills/SkillsManagerView.swift` | `SkillsImportView` | `Skills` | `Agent` |
| `SwiftCode/Views/Agent/Skills/SkillsManagerView.swift` | `SkillsCreateView` | `Skills` | `Agent` |
| `SwiftCode/Views/Build/AppDetailsInfo.swift` | `AppDetailsInfo` | `Build` | `Views` |
| `SwiftCode/Views/Build/BuildLogsView.swift` | `BuildLogsView` | `Build` | `Views` |
| `SwiftCode/Views/Build/BuildStatusView.swift` | `BuildStatusView` | `Build` | `Views` |
| `SwiftCode/Views/Build/BuildStatusView.swift` | `BuildRunCard` | `Build` | `Views` |
| `SwiftCode/Views/Build/BuildStatusView.swift` | `ReleaseRow` | `Build` | `Views` |
| `SwiftCode/Views/Build/BuildStatusView.swift` | `BuildGuideView` | `Build` | `Views` |
| `SwiftCode/Views/Build/CIBuildView.swift` | `CIBuildView` | `Build` | `Views` |
| `SwiftCode/Views/Build/LocalBuildDemoView.swift` | `LocalBuildDemoView` | `Build` | `Views` |
| `SwiftCode/Views/Build/LocalBuildView.swift` | `LocalBuildView` | `Build` | `Views` |
| `SwiftCode/Views/Build/PrepareCompileWaitingView.swift` | `PrepareCompileWaitingView` | `Build` | `Views` |
| `SwiftCode/Views/Build/TerminalView.swift` | `TerminalView` | `Build` | `Views` |
| `SwiftCode/Views/BuildConsoleView.swift` | `BuildConsoleView` | `Views` | `SwiftCode` |
| `SwiftCode/Views/BuildToolbarView.swift` | `BuildToolbarView` | `Views` | `SwiftCode` |
| `SwiftCode/Views/Collaboration/ActivityLogView.swift` | `ActivityLogView` | `Collaboration` | `Views` |
| `SwiftCode/Views/Collaboration/BranchGraphView.swift` | `BranchGraphView` | `Collaboration` | `Views` |
| `SwiftCode/Views/Collaboration/BranchWorkspaceView.swift` | `BranchWorkspaceView` | `Collaboration` | `Views` |
| `SwiftCode/Views/Collaboration/CollaborationAuditLogView.swift` | `CollaborationAuditLogView` | `Collaboration` | `Views` |
| `SwiftCode/Views/Collaboration/CollaborationAuditLogView.swift` | `ActivityEntryRow` | `Collaboration` | `Views` |
| `SwiftCode/Views/Collaboration/CollaborationBranchGraphView.swift` | `CollaborationBranchGraphView` | `Collaboration` | `Views` |
| `SwiftCode/Views/Collaboration/CollaborationBranchGraphView.swift` | `BranchLine` | `Collaboration` | `Views` |
| `SwiftCode/Views/Collaboration/CollaborationBranchGraphView.swift` | `CommitNode` | `Collaboration` | `Views` |
| `SwiftCode/Views/Collaboration/CollaborationBranchManagementView.swift` | `CollaborationBranchManagementView` | `Collaboration` | `Views` |
| `SwiftCode/Views/Collaboration/CollaborationChatView.swift` | `CollaborationChatView` | `Collaboration` | `Views` |
| `SwiftCode/Views/Collaboration/CollaborationChatView.swift` | `ChannelTab` | `Collaboration` | `Views` |
| `SwiftCode/Views/Collaboration/CollaborationChatView.swift` | `ChatRow` | `Collaboration` | `Views` |
| `SwiftCode/Views/Collaboration/CollaborationCodeReviewView.swift` | `CollaborationCodeReviewView` | `Collaboration` | `Views` |
| `SwiftCode/Views/Collaboration/CollaborationCommitHistoryView.swift` | `CollaborationCommitHistoryView` | `Collaboration` | `Views` |
| `SwiftCode/Views/Collaboration/CollaborationConflictResolverView.swift` | `CollaborationConflictResolverView` | `Collaboration` | `Views` |
| `SwiftCode/Views/Collaboration/CollaborationDashboardView.swift` | `CollaborationDashboardView` | `Collaboration` | `Views` |
| `SwiftCode/Views/Collaboration/CollaborationDashboardView.swift` | `StatCard` | `Collaboration` | `Views` |
| `SwiftCode/Views/Collaboration/CollaborationDashboardView.swift` | `ActivityRow` | `Collaboration` | `Views` |
| `SwiftCode/Views/Collaboration/CollaborationDashboardView.swift` | `CollaboratorMiniCard` | `Collaboration` | `Views` |
| `SwiftCode/Views/Collaboration/CollaborationDiffViewerView.swift` | `CollaborationDiffViewerView` | `Collaboration` | `Views` |
| `SwiftCode/Views/Collaboration/CollaborationDiffViewerView.swift` | `DiffViewerTestView` | `Collaboration` | `Views` |
| `SwiftCode/Views/Collaboration/CollaborationFeedbackView.swift` | `CollaborationFeedbackView` | `Collaboration` | `Views` |
| `SwiftCode/Views/Collaboration/CollaborationFilePresenceOverlay.swift` | `CollaborationFilePresenceOverlay` | `Collaboration` | `Views` |
| `SwiftCode/Views/Collaboration/CollaborationFilePresenceOverlay.swift` | `CollaboratorAvatar` | `Collaboration` | `Views` |
| `SwiftCode/Views/Collaboration/CollaborationMainView.swift` | `CollaborationMainView` | `Collaboration` | `Views` |
| `SwiftCode/Views/Collaboration/CollaborationNotificationCenterView.swift` | `CollaborationNotificationCenterView` | `Collaboration` | `Views` |
| `SwiftCode/Views/Collaboration/CollaborationNotificationCenterView.swift` | `NotificationRow` | `Collaboration` | `Views` |
| `SwiftCode/Views/Collaboration/CollaborationPullRequestView.swift` | `CollaborationPullRequestView` | `Collaboration` | `Views` |
| `SwiftCode/Views/Collaboration/CollaborationPullRequestView.swift` | `MultipleSelectionRow` | `Collaboration` | `Views` |
| `SwiftCode/Views/Collaboration/CollaborationSidebarView.swift` | `CollaborationSidebarView` | `Collaboration` | `Views` |
| `SwiftCode/Views/Collaboration/CollaborationSidebarView.swift` | `SidebarItem` | `Collaboration` | `Views` |
| `SwiftCode/Views/Collaboration/CommitManagerView.swift` | `CommitManagerView` | `Collaboration` | `Views` |
| `SwiftCode/Views/Collaboration/CommitManagerView.swift` | `WorkingChangeRow` | `Collaboration` | `Views` |
| `SwiftCode/Views/Collaboration/ConflictResolverView.swift` | `ConflictResolverView` | `Collaboration` | `Views` |
| `SwiftCode/Views/Collaboration/FilePermissionView.swift` | `FilePermissionView` | `Collaboration` | `Views` |
| `SwiftCode/Views/Collaboration/InviteMembersView.swift` | `InviteMembersView` | `Collaboration` | `Views` |
| `SwiftCode/Views/Collaboration/MemberManagementView.swift` | `MemberManagementView` | `Collaboration` | `Views` |
| `SwiftCode/Views/Collaboration/PRCreateView.swift` | `PRCreateView` | `Collaboration` | `Views` |
| `SwiftCode/Views/Collaboration/PRCreateView.swift` | `PRCommitSelectionRow` | `Collaboration` | `Views` |
| `SwiftCode/Views/Collaboration/PushPullManagerView.swift` | `PushPullManagerView` | `Collaboration` | `Views` |
| `SwiftCode/Views/Collaboration/PushPullView.swift` | `PushPullView` | `Collaboration` | `Views` |
| `SwiftCode/Views/CommandPalette/CommandPaletteView.swift` | `CommandPaletteView` | `CommandPalette` | `Views` |
| `SwiftCode/Views/Dashboard/FolderCardView.swift` | `FolderCardView` | `Dashboard` | `Views` |
| `SwiftCode/Views/Dashboard/FolderCreateView.swift` | `FolderCreateView` | `Dashboard` | `Views` |
| `SwiftCode/Views/Dashboard/FoldersView.swift` | `FoldersView` | `Dashboard` | `Views` |
| `SwiftCode/Views/Dashboard/GitHubRemoteSetupView.swift` | `GitHubRemoteSetupView` | `Dashboard` | `Views` |
| `SwiftCode/Views/DebugConsoleView.swift` | `DebugConsoleView` | `Views` | `SwiftCode` |
| `SwiftCode/Views/Dependencies/DependencyManagerView.swift` | `DependencyManagerView` | `Dependencies` | `Views` |
| `SwiftCode/Views/Deployments/DeploymentLogsView.swift` | `DeploymentLogsView` | `Deployments` | `Views` |
| `SwiftCode/Views/Deployments/DeploymentLogsView.swift` | `AnalysisResultView` | `Deployments` | `Views` |
| `SwiftCode/Views/Deployments/DeploymentsView.swift` | `DeploymentsView` | `Deployments` | `Views` |
| `SwiftCode/Views/Dev Tools/APITesterView.swift` | `APITesterView` | `Dev Tools` | `Views` |
| `SwiftCode/Views/Dev Tools/ASCIIArtGeneratorView.swift` | `ASCIIArtGeneratorView` | `Dev Tools` | `Views` |
| `SwiftCode/Views/Dev Tools/AspectRatioCalculatorView.swift` | `AspectRatioCalculatorView` | `Dev Tools` | `Views` |
| `SwiftCode/Views/Dev Tools/Base64ConverterView.swift` | `Base64ConverterView` | `Dev Tools` | `Views` |
| `SwiftCode/Views/Dev Tools/Base64FileConverterView.swift` | `Base64FileConverterView` | `Dev Tools` | `Views` |
| `SwiftCode/Views/Dev Tools/BcryptHashGeneratorView.swift` | `BcryptHashGeneratorView` | `Dev Tools` | `Views` |
| `SwiftCode/Views/Dev Tools/BinaryConverterView.swift` | `BinaryConverterView` | `Dev Tools` | `Views` |
| `SwiftCode/Views/Dev Tools/CSSBorderRadiusGeneratorView.swift` | `CSSBorderRadiusGeneratorView` | `Dev Tools` | `Views` |
| `SwiftCode/Views/Dev Tools/CSSMinifierView.swift` | `CSSMinifierView` | `Dev Tools` | `Views` |
| `SwiftCode/Views/Dev Tools/CSSShadowGeneratorView.swift` | `CSSShadowGeneratorView` | `Dev Tools` | `Views` |
| `SwiftCode/Views/Dev Tools/CSSUnitConverterView.swift` | `CSSUnitConverterView` | `Dev Tools` | `Views` |
| `SwiftCode/Views/Dev Tools/CSSUnitConverterView.swift` | `UnitRow` | `Dev Tools` | `Views` |
| `SwiftCode/Views/Dev Tools/CSVToJSONView.swift` | `CSVToJSONView` | `Dev Tools` | `Views` |
| `SwiftCode/Views/Dev Tools/CaseConverterView.swift` | `CaseConverterView` | `Dev Tools` | `Views` |
| `SwiftCode/Views/Dev Tools/CertificateDecoderView.swift` | `CertificateDecoderView` | `Dev Tools` | `Views` |
| `SwiftCode/Views/Dev Tools/ColorConverterView.swift` | `ColorConverterView` | `Dev Tools` | `Views` |
| `SwiftCode/Views/Dev Tools/ColorConverterView.swift` | `ColorRow` | `Dev Tools` | `Views` |
| `SwiftCode/Views/Dev Tools/ColorGradientGeneratorView.swift` | `ColorGradientGeneratorView` | `Dev Tools` | `Views` |
| `SwiftCode/Views/Dev Tools/CookieParserView.swift` | `CookieParserView` | `Dev Tools` | `Views` |
| `SwiftCode/Views/Dev Tools/CronGeneratorView.swift` | `CronGeneratorView` | `Dev Tools` | `Views` |
| `SwiftCode/Views/Dev Tools/CronParserView.swift` | `CronParserView` | `Dev Tools` | `Views` |
| `SwiftCode/Views/Dev Tools/DNSLookupView.swift` | `DNSLookupView` | `Dev Tools` | `Views` |
| `SwiftCode/Views/Dev Tools/DevToolsMainView.swift` | `DevToolsMainView` | `Dev Tools` | `Views` |
| `SwiftCode/Views/Dev Tools/DeviceInfoView.swift` | `DeviceInfoView` | `Dev Tools` | `Views` |
| `SwiftCode/Views/Dev Tools/DeviceInfoView.swift` | `InfoRow` | `Dev Tools` | `Views` |
| `SwiftCode/Views/Dev Tools/DiffCheckerView.swift` | `DiffCheckerView` | `Dev Tools` | `Views` |
| `SwiftCode/Views/Dev Tools/GitCheatsheetView.swift` | `GitCheatsheetView` | `Dev Tools` | `Views` |
| `SwiftCode/Views/Dev Tools/GzipCompressorView.swift` | `GzipCompressorView` | `Dev Tools` | `Views` |
| `SwiftCode/Views/Dev Tools/HMACGeneratorView.swift` | `HMACGeneratorView` | `Dev Tools` | `Views` |
| `SwiftCode/Views/Dev Tools/HTMLEntityConverterView.swift` | `HTMLEntityConverterView` | `Dev Tools` | `Views` |
| `SwiftCode/Views/Dev Tools/HTMLMinifierView.swift` | `HTMLMinifierView` | `Dev Tools` | `Views` |
| `SwiftCode/Views/Dev Tools/HTTPHeaderParserView.swift` | `HTTPHeaderParserView` | `Dev Tools` | `Views` |
| `SwiftCode/Views/Dev Tools/HTTPStatusView.swift` | `HTTPStatusView` | `Dev Tools` | `Views` |
| `SwiftCode/Views/Dev Tools/HashGeneratorView.swift` | `HashGeneratorView` | `Dev Tools` | `Views` |
| `SwiftCode/Views/Dev Tools/HashGeneratorView.swift` | `HashResultRow` | `Dev Tools` | `Views` |
| `SwiftCode/Views/Dev Tools/HexDecimalConverterView.swift` | `HexDecimalConverterView` | `Dev Tools` | `Views` |
| `SwiftCode/Views/Dev Tools/IPAddressInfoView.swift` | `IPAddressInfoView` | `Dev Tools` | `Views` |
| `SwiftCode/Views/Dev Tools/ImageBase64View.swift` | `ImageBase64View` | `Dev Tools` | `Views` |
| `SwiftCode/Views/Dev Tools/JSMinifierView.swift` | `JSMinifierView` | `Dev Tools` | `Views` |
| `SwiftCode/Views/Dev Tools/JSONFormatterView.swift` | `JSONFormatterView` | `Dev Tools` | `Views` |
| `SwiftCode/Views/Dev Tools/JSONSchemaGeneratorView.swift` | `JSONSchemaGeneratorView` | `Dev Tools` | `Views` |
| `SwiftCode/Views/Dev Tools/JSONToCSVView.swift` | `JSONToCSVView` | `Dev Tools` | `Views` |
| `SwiftCode/Views/Dev Tools/JSONToCSharpView.swift` | `JSONToCSharpView` | `Dev Tools` | `Views` |
| `SwiftCode/Views/Dev Tools/JSONToDartView.swift` | `JSONToDartView` | `Dev Tools` | `Views` |
| `SwiftCode/Views/Dev Tools/JSONToGoView.swift` | `JSONToGoView` | `Dev Tools` | `Views` |
| `SwiftCode/Views/Dev Tools/JSONToJavaView.swift` | `JSONToJavaView` | `Dev Tools` | `Views` |
| `SwiftCode/Views/Dev Tools/JSONToKotlinView.swift` | `JSONToKotlinView` | `Dev Tools` | `Views` |
| `SwiftCode/Views/Dev Tools/JSONToPHPView.swift` | `JSONToPHPView` | `Dev Tools` | `Views` |
| `SwiftCode/Views/Dev Tools/JSONToPythonView.swift` | `JSONToPythonView` | `Dev Tools` | `Views` |
| `SwiftCode/Views/Dev Tools/JSONToRustView.swift` | `JSONToRustView` | `Dev Tools` | `Views` |
| `SwiftCode/Views/Dev Tools/JSONToSwiftView.swift` | `JSONToSwiftView` | `Dev Tools` | `Views` |
| `SwiftCode/Views/Dev Tools/JSONToTOMLView.swift` | `JSONToTOMLView` | `Dev Tools` | `Views` |
| `SwiftCode/Views/Dev Tools/JSONToTSView.swift` | `JSONToTSView` | `Dev Tools` | `Views` |
| `SwiftCode/Views/Dev Tools/JWTDecoderView.swift` | `JWTDecoderView` | `Dev Tools` | `Views` |
| `SwiftCode/Views/Dev Tools/LengthConverterView.swift` | `LengthConverterView` | `Dev Tools` | `Views` |
| `SwiftCode/Views/Dev Tools/LoremIpsumGeneratorView.swift` | `LoremIpsumGeneratorView` | `Dev Tools` | `Views` |
| `SwiftCode/Views/Dev Tools/MACAddressGeneratorView.swift` | `MACAddressGeneratorView` | `Dev Tools` | `Views` |
| `SwiftCode/Views/Dev Tools/MIMETypeLookupView.swift` | `MIMETypeLookupView` | `Dev Tools` | `Views` |
| `SwiftCode/Views/Dev Tools/MarkdownPreviewerView.swift` | `MarkdownPreviewerView` | `Dev Tools` | `Views` |
| `SwiftCode/Views/Dev Tools/PasswordGeneratorView.swift` | `PasswordGeneratorView` | `Dev Tools` | `Views` |
| `SwiftCode/Views/Dev Tools/PasswordStrengthMeterView.swift` | `PasswordStrengthMeterView` | `Dev Tools` | `Views` |
| `SwiftCode/Views/Dev Tools/PasswordStrengthMeterView.swift` | `StrengthCriteriaRow` | `Dev Tools` | `Views` |
| `SwiftCode/Views/Dev Tools/PercentageCalculatorView.swift` | `PercentageCalculatorView` | `Dev Tools` | `Views` |
| `SwiftCode/Views/Dev Tools/PortLookupView.swift` | `PortLookupView` | `Dev Tools` | `Views` |
| `SwiftCode/Views/Dev Tools/PortScannerView.swift` | `PortScannerView` | `Dev Tools` | `Views` |
| `SwiftCode/Views/Dev Tools/QRCodeGeneratorView.swift` | `QRCodeGeneratorView` | `Dev Tools` | `Views` |
| `SwiftCode/Views/Dev Tools/RSAKeyGeneratorView.swift` | `RSAKeyGeneratorView` | `Dev Tools` | `Views` |
| `SwiftCode/Views/Dev Tools/RandomStringGeneratorView.swift` | `RandomStringGeneratorView` | `Dev Tools` | `Views` |
| `SwiftCode/Views/Dev Tools/RegexTesterView.swift` | `RegexTesterView` | `Dev Tools` | `Views` |
| `SwiftCode/Views/Dev Tools/SQLFormatterView.swift` | `SQLFormatterView` | `Dev Tools` | `Views` |
| `SwiftCode/Views/Dev Tools/SSLCheckerView.swift` | `SSLCheckerView` | `Dev Tools` | `Views` |
| `SwiftCode/Views/Dev Tools/SVGMinifierView.swift` | `SVGMinifierView` | `Dev Tools` | `Views` |
| `SwiftCode/Views/Dev Tools/SemVerCheckerView.swift` | `SemVerCheckerView` | `Dev Tools` | `Views` |
| `SwiftCode/Views/Dev Tools/StringEscaperView.swift` | `StringEscaperView` | `Dev Tools` | `Views` |
| `SwiftCode/Views/Dev Tools/StringLengthCounterView.swift` | `StringLengthCounterView` | `Dev Tools` | `Views` |
| `SwiftCode/Views/Dev Tools/StringLengthCounterView.swift` | `StringLengthStatCard` | `Dev Tools` | `Views` |
| `SwiftCode/Views/Dev Tools/SubnetCalculatorView.swift` | `SubnetCalculatorView` | `Dev Tools` | `Views` |
| `SwiftCode/Views/Dev Tools/TOMLToJSONView.swift` | `TOMLToJSONView` | `Dev Tools` | `Views` |
| `SwiftCode/Views/Dev Tools/TemperatureConverterView.swift` | `TemperatureConverterView` | `Dev Tools` | `Views` |
| `SwiftCode/Views/Dev Tools/TextCaseSwapperView.swift` | `TextCaseSwapperView` | `Dev Tools` | `Views` |
| `SwiftCode/Views/Dev Tools/TextCounterView.swift` | `TextCounterView` | `Dev Tools` | `Views` |
| `SwiftCode/Views/Dev Tools/TextCounterView.swift` | `StatView` | `Dev Tools` | `Views` |
| `SwiftCode/Views/Dev Tools/TextDeduplicatorView.swift` | `TextDeduplicatorView` | `Dev Tools` | `Views` |
| `SwiftCode/Views/Dev Tools/TextLineRemoverView.swift` | `TextLineRemoverView` | `Dev Tools` | `Views` |
| `SwiftCode/Views/Dev Tools/TimestampConverterView.swift` | `TimestampConverterView` | `Dev Tools` | `Views` |
| `SwiftCode/Views/Dev Tools/TimezoneConverterView.swift` | `TimezoneConverterView` | `Dev Tools` | `Views` |
| `SwiftCode/Views/Dev Tools/URLDecomposerView.swift` | `URLDecomposerView` | `Dev Tools` | `Views` |
| `SwiftCode/Views/Dev Tools/URLEncoderView.swift` | `URLEncoderView` | `Dev Tools` | `Views` |
| `SwiftCode/Views/Dev Tools/URLSlugGeneratorView.swift` | `URLSlugGeneratorView` | `Dev Tools` | `Views` |
| `SwiftCode/Views/Dev Tools/UUIDGeneratorView.swift` | `UUIDGeneratorView` | `Dev Tools` | `Views` |
| `SwiftCode/Views/Dev Tools/UserAgentParserView.swift` | `UserAgentParserView` | `Dev Tools` | `Views` |
| `SwiftCode/Views/Dev Tools/WebhookTesterView.swift` | `WebhookTesterView` | `Dev Tools` | `Views` |
| `SwiftCode/Views/Dev Tools/WeightConverterView.swift` | `WeightConverterView` | `Dev Tools` | `Views` |
| `SwiftCode/Views/Dev Tools/WhoisLookupView.swift` | `WhoisLookupView` | `Dev Tools` | `Views` |
| `SwiftCode/Views/Dev Tools/XMLFormatterView.swift` | `XMLFormatterView` | `Dev Tools` | `Views` |
| `SwiftCode/Views/Dev Tools/XMLToJSONView.swift` | `XMLToJSONView` | `Dev Tools` | `Views` |
| `SwiftCode/Views/Dev Tools/YAMLConverterView.swift` | `YAMLConverterView` | `Dev Tools` | `Views` |
| `SwiftCode/Views/Dev Tools/YAMLToJSONView.swift` | `YAMLToJSONView` | `Dev Tools` | `Views` |
| `SwiftCode/Views/Developer/AIModelDebugger/AIModelDebuggerView.swift` | `AIModelDebuggerView` | `AIModelDebugger` | `Developer` |
| `SwiftCode/Views/Developer/APIInspector/APIInspectorView.swift` | `APIInspectorView` | `APIInspector` | `Developer` |
| `SwiftCode/Views/Developer/APILatencyTrackerView.swift` | `APILatencyTrackerView` | `Developer` | `Views` |
| `SwiftCode/Views/Developer/BackgroundTaskMonitorView.swift` | `BackgroundTaskMonitorView` | `Developer` | `Views` |
| `SwiftCode/Views/Developer/BinaryTools/BinaryToolsViews.swift` | `BinaryToolsViews` | `BinaryTools` | `Developer` |
| `SwiftCode/Views/Developer/BuildDiagnosticsView.swift` | `BuildDiagnosticsView` | `Developer` | `Views` |
| `SwiftCode/Views/Developer/BuildPipelineDebugger/BuildPipelineDebuggerView.swift` | `BuildPipelineDebuggerView` | `BuildPipelineDebugger` | `Developer` |
| `SwiftCode/Views/Developer/CacheInspectorView.swift` | `CacheInspectorView` | `Developer` | `Views` |
| `SwiftCode/Views/Developer/ConsoleCommandRunnerView.swift` | `ConsoleCommandRunnerView` | `Developer` | `Views` |
| `SwiftCode/Views/Developer/CoreMLInspector/CoreMLInspectorView.swift` | `CoreMLInspectorView` | `CoreMLInspector` | `Developer` |
| `SwiftCode/Views/Developer/CrashDebugger/CrashDebuggerView.swift` | `CrashDebuggerView` | `CrashDebugger` | `Developer` |
| `SwiftCode/Views/Developer/DatabaseInspector/DatabaseInspectorView.swift` | `DatabaseInspectorView` | `DatabaseInspector` | `Developer` |
| `SwiftCode/Views/Developer/DatabaseInspectorView.swift` | `DatabaseInspectorView` | `Developer` | `Views` |
| `SwiftCode/Views/Developer/DebugOverlaysView.swift` | `DebugOverlaysView` | `Developer` | `Views` |
| `SwiftCode/Views/Developer/DependencyHealthView.swift` | `DependencyHealthView` | `Developer` | `Views` |
| `SwiftCode/Views/Developer/DeploymentDebug/DeploymentDebugView.swift` | `DeploymentDebugView` | `DeploymentDebug` | `Developer` |
| `SwiftCode/Views/Developer/DeveloperDashboard/DeveloperDashboardView.swift` | `DeveloperDashboardView` | `DeveloperDashboard` | `Developer` |
| `SwiftCode/Views/Developer/EnvironmentSwitcherView.swift` | `EnvironmentSwitcherView` | `Developer` | `Views` |
| `SwiftCode/Views/Developer/ErrorFrequencyTrackerView.swift` | `ErrorFrequencyTrackerView` | `Developer` | `Views` |
| `SwiftCode/Views/Developer/ExtensionDebugger/ExtensionDebuggerView.swift` | `ExtensionDebuggerView` | `ExtensionDebugger` | `Developer` |
| `SwiftCode/Views/Developer/FeatureFlags/FeatureFlagsView.swift` | `FeatureFlagsView` | `FeatureFlags` | `Developer` |
| `SwiftCode/Views/Developer/FileSystemInspector/FileSystemInspectorView.swift` | `FileSystemInspectorView` | `FileSystemInspector` | `Developer` |
| `SwiftCode/Views/Developer/GitHubAPIDebug/GitHubAPIDebugView.swift` | `GitHubAPIDebugView` | `GitHubAPIDebug` | `Developer` |
| `SwiftCode/Views/Developer/LogConsole/LogConsoleView.swift` | `LogConsoleView` | `LogConsole` | `Developer` |
| `SwiftCode/Views/Developer/MemoryInspector/MemoryInspectorView.swift` | `MemoryInspectorView` | `MemoryInspector` | `Developer` |
| `SwiftCode/Views/Developer/MemoryLeakDetectionView.swift` | `MemoryLeakDetectionView` | `Developer` | `Views` |
| `SwiftCode/Views/Developer/NetworkInspector/NetworkInspectorView.swift` | `NetworkInspectorView` | `NetworkInspector` | `Developer` |
| `SwiftCode/Views/Developer/PaywallDebug/PaywallDebugView.swift` | `PaywallDebugView` | `PaywallDebug` | `Developer` |
| `SwiftCode/Views/Developer/PerformanceMonitor/PerformanceMonitorView.swift` | `PerformanceMonitorView` | `PerformanceMonitor` | `Developer` |
| `SwiftCode/Views/Developer/PerformanceMonitor/PerformanceMonitorView.swift` | `PerformanceChart` | `PerformanceMonitor` | `Developer` |
| `SwiftCode/Views/Developer/PermissionsCheckerView.swift` | `PermissionsCheckerView` | `Developer` | `Views` |
| `SwiftCode/Views/Developer/RealtimeMetricsDashboardView.swift` | `RealtimeMetricsDashboardView` | `Developer` | `Views` |
| `SwiftCode/Views/Developer/RealtimeMetricsDashboardView.swift` | `MetricTile` | `Developer` | `Views` |
| `SwiftCode/Views/Developer/RuntimeFlags/RuntimeFlagsView.swift` | `RuntimeFlagsView` | `RuntimeFlags` | `Developer` |
| `SwiftCode/Views/Developer/StateInspectorView.swift` | `StateInspectorView` | `Developer` | `Views` |
| `SwiftCode/Views/Developer/StateInspectorView.swift` | `StateNodeView` | `Developer` | `Views` |
| `SwiftCode/Views/Developer/StoreKitDebug/StoreKitDebugView.swift` | `StoreKitDebugView` | `StoreKitDebug` | `Developer` |
| `SwiftCode/Views/Developer/ThreadInspector/ThreadInspectorView.swift` | `ThreadInspectorView` | `ThreadInspector` | `Developer` |
| `SwiftCode/Views/Developer/VerboseLogging/VerboseLoggingView.swift` | `VerboseLoggingView` | `VerboseLogging` | `Developer` |
| `SwiftCode/Views/Developer/WebViewDebugger/WebViewDebuggerView.swift` | `WebViewDebuggerView` | `WebViewDebugger` | `Developer` |
| `SwiftCode/Views/DiffViewer/DiffViewerView.swift` | `DiffViewerView` | `DiffViewer` | `Views` |
| `SwiftCode/Views/Editor/CodeEditorManagementView.swift` | `CodeEditorManagementView` | `Editor` | `Views` |
| `SwiftCode/Views/Editor/CodeEditorView.swift` | `CodeEditorView` | `Editor` | `Views` |
| `SwiftCode/Views/Editor/CodeEditorView.swift` | `MinimapView` | `Editor` | `Views` |
| `SwiftCode/Views/Editor/EditorLogicFrameworks/AISuggestionEngine.swift` | `AISuggestionEngine` | `EditorLogicFrameworks` | `Editor` |
| `SwiftCode/Views/Editor/EditorLogicFrameworks/CodeColoringTheme.swift` | `CodeColoringTheme` | `EditorLogicFrameworks` | `Editor` |
| `SwiftCode/Views/Editor/EditorLogicFrameworks/CodeExecutionManager.swift` | `CodeExecutionManager` | `EditorLogicFrameworks` | `Editor` |
| `SwiftCode/Views/Editor/EditorLogicFrameworks/CodeStructureAnalyzer.swift` | `CodeStructureAnalyzer` | `EditorLogicFrameworks` | `Editor` |
| `SwiftCode/Views/Editor/EditorLogicFrameworks/TextLayoutEngine.swift` | `TextLayoutEngine` | `EditorLogicFrameworks` | `Editor` |
| `SwiftCode/Views/Editor/GoToLineView.swift` | `GoToLineView` | `Editor` | `Views` |
| `SwiftCode/Views/Editor/MinimapSettingsView.swift` | `MinimapSettingsView` | `Editor` | `Views` |
| `SwiftCode/Views/Editor/SymbolNavigatorView.swift` | `SymbolNavigatorView` | `Editor` | `Views` |
| `SwiftCode/Views/Editor/SymbolOutlineView.swift` | `SymbolOutlineView` | `Editor` | `Views` |
| `SwiftCode/Views/EditorGutterView.swift` | `EditorGutterView` | `Views` | `SwiftCode` |
| `SwiftCode/Views/EditorTabBarView.swift` | `EditorTabBarView` | `Views` | `SwiftCode` |
| `SwiftCode/Views/EditorTextView.swift` | `EditorTextView` | `Views` | `SwiftCode` |
| `SwiftCode/Views/EditorView.swift` | `EditorView` | `Views` | `SwiftCode` |
| `SwiftCode/Views/Errors/ErrorsPanelView.swift` | `ErrorsPanelView` | `Errors` | `Views` |
| `SwiftCode/Views/ExportProjView.swift` | `ExportProjView` | `Views` | `SwiftCode` |
| `SwiftCode/Views/ExtensionsView.swift` | `ExtensionsView` | `Views` | `SwiftCode` |
| `SwiftCode/Views/ExtensionsView.swift` | `ExtensionDemoView` | `Views` | `SwiftCode` |
| `SwiftCode/Views/ExtensionsView.swift` | `ExtensionRow` | `Views` | `SwiftCode` |
| `SwiftCode/Views/Gists/Components/GistCommentSectionView.swift` | `GistCommentSectionView` | `Components` | `Gists` |
| `SwiftCode/Views/Gists/Components/GistFileEditorView.swift` | `GistFileEditorView` | `Components` | `Gists` |
| `SwiftCode/Views/Gists/Components/GistFileTabBar.swift` | `GistFileTabBar` | `Components` | `Gists` |
| `SwiftCode/Views/Gists/Components/GistRowView.swift` | `GistRowView` | `Components` | `Gists` |
| `SwiftCode/Views/Gists/Components/MarkdownToolbar.swift` | `MarkdownToolbar` | `Components` | `Gists` |
| `SwiftCode/Views/Gists/CreateGistView.swift` | `CreateGistView` | `Gists` | `Views` |
| `SwiftCode/Views/Gists/GistDetailView.swift` | `GistDetailView` | `Gists` | `Views` |
| `SwiftCode/Views/Gists/GistDiffView.swift` | `GistDiffView` | `Gists` | `Views` |
| `SwiftCode/Views/Gists/GistRevisionsView.swift` | `GistRevisionsView` | `Gists` | `Views` |
| `SwiftCode/Views/Gists/GistsView.swift` | `GistsView` | `Gists` | `Views` |
| `SwiftCode/Views/GitHub/BranchManagementView.swift` | `BranchManagementView` | `GitHub` | `Views` |
| `SwiftCode/Views/GitHub/BranchManagementView.swift` | `BranchManagementRow` | `GitHub` | `Views` |
| `SwiftCode/Views/GitHub/CommitHistoryView.swift` | `CommitHistoryView` | `GitHub` | `Views` |
| `SwiftCode/Views/GitHub/CommitHistoryView.swift` | `CommitDetailView` | `GitHub` | `Views` |
| `SwiftCode/Views/GitHub/GitBranchesView.swift` | `GitBranchesView` | `GitHub` | `Views` |
| `SwiftCode/Views/GitHub/GitCLIView.swift` | `GitCLIView` | `GitHub` | `Views` |
| `SwiftCode/Views/GitHub/GitChangesView.swift` | `GitChangesView` | `GitHub` | `Views` |
| `SwiftCode/Views/GitHub/GitCloneSheetView.swift` | `GitCloneSheetView` | `GitHub` | `Views` |
| `SwiftCode/Views/GitHub/GitCommandView.swift` | `GitCommandView` | `GitHub` | `Views` |
| `SwiftCode/Views/GitHub/GitCommandView.swift` | `GitCommandRow` | `GitHub` | `Views` |
| `SwiftCode/Views/GitHub/GitCommitComposerView.swift` | `GitCommitComposerView` | `GitHub` | `Views` |
| `SwiftCode/Views/GitHub/GitConflictBannerView.swift` | `GitConflictBannerView` | `GitHub` | `Views` |
| `SwiftCode/Views/GitHub/GitDiffView.swift` | `GitDiffView` | `GitHub` | `Views` |
| `SwiftCode/Views/GitHub/GitFileRowView.swift` | `GitFileRowView` | `GitHub` | `Views` |
| `SwiftCode/Views/GitHub/GitHistoryView.swift` | `GitHistoryView` | `GitHub` | `Views` |
| `SwiftCode/Views/GitHub/GitHubCodeSearchView.swift` | `GitHubCodeSearchView` | `GitHub` | `Views` |
| `SwiftCode/Views/GitHub/GitHubIntegrationView.swift` | `GitHubIntegrationView` | `GitHub` | `Views` |
| `SwiftCode/Views/GitHub/GitHubIntegrationView.swift` | `BranchRow` | `GitHub` | `Views` |
| `SwiftCode/Views/GitHub/GitHubIntegrationView.swift` | `WorkflowRunRow` | `GitHub` | `Views` |
| `SwiftCode/Views/GitHub/GitHubIssuesView.swift` | `GitHubIssuesView` | `GitHub` | `Views` |
| `SwiftCode/Views/GitHub/GitHubIssuesView.swift` | `IssueDetailView` | `GitHub` | `Views` |
| `SwiftCode/Views/GitHub/GitNotInstalledView.swift` | `GitNotInstalledView` | `GitHub` | `Views` |
| `SwiftCode/Views/GitHub/GitPanelView.swift` | `GitPanelView` | `GitHub` | `Views` |
| `SwiftCode/Views/GitHub/LicencesAddView.swift` | `LicencesAddView` | `GitHub` | `Views` |
| `SwiftCode/Views/GitHub/PullRequestView.swift` | `PullRequestView` | `GitHub` | `Views` |
| `SwiftCode/Views/GitHub/SCSetupOnboard.swift` | `SCSetupOnboard` | `GitHub` | `Views` |
| `SwiftCode/Views/GitHub/SourceControlView.swift` | `SourceControlView` | `GitHub` | `Views` |
| `SwiftCode/Views/HomeProjectGridView.swift` | `HomeProjectGridView` | `Views` | `SwiftCode` |
| `SwiftCode/Views/HomeView.swift` | `HomeView` | `Views` | `SwiftCode` |
| `SwiftCode/Views/HomeView.swift` | `QuickStartRow` | `Views` | `SwiftCode` |
| `SwiftCode/Views/HomeView.swift` | `HomeProjectCardView` | `Views` | `SwiftCode` |
| `SwiftCode/Views/ImportProjView.swift` | `ImportProjView` | `Views` | `SwiftCode` |
| `SwiftCode/Views/InfoProjView.swift` | `InfoProjView` | `Views` | `SwiftCode` |
| `SwiftCode/Views/IssueNavigatorView.swift` | `IssueNavigatorView` | `Views` | `SwiftCode` |
| `SwiftCode/Views/NativeTextView.swift` | `NativeTextView` | `Views` | `SwiftCode` |
| `SwiftCode/Views/Navigator/FileNavigatorView.swift` | `FileNavigatorView` | `Navigator` | `Views` |
| `SwiftCode/Views/Navigator/FileNavigatorView.swift` | `FileNodeRowView` | `Navigator` | `Views` |
| `SwiftCode/Views/NewProjectSheetView.swift` | `NewProjectSheetView` | `Views` | `SwiftCode` |
| `SwiftCode/Views/Onboarding/OnboardingFeaturesView.swift` | `OnboardingFeaturesView` | `Onboarding` | `Views` |
| `SwiftCode/Views/Onboarding/OnboardingSplashView.swift` | `OnboardingSplashView` | `Onboarding` | `Views` |
| `SwiftCode/Views/Onboarding/OnboardingView.swift` | `OnboardingView` | `Onboarding` | `Views` |
| `SwiftCode/Views/Onboarding/OnboardingWelcomeView.swift` | `OnboardingWelcomeView` | `Onboarding` | `Views` |
| `SwiftCode/Views/Paywall/PaywallView.swift` | `PaywallView` | `Paywall` | `Views` |
| `SwiftCode/Views/ProjectNavigatorView.swift` | `ProjectNavigatorView` | `Views` | `SwiftCode` |
| `SwiftCode/Views/ProjectTreeRowView.swift` | `ProjectTreeRowView` | `Views` | `SwiftCode` |
| `SwiftCode/Views/Search/CodeSearchView.swift` | `CodeSearchView` | `Search` | `Views` |
| `SwiftCode/Views/SectionView.swift` | `SectionView` | `Views` | `SwiftCode` |
| `SwiftCode/Views/Settings/AssistSettingsView.swift` | `AssistSettingsView` | `Settings` | `Views` |
| `SwiftCode/Views/Settings/CodeSuggestionsView.swift` | `CodeSuggestionsView` | `Settings` | `Views` |
| `SwiftCode/Views/Settings/CreditsView.swift` | `CreditsView` | `Settings` | `Views` |
| `SwiftCode/Views/Settings/CreditsView.swift` | `GitHubProfileCard` | `Settings` | `Views` |
| `SwiftCode/Views/Settings/Custom Tools/CustomToolBuilderView.swift` | `CustomToolBuilderView` | `Custom Tools` | `Settings` |
| `SwiftCode/Views/Settings/Custom Tools/CustomToolBuilderView.swift` | `ParameterEditorRow` | `Custom Tools` | `Settings` |
| `SwiftCode/Views/Settings/Extension Management/AIDocGenExtensionView.swift` | `AIDocGenExtensionView` | `Extension Management` | `Settings` |
| `SwiftCode/Views/Settings/Extension Management/AIRefactorExtensionView.swift` | `AIRefactorExtensionView` | `Extension Management` | `Settings` |
| `SwiftCode/Views/Settings/Extension Management/CodeStatsExtensionView.swift` | `CodeStatsExtensionView` | `Extension Management` | `Settings` |
| `SwiftCode/Views/Settings/Extension Management/ColorPickerExtensionView.swift` | `ColorPickerExtensionView` | `Extension Management` | `Settings` |
| `SwiftCode/Views/Settings/Extension Management/CreateExtensionView.swift` | `CreateExtensionView` | `Extension Management` | `Settings` |
| `SwiftCode/Views/Settings/Extension Management/DarkProThemeExtensionView.swift` | `DarkProThemeExtensionView` | `Extension Management` | `Settings` |
| `SwiftCode/Views/Settings/Extension Management/DocCGeneratorExtensionView.swift` | `DocCGeneratorExtensionView` | `Extension Management` | `Settings` |
| `SwiftCode/Views/Settings/Extension Management/EditExtensionView.swift` | `EditExtensionView` | `Extension Management` | `Settings` |
| `SwiftCode/Views/Settings/Extension Management/GitBlameExtensionView.swift` | `GitBlameExtensionView` | `Extension Management` | `Settings` |
| `SwiftCode/Views/Settings/Extension Management/GoSupportExtensionView.swift` | `GoSupportExtensionView` | `Extension Management` | `Settings` |
| `SwiftCode/Views/Settings/Extension Management/GruvboxThemeExtensionView.swift` | `GruvboxThemeExtensionView` | `Extension Management` | `Settings` |
| `SwiftCode/Views/Settings/Extension Management/JSONFormatterExtensionView.swift` | `JSONFormatterExtensionView` | `Extension Management` | `Settings` |
| `SwiftCode/Views/Settings/Extension Management/KotlinSupportExtensionView.swift` | `KotlinSupportExtensionView` | `Extension Management` | `Settings` |
| `SwiftCode/Views/Settings/Extension Management/MarkdownPreviewExtensionView.swift` | `MarkdownPreviewExtensionView` | `Extension Management` | `Settings` |
| `SwiftCode/Views/Settings/Extension Management/MultiCursorExtensionView.swift` | `MultiCursorExtensionView` | `Extension Management` | `Settings` |
| `SwiftCode/Views/Settings/Extension Management/NordThemeExtensionView.swift` | `NordThemeExtensionView` | `Extension Management` | `Settings` |
| `SwiftCode/Views/Settings/Extension Management/PythonSupportExtensionView.swift` | `PythonSupportExtensionView` | `Extension Management` | `Settings` |
| `SwiftCode/Views/Settings/Extension Management/RegexTesterExtensionView.swift` | `RegexTesterExtensionView` | `Extension Management` | `Settings` |
| `SwiftCode/Views/Settings/Extension Management/RustSupportExtensionView.swift` | `RustSupportExtensionView` | `Extension Management` | `Settings` |
| `SwiftCode/Views/Settings/Extension Management/SnippetLibraryExtensionView.swift` | `SnippetLibraryExtensionView` | `Extension Management` | `Settings` |
| `SwiftCode/Views/Settings/Extension Management/SwiftFormatterExtensionView.swift` | `SwiftFormatterExtensionView` | `Extension Management` | `Settings` |
| `SwiftCode/Views/Settings/Extension Management/SwiftLintRunnerExtensionView.swift` | `SwiftLintRunnerExtensionView` | `Extension Management` | `Settings` |
| `SwiftCode/Views/Settings/Extension Management/SwiftPackageManagerExtensionView.swift` | `SwiftPackageManagerExtensionView` | `Extension Management` | `Settings` |
| `SwiftCode/Views/Settings/Extension Management/TodoHighlighterExtensionView.swift` | `TodoHighlighterExtensionView` | `Extension Management` | `Settings` |
| `SwiftCode/Views/Settings/Extension Management/TypeScriptSupportExtensionView.swift` | `TypeScriptSupportExtensionView` | `Extension Management` | `Settings` |
| `SwiftCode/Views/Settings/Extension Management/UnitTestGenExtensionView.swift` | `UnitTestGenExtensionView` | `Extension Management` | `Settings` |
| `SwiftCode/Views/Settings/Extension Management/XcodeBuildToolExtensionView.swift` | `XcodeBuildToolExtensionView` | `Extension Management` | `Settings` |
| `SwiftCode/Views/Settings/GeneralSettingsView.swift` | `GeneralSettingsView` | `Settings` | `Views` |
| `SwiftCode/Views/Settings/GeneralSettingsView.swift` | `APIKeysManagementView` | `Settings` | `Views` |
| `SwiftCode/Views/Settings/GeneralSettingsView.swift` | `APIKeysHelpView` | `Settings` | `Views` |
| `SwiftCode/Views/Settings/GeneralSettingsView.swift` | `APIKeyRowView` | `Settings` | `Views` |
| `SwiftCode/Views/Settings/GeneralSettingsView.swift` | `AddEditAPIKeyView` | `Settings` | `Views` |
| `SwiftCode/Views/Settings/GeneralSettingsView.swift` | `ThemeManagementView` | `Settings` | `Views` |
| `SwiftCode/Views/Settings/GeneralSettingsView.swift` | `ThemeRowView` | `Settings` | `Views` |
| `SwiftCode/Views/Settings/GeneralSettingsView.swift` | `CustomThemeEditorView` | `Settings` | `Views` |
| `SwiftCode/Views/Settings/GeneralSettingsView.swift` | `GitHubConfigView` | `Settings` | `Views` |
| `SwiftCode/Views/Settings/GeneralSettingsView.swift` | `AgentConnectionsView` | `Settings` | `Views` |
| `SwiftCode/Views/Settings/GeneralSettingsView.swift` | `CustomToolEditorView` | `Settings` | `Views` |
| `SwiftCode/Views/Settings/GeneralSettingsView.swift` | `CoreMLSettingsView` | `Settings` | `Views` |
| `SwiftCode/Views/Settings/InstalledOfflineModelsView.swift` | `InstalledOfflineModelsView` | `Settings` | `Views` |
| `SwiftCode/Views/Settings/ModelDownloadProgressView.swift` | `ModelDownloadProgressView` | `Settings` | `Views` |
| `SwiftCode/Views/Settings/ModelLinkInstallGuideView.swift` | `ModelLinkInstallGuideView` | `Settings` | `Views` |
| `SwiftCode/Views/Settings/OfflineModelsView.swift` | `OfflineModelsView` | `Settings` | `Views` |
| `SwiftCode/Views/Settings/PluginCodeCreateView.swift` | `PluginCodeCreateView` | `Settings` | `Views` |
| `SwiftCode/Views/Settings/PluginManagerView.swift` | `PluginManagerView` | `Settings` | `Views` |
| `SwiftCode/Views/Settings/PluginManagerView.swift` | `PluginRowView` | `Settings` | `Views` |
| `SwiftCode/Views/Settings/ProjectSettingsView.swift` | `ProjectSettingsView` | `Settings` | `Views` |
| `SwiftCode/Views/Settings/ProjectTemplateView.swift` | `ProjectTemplateView` | `Settings` | `Views` |
| `SwiftCode/Views/Settings/ProjectTemplateView.swift` | `TemplateRowView` | `Settings` | `Views` |
| `SwiftCode/Views/Settings/ProjectTemplateView.swift` | `TemplateDetailView` | `Settings` | `Views` |
| `SwiftCode/Views/Settings/SettingsView.swift` | `SettingsView` | `Settings` | `Views` |
| `SwiftCode/Views/Settings/Skills/SkillsAddView.swift` | `SkillsAddView` | `Skills` | `Settings` |
| `SwiftCode/Views/Settings/Skills/SkillsInfoView.swift` | `SkillsInfoView` | `Skills` | `Settings` |
| `SwiftCode/Views/Settings/Skills/SkillsView.swift` | `SkillsView` | `Skills` | `Settings` |
| `SwiftCode/Views/Settings/UpdatesView.swift` | `UpdatesView` | `Settings` | `Views` |
| `SwiftCode/Views/Sidebar/BookmarksSidebarView.swift` | `BookmarksSidebarView` | `Sidebar` | `Views` |
| `SwiftCode/Views/Sidebar/BreakpointsSidebarView.swift` | `BreakpointsSidebarView` | `Sidebar` | `Views` |
| `SwiftCode/Views/Sidebar/DebugInspectorSidebarView.swift` | `DebugInspectorSidebarView` | `Sidebar` | `Views` |
| `SwiftCode/Views/Sidebar/DebugInspectorSidebarView.swift` | `VariableRow` | `Sidebar` | `Views` |
| `SwiftCode/Views/Sidebar/DebugInspectorSidebarView.swift` | `CallStackRow` | `Sidebar` | `Views` |
| `SwiftCode/Views/Sidebar/DebugSessionsSidebarView.swift` | `DebugSessionsSidebarView` | `Sidebar` | `Views` |
| `SwiftCode/Views/Sidebar/FileNavigatorSidebarView.swift` | `FileNavigatorSidebarView` | `Sidebar` | `Views` |
| `SwiftCode/Views/Sidebar/FileNavigatorSidebarView.swift` | `ProjectTreeNodeView` | `Sidebar` | `Views` |
| `SwiftCode/Views/Sidebar/GitHubWorkflowsSidebarView.swift` | `GitHubWorkflowsSidebarView` | `Sidebar` | `Views` |
| `SwiftCode/Views/Sidebar/GitSidebarView.swift` | `GitSidebarView` | `Sidebar` | `Views` |
| `SwiftCode/Views/Sidebar/SearchSidebarView.swift` | `SearchSidebarView` | `Sidebar` | `Views` |
| `SwiftCode/Views/Sidebar/SidebarMainView.swift` | `SidebarMainView` | `Sidebar` | `Views` |
| `SwiftCode/Views/Sidebar/StatusIndicator.swift` | `StatusIndicator` | `Sidebar` | `Views` |
| `SwiftCode/Views/Sidebar/TestsSidebarView.swift` | `TestsSidebarView` | `Sidebar` | `Views` |
| `SwiftCode/Views/Sidebar/WorkflowEditorView.swift` | `WorkflowEditorView` | `Sidebar` | `Views` |
| `SwiftCode/Views/Sidebar/WorkflowEditorView.swift` | `SnippetRow` | `Sidebar` | `Views` |
| `SwiftCode/Views/StatusBarView.swift` | `StatusBarView` | `Views` | `SwiftCode` |
| `SwiftCode/Views/TemplatePickerView.swift` | `TemplatePickerView` | `Views` | `SwiftCode` |
| `SwiftCode/Views/ThemeEditorView.swift` | `ThemeEditorView` | `Views` | `SwiftCode` |
| `SwiftCode/Views/ThemeEditorView.swift` | `ColorPickerView` | `Views` | `SwiftCode` |
| `SwiftCode/Views/ThemeGalleryView.swift` | `ThemeGalleryView` | `Views` | `SwiftCode` |
| `SwiftCode/Views/Toolbar/ToolbarCustomizationView.swift` | `ToolbarCustomizationView` | `Toolbar` | `Views` |
| `SwiftCode/Views/Toolbar/ToolbarMinimizedView.swift` | `ToolbarMinimizedView` | `Toolbar` | `Views` |
| `SwiftCode/Views/Toolbar/ToolbarMinimizedView.swift` | `ToolbarExpandedPanelView` | `Toolbar` | `Views` |
| `SwiftCode/Views/Transfer Projects/DevicePickerView.swift` | `DevicePickerView` | `Transfer Projects` | `Views` |
| `SwiftCode/Views/Transfer Projects/IncomingTransferView.swift` | `IncomingTransferView` | `Transfer Projects` | `Views` |
| `SwiftCode/Views/Transfer Projects/PermissionConfigView.swift` | `PermissionConfigView` | `Transfer Projects` | `Views` |
| `SwiftCode/Views/Transfer Projects/TransferProgressView.swift` | `TransferProgressView` | `Transfer Projects` | `Views` |
| `SwiftCode/Views/Transfer Projects/TransferProjectsHomeView.swift` | `TransferProjectsHomeView` | `Transfer Projects` | `Views` |
| `SwiftCode/Views/Utilities/FileImporterRepresentableView.swift` | `FileImporterRepresentableView` | `Utilities` | `Views` |
| `SwiftCode/Views/Utilities/FilePreviewView.swift` | `FilePreviewView` | `Utilities` | `Views` |
| `SwiftCode/Views/Utilities/ShareSheet.swift` | `ShareSheet` | `Utilities` | `Views` |
| `SwiftCode/Views/WorkspaceView.swift` | `WorkspaceView` | `Views` | `SwiftCode` |
