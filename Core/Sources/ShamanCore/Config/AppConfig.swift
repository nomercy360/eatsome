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
        /// The OpenAI model. Named `model` because it was here first and remote
        /// config files in the wild still spell it that way.
        public var model: String
        public var imageDetail: String
        public var reasoningEffort: String?
        /// Overrides `MealPrompt.system` when present. This is the field that
        /// justifies the whole file.
        public var systemPrompt: String?
        /// Required whenever `systemPrompt` is overridden so saved eval rows
        /// can be traced to the exact instructions that produced them.
        public var promptVersion: String?
        /// Which provider a device uses until it is switched in Settings.
        public var provider: RecognitionProvider?
        /// The Gemini half of the comparison. Absent fields fall back to the
        /// compiled defaults in `GeminiSession.Configuration`.
        public var geminiModel: String?
        public var geminiThinkingLevel: String?
        public var geminiMediaResolution: String?
    }

    public var defaultProvider: RecognitionProvider { recognition.provider ?? .openAI }

    public static let fallback = AppConfig(
        version: 1,
        movements: MovementDefinition.builtIn,
        medas: MedasConfiguration(),
        recognition: Recognition(
            model: "gpt-5.6-luna",
            imageDetail: "low",
            reasoningEffort: "low",
            systemPrompt: nil,
            promptVersion: nil,
            provider: .openAI,
            geminiModel: "gemini-3.6-flash",
            geminiThinkingLevel: "low",
            geminiMediaResolution: nil
        )
    )

    public func movement(id: String) -> MovementDefinition? {
        movements.first { $0.id == id }
    }

    /// Prompt identity, before the model is folded in.
    private var promptBaseVersion: String {
        recognition.promptVersion
            ?? (recognition.systemPrompt == nil ? MealPrompt.version : "config-\(version)")
    }

    /// What every eval row is stamped with. The model belongs in it: two
    /// providers answering the same prompt are two different generators, and a
    /// comparison you cannot group by is not a comparison.
    public func promptVersion(forModel model: String) -> String {
        "\(promptBaseVersion)/\(model)"
    }

    public var lunaConfiguration: LunaSession.Configuration {
        .init(
            model: recognition.model,
            reasoningEffort: recognition.reasoningEffort,
            imageDetail: recognition.imageDetail,
            systemPrompt: recognition.systemPrompt ?? MealPrompt.system,
            promptVersion: promptVersion(forModel: recognition.model)
        )
    }

    public var geminiConfiguration: GeminiSession.Configuration {
        let defaults = GeminiSession.Configuration()
        let model = recognition.geminiModel ?? defaults.model
        return .init(
            model: model,
            thinkingLevel: recognition.geminiThinkingLevel ?? defaults.thinkingLevel,
            mediaResolution: recognition.geminiMediaResolution,
            systemPrompt: recognition.systemPrompt ?? MealPrompt.system,
            promptVersion: promptVersion(forModel: model)
        )
    }

    /// The model actually in use, for Settings to display.
    public func model(for provider: RecognitionProvider) -> String {
        switch provider {
        case .openAI: recognition.model
        case .gemini: recognition.geminiModel ?? GeminiSession.Configuration().model
        }
    }
}

/// Which vendor recognizes a plate. Both answer the same `MealRecognizer`
/// contract and the same prompt, so switching is a tap and the eval log stays
/// comparable.
public enum RecognitionProvider: String, Codable, Sendable, CaseIterable {
    case openAI = "openai"
    case gemini

    public var displayName: String {
        switch self {
        case .openAI: "OpenAI"
        case .gemini: "Gemini"
        }
    }

    /// Shown in Settings next to the key field, so it is obvious where the
    /// photograph is about to go.
    public var host: String {
        switch self {
        case .openAI: "api.openai.com"
        case .gemini: "generativelanguage.googleapis.com"
        }
    }

    public var keychainKey: KeychainStore.Key {
        switch self {
        case .openAI: .openAIAPIKey
        case .gemini: .geminiAPIKey
        }
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
