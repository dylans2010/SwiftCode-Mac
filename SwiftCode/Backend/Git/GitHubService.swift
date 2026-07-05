import Foundation

public struct GitHubRepository: Codable, Identifiable, Sendable {
    public let id: Int
    public let name: String
    public let fullName: String
    public let cloneUrl: String
    public let isPrivate: Bool
    public let description: String?

    enum CodingKeys: String, CodingKey {
        case id, name, description
        case fullName = "full_name"
        case cloneUrl = "clone_url"
        case isPrivate = "private"
    }
}

public actor GitHubService {
    public static let shared = GitHubService()

    private init() {}

    public func fetchRepositories(token: String) async throws -> [GitHubRepository] {
        guard let url = URL(string: "https://api.github.com/user/repos?sort=updated&per_page=100") else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        request.setValue("token \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }

        let decoder = JSONDecoder()
        return try decoder.decode([GitHubRepository].self, from: data)
    }
}
