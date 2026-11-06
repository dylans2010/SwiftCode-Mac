# MIGRATE_AND_ADAPT reconciliation

Legacy rows audited: 285

- ALREADY_PRESENT: 9
- PARTIAL: 28
- GENUINELY_MISSING: 248

## Per-file

| Legacy path | Class | Types | Matched | Destination symbols |
|---|---|---|---|---|
| `SwiftCode/Backend/Assist/API/Internal API/Reverse/ReverseBridge.swift` | PARTIAL | 6 | 3 | FlagBox->swiftcode/Sources/SwiftCodeUI/Navigator/NavigatorAreaController.swift, ProcessBox->swiftcode/Sources/SwiftCodeUI/Terminal/SandboxedCommandRunner.swift, ReverseBridge->swiftcode/Sources/SwiftCodeMCP/SwiftCodeTools+Engines.swift |
| `SwiftCode/Backend/Assist/API/Internal API/Reverse/ReverseCommandParser.swift` | ALREADY_PRESENT | 2 | 2 | ReverseCommandParser->swiftcode/Sources/SwiftCodeMCP/SwiftCodeTools+EnginesSupport.swift, ReverseTargetValidator->swiftcode/Sources/SwiftCodeMCP/SwiftCodeTools+EnginesSupport.swift |
| `SwiftCode/Backend/Assist/API/Internal API/Reverse/ReverseEvidenceProcessor.swift` | GENUINELY_MISSING | 2 | 0 |  |
| `SwiftCode/Backend/Assist/API/Internal API/Reverse/ReverseManager.swift` | PARTIAL | 2 | 1 | ReverseManager->swiftcode/Sources/SwiftCodeAssistant/MetaAssistTurnExecutor.swift |
| `SwiftCode/Backend/Assist/API/Internal API/Reverse/ReverseModels.swift` | PARTIAL | 24 | 7 | CodingKeys->swiftcode/Sources/SwiftCodeExtensions/SwiftCodeManifest.swift, Digest->swiftcode/Sources/swiftcode-ide/SDKStudio/SDKStudioExtensionsViews.swift, Provider->swiftcode/Sources/swiftcode-ide/SettingsPaneCodingAssistant.swift, ReverseObjdumpOperation->swiftcode/Sources/SwiftCodeMCP/SwiftCodeTools+EnginesSupport.swift, ReverseOperation->swiftcode/Sources/SwiftCodeMCP/SwiftCodeTools+EnginesSu |
| `SwiftCode/Backend/Assist/AgentContextManager.swift` | GENUINELY_MISSING | 4 | 0 |  |
| `SwiftCode/Backend/Assist/AgentPhaseCoordinator.swift` | PARTIAL | 4 | 1 | AgentPhaseCoordinator->swiftcode/Sources/SwiftCodeMCP/SwiftCodeTools+ReviewDocs.swift |
| `SwiftCode/Backend/Assist/Assist Frameworks/AssistAutonomousDecisionEngine.swift` | PARTIAL | 2 | 1 | Decision->swiftcode/Sources/SwiftCodePreviews/PreviewDiscovery.swift |
| `SwiftCode/Backend/Assist/Assist Frameworks/AssistContextDriftDetector.swift` | GENUINELY_MISSING | 2 | 0 |  |
| `SwiftCode/Backend/Assist/Assist Frameworks/AssistExecutionTraceEngine.swift` | PARTIAL | 3 | 1 | EventType->swiftcode/Sources/SwiftCodeUI/Navigator/FindNavigator.swift |
| `SwiftCode/Backend/Assist/Assist Frameworks/AssistGoalExpansionEngine.swift` | GENUINELY_MISSING | 1 | 0 |  |
| `SwiftCode/Backend/Assist/Assist Frameworks/AssistMemoryConsistencyValidator.swift` | GENUINELY_MISSING | 2 | 0 |  |
| `SwiftCode/Backend/Assist/Assist Frameworks/AssistOptimizationEngine.swift` | GENUINELY_MISSING | 2 | 0 |  |
| `SwiftCode/Backend/Assist/Assist Frameworks/AssistPerformanceProfilingEngine.swift` | GENUINELY_MISSING | 3 | 0 |  |
| `SwiftCode/Backend/Assist/Assist Frameworks/AssistResourceUsageMonitor.swift` | GENUINELY_MISSING | 2 | 0 |  |
| `SwiftCode/Backend/Assist/Assist Frameworks/AssistRuntimeBehaviorMonitor.swift` | GENUINELY_MISSING | 3 | 0 |  |
| `SwiftCode/Backend/Assist/Assist Frameworks/AssistTaskContinuationEngine.swift` | GENUINELY_MISSING | 3 | 0 |  |
| `SwiftCode/Backend/Assist/Assist Frameworks/Google Cloud SDK/GoogleCloudSDKBridge.swift` | GENUINELY_MISSING | 1 | 0 |  |
| `SwiftCode/Backend/Assist/Assist Frameworks/Google Cloud SDK/GoogleCloudSDKConfiguration.swift` | PARTIAL | 3 | 2 | CodingKeys->swiftcode/Sources/SwiftCodeExtensions/SwiftCodeManifest.swift, GoogleCloudSDKConfiguration->swiftcode/Sources/SwiftCodeAssistant/AssistSDKModelSelection.swift |
| `SwiftCode/Backend/Assist/Assist Frameworks/Google Cloud SDK/GoogleCloudSDKError.swift` | GENUINELY_MISSING | 1 | 0 |  |
| `SwiftCode/Backend/Assist/Assist Frameworks/Google Cloud SDK/GoogleCloudSDKEvent.swift` | GENUINELY_MISSING | 2 | 0 |  |
| `SwiftCode/Backend/Assist/Assist Frameworks/Google Cloud SDK/GoogleCloudSDKLifecycleManager.swift` | ALREADY_PRESENT | 1 | 1 | GoogleCloudSDKLifecycleManager->swiftcode/Sources/SwiftCodeGoogleAuth/GoogleAccountAuthService.swift |
| `SwiftCode/Backend/Assist/Assist Frameworks/Google Cloud SDK/GoogleCloudSDKMessage.swift` | GENUINELY_MISSING | 4 | 0 |  |
| `SwiftCode/Backend/Assist/Assist Frameworks/Google Cloud SDK/GoogleCloudSDKProcess.swift` | GENUINELY_MISSING | 1 | 0 |  |
| `SwiftCode/Backend/Assist/Assist Frameworks/Google Cloud SDK/GoogleCloudSDKRuntime.swift` | GENUINELY_MISSING | 1 | 0 |  |
| `SwiftCode/Backend/Assist/Assist Frameworks/Google Cloud SDK/GoogleCloudSDKSession.swift` | GENUINELY_MISSING | 1 | 0 |  |
| `SwiftCode/Backend/Assist/Assist Frameworks/Google Cloud SDK/GoogleCloudSDKTool.swift` | GENUINELY_MISSING | 3 | 0 |  |
| `SwiftCode/Backend/Assist/Assist Frameworks/Google Cloud SDK/GoogleCloudSDKTransport.swift` | GENUINELY_MISSING | 1 | 0 |  |
| `SwiftCode/Backend/Assist/Assist Frameworks/_AssistCriticalAutonomousEngine.swift` | GENUINELY_MISSING | 1 | 0 |  |
| `SwiftCode/Backend/Assist/Assist Frameworks/_AssistCriticalExecutionEngine.swift` | NO_TYPES | - | - | no top-level types (functions/config only) |
| `SwiftCode/Backend/Assist/Assist Frameworks/_AssistCriticalTaskOrchestrator.swift` | NO_TYPES | - | - | no top-level types (functions/config only) |
| `SwiftCode/Backend/Assist/Assist Frameworks/_AssistCriticalValidationEngine.swift` | GENUINELY_MISSING | 1 | 0 |  |
| `SwiftCode/Backend/Assist/AssistFeedbackService.swift` | GENUINELY_MISSING | 6 | 0 |  |
| `SwiftCode/Backend/Assist/AssistParallelExecutionEngine.swift` | GENUINELY_MISSING | 5 | 0 |  |
| `SwiftCode/Backend/Assist/AssistSystemPromptSections.swift` | GENUINELY_MISSING | 1 | 0 |  |
| `SwiftCode/Backend/Assist/AssistToolKnowledgeValidator.swift` | GENUINELY_MISSING | 1 | 0 |  |
| `SwiftCode/Backend/Assist/Functions/SystemIndex.swift` | PARTIAL | 18 | 2 | Scored->swiftcode/Sources/SwiftCodeIDECore/Model/CodeReviewModels.swift, SystemIndexService->swiftcode/Sources/SwiftCodeAssistant/MetaAssistTurnExecutor.swift |
| `SwiftCode/Backend/Assist/Subagents/Context/WorkerContextBuilder.swift` | GENUINELY_MISSING | 1 | 0 |  |
| `SwiftCode/Backend/Assist/Subagents/Context/WorkerTaskDecomposer.swift` | GENUINELY_MISSING | 1 | 0 |  |
| `SwiftCode/Backend/Assist/Subagents/Coordination/WorkerScheduler.swift` | GENUINELY_MISSING | 1 | 0 |  |
| `SwiftCode/Backend/Assist/Subagents/Engine/WorkerEngine.swift` | GENUINELY_MISSING | 1 | 0 |  |
| `SwiftCode/Backend/Assist/Subagents/Engine/WorkerEventBus.swift` | GENUINELY_MISSING | 1 | 0 |  |
| `SwiftCode/Backend/Assist/Subagents/Engine/WorkerFileTracker.swift` | GENUINELY_MISSING | 1 | 0 |  |
| `SwiftCode/Backend/Assist/Subagents/Engine/WorkerRuntimeState.swift` | GENUINELY_MISSING | 1 | 0 |  |
| `SwiftCode/Backend/Assist/Subagents/Models/WorkerEvent.swift` | GENUINELY_MISSING | 2 | 0 |  |
| `SwiftCode/Backend/Assist/Subagents/Models/WorkerModelSelector.swift` | GENUINELY_MISSING | 1 | 0 |  |
| `SwiftCode/Backend/Assist/Subagents/Models/WorkerModels.swift` | PARTIAL | 23 | 2 | Worker->swiftcode/Sources/SwiftCodeDarwinKernel/Snapshot/SnapshotTags.swift, WorkerAssignment->swiftcode/Sources/SwiftCodeMCP/SwiftCodeTools+PlanningSupport.swift |
| `SwiftCode/Backend/Assist/Subagents/Persistence/WorkerPersistenceStore.swift` | GENUINELY_MISSING | 4 | 0 |  |
| `SwiftCode/Backend/Assist/Subagents/Recovery/WorkerHandoffCoordinator.swift` | GENUINELY_MISSING | 1 | 0 |  |
| `SwiftCode/Backend/Assist/Subagents/Recovery/WorkerRecoveryEngine.swift` | GENUINELY_MISSING | 1 | 0 |  |
| `SwiftCode/Backend/Assist/Subagents/Review/WorkerRecapGenerator.swift` | GENUINELY_MISSING | 1 | 0 |  |
| `SwiftCode/Backend/Assist/Subagents/Review/WorkerReviewEngine.swift` | GENUINELY_MISSING | 1 | 0 |  |
| `SwiftCode/Backend/Assist/Subagents/UI/WorkerStopConfirmationSheet.swift` | GENUINELY_MISSING | 1 | 0 |  |
| `SwiftCode/Backend/Assist/Subagents/UI/WorkersHeaderButton.swift` | GENUINELY_MISSING | 1 | 0 |  |
| `SwiftCode/Backend/Assist/Subagents/UI/WorkersInfoView.swift` | GENUINELY_MISSING | 1 | 0 |  |
| `SwiftCode/Backend/Assist/Subagents/UI/WorkersMainView.swift` | GENUINELY_MISSING | 2 | 0 |  |
| `SwiftCode/Backend/Assist/Subagents/UI/WorkersOnAssistView.swift` | GENUINELY_MISSING | 1 | 0 |  |
| `SwiftCode/Backend/Build/XcodeBuildAPI.swift` | PARTIAL | 19 | 9 | AppEntry->swiftcode/Sources/SwiftCodeIDECore/Model/NewProject/LegacyProjectTemplateManager.swift, BuildConfiguration->swiftcode/Sources/SwiftCodeMCP/CIBuildYAML.swift, BuildResult->swiftcode/Sources/SwiftCodeSDK/Host/ServiceAdapters/Build/SDKBuildService.swift, BuildStatus->swiftcode/Sources/SwiftCodeDeviceModel/DeviceConnectModels.swift, ContentView->swiftcode/Sources/swiftcode-ide/SDKStudio/SDKS |
| `SwiftCode/Backend/Codex/CodexBridgeManager.swift` | GENUINELY_MISSING | 3 | 0 |  |
| `SwiftCode/Backend/Git/GitHubService.swift` | PARTIAL | 48 | 20 | CodingKeys->swiftcode/Sources/SwiftCodeExtensions/SwiftCodeManifest.swift, CommitDetail->swiftcode/Sources/swiftcode-ide/SourceControlEditor.swift, GitHubArtifact->swiftcode/Sources/SwiftCodeGitHub/GitHubModels.swift, GitHubArtifactsResponse->swiftcode/Sources/SwiftCodeGitHub/GitHubClient.swift, GitHubBranch->swiftcode/Sources/SwiftCodeGitHub/GitHubModels.swift, GitHubCommit->swiftcode/Sources/Swi |
| `SwiftCode/Backend/GitHub/BuildingSystemAPI.swift` | GENUINELY_MISSING | 1 | 0 |  |
| `SwiftCode/Backend/GitHub/GitHubImport.swift` | GENUINELY_MISSING | 2 | 0 |  |
| `SwiftCode/Backend/Offline Models/MLXSwift Foundation/MLXIntegration.swift` | GENUINELY_MISSING | 4 | 0 |  |
| `SwiftCode/Backend/Offline Models/MLXSwift Foundation/MLXModelContainer.swift` | GENUINELY_MISSING | 1 | 0 |  |
| `SwiftCode/Backend/Offline Models/MLXSwift Foundation/UniversalModelLoader.swift` | PARTIAL | 16 | 2 | Builder->swiftcode/Sources/SwiftCodeStrings/StringsCLI.swift, CodingKeys->swiftcode/Sources/SwiftCodeExtensions/SwiftCodeManifest.swift |
| `SwiftCode/Backend/Offline Models/OfflineModelRunner.swift` | GENUINELY_MISSING | 1 | 0 |  |
| `SwiftCode/Backend/On Device Intelligence/AppleIntelligenceService.swift` | GENUINELY_MISSING | 2 | 0 |  |
| `SwiftCode/Backend/On Device Intelligence/DeviceUtilityManager.swift` | GENUINELY_MISSING | 1 | 0 |  |
| `SwiftCode/Backend/On Device Intelligence/OnDeviceAIManager.swift` | GENUINELY_MISSING | 1 | 0 |  |
| `SwiftCode/Backend/On Device Intelligence/OnDeviceCapabilities.swift` | GENUINELY_MISSING | 2 | 0 |  |
| `SwiftCode/Backend/On Device Intelligence/OnDeviceModelRouter.swift` | GENUINELY_MISSING | 1 | 0 |  |
| `SwiftCode/Backend/On Device Intelligence/OnDeviceSession.swift` | GENUINELY_MISSING | 1 | 0 |  |
| `SwiftCode/Backend/Updates/AppUpdateService.swift` | PARTIAL | 2 | 1 | AppUpdateService->swiftcode/Sources/SwiftCodeIDECore/Utilities/AppUpdateSupport.swift |
| `SwiftCode/Core/AI/Agent/AgentSystemInitializer.swift` | GENUINELY_MISSING | 1 | 0 |  |
| `SwiftCode/Features/AdvancedTools/Views/AdvancedToolsDesignSystem.swift` | NO_TYPES | - | - | no top-level types (functions/config only) |
| `SwiftCode/Features/AdvancedTools/Views/DocumentationAIInsightsView.swift` | GENUINELY_MISSING | 1 | 0 |  |
| `SwiftCode/Features/AdvancedTools/Views/DocumentationAIScanView.swift` | GENUINELY_MISSING | 2 | 0 |  |
| `SwiftCode/Frameworks/Diff/DiffEngine.swift` | GENUINELY_MISSING | 1 | 0 |  |
| `SwiftCode/Frameworks/Diff/MyersDiffAlgorithm.swift` | PARTIAL | 6 | 2 | LiveDiffStreamer->swiftcode/Sources/SwiftCodeMCP/SwiftCodeTools+AssetsLocalization.swift, MyersDiffAlgorithm->swiftcode/Sources/SwiftCodeIDECore/MyersDiff.swift |
| `SwiftCode/Frameworks/Internal/MCP/MCPClient.swift` | PARTIAL | 15 | 4 | CodingKeys->swiftcode/Sources/SwiftCodeExtensions/SwiftCodeManifest.swift, JSONRPCError->swiftcode/Sources/SwiftCodeAssistant/ACPClient.swift, JSONRPCID->swiftcode/Sources/SwiftCodeAssistant/JSONRPCPeer.swift, MCPClient->swiftcode/Sources/swiftcode-ide/ExternalMCPServersView.swift |
| `SwiftCode/Frameworks/Internal/MCP/MCPModels.swift` | PARTIAL | 17 | 3 | CodingKeys->swiftcode/Sources/SwiftCodeExtensions/SwiftCodeManifest.swift, MCPServer->swiftcode/Sources/SwiftCodeAssistant/MetaAssistTurnExecutor.swift, MCPTool->swiftcode/Sources/SwiftCodeMCP/SwiftCodeTools+ArchiveData.swift |
| `SwiftCode/Frameworks/Internal/MCP/MCPServerManager.swift` | ALREADY_PRESENT | 1 | 1 | MCPServerManager->swiftcode/Sources/SwiftCodeMCP/SwiftCodeTools+MCPClient.swift |
| `SwiftCode/Models/AppSettings.swift` | PARTIAL | 6 | 1 | AppSettings->swiftcode/Sources/SwiftCodeAssistant/LocalModelManager.swift |
| `SwiftCode/Resources/Google Cloud SDK/README.md` | NO_TYPES | - | - | no top-level types (functions/config only) |
| `SwiftCode/Resources/Google Cloud SDK/bridge/__init__.py` | NO_TYPES | - | - | no top-level types (functions/config only) |
| `SwiftCode/Resources/Google Cloud SDK/bridge/agent_runner.py` | GENUINELY_MISSING | 5 | 0 |  |
| `SwiftCode/Resources/Google Cloud SDK/bridge/gemini_auth_test.py` | GENUINELY_MISSING | 5 | 0 |  |
| `SwiftCode/Resources/Google Cloud SDK/bridge/main.py` | GENUINELY_MISSING | 1 | 0 |  |
| `SwiftCode/Resources/Google Cloud SDK/bridge/model_adapter_server.py` | GENUINELY_MISSING | 2 | 0 |  |
| `SwiftCode/Resources/Google Cloud SDK/bridge/protocol.py` | GENUINELY_MISSING | 1 | 0 |  |
| `SwiftCode/Resources/Google Cloud SDK/bridge/session_auth_test.py` | GENUINELY_MISSING | 3 | 0 |  |
| `SwiftCode/Resources/Google Cloud SDK/requirements.txt` | NO_TYPES | - | - | no top-level types (functions/config only) |
| `SwiftCode/Resources/Google Cloud SDK/skills/swift_development/SKILL.md` | NO_TYPES | - | - | no top-level types (functions/config only) |
| `SwiftCode/Services/AgentSkillManager.swift` | GENUINELY_MISSING | 1 | 0 |  |
| `SwiftCode/Services/ComposioService.swift` | GENUINELY_MISSING | 3 | 0 |  |
| `SwiftCode/Services/NotificationManager.swift` | ALREADY_PRESENT | 1 | 1 | NotificationManager->swiftcode/Sources/SwiftCodeAssistant/OfflineModelDownloader.swift |
| `SwiftCode/Services/ProjectFilesExtracter.swift` | GENUINELY_MISSING | 1 | 0 |  |
| `SwiftCode/Services/SoundManager.swift` | GENUINELY_MISSING | 3 | 0 |  |
| `SwiftCode/Services/ToolbarSettings.swift` | GENUINELY_MISSING | 1 | 0 |  |
| `SwiftCode/Shared/Markdown/MarkdownBlockRenderer.swift` | GENUINELY_MISSING | 1 | 0 |  |
| `SwiftCode/Tools/generate_app_icons.swift` | GENUINELY_MISSING | 1 | 0 |  |
| `SwiftCode/UI/Utilities/SFSymbolBrowserView.swift` | GENUINELY_MISSING | 7 | 0 |  |
| `SwiftCode/Views/AdvancedTools/Views/MainToolsView.swift` | GENUINELY_MISSING | 5 | 0 |  |
| `SwiftCode/Views/Assist/AntigravityLimitsModelsUI.swift` | GENUINELY_MISSING | 2 | 0 |  |
| `SwiftCode/Views/Assist/AssistSpeechUI.swift` | GENUINELY_MISSING | 1 | 0 |  |
| `SwiftCode/Views/Assist/ReverseFillOutView.swift` | GENUINELY_MISSING | 1 | 0 |  |
| `SwiftCode/Views/Build/LocalBuildDemoView.swift` | GENUINELY_MISSING | 1 | 0 |  |
| `SwiftCode/Views/Build/Xcode Build/AppleSignInManager.swift` | GENUINELY_MISSING | 8 | 0 |  |
| `SwiftCode/Views/Build/Xcode Build/AppleSignInView.swift` | GENUINELY_MISSING | 2 | 0 |  |
| `SwiftCode/Views/Build/Xcode Build/IPABuildView.swift` | GENUINELY_MISSING | 1 | 0 |  |
| `SwiftCode/Views/Collaboration/ActivityLogView.swift` | GENUINELY_MISSING | 1 | 0 |  |
| `SwiftCode/Views/Collaboration/CollaborationAuditLogView.swift` | GENUINELY_MISSING | 2 | 0 |  |
| `SwiftCode/Views/Collaboration/CollaborationChatView.swift` | GENUINELY_MISSING | 3 | 0 |  |
| `SwiftCode/Views/Collaboration/CollaborationDashboardView.swift` | GENUINELY_MISSING | 4 | 0 |  |
| `SwiftCode/Views/Collaboration/CollaborationFeedbackView.swift` | GENUINELY_MISSING | 2 | 0 |  |
| `SwiftCode/Views/Collaboration/CollaborationFilePresenceOverlay.swift` | GENUINELY_MISSING | 2 | 0 |  |
| `SwiftCode/Views/Collaboration/CollaborationMainView.swift` | GENUINELY_MISSING | 1 | 0 |  |
| `SwiftCode/Views/Collaboration/CollaborationNotificationCenterView.swift` | GENUINELY_MISSING | 2 | 0 |  |
| `SwiftCode/Views/Collaboration/CollaborationSidebarView.swift` | GENUINELY_MISSING | 3 | 0 |  |
| `SwiftCode/Views/Collaboration/FilePermissionView.swift` | GENUINELY_MISSING | 1 | 0 |  |
| `SwiftCode/Views/Collaboration/InviteMembersView.swift` | GENUINELY_MISSING | 1 | 0 |  |
| `SwiftCode/Views/Collaboration/MemberManagementView.swift` | GENUINELY_MISSING | 1 | 0 |  |
| `SwiftCode/Views/Deployments/DeploymentLogsView.swift` | PARTIAL | 3 | 2 | DeploymentLogLine->swiftcode/Sources/SwiftCodeIDECore/Session/DeploymentLogStore.swift, DeploymentLogsView->swiftcode/Sources/SwiftCodeIDECore/Session/DeploymentLogStore.swift |
| `SwiftCode/Views/Dev Tools/AppReceiptInspectorDevToolView.swift` | GENUINELY_MISSING | 2 | 0 |  |
| `SwiftCode/Views/Dev Tools/BarcodeGeneratorDevToolView.swift` | GENUINELY_MISSING | 2 | 0 |  |
| `SwiftCode/Views/Dev Tools/Base64FileConverterView.swift` | GENUINELY_MISSING | 1 | 0 |  |
| `SwiftCode/Views/Dev Tools/BatteryStatusDevToolView.swift` | GENUINELY_MISSING | 2 | 0 |  |
| `SwiftCode/Views/Dev Tools/BreakpointManagerDevToolView.swift` | GENUINELY_MISSING | 3 | 0 |  |
| `SwiftCode/Views/Dev Tools/BundleSizeAnalyzerDevToolView.swift` | GENUINELY_MISSING | 3 | 0 |  |
| `SwiftCode/Views/Dev Tools/CPUMonitorDevToolView.swift` | GENUINELY_MISSING | 2 | 0 |  |
| `SwiftCode/Views/Dev Tools/CacheViewerDevToolView.swift` | GENUINELY_MISSING | 3 | 0 |  |
| `SwiftCode/Views/Dev Tools/ClipboardInspectorDevToolView.swift` | GENUINELY_MISSING | 2 | 0 |  |
| `SwiftCode/Views/Dev Tools/DeepLinkTesterDevToolView.swift` | GENUINELY_MISSING | 2 | 0 |  |
| `SwiftCode/Views/Dev Tools/DesignerDevToolView.swift` | GENUINELY_MISSING | 8 | 0 |  |
| `SwiftCode/Views/Dev Tools/DevToolsMainView.swift` | GENUINELY_MISSING | 2 | 0 |  |
| `SwiftCode/Views/Dev Tools/DiskUsageAnalyzerDevToolView.swift` | GENUINELY_MISSING | 3 | 0 |  |
| `SwiftCode/Views/Dev Tools/EnergyImpactMonitorDevToolView.swift` | GENUINELY_MISSING | 2 | 0 |  |
| `SwiftCode/Views/Dev Tools/ExpandedDevTools.swift` | GENUINELY_MISSING | 30 | 0 |  |
| `SwiftCode/Views/Dev Tools/FPSMonitorDevToolView.swift` | GENUINELY_MISSING | 2 | 0 |  |
| `SwiftCode/Views/Dev Tools/NetworkReachabilityDevToolView.swift` | GENUINELY_MISSING | 2 | 0 |  |
| `SwiftCode/Views/Dev Tools/QRCodeGeneratorView.swift` | GENUINELY_MISSING | 1 | 0 |  |
| `SwiftCode/Views/Developer/BackgroundTaskMonitorView.swift` | GENUINELY_MISSING | 2 | 0 |  |
| `SwiftCode/Views/Developer/BinaryTools/BinaryToolsViews.swift` | GENUINELY_MISSING | 1 | 0 |  |
| `SwiftCode/Views/Developer/BuildDiagnosticsView.swift` | GENUINELY_MISSING | 3 | 0 |  |
| `SwiftCode/Views/Developer/CacheInspectorView.swift` | GENUINELY_MISSING | 2 | 0 |  |
| `SwiftCode/Views/Developer/ConsoleCommandRunnerView.swift` | GENUINELY_MISSING | 1 | 0 |  |
| `SwiftCode/Views/Developer/CoreMLInspector/CoreMLInspectorView.swift` | GENUINELY_MISSING | 1 | 0 |  |
| `SwiftCode/Views/Developer/DebugOverlaysView.swift` | GENUINELY_MISSING | 1 | 0 |  |
| `SwiftCode/Views/Developer/DependencyHealthView.swift` | GENUINELY_MISSING | 2 | 0 |  |
| `SwiftCode/Views/Developer/DeveloperDashboard/DeveloperDashboardView.swift` | GENUINELY_MISSING | 1 | 0 |  |
| `SwiftCode/Views/Developer/EnvironmentSwitcherView.swift` | GENUINELY_MISSING | 1 | 0 |  |
| `SwiftCode/Views/Developer/ErrorFrequencyTrackerView.swift` | GENUINELY_MISSING | 2 | 0 |  |
| `SwiftCode/Views/Developer/ExtensionDebugger/ExtensionDebuggerView.swift` | GENUINELY_MISSING | 1 | 0 |  |
| `SwiftCode/Views/Developer/FeatureFlags/FeatureFlagsView.swift` | ALREADY_PRESENT | 1 | 1 | FeatureFlagsView->swiftcode/Sources/SwiftCodePaywall/PaywallBypass.swift |
| `SwiftCode/Views/Developer/GitHubAPIDebug/GitHubAPIDebugView.swift` | GENUINELY_MISSING | 1 | 0 |  |
| `SwiftCode/Views/Developer/MemoryInspector/MemoryInspectorView.swift` | GENUINELY_MISSING | 1 | 0 |  |
| `SwiftCode/Views/Developer/MemoryLeakDetectionView.swift` | GENUINELY_MISSING | 2 | 0 |  |
| `SwiftCode/Views/Developer/PerformanceMonitor/PerformanceMonitorView.swift` | GENUINELY_MISSING | 3 | 0 |  |
| `SwiftCode/Views/Developer/PermissionsCheckerView.swift` | GENUINELY_MISSING | 2 | 0 |  |
| `SwiftCode/Views/Developer/RealtimeMetricsDashboardView.swift` | GENUINELY_MISSING | 2 | 0 |  |
| `SwiftCode/Views/Developer/RuntimeFlags/RuntimeFlagsView.swift` | GENUINELY_MISSING | 1 | 0 |  |
| `SwiftCode/Views/Developer/StateInspectorView.swift` | GENUINELY_MISSING | 2 | 0 |  |
| `SwiftCode/Views/Developer/ThreadInspector/ThreadInspectorView.swift` | GENUINELY_MISSING | 1 | 0 |  |
| `SwiftCode/Views/Developer/Virtualization/AppKit/VirtualizationCoordinator.swift` | GENUINELY_MISSING | 1 | 0 |  |
| `SwiftCode/Views/Developer/Virtualization/AppKit/VirtualizationSplitViewController.swift` | GENUINELY_MISSING | 1 | 0 |  |
| `SwiftCode/Views/Developer/Virtualization/Core/SCVirtualizationEngine.swift` | ALREADY_PRESENT | 1 | 1 | SCVirtualizationEngine->swiftcode/Sources/SwiftCodeUI/Virtualization/VirtualMachineRegistry.swift |
| `SwiftCode/Views/Developer/Virtualization/Core/VirtualMachineController.swift` | GENUINELY_MISSING | 1 | 0 |  |
| `SwiftCode/Views/Developer/Virtualization/Core/VirtualizationEventBus.swift` | GENUINELY_MISSING | 2 | 0 |  |
| `SwiftCode/Views/Developer/Virtualization/Core/VirtualizationRuntime.swift` | GENUINELY_MISSING | 2 | 0 |  |
| `SwiftCode/Views/Developer/Virtualization/Core/VirtualizationStateStore.swift` | PARTIAL | 6 | 1 | LogType->swiftcode/Sources/SwiftCodeDeviceModel/DeviceConnectParsers.swift |
| `SwiftCode/Views/Developer/Virtualization/Managers/SnapshotManager.swift` | GENUINELY_MISSING | 1 | 0 |  |
| `SwiftCode/Views/Developer/Virtualization/Managers/VMBackupManager.swift` | GENUINELY_MISSING | 1 | 0 |  |
| `SwiftCode/Views/Developer/Virtualization/Managers/VMImageManager.swift` | GENUINELY_MISSING | 1 | 0 |  |
| `SwiftCode/Views/Developer/Virtualization/Managers/VMMonitoringManager.swift` | GENUINELY_MISSING | 2 | 0 |  |
| `SwiftCode/Views/Developer/Virtualization/Managers/VMNetworkManager.swift` | GENUINELY_MISSING | 1 | 0 |  |
| `SwiftCode/Views/Developer/Virtualization/Managers/VMSharedFolderManager.swift` | GENUINELY_MISSING | 1 | 0 |  |
| `SwiftCode/Views/Developer/Virtualization/Models/EnvironmentProfile.swift` | GENUINELY_MISSING | 1 | 0 |  |
| `SwiftCode/Views/Developer/Virtualization/Models/VirtualMachine.swift` | PARTIAL | 6 | 2 | CodingKeys->swiftcode/Sources/SwiftCodeExtensions/SwiftCodeManifest.swift, VirtualMachine->swiftcode/Sources/SwiftCodeHypervisor/KVMSmokeTest.swift |
| `SwiftCode/Views/Developer/Virtualization/Models/VirtualMachineImage.swift` | GENUINELY_MISSING | 1 | 0 |  |
| `SwiftCode/Views/Developer/Virtualization/Providers/AlpineProvider.swift` | GENUINELY_MISSING | 1 | 0 |  |
| `SwiftCode/Views/Developer/Virtualization/Providers/DebianProvider.swift` | GENUINELY_MISSING | 1 | 0 |  |
| `SwiftCode/Views/Developer/Virtualization/Providers/FedoraProvider.swift` | GENUINELY_MISSING | 1 | 0 |  |
| `SwiftCode/Views/Developer/Virtualization/Providers/OperatingSystemProvider.swift` | GENUINELY_MISSING | 1 | 0 |  |
| `SwiftCode/Views/Developer/Virtualization/Providers/UbuntuProvider.swift` | GENUINELY_MISSING | 1 | 0 |  |
| `SwiftCode/Views/Developer/Virtualization/Services/VirtualizationService.swift` | GENUINELY_MISSING | 1 | 0 |  |
| `SwiftCode/Views/Developer/Virtualization/UI/CreateVirtualMachineWizardView.swift` | GENUINELY_MISSING | 2 | 0 |  |
| `SwiftCode/Views/Developer/Virtualization/UI/EnvironmentProfilesView.swift` | GENUINELY_MISSING | 2 | 0 |  |
| `SwiftCode/Views/Developer/Virtualization/UI/OperatingSystemProviderView.swift` | GENUINELY_MISSING | 1 | 0 |  |
| `SwiftCode/Views/Developer/Virtualization/UI/VirtualMachineConsoleView.swift` | GENUINELY_MISSING | 1 | 0 |  |
| `SwiftCode/Views/Developer/Virtualization/UI/VirtualMachineDetailView.swift` | GENUINELY_MISSING | 4 | 0 |  |
| `SwiftCode/Views/Developer/Virtualization/UI/VirtualMachineListView.swift` | PARTIAL | 3 | 1 | SortOption->swiftcode/Sources/SwiftCodeUI/Notes/ProjectNotesWorkspaceView.swift |
| `SwiftCode/Views/Developer/Virtualization/UI/VirtualMachineMonitorView.swift` | GENUINELY_MISSING | 1 | 0 |  |
| `SwiftCode/Views/Developer/Virtualization/UI/VirtualMachineNetworkView.swift` | GENUINELY_MISSING | 1 | 0 |  |
| `SwiftCode/Views/Developer/Virtualization/UI/VirtualMachineSettingsView.swift` | GENUINELY_MISSING | 1 | 0 |  |
| `SwiftCode/Views/Developer/Virtualization/UI/VirtualMachineSharedFoldersView.swift` | GENUINELY_MISSING | 1 | 0 |  |
| `SwiftCode/Views/Developer/Virtualization/UI/VirtualMachineSnapshotsView.swift` | GENUINELY_MISSING | 1 | 0 |  |
| `SwiftCode/Views/Developer/Virtualization/UI/VirtualMachineStorageView.swift` | GENUINELY_MISSING | 1 | 0 |  |
| `SwiftCode/Views/Developer/Virtualization/UI/VirtualMachineTerminalView.swift` | GENUINELY_MISSING | 5 | 0 |  |
| `SwiftCode/Views/Developer/Virtualization/UI/VirtualizationDashboardView.swift` | GENUINELY_MISSING | 1 | 0 |  |
| `SwiftCode/Views/Developer/Virtualization/UI/VirtualizationImageBrowserView.swift` | GENUINELY_MISSING | 1 | 0 |  |
| `SwiftCode/Views/Developer/Virtualization/UI/VirtualizationPreferencesView.swift` | GENUINELY_MISSING | 1 | 0 |  |
| `SwiftCode/Views/Developer/Virtualization/UI/VirtualizationSidebarView.swift` | GENUINELY_MISSING | 1 | 0 |  |
| `SwiftCode/Views/Developer/Virtualization/UI/VirtualizationWorkspaceView.swift` | GENUINELY_MISSING | 1 | 0 |  |
| `SwiftCode/Views/Developer/WebViewDebugger/WebViewDebuggerView.swift` | GENUINELY_MISSING | 1 | 0 |  |
| `SwiftCode/Views/GitHub/DiscussionsView.swift` | GENUINELY_MISSING | 1 | 0 |  |
| `SwiftCode/Views/GitHub/GitHubIntelligenceAndOperations.swift` | PARTIAL | 26 | 3 | EventType->swiftcode/Sources/SwiftCodeUI/Navigator/FindNavigator.swift, GitHubDiscoveryView->swiftcode/Sources/swiftcode-ide/PackageDiscoveryView.swift, RelationshipType->swiftcode/Sources/SwiftCodeCloud/DatabaseModels.swift |
| `SwiftCode/Views/GitHub/GitWorktreesView.swift` | PARTIAL | 3 | 1 | SortOption->swiftcode/Sources/SwiftCodeUI/Notes/ProjectNotesWorkspaceView.swift |
| `SwiftCode/Views/GitHub/Legacy/LicencesAddView.swift` | PARTIAL | 3 | 1 | LicencesAddView->swiftcode/Sources/SwiftCodeIDECore/Utilities/LicenseCatalog.swift |
| `SwiftCode/Views/GitHub/Menu Bar/MenuBarManager.swift` | GENUINELY_MISSING | 6 | 0 |  |
| `SwiftCode/Views/GitHub/RepositoryAutomationBuilderView.swift` | GENUINELY_MISSING | 6 | 0 |  |
| `SwiftCode/Views/GitHub/SwiftCodeWorkflows/WorkflowBuilderView.swift` | PARTIAL | 2 | 1 | EditorMode->swiftcode/Sources/SwiftCodeUI/Window/WorkspaceWindowController+ToolbarRight.swift |
| `SwiftCode/Views/GitHub/SwiftCodeWorkflows/WorkflowDashboardView.swift` | PARTIAL | 2 | 1 | WorkflowDashboardView->swiftcode/Sources/SwiftCodeUI/CI/GitHubActionsService.swift |
| `SwiftCode/Views/GitHub/SwiftCodeWorkflows/WorkflowExecutionView.swift` | GENUINELY_MISSING | 1 | 0 |  |
| `SwiftCode/Views/GitHub/SwiftCodeWorkflows/WorkflowManager.swift` | ALREADY_PRESENT | 1 | 1 | WorkflowManager->swiftcode/Sources/SwiftCodeUI/CI/CIWindowController.swift |
| `SwiftCode/Views/GitHub/SwiftCodeWorkflows/WorkflowModels.swift` | GENUINELY_MISSING | 3 | 0 |  |
| `SwiftCode/Views/GitHub/SwiftCodeWorkflows/WorkflowTemplates.swift` | GENUINELY_MISSING | 1 | 0 |  |
| `SwiftCode/Views/GitHub/SwiftCodeWorkflows/WorkflowsCreateView.swift` | GENUINELY_MISSING | 1 | 0 |  |
| `SwiftCode/Views/Settings/AllowedTerminalCommandsView.swift` | GENUINELY_MISSING | 1 | 0 |  |
| `SwiftCode/Views/Settings/Custom Tools/CustomToolBuilderView.swift` | PARTIAL | 5 | 1 | Tab->swiftcode/Sources/SwiftCodeStrings/StringExtractor.swift |
| `SwiftCode/Views/Settings/Skills/DraftSkillWithAIView.swift` | GENUINELY_MISSING | 1 | 0 |  |
| `SwiftCode/Views/Settings/SoundPickerView.swift` | GENUINELY_MISSING | 2 | 0 |  |
| `SwiftCode/Views/Settings/SoundPreviewView.swift` | GENUINELY_MISSING | 2 | 0 |  |
| `SwiftCode/Views/Settings/UpdateWindowView.swift` | GENUINELY_MISSING | 2 | 0 |  |
| `SwiftCode/Views/Settings/UpdatesView.swift` | PARTIAL | 6 | 1 | CodingKeys->swiftcode/Sources/SwiftCodeExtensions/SwiftCodeManifest.swift |
| `SwiftCode/Views/Transfer Projects/DevicePickerView.swift` | GENUINELY_MISSING | 1 | 0 |  |
| `SwiftCode/Views/Transfer Projects/IncomingTransferView.swift` | GENUINELY_MISSING | 1 | 0 |  |
| `SwiftCode/Views/Transfer Projects/PermissionConfigView.swift` | GENUINELY_MISSING | 1 | 0 |  |
| `SwiftCode/Views/Transfer Projects/TransferProgressView.swift` | GENUINELY_MISSING | 1 | 0 |  |
| `SwiftCode/Views/Transfer Projects/TransferProjectsHomeView.swift` | GENUINELY_MISSING | 1 | 0 |  |
| `SwiftCode/Views/Utilities/Database/Core/DatabaseCache.swift` | GENUINELY_MISSING | 1 | 0 |  |
| `SwiftCode/Views/Utilities/Database/Core/DatabaseConnectionManager.swift` | GENUINELY_MISSING | 1 | 0 |  |
| `SwiftCode/Views/Utilities/Database/Core/DatabaseManager.swift` | GENUINELY_MISSING | 1 | 0 |  |
| `SwiftCode/Views/Utilities/Database/Core/DatabaseSchemaManager.swift` | GENUINELY_MISSING | 1 | 0 |  |
| `SwiftCode/Views/Utilities/Database/Core/DatabaseSyncManager.swift` | GENUINELY_MISSING | 1 | 0 |  |
| `SwiftCode/Views/Utilities/Database/Core/DatabaseValidationManager.swift` | GENUINELY_MISSING | 2 | 0 |  |
| `SwiftCode/Views/Utilities/Database/DatabaseExplorerSidebarViewController.swift` | GENUINELY_MISSING | 3 | 0 |  |
| `SwiftCode/Views/Utilities/Database/DatabaseExplorerSplitViewController.swift` | GENUINELY_MISSING | 6 | 0 |  |
| `SwiftCode/Views/Utilities/Database/Helpers/DatabaseConstants.swift` | GENUINELY_MISSING | 1 | 0 |  |
| `SwiftCode/Views/Utilities/Database/Helpers/DatabaseFormatter.swift` | GENUINELY_MISSING | 1 | 0 |  |
| `SwiftCode/Views/Utilities/Database/Helpers/DatabaseValidators.swift` | GENUINELY_MISSING | 1 | 0 |  |
| `SwiftCode/Views/Utilities/Database/Models/DatabaseIndex.swift` | ALREADY_PRESENT | 1 | 1 | DatabaseIndex->swiftcode/Sources/SwiftCodeCloud/DatabaseModels.swift |
| `SwiftCode/Views/Utilities/Database/Models/DatabaseTrigger.swift` | ALREADY_PRESENT | 1 | 1 | DatabaseTrigger->swiftcode/Sources/SwiftCodeCloud/DatabaseModels.swift |
| `SwiftCode/Views/Utilities/Database/Views/DatabaseConnectionWizard.swift` | GENUINELY_MISSING | 1 | 0 |  |
| `SwiftCode/Views/Utilities/Database/Views/DatabaseConnectionsView.swift` | GENUINELY_MISSING | 1 | 0 |  |
| `SwiftCode/Views/Utilities/Database/Views/DatabaseIndexesView.swift` | GENUINELY_MISSING | 1 | 0 |  |
| `SwiftCode/Views/Utilities/Database/Views/DatabaseInspector.swift` | GENUINELY_MISSING | 1 | 0 |  |
| `SwiftCode/Views/Utilities/Database/Views/DatabasePermissionsView.swift` | GENUINELY_MISSING | 1 | 0 |  |
| `SwiftCode/Views/Utilities/Database/Views/DatabaseQueryEditor.swift` | GENUINELY_MISSING | 1 | 0 |  |
| `SwiftCode/Views/Utilities/Database/Views/DatabaseRecordEditor.swift` | GENUINELY_MISSING | 1 | 0 |  |
| `SwiftCode/Views/Utilities/Database/Views/DatabaseRecordViewer.swift` | GENUINELY_MISSING | 1 | 0 |  |
| `SwiftCode/Views/Utilities/Database/Views/DatabaseRelationshipEditor.swift` | GENUINELY_MISSING | 1 | 0 |  |
| `SwiftCode/Views/Utilities/Database/Views/DatabaseSchemaGenerator.swift` | GENUINELY_MISSING | 1 | 0 |  |
| `SwiftCode/Views/Utilities/Database/Views/DatabaseSchemaView.swift` | GENUINELY_MISSING | 3 | 0 |  |
| `SwiftCode/Views/Utilities/Database/Views/DatabaseSettingsView.swift` | GENUINELY_MISSING | 1 | 0 |  |
| `SwiftCode/Views/Utilities/Database/Views/DatabaseSidebar.swift` | GENUINELY_MISSING | 1 | 0 |  |
| `SwiftCode/Views/Utilities/Database/Views/DatabaseTableEditor.swift` | GENUINELY_MISSING | 1 | 0 |  |
| `SwiftCode/Views/Utilities/Database/Views/DatabaseTablesView.swift` | GENUINELY_MISSING | 1 | 0 |  |
| `SwiftCode/Views/Utilities/SFSymbolPickerView.swift` | GENUINELY_MISSING | 9 | 0 |  |
| `SwiftCode/Views/Utilities/VisualUIBuilder/AddArtboardSheet.swift` | GENUINELY_MISSING | 2 | 0 |  |
| `SwiftCode/Views/Utilities/VisualUIBuilder/ArtboardSimulator.swift` | GENUINELY_MISSING | 2 | 0 |  |
| `SwiftCode/Views/Utilities/VisualUIBuilder/CodeForArtboard.swift` | GENUINELY_MISSING | 1 | 0 |  |
| `SwiftCode/Views/Utilities/VisualUIBuilder/PreviewLogsView.swift` | GENUINELY_MISSING | 2 | 0 |  |
| `SwiftCode/Views/Utilities/VisualUIBuilder/RunFullAppView.swift` | GENUINELY_MISSING | 1 | 0 |  |
| `SwiftCode/Views/Utilities/VisualUIBuilder/VisualUIAIAssistant.swift` | GENUINELY_MISSING | 1 | 0 |  |
| `SwiftCode/Views/Utilities/VisualUIBuilder/VisualUIAnimationsPanel.swift` | GENUINELY_MISSING | 1 | 0 |  |
| `SwiftCode/Views/Utilities/VisualUIBuilder/VisualUIAssetsPanel.swift` | GENUINELY_MISSING | 1 | 0 |  |
| `SwiftCode/Views/Utilities/VisualUIBuilder/VisualUIBindingsPanel.swift` | GENUINELY_MISSING | 1 | 0 |  |
| `SwiftCode/Views/Utilities/VisualUIBuilder/VisualUIBuilderSidebarViewController.swift` | GENUINELY_MISSING | 4 | 0 |  |
| `SwiftCode/Views/Utilities/VisualUIBuilder/VisualUIBuilderSplitViewController.swift` | GENUINELY_MISSING | 5 | 0 |  |
| `SwiftCode/Views/Utilities/VisualUIBuilder/VisualUIBuilderView.swift` | GENUINELY_MISSING | 1 | 0 |  |
| `SwiftCode/Views/Utilities/VisualUIBuilder/VisualUIBuilderWindowManager.swift` | GENUINELY_MISSING | 1 | 0 |  |
| `SwiftCode/Views/Utilities/VisualUIBuilder/VisualUICanvasView.swift` | GENUINELY_MISSING | 6 | 0 |  |
| `SwiftCode/Views/Utilities/VisualUIBuilder/VisualUICodePanel.swift` | GENUINELY_MISSING | 1 | 0 |  |
| `SwiftCode/Views/Utilities/VisualUIBuilder/VisualUIComponentLibrary.swift` | GENUINELY_MISSING | 2 | 0 |  |
| `SwiftCode/Views/Utilities/VisualUIBuilder/VisualUIExportView.swift` | GENUINELY_MISSING | 1 | 0 |  |
| `SwiftCode/Views/Utilities/VisualUIBuilder/VisualUIHierarchy.swift` | GENUINELY_MISSING | 2 | 0 |  |
| `SwiftCode/Views/Utilities/VisualUIBuilder/VisualUIInspector.swift` | GENUINELY_MISSING | 1 | 0 |  |
| `SwiftCode/Views/Utilities/VisualUIBuilder/VisualUILayersPanel.swift` | GENUINELY_MISSING | 2 | 0 |  |
| `SwiftCode/Views/Utilities/VisualUIBuilder/VisualUINavigationPanel.swift` | GENUINELY_MISSING | 1 | 0 |  |
| `SwiftCode/Views/Utilities/VisualUIBuilder/VisualUIPreviewPanel.swift` | GENUINELY_MISSING | 2 | 0 |  |
| `SwiftCode/Views/Utilities/VisualUIBuilder/VisualUIPropertiesPanel.swift` | GENUINELY_MISSING | 1 | 0 |  |
| `SwiftCode/Views/Utilities/VisualUIBuilder/VisualUIRenderer.swift` | GENUINELY_MISSING | 1 | 0 |  |
| `SwiftCode/Views/Utilities/VisualUIBuilder/VisualUISettings.swift` | GENUINELY_MISSING | 1 | 0 |  |
| `SwiftCode/Views/Utilities/VisualUIBuilder/VisualUITemplatesView.swift` | GENUINELY_MISSING | 4 | 0 |  |
| `SwiftCode/Views/Utilities/VisualUIBuilder/VisualUIToolbar.swift` | GENUINELY_MISSING | 1 | 0 |  |

