import Foundation

struct DesktopGitHubRelease: Equatable {
    let version: String
    let downloadURL: URL

    private static let repository = "akinal5765-byte/Silverphase"
    static let releasesURL = URL(string: "https://github.com/\(repository)/releases")!

    @MainActor private static var apiRetryAt: Date?

    @MainActor static func fetchLatest() async throws -> Self? {
        if let apiRetryAt, apiRetryAt > Date() {
            return try await fetchFromFeed(rateLimit: .rateLimited(apiRetryAt))
        }
        do {
            return try await fetchFromAPI()
        } catch CheckError.rateLimited(let retryAt) {
            apiRetryAt = retryAt ?? Date().addingTimeInterval(60)
            return try await fetchFromFeed(rateLimit: .rateLimited(apiRetryAt))
        }
    }

    private static func fetchFromAPI() async throws -> Self? {
        // The repository publishes mobile and desktop releases independently.
        // GitHub's single "latest" release can be an iOS-only release.
        let url = URL(string: "https://api.github.com/repos/\(repository)/releases?per_page=100")!
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        return try parse(data, response: http)
    }

    private static func fetchFromFeed(rateLimit: CheckError) async throws -> Self? {
        do {
            let feed = URL(string: releasesURL.absoluteString + ".atom")!
            let (data, response) = try await URLSession.shared.data(for: URLRequest(url: feed, timeoutInterval: 10))
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw rateLimit }
            for release in feedCandidates(in: data) {
                var request = URLRequest(url: release.downloadURL, timeoutInterval: 10)
                request.httpMethod = "HEAD"
                let (_, response) = try await URLSession.shared.data(for: request)
                guard let http = response as? HTTPURLResponse else { throw rateLimit }
                if http.statusCode == 200 { return release }
                guard http.statusCode == 404 else { throw rateLimit }
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            try Task.checkCancellation()
            throw rateLimit
        }
        throw rateLimit
    }

    static func feedCandidates(in data: Data) -> [Self] {
        let parser = XMLParser(data: data)
        let links = ReleaseFeedLinks()
        parser.delegate = links
        guard parser.parse() else { return [] }
        let prefix = "/\(repository)/releases/tag/"
        return links.urls.compactMap { url -> Self? in
            guard url.scheme == "https", url.host == "github.com", url.path.hasPrefix(prefix) else { return nil }
            let tag = String(url.path.dropFirst(prefix.count))
            guard let version = stableVersion(for: tag) else { return nil }
            let asset = "Silverphase-\(version)-macOS-arm64.dmg"
            let download = releasesURL.appendingPathComponent("download").appendingPathComponent(tag)
                .appendingPathComponent(asset)
            return Self(version: version, downloadURL: download)
        }.sorted { $0.version.compare($1.version, options: .numeric) == .orderedDescending }
    }

    private final class ReleaseFeedLinks: NSObject, XMLParserDelegate {
        var urls: [URL] = []
        private var inEntry = false

        func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                    qualifiedName: String?, attributes: [String: String]) {
            if elementName == "entry" { inEntry = true }
            if inEntry, elementName == "link", attributes["rel"] == "alternate",
               let href = attributes["href"], let url = URL(string: href) {
                urls.append(url)
            }
        }

        func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?,
                    qualifiedName: String?) {
            if elementName == "entry" { inEntry = false }
        }
    }

    private static func stableVersion(for tag: String) -> String? {
        let versionTag = tag.hasPrefix("macos-") ? tag.dropFirst("macos-".count) : tag[...]
        let version = String(versionTag.hasPrefix("v") ? versionTag.dropFirst() : versionTag)
        let components = version.split(separator: ".", omittingEmptySubsequences: false)
        guard components.count == 3,
              components.allSatisfy({ !$0.isEmpty && $0.utf8.allSatisfy { (48...57).contains($0) } })
        else { return nil }
        return version
    }

    enum CheckError: Error {
        case rateLimited(Date?)
    }

    static func parse(_ data: Data, response: HTTPURLResponse) throws -> Self? {
        let retryAfter = response.value(forHTTPHeaderField: "Retry-After")
        let remaining = response.value(forHTTPHeaderField: "X-RateLimit-Remaining")
        if response.statusCode == 429 || (response.statusCode == 403 && (remaining == "0" || retryAfter != nil)) {
            let reset = response.value(forHTTPHeaderField: "X-RateLimit-Reset").flatMap(TimeInterval.init)
            let retryAt = retryAfter.flatMap(TimeInterval.init).map { Date().addingTimeInterval($0) }
                ?? reset.map { Date(timeIntervalSince1970: $0) }
            throw CheckError.rateLimited(retryAt)
        }
        guard response.statusCode == 200 else { throw URLError(.badServerResponse) }
        return try latest(in: data)
    }

    static func latest(in data: Data) throws -> Self? {
        try JSONDecoder().decode([Release].self, from: data).compactMap { release -> Self? in
            guard !release.draft, !release.prerelease else { return nil }
            guard let version = stableVersion(for: release.tag_name) else { return nil }

            let expectedName = "Silverphase-\(version)-macOS-arm64.dmg"
            guard let asset = release.assets.first(where: { $0.name == expectedName }),
                  asset.browser_download_url.scheme == "https",
                  asset.browser_download_url.host == "github.com",
                  asset.browser_download_url.path == "/\(repository)/releases/download/\(release.tag_name)/\(expectedName)"
            else { return nil }
            return Self(version: version, downloadURL: asset.browser_download_url)
        }.max { $0.version.compare($1.version, options: .numeric) == .orderedAscending }
    }

    private struct Release: Decodable {
        struct Asset: Decodable {
            let name: String
            let browser_download_url: URL
        }
        let tag_name: String
        let draft: Bool
        let prerelease: Bool
        let assets: [Asset]
    }
}
