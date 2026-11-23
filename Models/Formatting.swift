import Foundation

/// Display formatting. All formatters are cached: these are called from card
/// bodies, which re-evaluate on every timeline tick and scroll frame, and
/// building a `NumberFormatter` per call is measurably expensive at that rate.
enum Format {
    /// Keyed by "<code>-<precision>" so a USD spend total and a CNY balance
    /// each keep their own configured formatter.
    private static let currencyFormatters = NSCache<NSString, NumberFormatter>()

    private static func currencyFormatter(code: String, subCentPrecision: Bool) -> NumberFormatter {
        let key = "\(code)-\(subCentPrecision)" as NSString
        if let cached = currencyFormatters.object(forKey: key) { return cached }
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = code
        // Sub-cent spend is common on token billing, so keep a little more
        // precision until the number is big enough not to need it.
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = subCentPrecision ? 4 : 2
        currencyFormatters.setObject(formatter, forKey: key)
        return formatter
    }

    static func value(_ amount: Double, unit: MetricUnit, currencyCode: String? = nil) -> String {
        switch unit {
        case .usd: return currency(amount, code: currencyCode ?? "USD")
        case .tokens: return compact(amount)
        case .requests: return compact(amount)
        case .credits: return compact(amount)
        case .percent: return "\(Int(amount.rounded()))%"
        }
    }

    static func currency(_ amount: Double, code: String = "USD") -> String {
        let formatter = currencyFormatter(code: code, subCentPrecision: abs(amount) < 1)
        return formatter.string(from: NSNumber(value: amount)) ?? "\(amount) \(code)"
    }

    static func compact(_ amount: Double) -> String {
        let magnitude = abs(amount)
        switch magnitude {
        case 1_000_000_000...:
            return trim(amount / 1_000_000_000) + "B"
        case 1_000_000...:
            return trim(amount / 1_000_000) + "M"
        case 10_000...:
            return trim(amount / 1_000) + "K"
        default:
            return NumberFormatter.localizedString(
                from: NSNumber(value: Int(amount.rounded())), number: .decimal)
        }
    }

    private static func trim(_ value: Double) -> String {
        let rounded = (value * 10).rounded() / 10
        return rounded == rounded.rounded()
            ? String(Int(rounded))
            : String(format: "%.1f", rounded)
    }

    // Countdown formatters are configured once; `allowedUnits` decides which
    // cached instance is used rather than reconfiguring per call.
    private static let hourMinuteCountdown: DateComponentsFormatter = {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute]
        formatter.unitsStyle = .abbreviated
        formatter.maximumUnitCount = 2
        return formatter
    }()

    private static let dayHourCountdown: DateComponentsFormatter = {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.day, .hour]
        formatter.unitsStyle = .abbreviated
        formatter.maximumUnitCount = 2
        return formatter
    }()

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter
    }()

    /// "resets in 4h 12m" style countdown, or nil once the date has passed.
    static func countdown(to date: Date, from now: Date = Date()) -> String? {
        let seconds = date.timeIntervalSince(now)
        guard seconds > 0 else { return nil }
        let formatter = seconds > 86_400 ? dayHourCountdown : hourMinuteCountdown
        return formatter.string(from: seconds)
    }

    static func relative(_ date: Date, from now: Date = Date()) -> String {
        if now.timeIntervalSince(date) < 60 { return "just now" }
        return relativeFormatter.localizedString(for: date, relativeTo: now)
    }
}