## GENUINELY_MISSING (actual remaining work)

- `SwiftCode/Backend/Assist/API/Internal API/Reverse/ReverseEvidenceProcessor.swift`
- `SwiftCode/Backend/Assist/AgentContextManager.swift`
- `SwiftCode/Backend/Assist/Assist Frameworks/AssistContextDriftDetector.swift`
- `SwiftCode/Backend/Assist/Assist Frameworks/AssistGoalExpansionEngine.swift`
- `SwiftCode/Backend/Assist/Assist Frameworks/AssistMemoryConsistencyValidator.swift`
- `SwiftCode/Backend/Assist/Assist Frameworks/AssistOptimizationEngine.swift`
- `SwiftCode/Backend/Assist/Assist Frameworks/AssistPerformanceProfilingEngine.swift`
- `SwiftCode/Backend/Assist/Assist Frameworks/AssistResourceUsageMonitor.swift`
- `SwiftCode/Backend/Assist/Assist Frameworks/AssistRuntimeBehaviorMonitor.swift`
- `SwiftCode/Backend/Assist/Assist Frameworks/AssistTaskContinuationEngine.swift`
- `SwiftCode/Backend/Assist/Assist Frameworks/Google Cloud SDK/GoogleCloudSDKBridge.swift`
- `SwiftCode/Backend/Assist/Assist Frameworks/Google Cloud SDK/GoogleCloudSDKError.swift`
- `SwiftCode/Backend/Assist/Assist Frameworks/Google Cloud SDK/GoogleCloudSDKEvent.swift`
- `SwiftCode/Backend/Assist/Assist Frameworks/Google Cloud SDK/GoogleCloudSDKMessage.swift`
- `SwiftCode/Backend/Assist/Assist Frameworks/Google Cloud SDK/GoogleCloudSDKProcess.swift`
- `SwiftCode/Backend/Assist/Assist Frameworks/Google Cloud SDK/GoogleCloudSDKRuntime.swift`
- `SwiftCode/Backend/Assist/Assist Frameworks/Google Cloud SDK/GoogleCloudSDKSession.swift`
- `SwiftCode/Backend/Assist/Assist Frameworks/Google Cloud SDK/GoogleCloudSDKTool.swift`
- `SwiftCode/Backend/Assist/Assist Frameworks/Google Cloud SDK/GoogleCloudSDKTransport.swift`
- `SwiftCode/Backend/Assist/Assist Frameworks/_AssistCriticalAutonomousEngine.swift`
- `SwiftCode/Backend/Assist/Assist Frameworks/_AssistCriticalExecutionEngine.swift`
- `SwiftCode/Backend/Assist/Assist Frameworks/_AssistCriticalTaskOrchestrator.swift`
- `SwiftCode/Backend/Assist/Assist Frameworks/_AssistCriticalValidationEngine.swift`
- `SwiftCode/Backend/Assist/AssistFeedbackService.swift`
- `SwiftCode/Backend/Assist/AssistParallelExecutionEngine.swift`
- `SwiftCode/Backend/Assist/AssistSystemPromptSections.swift`
- `SwiftCode/Backend/Assist/AssistToolKnowledgeValidator.swift`
- `SwiftCode/Backend/Assist/Subagents/Context/WorkerContextBuilder.swift`
- `SwiftCode/Backend/Assist/Subagents/Context/WorkerTaskDecomposer.swift`
- `SwiftCode/Backend/Assist/Subagents/Coordination/WorkerScheduler.swift`
- `SwiftCode/Backend/Assist/Subagents/Engine/WorkerEngine.swift`
- `SwiftCode/Backend/Assist/Subagents/Engine/WorkerEventBus.swift`
- `SwiftCode/Backend/Assist/Subagents/Engine/WorkerFileTracker.swift`
- `SwiftCode/Backend/Assist/Subagents/Engine/WorkerRuntimeState.swift`
- `SwiftCode/Backend/Assist/Subagents/Models/WorkerEvent.swift`
- `SwiftCode/Backend/Assist/Subagents/Models/WorkerModelSelector.swift`
- `SwiftCode/Backend/Assist/Subagents/Persistence/WorkerPersistenceStore.swift`
- `SwiftCode/Backend/Assist/Subagents/Recovery/WorkerHandoffCoordinator.swift`
- `SwiftCode/Backend/Assist/Subagents/Recovery/WorkerRecoveryEngine.swift`
- `SwiftCode/Backend/Assist/Subagents/Review/WorkerRecapGenerator.swift`
- `SwiftCode/Backend/Assist/Subagents/Review/WorkerReviewEngine.swift`
- `SwiftCode/Backend/Assist/Subagents/UI/WorkerStopConfirmationSheet.swift`
- `SwiftCode/Backend/Assist/Subagents/UI/WorkersHeaderButton.swift`
- `SwiftCode/Backend/Assist/Subagents/UI/WorkersInfoView.swift`
- `SwiftCode/Backend/Assist/Subagents/UI/WorkersMainView.swift`
- `SwiftCode/Backend/Assist/Subagents/UI/WorkersOnAssistView.swift`
- `SwiftCode/Backend/Codex/CodexBridgeManager.swift`
- `SwiftCode/Backend/GitHub/BuildingSystemAPI.swift`
- `SwiftCode/Backend/GitHub/GitHubImport.swift`
- `SwiftCode/Backend/Offline Models/MLXSwift Foundation/MLXIntegration.swift`
- `SwiftCode/Backend/Offline Models/MLXSwift Foundation/MLXModelContainer.swift`
- `SwiftCode/Backend/Offline Models/OfflineModelRunner.swift`
- `SwiftCode/Backend/On Device Intelligence/AppleIntelligenceService.swift`
- `SwiftCode/Backend/On Device Intelligence/DeviceUtilityManager.swift`
- `SwiftCode/Backend/On Device Intelligence/OnDeviceAIManager.swift`
- `SwiftCode/Backend/On Device Intelligence/OnDeviceCapabilities.swift`
- `SwiftCode/Backend/On Device Intelligence/OnDeviceModelRouter.swift`
- `SwiftCode/Backend/On Device Intelligence/OnDeviceSession.swift`
- `SwiftCode/Core/AI/Agent/AgentSystemInitializer.swift`
- `SwiftCode/Features/AdvancedTools/Views/AdvancedToolsDesignSystem.swift`
- `SwiftCode/Features/AdvancedTools/Views/DocumentationAIInsightsView.swift`
- `SwiftCode/Features/AdvancedTools/Views/DocumentationAIScanView.swift`
- `SwiftCode/Frameworks/Diff/DiffEngine.swift`
- `SwiftCode/Resources/Google Cloud SDK/README.md`
- `SwiftCode/Resources/Google Cloud SDK/bridge/__init__.py`
- `SwiftCode/Resources/Google Cloud SDK/bridge/agent_runner.py`
- `SwiftCode/Resources/Google Cloud SDK/bridge/gemini_auth_test.py`
- `SwiftCode/Resources/Google Cloud SDK/bridge/main.py`
- `SwiftCode/Resources/Google Cloud SDK/bridge/model_adapter_server.py`
- `SwiftCode/Resources/Google Cloud SDK/bridge/protocol.py`
- `SwiftCode/Resources/Google Cloud SDK/bridge/session_auth_test.py`
- `SwiftCode/Resources/Google Cloud SDK/requirements.txt`
- `SwiftCode/Resources/Google Cloud SDK/skills/swift_development/SKILL.md`
- `SwiftCode/Services/AgentSkillManager.swift`
- `SwiftCode/Services/ComposioService.swift`
- `SwiftCode/Services/ProjectFilesExtracter.swift`
- `SwiftCode/Services/SoundManager.swift`
- `SwiftCode/Services/ToolbarSettings.swift`
- `SwiftCode/Shared/Markdown/MarkdownBlockRenderer.swift`
- `SwiftCode/Tools/generate_app_icons.swift`
- `SwiftCode/UI/Utilities/SFSymbolBrowserView.swift`
- `SwiftCode/Views/AdvancedTools/Views/MainToolsView.swift`
- `SwiftCode/Views/Assist/AntigravityLimitsModelsUI.swift`
- `SwiftCode/Views/Assist/AssistSpeechUI.swift`
- `SwiftCode/Views/Assist/ReverseFillOutView.swift`
- `SwiftCode/Views/Build/LocalBuildDemoView.swift`
- `SwiftCode/Views/Build/Xcode Build/AppleSignInManager.swift`
- `SwiftCode/Views/Build/Xcode Build/AppleSignInView.swift`
- `SwiftCode/Views/Build/Xcode Build/IPABuildView.swift`
- `SwiftCode/Views/Collaboration/ActivityLogView.swift`
- `SwiftCode/Views/Collaboration/CollaborationAuditLogView.swift`
- `SwiftCode/Views/Collaboration/CollaborationChatView.swift`
- `SwiftCode/Views/Collaboration/CollaborationDashboardView.swift`
- `SwiftCode/Views/Collaboration/CollaborationFeedbackView.swift`
- `SwiftCode/Views/Collaboration/CollaborationFilePresenceOverlay.swift`
- `SwiftCode/Views/Collaboration/CollaborationMainView.swift`
- `SwiftCode/Views/Collaboration/CollaborationNotificationCenterView.swift`
- `SwiftCode/Views/Collaboration/CollaborationSidebarView.swift`
- `SwiftCode/Views/Collaboration/FilePermissionView.swift`
- `SwiftCode/Views/Collaboration/InviteMembersView.swift`
- `SwiftCode/Views/Collaboration/MemberManagementView.swift`
- `SwiftCode/Views/Dev Tools/AppReceiptInspectorDevToolView.swift`
- `SwiftCode/Views/Dev Tools/BarcodeGeneratorDevToolView.swift`
- `SwiftCode/Views/Dev Tools/Base64FileConverterView.swift`
- `SwiftCode/Views/Dev Tools/BatteryStatusDevToolView.swift`
- `SwiftCode/Views/Dev Tools/BreakpointManagerDevToolView.swift`
- `SwiftCode/Views/Dev Tools/BundleSizeAnalyzerDevToolView.swift`
- `SwiftCode/Views/Dev Tools/CPUMonitorDevToolView.swift`
- `SwiftCode/Views/Dev Tools/CacheViewerDevToolView.swift`
- `SwiftCode/Views/Dev Tools/ClipboardInspectorDevToolView.swift`
- `SwiftCode/Views/Dev Tools/DeepLinkTesterDevToolView.swift`
- `SwiftCode/Views/Dev Tools/DesignerDevToolView.swift`
- `SwiftCode/Views/Dev Tools/DevToolsMainView.swift`
- `SwiftCode/Views/Dev Tools/DiskUsageAnalyzerDevToolView.swift`
- `SwiftCode/Views/Dev Tools/EnergyImpactMonitorDevToolView.swift`
- `SwiftCode/Views/Dev Tools/ExpandedDevTools.swift`
- `SwiftCode/Views/Dev Tools/FPSMonitorDevToolView.swift`
- `SwiftCode/Views/Dev Tools/NetworkReachabilityDevToolView.swift`
- `SwiftCode/Views/Dev Tools/QRCodeGeneratorView.swift`
- `SwiftCode/Views/Developer/BackgroundTaskMonitorView.swift`
- `SwiftCode/Views/Developer/BinaryTools/BinaryToolsViews.swift`
- `SwiftCode/Views/Developer/BuildDiagnosticsView.swift`
- `SwiftCode/Views/Developer/CacheInspectorView.swift`
- `SwiftCode/Views/Developer/ConsoleCommandRunnerView.swift`
- `SwiftCode/Views/Developer/CoreMLInspector/CoreMLInspectorView.swift`
- `SwiftCode/Views/Developer/DebugOverlaysView.swift`
- `SwiftCode/Views/Developer/DependencyHealthView.swift`
- `SwiftCode/Views/Developer/DeveloperDashboard/DeveloperDashboardView.swift`
- `SwiftCode/Views/Developer/EnvironmentSwitcherView.swift`
- `SwiftCode/Views/Developer/ErrorFrequencyTrackerView.swift`
- `SwiftCode/Views/Developer/ExtensionDebugger/ExtensionDebuggerView.swift`
- `SwiftCode/Views/Developer/GitHubAPIDebug/GitHubAPIDebugView.swift`
- `SwiftCode/Views/Developer/MemoryInspector/MemoryInspectorView.swift`
- `SwiftCode/Views/Developer/MemoryLeakDetectionView.swift`
- `SwiftCode/Views/Developer/PerformanceMonitor/PerformanceMonitorView.swift`
- `SwiftCode/Views/Developer/PermissionsCheckerView.swift`
- `SwiftCode/Views/Developer/RealtimeMetricsDashboardView.swift`
- `SwiftCode/Views/Developer/RuntimeFlags/RuntimeFlagsView.swift`
- `SwiftCode/Views/Developer/StateInspectorView.swift`
- `SwiftCode/Views/Developer/ThreadInspector/ThreadInspectorView.swift`
- `SwiftCode/Views/Developer/Virtualization/AppKit/VirtualizationCoordinator.swift`
- `SwiftCode/Views/Developer/Virtualization/AppKit/VirtualizationSplitViewController.swift`
- `SwiftCode/Views/Developer/Virtualization/Core/VirtualMachineController.swift`
- `SwiftCode/Views/Developer/Virtualization/Core/VirtualizationEventBus.swift`
- `SwiftCode/Views/Developer/Virtualization/Core/VirtualizationRuntime.swift`
- `SwiftCode/Views/Developer/Virtualization/Managers/SnapshotManager.swift`
- `SwiftCode/Views/Developer/Virtualization/Managers/VMBackupManager.swift`
- `SwiftCode/Views/Developer/Virtualization/Managers/VMImageManager.swift`
- `SwiftCode/Views/Developer/Virtualization/Managers/VMMonitoringManager.swift`
- `SwiftCode/Views/Developer/Virtualization/Managers/VMNetworkManager.swift`
- `SwiftCode/Views/Developer/Virtualization/Managers/VMSharedFolderManager.swift`
- `SwiftCode/Views/Developer/Virtualization/Models/EnvironmentProfile.swift`
- `SwiftCode/Views/Developer/Virtualization/Models/VirtualMachineImage.swift`
- `SwiftCode/Views/Developer/Virtualization/Providers/AlpineProvider.swift`
- `SwiftCode/Views/Developer/Virtualization/Providers/DebianProvider.swift`
- `SwiftCode/Views/Developer/Virtualization/Providers/FedoraProvider.swift`
- `SwiftCode/Views/Developer/Virtualization/Providers/OperatingSystemProvider.swift`
- `SwiftCode/Views/Developer/Virtualization/Providers/UbuntuProvider.swift`
- `SwiftCode/Views/Developer/Virtualization/Services/VirtualizationService.swift`
- `SwiftCode/Views/Developer/Virtualization/UI/CreateVirtualMachineWizardView.swift`
- `SwiftCode/Views/Developer/Virtualization/UI/EnvironmentProfilesView.swift`
- `SwiftCode/Views/Developer/Virtualization/UI/OperatingSystemProviderView.swift`
- `SwiftCode/Views/Developer/Virtualization/UI/VirtualMachineConsoleView.swift`
- `SwiftCode/Views/Developer/Virtualization/UI/VirtualMachineDetailView.swift`
- `SwiftCode/Views/Developer/Virtualization/UI/VirtualMachineMonitorView.swift`
- `SwiftCode/Views/Developer/Virtualization/UI/VirtualMachineNetworkView.swift`
- `SwiftCode/Views/Developer/Virtualization/UI/VirtualMachineSettingsView.swift`
- `SwiftCode/Views/Developer/Virtualization/UI/VirtualMachineSharedFoldersView.swift`
- `SwiftCode/Views/Developer/Virtualization/UI/VirtualMachineSnapshotsView.swift`
- `SwiftCode/Views/Developer/Virtualization/UI/VirtualMachineStorageView.swift`
- `SwiftCode/Views/Developer/Virtualization/UI/VirtualMachineTerminalView.swift`
- `SwiftCode/Views/Developer/Virtualization/UI/VirtualizationDashboardView.swift`
- `SwiftCode/Views/Developer/Virtualization/UI/VirtualizationImageBrowserView.swift`
- `SwiftCode/Views/Developer/Virtualization/UI/VirtualizationPreferencesView.swift`
- `SwiftCode/Views/Developer/Virtualization/UI/VirtualizationSidebarView.swift`
- `SwiftCode/Views/Developer/Virtualization/UI/VirtualizationWorkspaceView.swift`
- `SwiftCode/Views/Developer/WebViewDebugger/WebViewDebuggerView.swift`
- `SwiftCode/Views/GitHub/DiscussionsView.swift`
- `SwiftCode/Views/GitHub/Menu Bar/MenuBarManager.swift`
- `SwiftCode/Views/GitHub/RepositoryAutomationBuilderView.swift`
- `SwiftCode/Views/GitHub/SwiftCodeWorkflows/WorkflowExecutionView.swift`
- `SwiftCode/Views/GitHub/SwiftCodeWorkflows/WorkflowModels.swift`
- `SwiftCode/Views/GitHub/SwiftCodeWorkflows/WorkflowTemplates.swift`
- `SwiftCode/Views/GitHub/SwiftCodeWorkflows/WorkflowsCreateView.swift`
- `SwiftCode/Views/Settings/AllowedTerminalCommandsView.swift`
- `SwiftCode/Views/Settings/Skills/DraftSkillWithAIView.swift`
- `SwiftCode/Views/Settings/SoundPickerView.swift`
- `SwiftCode/Views/Settings/SoundPreviewView.swift`
- `SwiftCode/Views/Settings/UpdateWindowView.swift`
- `SwiftCode/Views/Transfer Projects/DevicePickerView.swift`
- `SwiftCode/Views/Transfer Projects/IncomingTransferView.swift`
- `SwiftCode/Views/Transfer Projects/PermissionConfigView.swift`
- `SwiftCode/Views/Transfer Projects/TransferProgressView.swift`
- `SwiftCode/Views/Transfer Projects/TransferProjectsHomeView.swift`
- `SwiftCode/Views/Utilities/Database/Core/DatabaseCache.swift`
- `SwiftCode/Views/Utilities/Database/Core/DatabaseConnectionManager.swift`
- `SwiftCode/Views/Utilities/Database/Core/DatabaseManager.swift`
- `SwiftCode/Views/Utilities/Database/Core/DatabaseSchemaManager.swift`
- `SwiftCode/Views/Utilities/Database/Core/DatabaseSyncManager.swift`
- `SwiftCode/Views/Utilities/Database/Core/DatabaseValidationManager.swift`
- `SwiftCode/Views/Utilities/Database/DatabaseExplorerSidebarViewController.swift`
- `SwiftCode/Views/Utilities/Database/DatabaseExplorerSplitViewController.swift`
- `SwiftCode/Views/Utilities/Database/Helpers/DatabaseConstants.swift`
- `SwiftCode/Views/Utilities/Database/Helpers/DatabaseFormatter.swift`
- `SwiftCode/Views/Utilities/Database/Helpers/DatabaseValidators.swift`
- `SwiftCode/Views/Utilities/Database/Views/DatabaseConnectionWizard.swift`
- `SwiftCode/Views/Utilities/Database/Views/DatabaseConnectionsView.swift`
- `SwiftCode/Views/Utilities/Database/Views/DatabaseIndexesView.swift`
- `SwiftCode/Views/Utilities/Database/Views/DatabaseInspector.swift`
- `SwiftCode/Views/Utilities/Database/Views/DatabasePermissionsView.swift`
- `SwiftCode/Views/Utilities/Database/Views/DatabaseQueryEditor.swift`
- `SwiftCode/Views/Utilities/Database/Views/DatabaseRecordEditor.swift`
- `SwiftCode/Views/Utilities/Database/Views/DatabaseRecordViewer.swift`
- `SwiftCode/Views/Utilities/Database/Views/DatabaseRelationshipEditor.swift`
- `SwiftCode/Views/Utilities/Database/Views/DatabaseSchemaGenerator.swift`
- `SwiftCode/Views/Utilities/Database/Views/DatabaseSchemaView.swift`
- `SwiftCode/Views/Utilities/Database/Views/DatabaseSettingsView.swift`
- `SwiftCode/Views/Utilities/Database/Views/DatabaseSidebar.swift`
- `SwiftCode/Views/Utilities/Database/Views/DatabaseTableEditor.swift`
- `SwiftCode/Views/Utilities/Database/Views/DatabaseTablesView.swift`
- `SwiftCode/Views/Utilities/SFSymbolPickerView.swift`
- `SwiftCode/Views/Utilities/VisualUIBuilder/AddArtboardSheet.swift`
- `SwiftCode/Views/Utilities/VisualUIBuilder/ArtboardSimulator.swift`
- `SwiftCode/Views/Utilities/VisualUIBuilder/CodeForArtboard.swift`
- `SwiftCode/Views/Utilities/VisualUIBuilder/PreviewLogsView.swift`
- `SwiftCode/Views/Utilities/VisualUIBuilder/RunFullAppView.swift`
- `SwiftCode/Views/Utilities/VisualUIBuilder/VisualUIAIAssistant.swift`
- `SwiftCode/Views/Utilities/VisualUIBuilder/VisualUIAnimationsPanel.swift`
- `SwiftCode/Views/Utilities/VisualUIBuilder/VisualUIAssetsPanel.swift`
- `SwiftCode/Views/Utilities/VisualUIBuilder/VisualUIBindingsPanel.swift`
- `SwiftCode/Views/Utilities/VisualUIBuilder/VisualUIBuilderSidebarViewController.swift`
- `SwiftCode/Views/Utilities/VisualUIBuilder/VisualUIBuilderSplitViewController.swift`
- `SwiftCode/Views/Utilities/VisualUIBuilder/VisualUIBuilderView.swift`
- `SwiftCode/Views/Utilities/VisualUIBuilder/VisualUIBuilderWindowManager.swift`
- `SwiftCode/Views/Utilities/VisualUIBuilder/VisualUICanvasView.swift`
- `SwiftCode/Views/Utilities/VisualUIBuilder/VisualUICodePanel.swift`
- `SwiftCode/Views/Utilities/VisualUIBuilder/VisualUIComponentLibrary.swift`
- `SwiftCode/Views/Utilities/VisualUIBuilder/VisualUIExportView.swift`
- `SwiftCode/Views/Utilities/VisualUIBuilder/VisualUIHierarchy.swift`
- `SwiftCode/Views/Utilities/VisualUIBuilder/VisualUIInspector.swift`
- `SwiftCode/Views/Utilities/VisualUIBuilder/VisualUILayersPanel.swift`
- `SwiftCode/Views/Utilities/VisualUIBuilder/VisualUINavigationPanel.swift`
- `SwiftCode/Views/Utilities/VisualUIBuilder/VisualUIPreviewPanel.swift`
- `SwiftCode/Views/Utilities/VisualUIBuilder/VisualUIPropertiesPanel.swift`
- `SwiftCode/Views/Utilities/VisualUIBuilder/VisualUIRenderer.swift`
- `SwiftCode/Views/Utilities/VisualUIBuilder/VisualUISettings.swift`
- `SwiftCode/Views/Utilities/VisualUIBuilder/VisualUITemplatesView.swift`
- `SwiftCode/Views/Utilities/VisualUIBuilder/VisualUIToolbar.swift`
