import Foundation

/// Alibaba Cloud Model Studio Token Plan (Personal/Solo) quota. Unlike the
/// pay-as-you-go balance, this is only reachable through the console's
/// cookie session — API keys cannot read it (CodexBar documents this).
///
/// Connect by signing in on the Model Studio console inside the app; the
/// resulting session cookie is stored in the Keychain. Use "Sign in again"
/// when the session expires.
struct AlibabaTokenPlanProvider: UsageProvider {
    let descriptor = ProviderDescriptor(
        id: "alibaba-token-plan",
        name: "Alibaba Token Plan",
        subtitle: "Rolling 5-hour and weekly Credits quota (cookie session)",
        symbol: "ticket",
        tintHex: "FF6A00",
        credentialTitle: "Session cookie",
        credentialHint: "Pasted automatically after sign-in",
        keyPrefix: nil,
        category: .limits,
        docsURL: URL(string: "https://modelstudio.console.alibabacloud.com"),
        caveat: "Personal/Solo Token Plan quota is only exposed through the "
              + "console session, so this provider signs in on the console. "
              + "API keys cannot read it.",
        webSignIn: nil)

    // MARK: - Endpoints

    private static let intlGateway = "https://bailian-singapore-cs.alibabacloud.com"
    private static let cnGateway = "https://bailian-cs.console.aliyun.com"
    private static let userInfoPath = "/tool/user/info.json"

    func fetch(key: String, extra: String?) async throws -> ProviderReading {
        let cookie = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cookie.isEmpty else { throw ProviderError.unauthorized }

        let isCN = (extra?.lowercased().contains("cn") == true)
        let gateway = isCN ? Self.cnGateway : Self.intlGateway
        let consoleHost = isCN ? "bailian.console.aliyun.com" : "modelstudio.console.alibabacloud.com"

        // 1. Resolve sec_token (best effort).
        var secToken = ""
        if let url = URL(string: "https://\(consoleHost)\(Self.userInfoPath)") {
            var request = URLRequest(url: url)
            request.setValue(cookie, forHTTPHeaderField: "Cookie")
            request.setValue(WebSession.userAgent, forHTTPHeaderField: "User-Agent")
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            if let (data, _) = try? await WebSession.session.data(for: request),
               let object = JSON.object(data),
               let dataObj = object["data"] as? [String: Any],
               let token = dataObj["secToken"] as? String {
                secToken = token
            }
        }

        // 2. Fetch usage, subscription and quota-config.
        let usage = try await gatewayPost(gateway: gateway, api: "zeldaHttp.apikeyMgr./tokenplan/personal/api/v2/usage", secToken: secToken, cookie: cookie)
        let subscription = try? await gatewayPost(gateway: gateway, api: "zeldaHttp.apikeyMgr./tokenplan/personal/api/v2/subscription", secToken: secToken, cookie: cookie)
        let quotaConfig = try? await gatewayPost(gateway: gateway, api: "zeldaHttp.apikeyMgr./tokenplan/personal/api/v2/quota-config", secToken: secToken, cookie: cookie)

        // 3. Resolve tier ceilings.
        let specCode = (subscription?["specCode"] as? String)?.lowercased()
        var fiveHourCeiling: Double?
        var weeklyCeiling: Double?
        var monthlyCeiling: Double?
        if let qc = quotaConfig, let tier = specCode, let tierObj = qc[tier] as? [String: Any] {
            fiveHourCeiling = JSON.number(tierObj, "five_hour") ?? JSON.number(tierObj, "fiveHour")
            weeklyCeiling = JSON.number(tierObj, "weekly")
            monthlyCeiling = JSON.number(tierObj, "monthly")
        }

        var metrics: [UsageMetric] = []

        // Helper to append a window metric for whichever windows the plan reports.
        func addWindow(id: String, title: String, pctKey: String, resetKey: String, ceiling: Double?, headline: Bool) {
            guard let pct = JSON.number(usage, pctKey) else { return }
            let resetMs = JSON.number(usage, resetKey)
            let resetDate = resetMs.map { Date(timeIntervalSince1970: $0 / 1000) }
            if let ceiling, ceiling > 0 {
                let used = pct * ceiling
                metrics.append(UsageMetric(
                    id: id, title: title, used: used, limit: ceiling,
                    remaining: ceiling - used, unit: .requests,
                    resetsAt: resetDate, caption: "Credits used", isHeadline: headline))
            } else {
                metrics.append(UsageMetric(
                    id: id, title: title, used: pct * 100, limit: 100,
                    remaining: (1 - pct) * 100, unit: .percent,
                    resetsAt: resetDate, caption: "fraction consumed", isHeadline: headline))
            }
        }

        addWindow(id: "5h", title: "5-hour window", pctKey: "per5HourPercentage", resetKey: "per5HourResetTime", ceiling: fiveHourCeiling, headline: true)
        addWindow(id: "week", title: "Weekly window", pctKey: "per1WeekPercentage", resetKey: "per1WeekResetTime", ceiling: weeklyCeiling, headline: metrics.isEmpty)
        addWindow(id: "month", title: "Monthly window", pctKey: "per1MonthPercentage", resetKey: "per1MonthResetTime", ceiling: monthlyCeiling, headline: metrics.isEmpty)

        if metrics.isEmpty {
            throw ProviderError.decoding
        }

        var notes: [String] = []
        if let spec = specCode { notes.append("Tier: \(spec).") }
        if fiveHourCeiling == nil { notes.append("Quota ceilings unavailable; showing fractions.") }

        return ProviderReading(label: nil, metrics: metrics, notes: notes)
    }

