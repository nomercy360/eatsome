import Foundation

/// Everything you will want to change without shipping a build.
///
/// You will edit the rep thresholds a dozen times in the first week of camera
/// testing, and the recognition prompt more often than that. Waiting on a
/// TestFlight round-trip to change a number is the kind of friction that ends
/// projects. This is a static JSON file, not a service: no deploy, no uptime,
/// no secrets — fetched at launch, cached, falls back to the bundle.
public struct AppConfig: Codable, Sendable {
    public var version: Int
    public var movements: [MovementDefinition]
    public var medas: MedasConfiguration
    public var recognition: Recognition

    public struct Recognition: Codable, Sendable {
        public var model: String
        public var imageDetail: String
        public var reasoningEffort: String?
        /// Overrides `MealPrompt.system` when present. This is the field that
        /// justifies the whole file.
        public var systemPrompt: String?
        /// Below this, open the correction sheet instead of saving silently.
        public var autoConfirmConfidence: Double
    }

    public static let fallback = AppConfig(
        version: 1,
        movements: MovementDefinition.builtIn,
        medas: MedasConfiguration(),
        recognition: Recognition(
            model: "gpt-5.6-luna",
            imageDetail: "low",
            reasoningEffort: "low",
            systemPrompt: nil,
            autoConfirmConfidence: 0.85
        )
    )

    public func movement(id: String) -> MovementDefinition? {
        movements.first { $0.id == id }
    }

    public var lunaConfiguration: LunaSession.Configuration {
        .init(model: recognition.model,
              reasoningEffort: recognition.reasoningEffort,
              imageDetail: recognition.imageDetail)
    }
}

/// Remote → cache → bundle → compiled-in defaults. Never throws: a config
/// fetch failing at 6am must not be the reason you cannot log breakfast.
public actor ConfigLoader {
    public enum Source: String, Sendable { case remote, cache, bundle, fallback }

    private let remoteURL: URL?
    private let cacheURL: URL
    private let bundle: Bundle
    private let session: URLSession

    public init(remoteURL: URL?, cacheURL: URL, bundle: Bundle? = nil, session: URLSession = .shared) {
        self.remoteURL = remoteURL
        self.cacheURL = cacheURL
        self.bundle = bundle ?? .module
        self.session = session
    }

    public func load() async -> (config: AppConfig, source: Source) {
        if let remoteURL, let fetched = await fetch(remoteURL) {
            try? FileManager.default.createDirectory(
                at: cacheURL.deletingLastPathComponent(), withIntermediateDirectories: true
            )
            try? JSONEncoder().encode(fetched).write(to: cacheURL, options: .atomic)
            return (fetched, .remote)
        }
        if let data = try? Data(contentsOf: cacheURL),
           let cached = try? JSONDecoder().decode(AppConfig.self, from: data) {
            return (cached, .cache)
        }
        if let url = bundle.url(forResource: "shaman-config", withExtension: "json"),
           let data = try? Data(contentsOf: url),
           let bundled = try? JSONDecoder().decode(AppConfig.self, from: data) {
            return (bundled, .bundle)
        }
        return (.fallback, .fallback)
    }

    private func fetch(_ url: URL) async -> AppConfig? {
        var request = URLRequest(url: url)
        request.timeoutInterval = 5
        request.cachePolicy = .reloadIgnoringLocalCacheData
        guard let (data, response) = try? await session.data(for: request),
              let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode)
        else { return nil }
        return try? JSONDecoder().decode(AppConfig.self, from: data)
    }
}
