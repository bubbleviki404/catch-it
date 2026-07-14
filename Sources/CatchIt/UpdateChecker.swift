import Foundation

final class UpdateChecker {
    enum CheckResult {
        case upToDate(currentVersion: String)
        case updateAvailable(currentVersion: String, latestVersion: String, downloadURL: URL, notes: String?)
    }

    enum UpdateError: LocalizedError {
        case repositoryNotConfigured
        case invalidResponse
        case noPublishedRelease

        var errorDescription: String? {
            switch self {
            case .repositoryNotConfigured:
                return "更新渠道尚未配置。发布时请设置 GitHub 仓库地址。"
            case .invalidResponse:
                return "GitHub 返回了无法识别的更新信息，请稍后重试。"
            case .noPublishedRelease:
                return "GitHub 仓库中还没有可用的正式版本。"
            }
        }
    }

    private struct GitHubRelease: Decodable {
        let tagName: String
        let htmlURL: URL
        let body: String?
        let draft: Bool
        let prerelease: Bool

        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case htmlURL = "html_url"
            case body, draft, prerelease
        }
    }

    private let session: URLSession
    private let bundle: Bundle

    init(session: URLSession = .shared, bundle: Bundle = .main) {
        self.session = session
        self.bundle = bundle
    }

    var repository: String? {
        guard let value = bundle.object(forInfoDictionaryKey: "CatchItGitHubRepository") as? String else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    var repositoryURL: URL? {
        repository.flatMap { URL(string: "https://github.com/\($0)") }
    }

    func check(completion: @escaping (Result<CheckResult, Error>) -> Void) {
        guard let repository,
              let url = URL(string: "https://api.github.com/repos/\(repository)/releases/latest") else {
            completion(.failure(UpdateError.repositoryNotConfigured))
            return
        }

        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("CatchIt-Update-Checker", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 12
        session.dataTask(with: request) { [bundle] data, response, error in
            let result: Result<CheckResult, Error> = Result {
                if let error { throw error }
                guard let http = response as? HTTPURLResponse else { throw UpdateError.invalidResponse }
                if http.statusCode == 404 { throw UpdateError.noPublishedRelease }
                guard (200..<300).contains(http.statusCode), let data else { throw UpdateError.invalidResponse }
                let release = try JSONDecoder().decode(GitHubRelease.self, from: data)
                guard !release.draft, !release.prerelease else { throw UpdateError.noPublishedRelease }
                let current = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
                let latest = Self.normalizedVersion(release.tagName)
                if Self.isVersion(latest, newerThan: current) {
                    return .updateAvailable(
                        currentVersion: current,
                        latestVersion: latest,
                        downloadURL: release.htmlURL,
                        notes: release.body
                    )
                }
                return .upToDate(currentVersion: current)
            }
            DispatchQueue.main.async { completion(result) }
        }.resume()
    }

    static func normalizedVersion(_ value: String) -> String {
        var result = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if result.lowercased().hasPrefix("v") { result.removeFirst() }
        return result
    }

    static func isVersion(_ candidate: String, newerThan current: String) -> Bool {
        candidate.compare(current, options: .numeric) == .orderedDescending
    }
}
