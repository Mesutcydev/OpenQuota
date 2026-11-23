import Foundation
import SwiftUI

/// Everything the UI needs to know about a provider before the user has
/// connected it: how to name it, how to ask for a credential, and what to
/// warn them about.
/// A second input some providers need next to the key.
struct ExtraFieldSpec: Hashable {
    var label: String
    var placeholder: String
    var isURL: Bool = false
    /// Fixed choices instead of free text (e.g. Moonshot's region).
    var options: [Option] = []

    struct Option: Hashable, Identifiable {
        var id: String { value }
        var title: String
        var value: String
        var caption: String?
    }
}

/// Groups the connect list so a dozen providers stay scannable.
enum ProviderCategory: String, CaseIterable {
    case plan = "Subscription plans"
    case balance = "Prepaid balance"
    case spend = "Organization spend"
    case limits = "Rate limits"
}

struct ProviderDescriptor: Identifiable, Hashable {
    var id: String
    var name: String
    /// One line under the name in the picker.
    var subtitle: String
    var symbol: String
    var tintHex: String
    /// Optional lifted variant for dark mode. See `tint`.
    var tintHexDark: String?
    /// Label for the secret field, e.g. "Admin API key".
    var credentialTitle: String = "API key"
    var credentialHint: String = ""
    /// Expected prefix, used for a soft inline warning (never a hard block —
    /// providers change key formats more often than apps ship updates).
    var keyPrefix: String?
    var extraField: ExtraFieldSpec?
    var category: ProviderCategory = .balance
    var docsURL: URL?
    /// Shown on the connect screen when the provider's data has real limits
    /// the user should know about up front.
    var caveat: String?
    /// Set for providers connected by signing in on the provider's own web
    /// page instead of pasting a key.
    var webSignIn: WebSignInKind? = nil

    /// Provider brand colour, used for the glyph, the card accent stripe and
    /// the progress bar.
    ///
    /// These are per-provider *identities* taken from each vendor's own palette,
    /// so they are not part of the general token ramp. But several of them are
    /// dark and muddy by design (xAI and OpenCode are near-greyscale brands)
    /// and would disappear against the dark canvas, so a descriptor may supply
    /// a lifted dark-mode variant. Where it is absent the light tint is used
    /// as-is, which is correct for the saturated mid-tone brands — those read
    /// fine on both backgrounds and changing them would make the provider
    /// unrecognisable.
    var tint: Color {
        guard let dark = tintHexDark else { return Color(hex: tintHex) }
        return Theme.adaptive(light: tintHex, dark: dark)
    }
}

/// A provider adapter. One instance per service; stateless, so a single
/// shared copy serves every account.
protocol UsageProvider: Sendable {
    var descriptor: ProviderDescriptor { get }
    func fetch(key: String, extra: String?) async throws -> ProviderReading
}

enum ProviderError: LocalizedError, Equatable {
    case unauthorized
    case forbidden(String?)
    case notFound
    case rateLimited
    case server(Int, String?)
    case insufficientFunds(String?)
    case decoding
    case transport(String)
    case message(String)

    var errorDescription: String? {
        switch self {
        case .unauthorized:
            return "Key rejected. Check that it is active and pasted in full."
        case .forbidden(let detail):
            return detail ?? "This key lacks permission to read usage."
        case .notFound:
            return "Endpoint not found. The provider may have changed its API."
        case .rateLimited:
            return "Provider is rate limiting. Try again shortly."
        case .server(let code, let detail):
            if let detail, !detail.isEmpty { return "\(detail) (HTTP \(code))" }
            return "Provider returned an error (HTTP \(code))."
        case .insufficientFunds(let detail):
            return detail ?? "The account is out of credit."
        case .decoding:
            return "Response did not match the expected format."
        case .transport(let detail):
            return detail
        case .message(let detail):
            return detail
        }
    }
}

