import AppKit
import Foundation
import Testing
import SwiftCodeAssistant
import SwiftCodeExtensions
@testable import SwiftCodeMCP
@testable import SwiftCodeUI

@Suite("Wave 17 follow-up gap tests")
struct Wave17FollowUpGapTests {

    @Suite("Deployment service", .serialized)
    struct DeploymentServiceTests {
        @Test("No token stored means no token for either platform")
        func tokenNilWithoutStoredToken() {
            let service = DeploymentService(store: MemorySecretStore())
            #expect(service.token(for: .netlify) == nil)
            #expect(service.token(for: .vercel) == nil)
        }

        @Test("Deploy without a token fails honestly")
        func deployWithoutTokenFailsHonestly() async {
            let service = DeploymentService(store: MemorySecretStore())
            let folder = FileManager.default.temporaryDirectory
                .appendingPathComponent("swiftcode-deploy-test-\(UUID().uuidString)")
            await #expect(throws: DeploymentError.missingToken(.netlify)) {
                try await service.deploy(platform: .netlify, workspaceFolder: folder, domain: nil) { _ in }
            }
        }

        @Test("Deploy with a token but no git repository fails honestly")
        func deployWithoutGitRepositoryFailsHonestly() async throws {
            let store = MemorySecretStore()
            try store.write(Data("netlify-token".utf8), for: DeploymentPlatform.netlify.tokenAccount)
            let service = DeploymentService(store: store)
            let folder = FileManager.default.temporaryDirectory
                .appendingPathComponent("swiftcode-deploy-test-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: folder) }
            await #expect(throws: DeploymentError.noGitRepository) {
                try await service.deploy(platform: .netlify, workspaceFolder: folder, domain: nil) { _ in }
            }
        }
    }

    @Suite("GitHub Actions service", .serialized)
    struct GitHubActionsServiceTests {
        private func stubSession(handler: @escaping (URLRequest) -> (status: Int, headers: [String: String], body: Data)) -> URLSession {
            CloudAccountsStubURLProtocol.requests = []
            CloudAccountsStubURLProtocol.handler = handler
            return CloudAccountsStubURLProtocol.stubSession()
        }

        @Test("listRuns decodes the runs from the API response")
        func listRunsDecodes() async throws {
            let session = stubSession { _ in
                CloudAccountsStubURLProtocol.ok("""
                {"total_count":2,"workflow_runs":[
                {"id":1,"name":"CI","status":"completed","conclusion":"success","head_branch":"main","head_sha":"abc","event":"push","created_at":"2026-11-06T00:00:00Z","html_url":"https://example.com/1"},
                {"id":2,"name":"CI","status":"in_progress","conclusion":null,"head_branch":"main","head_sha":"def","event":"push","created_at":"2026-11-06T01:00:00Z","html_url":"https://example.com/2"}]}
                """)
            }
            defer { CloudAccountsStubURLProtocol.handler = nil }
            let service = GitHubActionsService(session: session, store: MemorySecretStore())
            let runs = try await service.listRuns(owner: "octo", repo: "demo")
            #expect(runs.count == 2)
            #expect(runs[0].id == 1)
            #expect(runs[0].status == "completed")
            #expect(runs[0].conclusion == "success")
            #expect(runs[1].status == "in_progress")
            #expect(runs[1].conclusion == nil)
            #expect(CloudAccountsStubURLProtocol.requests.count == 1)
            #expect(CloudAccountsStubURLProtocol.requests[0].url?.path.contains("actions/runs") == true)
        }

        @Test("listRuns throws on a non-200 response")
        func listRunsThrowsOnError() async throws {
            let session = stubSession { _ in
                (401, [:], Data("{\"message\":\"Bad credentials\"}".utf8))
            }
            defer { CloudAccountsStubURLProtocol.handler = nil }
            let service = GitHubActionsService(session: session, store: MemorySecretStore())
            await #expect(throws: GitHubActionsError.self) {
                try await service.listRuns(owner: "octo", repo: "demo")
            }
        }
    }

    @Suite("Virtual machine registry")
    struct VirtualMachineRegistryTests {
        @Test("An unknown id has no record")
        func unknownIDHasNoRecord() {
            let registry = VirtualMachineRegistry()
            #expect(registry.record(id: UUID()) == nil)
        }

        @Test("Create, find, and delete round-trips through the store")
        func createFindDeleteRoundTrip() throws {
            let registry = VirtualMachineRegistry()
            let record = try registry.create(name: "Wave17GapTest VM", osType: "macOS", version: "26.0")
            defer { try? registry.delete(id: record.id) }
            #expect(registry.record(id: record.id)?.name == "Wave17GapTest VM")
            #expect(registry.record(id: record.id)?.status == "Stopped")

            let reloaded = VirtualMachineRegistry()
            #expect(reloaded.record(id: record.id)?.name == "Wave17GapTest VM")

            try registry.delete(id: record.id)
            #expect(registry.record(id: record.id) == nil)
        }

        @Test("Creating with a missing disk image fails honestly")
        func createWithMissingImageFails() {
            let registry = VirtualMachineRegistry()
            #expect(throws: VirtualMachineRegistryError.self) {
                try registry.create(name: "Wave17GapTest VM", osType: "macOS", imagePath: "/definitely/not/a/vm.img")
            }
        }
    }

    @Suite("Virtual machine host probe")
    struct VirtualMachineHostProbeTests {
        @Test("The probe reports the host honestly")
        func probeReportsHost() {
            let probe = VirtualMachineHostProbe.probe()
            #if os(macOS)
            #expect(probe.hypervisorAvailable == false)
            #expect(probe.error?.contains("KVM") == true)
            #else
            if probe.hypervisorAvailable {
                #expect(probe.vcpusAllocated == 1)
                #expect(probe.ramBytesAllocated == 256 << 20)
            } else {
                #expect(probe.error != nil)
            }
            #endif
        }
    }

    @Suite("Sandboxed command runner")
    struct SandboxedCommandRunnerTests {
        @Test("tokenize splits argv and honours quotes; an unbalanced quote is nil")
        func tokenizeSplitsAndQuotes() {
            #expect(SandboxedCommandRunner.tokenize("echo hello world") == ["echo", "hello", "world"])
            #expect(SandboxedCommandRunner.tokenize("echo 'hello world'") == ["echo", "hello world"])
            #expect(SandboxedCommandRunner.tokenize("echo \"hello world\"") == ["echo", "hello world"])
            #expect(SandboxedCommandRunner.tokenize("echo 'oops") == nil)
            #expect(SandboxedCommandRunner.tokenize("") == [])
        }

        @Test("validate rejects non-allowlisted commands, shell syntax, and mutating git")
        func validateRejects() {
            let policy = SandboxPolicy()
            #expect(throws: SandboxError.notAllowed("rm")) {
                try SandboxedCommandRunner.validate("rm -rf /", policy: policy)
            }
            #expect(throws: SandboxError.metacharacters("echo a; echo b")) {
                try SandboxedCommandRunner.validate("echo a; echo b", policy: policy)
            }
            #expect(throws: SandboxError.notAllowed("git push")) {
                try SandboxedCommandRunner.validate("git push", policy: policy)
            }
            #expect(throws: SandboxError.notAllowed("")) {
                try SandboxedCommandRunner.validate("   ", policy: policy)
            }
        }

        @Test("validate allows an allowlisted command and read-only git")
        func validateAllows() throws {
            let policy = SandboxPolicy()
            #expect(try SandboxedCommandRunner.validate("echo hello", policy: policy) == ["echo", "hello"])
            #expect(try SandboxedCommandRunner.validate("git status", policy: policy) == ["git", "status"])
        }

        @Test("run executes an allowlisted command inside the workspace")
        func runExecutesAllowlistedCommand() async throws {
            let folder = FileManager.default.temporaryDirectory
                .appendingPathComponent("swiftcode-sandbox-test-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: folder) }
            let result = try await SandboxedCommandRunner.run(
                commandLine: "echo hello", workingDirectory: folder, workspaceRoot: folder)
            #expect(result.exitCode == 0)
            #expect(result.output.contains("hello"))
            #expect(result.truncated == false)
        }

        @Test("run refuses a working directory outside the workspace")
        func runRefusesOutsideWorkspace() async throws {
            let folder = FileManager.default.temporaryDirectory
                .appendingPathComponent("swiftcode-sandbox-test-\(UUID().uuidString)")
            let outside = FileManager.default.temporaryDirectory
                .appendingPathComponent("swiftcode-sandbox-outside-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
            defer {
                try? FileManager.default.removeItem(at: folder)
                try? FileManager.default.removeItem(at: outside)
            }
            await #expect(throws: SandboxError.self) {
                try await SandboxedCommandRunner.run(
                    commandLine: "echo hello", workingDirectory: outside, workspaceRoot: folder)
            }
        }
    }

    @Suite("Extension change review presenter")
    @MainActor
    struct ExtensionChangeReviewPresenterTests {
        private func change() -> MCPChange {
            MCPChange(tool: "write", path: "/w/a", relativePath: "a", original: nil, proposed: "hello", summary: "Create a")
        }

        @Test("An injected reviewer answers instead of showing UI")
        func injectedReviewerAnswers() async {
            let presenter = ExtensionChangeReviewPresenter()
            presenter.reviewer = { _ in true }
            #expect(await presenter.review(change()) == true)
            presenter.reviewer = { _ in false }
            #expect(await presenter.review(change()) == false)
        }

        @Test("With no window to ask in, the answer is refuse")
        func noWindowRefuses() async {
            let presenter = ExtensionChangeReviewPresenter()
            presenter.windowProvider = { nil }
            #expect(await presenter.review(change()) == false)
        }

        @Test("The excerpt names new content and shows the first lines")
        func excerptShowsNewContent() {
            let excerpt = ExtensionChangeReviewPresenter.excerpt(of: change())
            #expect(excerpt.contains("New content:"))
            #expect(excerpt.contains("hello"))
            let edit = MCPChange(tool: "write", path: "/w/a", relativePath: "a", original: "old", proposed: "new", summary: "Edit a")
            #expect(ExtensionChangeReviewPresenter.excerpt(of: edit).contains("Proposed:"))
        }
    }

    @Suite("Artboards window")
    @MainActor
    struct ArtboardWindowControllerTests {
        private func workspaceFolder() throws -> URL {
            let folder = FileManager.default.temporaryDirectory
                .appendingPathComponent("swiftcode-artboard-test-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            return folder
        }

        @Test("Add, select, and delete artboards")
        func addSelectDeleteArtboards() throws {
            let folder = try workspaceFolder()
            defer {
                try? FileManager.default.removeItem(at: ArtboardStore.documentURL(forWorkspace: folder))
                try? FileManager.default.removeItem(at: folder)
            }
            let controller = ArtboardWindowController(workspaceFolder: folder)
            #expect(controller.document.artboards.isEmpty)
            let first = controller.addArtboard(name: "Home")
            #expect(controller.document.artboards.count == 1)
            #expect(controller.activeArtboard?.id == first.id)
            #expect(first.rootNode.name == "Home Root")
            let second = controller.addArtboard(name: "Settings", deviceFrame: "iPad Pro")
            #expect(controller.activeArtboard?.id == second.id)
            controller.selectArtboard(id: first.id)
            #expect(controller.activeArtboard?.id == first.id)
            controller.deleteArtboard(id: second.id)
            #expect(controller.document.artboards.count == 1)
            #expect(controller.activeArtboard?.id == first.id)
            controller.deleteArtboard(id: first.id)
            #expect(controller.document.artboards.isEmpty)
            #expect(controller.activeArtboard == nil)
        }

        @Test("Add, duplicate, and delete components")
        func addDuplicateDeleteComponents() throws {
            let folder = try workspaceFolder()
            defer {
                try? FileManager.default.removeItem(at: ArtboardStore.documentURL(forWorkspace: folder))
                try? FileManager.default.removeItem(at: folder)
            }
            let controller = ArtboardWindowController(workspaceFolder: folder)
            controller.addArtboard(name: "Home")
            let text = controller.addComponent(type: .text)
            #expect(text != nil)
            #expect(controller.activeArtboard?.rootNode.children.count == 1)
            let copy = controller.duplicateComponent(id: text!.id)
            #expect(copy != nil)
            #expect(copy?.id != text?.id)
            #expect(controller.activeArtboard?.rootNode.children.count == 2)
            controller.deleteComponent(id: copy!.id)
            #expect(controller.activeArtboard?.rootNode.children.count == 1)
            controller.deleteComponent(id: controller.activeArtboard!.rootNode.id)
            #expect(controller.activeArtboard?.rootNode.children.count == 1)
        }

        @Test("Edits save to the store and reload from it")
        func editsSaveAndReload() throws {
            let folder = try workspaceFolder()
            defer {
                try? FileManager.default.removeItem(at: ArtboardStore.documentURL(forWorkspace: folder))
                try? FileManager.default.removeItem(at: folder)
            }
            let controller = ArtboardWindowController(workspaceFolder: folder)
            controller.addArtboard(name: "Home")
            controller.updateArtboard { $0.name = "Renamed" }
            let loaded = ArtboardStore.load(forWorkspace: folder)
            #expect(loaded?.artboards.count == 1)
            #expect(loaded?.artboards.first?.name == "Renamed")
        }

        @Test("Render with no custom source says so instead of rendering nothing")
        func renderWithoutSourceSaysSo() throws {
            let folder = try workspaceFolder()
            defer {
                try? FileManager.default.removeItem(at: ArtboardStore.documentURL(forWorkspace: folder))
                try? FileManager.default.removeItem(at: folder)
            }
            let controller = ArtboardWindowController(workspaceFolder: folder)
            controller.addArtboard(name: "Home")
            controller.renderPreview()
            #expect(controller.statusText.contains("no custom SwiftUI source"))
            #expect(controller.previewImage == nil)
        }
    }

    @Suite("Extension permission approval center")
    @MainActor
    struct ExtensionPermissionApprovalCenterTests {
        private func request() -> PermissionRequest {
            PermissionRequest(extensionId: "com.example.ext", capability: .workspaceWrite, reason: "Write a file")
        }

        private func waitForPending(_ center: ExtensionPermissionApprovalCenter) async -> ExtensionPermissionRequest? {
            for _ in 0..<200 {
                if let pending = center.pendingRequest { return pending }
                try? await Task.sleep(nanoseconds: 10_000_000)
            }
            return nil
        }

        @Test("With no presenter installed, the request is denied immediately")
        func noPresenterDenies() async {
            let center = ExtensionPermissionApprovalCenter()
            #expect(await center.ask(request()) == false)
            #expect(center.pendingRequest == nil)
        }

        @Test("An approval answers true and clears the pending request")
        func approvalAnswersTrue() async {
            let center = ExtensionPermissionApprovalCenter()
            center.hasPresenter = true
            let task = Task { await center.ask(request()) }
            let pending = await waitForPending(center)
            #expect(pending != nil)
            #expect(pending?.extensionId == "com.example.ext")
            #expect(pending?.capability == .workspaceWrite)
            center.answer(id: pending!.id, approved: true)
            #expect(await task.value == true)
            #expect(center.pendingRequest == nil)
        }

        @Test("A denial answers false")
        func denialAnswersFalse() async {
            let center = ExtensionPermissionApprovalCenter()
            center.hasPresenter = true
            let task = Task { await center.ask(request()) }
            let pending = await waitForPending(center)
            center.answer(id: pending!.id, approved: false)
            #expect(await task.value == false)
            #expect(center.pendingRequest == nil)
        }

        @Test("A second request while one is pending is denied immediately, not queued")
        func secondRequestDeniedWhilePending() async {
            let center = ExtensionPermissionApprovalCenter()
            center.hasPresenter = true
            let first = Task { await center.ask(request()) }
            let pending = await waitForPending(center)
            #expect(pending != nil)
            #expect(await center.ask(request()) == false)
            center.dismissPending()
            #expect(await first.value == false)
            #expect(center.pendingRequest == nil)
        }

        @Test("Dismissing the pending request denies it")
        func dismissDenies() async {
            let center = ExtensionPermissionApprovalCenter()
            center.hasPresenter = true
            let task = Task { await center.ask(request()) }
            #expect(await waitForPending(center) != nil)
            center.dismissPending()
            #expect(await task.value == false)
            #expect(center.pendingRequest == nil)
        }

        @Test("An answer for the wrong id is ignored")
        func wrongIDAnswerIgnored() async {
            let center = ExtensionPermissionApprovalCenter()
            center.hasPresenter = true
            let task = Task { await center.ask(request()) }
            let pending = await waitForPending(center)
            center.answer(id: UUID(), approved: true)
            #expect(center.pendingRequest?.id == pending?.id)
            center.answer(id: pending!.id, approved: false)
            #expect(await task.value == false)
        }
    }

    @Suite("Extensions v2 language client")
    struct ExtV2LanguageClientTests {
        @Test("A missing server executable fails honestly before any process starts")
        func missingExecutableFails() async {
            let client = ExtV2LanguageClient()
            await #expect(throws: ExtV2LanguageClient.ClientError.executableNotFound("no-such-language-server-xyz")) {
                try await client.start(
                    server: .init(command: "no-such-language-server-xyz", language: "swift"),
                    workspaceRoot: FileManager.default.temporaryDirectory)
            }
            #expect(await client.isRunning == false)
        }

        @Test("A server that exits immediately fails at start, not on the first completion")
        func deadServerFailsAtStart() async {
            let client = ExtV2LanguageClient()
            await #expect(throws: Error.self) {
                try await client.start(
                    server: .init(command: "/usr/bin/false", language: "swift"),
                    workspaceRoot: FileManager.default.temporaryDirectory)
            }
            #expect(await client.isRunning == false)
        }
    }

}
