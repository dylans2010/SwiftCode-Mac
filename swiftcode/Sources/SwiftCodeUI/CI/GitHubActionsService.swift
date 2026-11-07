import Foundation
import SwiftCodeAssistant
import SwiftCodeGitHub

public struct GitHubActionsService: Sendable {
    public var session: URLSession
    public var store: SecretStore

    public init(session: URLSession = .shared, store: SecretStore) {
        self.session = session
        self.store = store
    }

    public var token: String? {
        store.readString(SecretAccount.githubToken)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func request(path: String, method: String = "GET", body: Data? = nil) -> URLRequest {
        var request = URLRequest(url: URL(string: "https://api.github.com/\(path)")!)
        request.httpMethod = method
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        if let token, !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        return request
    }

    func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(type, from: data)
    }

    public func listRuns(owner: String, repo: String, perPage: Int = 30) async throws -> [GitHubWorkflowRun] {
        let (data, response) = try await session.data(for: request(path: "repos/\(owner)/\(repo)/actions/runs?per_page=\(perPage)"))
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw GitHubActionsError.requestFailed("Could not list workflow runs for \(owner)/\(repo) (HTTP \((response as? HTTPURLResponse)?.statusCode ?? -1)).")
        }
        return try decode(GitHubWorkflowRunsResponse.self, from: data).workflowRuns
    }

    public func listJobs(owner: String, repo: String, runID: Int) async throws -> [GitHubWorkflowJob] {
        let (data, response) = try await session.data(for: request(path: "repos/\(owner)/\(repo)/actions/runs/\(runID)/jobs"))
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw GitHubActionsError.requestFailed("Could not list jobs for run \(runID) (HTTP \((response as? HTTPURLResponse)?.statusCode ?? -1)).")
        }
        return try decode(GitHubWorkflowJobsResponse.self, from: data).jobs
    }

    public func jobLogs(owner: String, repo: String, jobID: Int) async throws -> String {
        let (data, response) = try await session.data(for: request(path: "repos/\(owner)/\(repo)/actions/jobs/\(jobID)/logs"))
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw GitHubActionsError.requestFailed("Could not fetch logs for job \(jobID) (HTTP \((response as? HTTPURLResponse)?.statusCode ?? -1)).")
        }
        return String(decoding: data, as: UTF8.self)
    }

    public func listWorkflows(owner: String, repo: String) async throws -> [GitHubWorkflow] {
        let (data, response) = try await session.data(for: request(path: "repos/\(owner)/\(repo)/actions/workflows"))
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw GitHubActionsError.requestFailed("Could not list workflows for \(owner)/\(repo) (HTTP \((response as? HTTPURLResponse)?.statusCode ?? -1)).")
        }
        return try decode(GitHubWorkflowsResponse.self, from: data).workflows
    }

    public func rerun(owner: String, repo: String, runID: Int) async throws {
        guard let token, !token.isEmpty else {
            throw GitHubActionsError.missingToken
        }
        let (_, response) = try await session.data(for: request(path: "repos/\(owner)/\(repo)/actions/runs/\(runID)/rerun", method: "POST"))
        guard let http = response as? HTTPURLResponse, (200...204).contains(http.statusCode) else {
            throw GitHubActionsError.requestFailed("Could not re-run \(runID) (HTTP \((response as? HTTPURLResponse)?.statusCode ?? -1)).")
        }
    }
}

public enum GitHubActionsError: Error, LocalizedError, Equatable {
    case missingToken
    case requestFailed(String)

    public var errorDescription: String? {
        switch self {
        case .missingToken:
            return "Re-running a workflow needs a GitHub token. Add one in Settings ▸ Coding Assistant."
        case .requestFailed(let message):
            return message
        }
    }
}

public struct GitHubWorkflowRun: Codable, Sendable, Equatable, Identifiable {
    public var id: Int
    public var name: String?
    public var status: String?
    public var conclusion: String?
    public var headBranch: String?
    public var headSha: String?
    public var event: String?
    public var createdAt: Date?
    public var htmlUrl: String?

    public init(id: Int, name: String? = nil, status: String? = nil, conclusion: String? = nil,
                headBranch: String? = nil, headSha: String? = nil, event: String? = nil,
                createdAt: Date? = nil, htmlUrl: String? = nil) {
        self.id = id
        self.name = name
        self.status = status
        self.conclusion = conclusion
        self.headBranch = headBranch
        self.headSha = headSha
        self.event = event
        self.createdAt = createdAt
        self.htmlUrl = htmlUrl
    }
}

struct GitHubWorkflowRunsResponse: Codable {
    var workflowRuns: [GitHubWorkflowRun]
}

public struct GitHubWorkflowJob: Codable, Sendable, Equatable, Identifiable {
    public var id: Int
    public var name: String?
    public var status: String?
    public var conclusion: String?
    public var steps: [GitHubWorkflowStep]?

    public init(id: Int, name: String? = nil, status: String? = nil, conclusion: String? = nil,
                steps: [GitHubWorkflowStep]? = nil) {
        self.id = id
        self.name = name
        self.status = status
        self.conclusion = conclusion
        self.steps = steps
    }
}

public struct GitHubWorkflowStep: Codable, Sendable, Equatable {
    public var name: String?
    public var status: String?
    public var conclusion: String?
    public var number: Int?

    public init(name: String? = nil, status: String? = nil, conclusion: String? = nil, number: Int? = nil) {
        self.name = name
        self.status = status
        self.conclusion = conclusion
        self.number = number
    }
}

struct GitHubWorkflowJobsResponse: Codable {
    var jobs: [GitHubWorkflowJob]
}

public struct GitHubWorkflow: Codable, Sendable, Equatable, Identifiable {
    public var id: Int
    public var name: String?
    public var path: String?
    public var state: String?

    public init(id: Int, name: String? = nil, path: String? = nil, state: String? = nil) {
        self.id = id
        self.name = name
        self.path = path
        self.state = state
    }
}

struct GitHubWorkflowsResponse: Codable {
    var workflows: [GitHubWorkflow]
}