enum HTTP {
    static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 20
        config.waitsForConnectivity = false
        return URLSession(configuration: config)
    }()

    static func get(
        _ url: URL,
        headers: [String: String],
        query: [URLQueryItem] = []
    ) async throws -> (Data, HTTPURLResponse) {
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        if !query.isEmpty { components?.queryItems = query }
        guard let finalURL = components?.url else { throw ProviderError.message("Bad URL") }

        var request = URLRequest(url: finalURL)
        request.httpMethod = "GET"
        for (field, value) in headers { request.setValue(value, forHTTPHeaderField: field) }

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw ProviderError.decoding }
            try check(http, data: data)
            return (data, http)
        } catch let error as ProviderError {
            throw error
        } catch let error as URLError where error.code == .cancelled {
            // A cancelled request is control flow, not a provider failure —
            // surface it as cancellation so callers can restore prior state
            // instead of painting an error.
            throw CancellationError()
        } catch let error as URLError {
            throw ProviderError.transport(friendly(error))
        }
    }

    private static func check(_ response: HTTPURLResponse, data: Data) throws {
        switch response.statusCode {
        case 200...299: return
        case 401: throw ProviderError.unauthorized
        case 403: throw ProviderError.forbidden(apiMessage(from: data))
        case 404: throw ProviderError.notFound
        case 402: throw ProviderError.insufficientFunds(apiMessage(from: data))
        case 429: throw ProviderError.rateLimited
        default: throw ProviderError.server(response.statusCode, apiMessage(from: data))
        }
    }

    /// Providers bury their human-readable reason in a few different shapes;
    /// dig out whichever one is present so the user sees the real cause.
    static func apiMessage(from data: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        if let error = object["error"] as? [String: Any],
           let message = error["message"] as? String { return message }
        if let error = object["error"] as? String { return error }
        if let message = object["message"] as? String { return message }
        if let detail = object["detail"] as? String { return detail }
        if let msg = object["msg"] as? String { return msg }
        return nil
    }

    private static func friendly(_ error: URLError) -> String {
        switch error.code {
        case .notConnectedToInternet: return "No internet connection."
        case .timedOut: return "Provider timed out."
        case .cannotFindHost, .cannotConnectToHost: return "Could not reach the provider."
        default: return error.localizedDescription
        }
    }

    /// Reads the near-universal `x-ratelimit-*` header family.
    static func rateLimitMetrics(from response: HTTPURLResponse) -> [UsageMetric] {
        func number(_ names: [String]) -> Double? {
            for name in names {
                if let raw = response.value(forHTTPHeaderField: name),
                   let value = Double(raw.trimmingCharacters(in: .whitespaces)) {
                    return value
                }
            }
            return nil
        }

        var metrics: [UsageMetric] = []
        let families: [(String, String, MetricUnit)] = [
            ("requests", "Requests", .requests),
            ("tokens", "Tokens", .tokens),
        ]

        for (slug, title, unit) in families {
            let limit = number(["x-ratelimit-limit-\(slug)", "X-RateLimit-Limit-\(slug)"])
            let remaining = number(["x-ratelimit-remaining-\(slug)", "X-RateLimit-Remaining-\(slug)"])
            guard limit != nil || remaining != nil else { continue }
            var metric = UsageMetric(
                id: "ratelimit-\(slug)",
                title: "\(title) remaining",
                used: limit.flatMap { total in remaining.map { total - $0 } },
                limit: limit,
                remaining: remaining,
                unit: unit,
                caption: "current rate-limit window")
            if let reset = response.value(forHTTPHeaderField: "x-ratelimit-reset-\(slug)") {
                metric.resetsAt = parseReset(reset)
            }
            metrics.append(metric)
        }
        return metrics
    }

    /// Reset headers arrive either as a duration ("7.66s", "2m59.56s") or as a
    /// unix timestamp, depending on the provider.
    /// Reset headers arrive either as a duration ("7.66s", "2m59.56s",
    /// "20ms") or as a unix timestamp, depending on the provider.
    static func parseReset(_ raw: String, now: Date = Date()) -> Date? {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        if let epoch = Double(trimmed) {
            if epoch > 1_000_000_000_000 { return Date(timeIntervalSince1970: epoch / 1000) }
            if epoch > 1_000_000_000 { return Date(timeIntervalSince1970: epoch) }
            return now.addingTimeInterval(epoch)
        }
        var seconds = 0.0
        var matched = false
        let chars = Array(trimmed)
        var index = 0
        var number = ""
        while index < chars.count {
            let character = chars[index]
            if character.isNumber || character == "." {
                number.append(character)
                index += 1
                continue
            }
            guard let value = Double(number) else { number = ""; index += 1; continue }
            number = ""
            if character == "m", index + 1 < chars.count, chars[index + 1] == "s" {
                seconds += value / 1000; matched = true; index += 2; continue
            }
            switch character {
            case "d": seconds += value * 86_400; matched = true
            case "h": seconds += value * 3600; matched = true
            case "m": seconds += value * 60; matched = true
            case "s": seconds += value; matched = true
            default: break
            }
            index += 1
        }
        if let iso = ISO8601DateFormatter().date(from: trimmed) { return iso }
        return matched ? now.addingTimeInterval(seconds) : nil
    }
}

/// Lenient JSON access for providers whose payloads are loosely documented:
/// numbers may arrive as numbers or strings, and keys may be nested.
enum JSON {
    static func object(_ data: Data) -> [String: Any]? {
        (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    static func number(_ value: Any?) -> Double? {
        switch value {
        case let n as NSNumber: return n.doubleValue
        case let s as String: return Double(s.trimmingCharacters(in: .whitespaces))
        default: return nil
        }
    }

    /// Follows a dotted path, e.g. "credits.current_balance".
    static func value(_ object: [String: Any]?, _ path: String) -> Any? {
        var current: Any? = object
        for key in path.split(separator: ".") {
            current = (current as? [String: Any])?[String(key)]
        }
        return current
    }

    static func number(_ object: [String: Any]?, _ path: String) -> Double? {
        number(value(object, path))
    }

    static func string(_ object: [String: Any]?, _ path: String) -> String? {
        value(object, path) as? String
    }

    /// Unix timestamp in seconds or milliseconds.
    static func date(_ value: Any?) -> Date? {
        guard let raw = number(value), raw > 0 else { return nil }
        return Date(timeIntervalSince1970: raw > 1_000_000_000_000 ? raw / 1000 : raw)
    }
}