    // MARK: - Gateway POST

    private func gatewayPost(gateway: String, api: String, secToken: String, cookie: String) async throws -> [String: Any] {
        guard let url = URL(string: "\(gateway)/data/api.json?product=sfm_bailian&action=IntlBroadScopeAspnGateway&api=\(api.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? api)") else {
            throw ProviderError.message("Bad URL")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue(cookie, forHTTPHeaderField: "Cookie")
        request.setValue(WebSession.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("https://modelstudio.console.alibabacloud.com", forHTTPHeaderField: "Origin")
        request.setValue("https://modelstudio.console.alibabacloud.com/billing/subscription/token-plan-individual", forHTTPHeaderField: "Referer")

        let paramsObj: [String: Any] = [
            "Api": api,
            "Data": [
                "cornerstoneParam": [
                    "domain": "modelstudio.console.alibabacloud.com",
                    "consoleSite": "MODELSTUDIO",
                    "console": "ONE_CONSOLE",
                    "xsp_lang": "en-US",
                    "protocol": "V2",
                    "productCode": "p_efm",
                ] as [String: Any],
            ] as [String: Any],
            "V": "1.0",
        ]
        let paramsJSON = (try? JSONSerialization.data(withJSONObject: paramsObj)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"

        var bodyComponents = URLComponents()
        bodyComponents.queryItems = [
            URLQueryItem(name: "product", value: "sfm_bailian"),
            URLQueryItem(name: "action", value: "IntlBroadScopeAspnGateway"),
            URLQueryItem(name: "sec_token", value: secToken),
            URLQueryItem(name: "region", value: "ap-southeast-1"),
            URLQueryItem(name: "params", value: paramsJSON),
        ]
        request.httpBody = bodyComponents.query?.data(using: .utf8)

        let (data, response) = try await WebSession.session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw ProviderError.decoding }
        if http.statusCode == 401 || http.statusCode == 403 {
            throw ProviderError.message("Your Alibaba console session has expired. Sign in again.")
        }
        guard (200...299).contains(http.statusCode) else {
            throw ProviderError.server(http.statusCode, HTTP.apiMessage(from: data))
        }

        // Response nests payload at .data.DataV2.data.data (per CodexBar).
        guard let object = JSON.object(data) else { throw ProviderError.decoding }
        var payload: [String: Any]? = nil
        if let d = object["data"] as? [String: Any],
           let d2 = d["DataV2"] as? [String: Any],
           let inner = d2["data"] as? [String: Any],
           let dataField = inner["data"] as? [String: Any] {
            payload = dataField
        } else if let d = object["data"] as? [String: Any] {
            payload = d
        }
        return payload ?? object
    }
}
