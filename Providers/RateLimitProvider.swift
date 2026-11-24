import Foundation

/// Covers services that publish no accounting endpoint but do return the
/// standard `x-ratelimit-*` header family. We probe a free, side-effect-free
/// endpoint (`/models`) and report whatever the response headers carry.
///
/// Used directly for Groq, and with a user-supplied base URL for any other
/// OpenAI-compatible gateway.
struct RateLimitProvider: UsageProvider {
    let descriptor: ProviderDescriptor
    private let fixedBase: String?

    init(descriptor: ProviderDescriptor, base: String?) {
        self.descriptor = descriptor
        self.fixedBase = base
    }

    static let groq = RateLimitProvider(
        descriptor: ProviderDescriptor(
            id: "groq",
            name: "Groq",
            subtitle: "Request and token rate limits",
            symbol: "bolt.horizontal",
            tintHex: "F55036",
            credentialTitle: "API key",
            credentialHint: "gsk_…",
            keyPrefix: "gsk_",
            category: .limits,
            docsURL: URL(string: "https://console.groq.com/keys"),
            caveat: "Groq bills per token without a balance endpoint, so this "
                  + "shows rate-limit headroom rather than spend."),
        base: "https://api.groq.com/openai/v1")

    static let cerebras = RateLimitProvider(
        descriptor: ProviderDescriptor(
            id: "cerebras",
            name: "Cerebras",
            subtitle: "Request and token rate limits",
            symbol: "cpu",
            tintHex: "F15A29",
            credentialTitle: "API key",
            credentialHint: "csk-…",
            keyPrefix: "csk-",
            category: .limits,
            docsURL: URL(string: "https://cloud.cerebras.ai"),
            caveat: "Cerebras has no balance endpoint, so this shows the rate-limit "
                  + "headroom it reports on each response."),
        base: "https://api.cerebras.ai/v1")

    static let custom = RateLimitProvider(
        descriptor: ProviderDescriptor(
            id: "custom",
            name: "Custom endpoint",
            subtitle: "Any OpenAI-compatible base URL",
            symbol: "slider.horizontal.3",
            tintHex: "8E8E93",
            tintHexDark: "A9A9B0",
            credentialTitle: "API key",
            credentialHint: "Bearer token for your endpoint",
            keyPrefix: nil,
            extraField: ExtraFieldSpec(
                label: "Base URL",
                placeholder: "https://api.example.com/v1",
                isURL: true),
            category: .limits,
            caveat: "Reads standard x-ratelimit-* headers. Endpoints that do not "
                  + "send them will show as connected with no quota data."),
        base: nil)

    func fetch(key: String, extra: String?) async throws -> ProviderReading {
        let root = (fixedBase ?? extra ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !root.isEmpty, let url = URL(string: root + "/models") else {
            throw ProviderError.message("Enter a base URL, e.g. https://api.example.com/v1")
        }

        let (data, response) = try await HTTP.get(
            url, headers: ["Authorization": "Bearer \(key)"])

        var metrics = HTTP.rateLimitMetrics(from: response)
        if var first = metrics.first {
            first.isHeadline = true
            metrics[0] = first
        }

        var notes: [String] = []
        if metrics.isEmpty {
            notes.append("Key is valid, but this endpoint does not publish "
                       + "x-ratelimit-* headers, so there is no quota to show.")
        }

        // A model count is a weak signal, but it confirms the connection is
        // live even when no rate-limit headers come back.
        if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let models = object["data"] as? [Any] {
            metrics.append(UsageMetric(
                id: "models", title: "Models available",
                used: Double(models.count), unit: .requests,
                caption: "visible to this key"))
        }

        return ProviderReading(label: nil, metrics: metrics, notes: notes)
    }
}

enum ProviderRegistry {
    static let all: [any UsageProvider] = [
        // Subscription plans
        ClaudeSubscriptionProvider(),
        ChatGPTSubscriptionProvider(),
        OpenCodeProvider(),
        CopilotProvider(),
        ZAIProvider(),
        MiniMaxProvider(),
        ElevenLabsProvider(),
        PoeProvider(),
        // Prepaid balance
        OpenRouterProvider(),
        DeepSeekProvider(),
        MoonshotProvider(),
        XAIProvider(),
        FalProvider(),
        VeniceProvider(),
        SiliconFlowProvider(),
        NovitaProvider(),
        DeepgramProvider(),
        FeatherlessProvider(),
        AIMLProvider(),
        AlibabaProvider(),
        RunwayProvider(),
        // Organization spend
        AnthropicProvider(),
        OpenAIProvider(),
        MistralProvider(),
        TogetherProvider(),
        DeepInfraProvider(),
        LiteLLMProvider(),
        // Rate limits
        RateLimitProvider.groq,
        RateLimitProvider.cerebras,
        RateLimitProvider.custom,
        AlibabaTokenPlanProvider(),
    ]

    /// Connect list grouped by what the provider can actually tell you.
    static var grouped: [(category: ProviderCategory, providers: [any UsageProvider])] {
        ProviderCategory.allCases.compactMap { category in
            let matches = all.filter { $0.descriptor.category == category }
            return matches.isEmpty ? nil : (category, matches)
        }
    }

    static func provider(id: String) -> (any UsageProvider)? {
        all.first { $0.descriptor.id == id }
    }

    static func descriptor(id: String) -> ProviderDescriptor {
        provider(id: id)?.descriptor
            ?? ProviderDescriptor(
                id: id, name: id.capitalized, subtitle: "Unknown provider",
                symbol: "questionmark.circle", tintHex: "8E8E93",
                tintHexDark: "A9A9B0")
    }
}
