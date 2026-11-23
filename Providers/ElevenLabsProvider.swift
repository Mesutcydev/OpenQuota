import Foundation

/// ElevenLabs: subscription credit (character) quota with its reset date.
struct ElevenLabsProvider: UsageProvider {
    let descriptor = ProviderDescriptor(
        id: "elevenlabs",
        name: "ElevenLabs",
        subtitle: "Voice credits left this cycle",
        symbol: "waveform",
        tintHex: "1F1F1F",
        tintHexDark: "8A8A8E",
        credentialTitle: "API key",
        credentialHint: "sk_…",
        keyPrefix: "sk_",
        category: .plan,
        docsURL: URL(string: "https://elevenlabs.io/app/settings/api-keys"),
        caveat: "The key needs the “User” read permission.")

    func fetch(key: String, extra: String?) async throws -> ProviderReading {
        let (data, _) = try await HTTP.get(
            URL(string: "https://api.elevenlabs.io/v1/user/subscription")!,
            headers: ["xi-api-key": key])
        guard let object = JSON.object(data),
              let used = JSON.number(object, "character_count"),
              let limit = JSON.number(object, "character_limit")
        else { throw ProviderError.decoding }
        return Self.reading(object: object, used: used, limit: limit)
    }

    static func reading(object: [String: Any], used: Double, limit: Double) -> ProviderReading {
        var metrics = [UsageMetric(
            id: "credits", title: "Credits left", used: used, limit: limit,
            remaining: max(limit - used, 0), unit: .credits,
            resetsAt: JSON.date(JSON.value(object, "next_character_count_reset_unix")),
            caption: JSON.string(object, "tier").map { "\($0.capitalized) plan" },
            isHeadline: true)]
        metrics.append(UsageMetric(
            id: "credits-used", title: "Credits used this cycle", used: used, unit: .credits))
        if let slots = JSON.number(object, "voice_slots_used"),
           let slotLimit = JSON.number(object, "voice_limit") {
            metrics.append(UsageMetric(
                id: "voices", title: "Voice slots", used: slots, limit: slotLimit,
                remaining: max(slotLimit - slots, 0), unit: .requests))
        }
        var notes: [String] = []
        if let status = JSON.string(object, "status"), status != "active" {
            notes.append("Subscription status: \(status.replacingOccurrences(of: "_", with: " ")).")
        }
        return ProviderReading(label: nil, metrics: metrics, notes: notes)
    }
}
