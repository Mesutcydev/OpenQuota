import Foundation

/// Z.ai / Zhipu GLM Coding Plan: prompt windows as % used, plus tool-call
/// (MCP) quota. The endpoint is the one the Z.ai console itself calls; it is
/// not in the public API reference, so parsing is deliberately lenient.
struct ZAIProvider: UsageProvider {
    let descriptor = ProviderDescriptor(
        id: "zai",
        name: "Z.ai GLM Coding Plan",
        subtitle: "5-hour and weekly plan windows",
        symbol: "z.square.fill",
        tintHex: "2D5BFF",
        credentialTitle: "API key",
        credentialHint: "Coding Plan API key",
        extraField: ExtraFieldSpec(
            label: "Region",
            placeholder: "International",
            options: [
                .init(title: "International (z.ai)", value: "https://api.z.ai",
                      caption: "GLM Coding Plan"),
                .init(title: "China (bigmodel.cn)", value: "https://open.bigmodel.cn",
                      caption: "智谱 GLM Coding Plan"),
            ]),
        category: .plan,
        docsURL: URL(string: "https://z.ai/manage-apikey/apikey-list"),
        caveat: "Uses the same quota endpoint as the Z.ai console. It is not part "
              + "of the documented API and may change.")

    func fetch(key: String, extra: String?) async throws -> ProviderReading {
        let base = (extra?.isEmpty == false ? extra! : "https://api.z.ai")
        guard let url = URL(string: base + "/api/monitor/usage/quota/limit") else {
            throw ProviderError.message("Invalid region.")
        }
        let (data, _) = try await HTTP.get(url, headers: [
            "Authorization": "Bearer \(key)",
            "Accept-Language": "en-US,en",
        ])
        return try Self.reading(from: data)
    }

    static func reading(from data: Data, now: Date = Date()) throws -> ProviderReading {
        guard let object = JSON.object(data) else { throw ProviderError.decoding }
        if (object["success"] as? Bool) == false {
            throw ProviderError.message((object["msg"] as? String) ?? "Z.ai rejected the request.")
        }
        let payload = (object["data"] as? [String: Any]) ?? object
        guard let limits = payload["limits"] as? [[String: Any]], !limits.isEmpty else {
            throw ProviderError.decoding
        }

        // Shortest window first: it is the one that interrupts you.
        let tokenWindows = limits
            .filter { ($0["type"] as? String) == "TOKENS_LIMIT" }
            .sorted { (JSON.date($0["nextResetTime"]) ?? .distantFuture) < (JSON.date($1["nextResetTime"]) ?? .distantFuture) }

        var metrics: [UsageMetric] = []
        for (index, window) in tokenWindows.enumerated() {
            guard let percent = JSON.number(window["percentage"]) else { continue }
            let reset = JSON.date(window["nextResetTime"])
            let title = Self.windowTitle(reset: reset, now: now, index: index)
            metrics.append(UsageMetric(
                id: "window-\(index)", title: title, used: percent, limit: 100,
                remaining: max(100 - percent, 0), unit: .percent,
                resetsAt: reset, caption: "prompts", isHeadline: metrics.isEmpty))
        }

        for (index, item) in limits.enumerated() where (item["type"] as? String) == "TIME_LIMIT" {
            // "usage" is the window's total quota, "currentValue" the amount
            // consumed; fall back to consumed + remaining when total is absent.
            let used = JSON.number(item["currentValue"])
            let total = JSON.number(item["usage"])
                ?? used.flatMap { u in JSON.number(item["remaining"]).map { u + $0 } }
            if let used, let total, total > 0, used <= total {
                metrics.append(UsageMetric(
                    id: "tools-\(index)", title: "Tool calls (MCP)", used: used, limit: total,
                    remaining: max(total - used, 0), unit: .requests,
                    resetsAt: JSON.date(item["nextResetTime"]),
                    isHeadline: metrics.isEmpty))
            } else if let percent = JSON.number(item["percentage"]) {
                metrics.append(UsageMetric(
                    id: "tools-\(index)", title: "Tool calls (MCP)", used: percent, limit: 100,
                    remaining: max(100 - percent, 0), unit: .percent,
                    resetsAt: JSON.date(item["nextResetTime"]), isHeadline: metrics.isEmpty))
            }
        }
        guard !metrics.isEmpty else { throw ProviderError.decoding }
        let level = (payload["level"] as? String).map { "\($0.capitalized) plan" }
        return ProviderReading(label: level, metrics: metrics)
    }

    static func windowTitle(reset: Date?, now: Date, index: Int) -> String {
        guard let reset else { return index == 0 ? "5-hour window" : "Weekly window" }
        let hours = reset.timeIntervalSince(now) / 3600
        if hours <= 5.5 { return "5-hour window" }
        if hours <= 24 * 7.5 { return "Weekly window" }
        return "Monthly window"
    }
}
