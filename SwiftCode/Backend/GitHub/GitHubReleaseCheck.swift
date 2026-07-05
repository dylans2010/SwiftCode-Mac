import Foundation

enum GitHubReleaseCheckError: LocalizedError {
    case invalidURL
    case invalidResponse
    case serverStatus(code: Int, message: String?)
    case transportError(URLError)
    case invalidData
    case noBuildReleases

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "The GitHub updates URL is invalid."
        case .invalidResponse:
            return "Received an invalid response from GitHub."
        case let .serverStatus(code, message):
            if let message, !message.isEmpty {
                return "GitHub returned HTTP \(code): \(message)"
            }
            return "GitHub returned HTTP \(code)."
        case let .transportError(error):
            return "Network error while checking GitHub updates: \(error.localizedDescription)"
        case .invalidData:
            return "GitHub returned data in an unexpected format."
        case .noBuildReleases:
            return "No valid build-* releases were found on GitHub."
        }
    }
}

struct GitHubReleaseCheckResult {
    let latestBuildNumber: Int
    let latestTag: String
    let releaseURL: URL?

    func isUpdateAvailable(currentBuild: Int) -> Bool {
        latestBuildNumber > currentBuild
    }
}

final class GitHubReleaseCheck {
    static let shared = GitHubReleaseCheck()
    private init() {}

    private let session = URLSession.shared
    private let buildPattern = #"build-(\d+)"#

    func checkLatestBuild(owner: String = "dylans2010", repo: String = "SwiftCode") async throws -> GitHubReleaseCheckResult {
        var components = URLComponents(string: "https://api.github.com/repos/\(owner)/\(repo)/releases")
        components?.queryItems = [URLQueryItem(name: "per_page", value: "30")]

        guard let url = components?.url else {
            throw GitHubReleaseCheckError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("SwiftCode", forHTTPHeaderField: "User-Agent")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let urlError as URLError {
            throw GitHubReleaseCheckError.transportError(urlError)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw GitHubReleaseCheckError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            let apiErrorMessage = try? JSONDecoder().decode(GitHubAPIErrorDTO.self, from: data).message
            throw GitHubReleaseCheckError.serverStatus(code: httpResponse.statusCode, message: apiErrorMessage)
        }

        let releases: [GitHubReleaseDTO]
        do {
            releases = try JSONDecoder().decode([GitHubReleaseDTO].self, from: data)
        } catch {
            throw GitHubReleaseCheckError.invalidData
        }

        let stableReleases = releases.filter { !$0.draft && !$0.prerelease }

        let parsed = stableReleases.compactMap { release -> (Int, GitHubReleaseDTO)? in
            guard let build = extractBuildNumber(from: release.tagName) else { return nil }
            return (build, release)
        }

        guard let latest = parsed.max(by: { $0.0 < $1.0 }) else {
            throw GitHubReleaseCheckError.noBuildReleases
        }

        return GitHubReleaseCheckResult(
            latestBuildNumber: latest.0,
            latestTag: latest.1.tagName,
            releaseURL: latest.1.htmlURL.flatMap(URL.init(string:))
        )
    }

    private func extractBuildNumber(from tag: String) -> Int? {
        guard let regex = try? NSRegularExpression(pattern: buildPattern, options: [.caseInsensitive]) else {
            return nil
        }

        let range = NSRange(location: 0, length: tag.utf16.count)
        guard let match = regex.firstMatch(in: tag, options: [], range: range),
              let valueRange = Range(match.range(at: 1), in: tag) else {
            return nil
        }

        return Int(tag[valueRange])
    }
}

private struct GitHubReleaseDTO: Decodable {
    let tagName: String
    let htmlURL: String?
    let draft: Bool
    let prerelease: Bool

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case htmlURL = "html_url"
        case draft
        case prerelease
    }
}

private struct GitHubAPIErrorDTO: Decodable {
    let message: String
}
