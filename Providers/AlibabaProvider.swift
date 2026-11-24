import Foundation
import CryptoKit

/// Alibaba Cloud reports the project account balance through the BSS OpenAPI
/// `QueryAccountBalance` operation. That endpoint is AccessKey-authenticated
/// (AK/SK), not an inference key, so the credential field holds the
/// AccessKey ID and the extra field holds the AccessKey Secret.
struct AlibabaProvider: UsageProvider {
    let descriptor = ProviderDescriptor(
        id: "alibaba",
        name: "Alibaba Cloud",
        subtitle: "Account balance (AccessKey)",
        symbol: "cloud",
        tintHex: "FF6A00",
        credentialTitle: "AccessKey ID",
        credentialHint: "LTAI…",
        keyPrefix: "LTAI",
        extraField: ExtraFieldSpec(
            label: "AccessKey Secret",
            placeholder: "your AccessKey secret"),
        category: .balance,
        docsURL: URL(string: "https://www.alibabacloud.com/help/en/user-center/developer-reference/api-bssopenapi-2017-12-14-queryaccountbalance"),
        caveat: "Uses Alibaba Cloud BSS OpenAPI, so it needs an AccessKey with "
              + "billing read permission rather than a DashScope inference key.")

    func fetch(key: String, extra: String?) async throws -> ProviderReading {
        let secret = (extra ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !secret.isEmpty else {
            throw ProviderError.message("Enter the AccessKey Secret in the extra field.")
        }

        let accessKeyId = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !accessKeyId.isEmpty else { throw ProviderError.unauthorized }

        // RPC-style V2 signature. Build the canonical (sorted) query string,
        // sign it with HMAC-SHA1, then issue the request.
        let nonce = UUID().uuidString
        let timestamp = Self.timestamp()
        var params: [String: String] = [
            "AccessKeyId": accessKeyId,
            "Action": "QueryAccountBalance",
            "Format": "JSON",
            "SignatureMethod": "HMAC-SHA1",
            "SignatureNonce": nonce,
            "SignatureVersion": "1.0",
            "Timestamp": timestamp,
            "Version": "2017-12-14",
        ]

        let canonical = params.keys.sorted().map { key in
            "\(Self.percentEncode(key))=\(Self.percentEncode(params[key]!))"
        }.joined(separator: "&")

        let stringToSign = "GET&\(Self.percentEncode("/"))&\(Self.percentEncode(canonical))"
        let signature = Self.sign(stringToSign, secret: secret)
        params["Signature"] = signature

        // International accounts are served from the Singapore region endpoint;
        // China-site accounts need business.aliyuncs.com. The signature does not
        // cover the host, so the same request works against either.
        let hosts = ["business.ap-southeast-1.aliyuncs.com", "business.aliyuncs.com"]
        var lastError: Error = ProviderError.message("Bad URL")
        var responseData: Data? = nil
        for host in hosts {
            var components = URLComponents(string: "https://\(host)/")!
            components.queryItems = params.keys.sorted().map { URLQueryItem(name: $0, value: params[$0]) }
            guard let url = components.url else { continue }
            do {
                let (d, _) = try await HTTP.get(url, headers: [:])
                responseData = d
                break
            } catch {
                lastError = error
                let isSiteMismatch: Bool
                if let pe = error as? ProviderError, case .server(let code, let msg) = pe {
                    isSiteMismatch = (code == 400) && (msg?.lowercased().contains("auth site") == true || msg?.lowercased().contains("not applicable") == true)
                } else {
                    isSiteMismatch = false
                }
                if isSiteMismatch { continue }
                // Retry on any 400 in case the other host is the right one.
                if let pe = error as? ProviderError, case .server(400, _) = pe { continue }
                throw error
            }
        }
        guard let data = responseData else { throw lastError }

        guard let object = JSON.object(data) else { throw ProviderError.decoding }
        // Response wraps the payload under "Data" (capital D) on success.
        let payload = (object["Data"] as? [String: Any]) ?? object
        guard let available = JSON.number(payload, "AvailableAmount")
                ?? JSON.number(payload, "AvailableCashAmount")
        else { throw ProviderError.decoding }

        let currency = (JSON.string(payload, "Currency") ?? "CNY").uppercased()

        var metrics = [UsageMetric(
            id: "balance",
            title: "Available balance",
            remaining: available,
            unit: .usd,
            currencyCode: currency,
            caption: "available to spend",
            isHeadline: true)]

        if let credit = JSON.number(payload, "CreditAmount"), credit > 0 {
            metrics.append(UsageMetric(
                id: "credit", title: "Credit", remaining: credit,
                unit: .usd, currencyCode: currency))
        }
        if let cash = JSON.number(payload, "AvailableCashAmount"), cash > 0, cash != available {
            metrics.append(UsageMetric(
                id: "cash", title: "Cash", remaining: cash,
                unit: .usd, currencyCode: currency))
        }

        var notes: [String] = []
        if let code = object["Code"] as? String, code != "200" && code != "Success" {
            if let message = object["Message"] as? String, !message.isEmpty {
                notes.append(message)
            }
        }
        if let quota = JSON.number(payload, "QuotaLimit"), quota > 0 {
            notes.append("Quota limit: \(String(format: "%.2f", quota)) \(currency).")
        }

        return ProviderReading(label: nil, metrics: metrics, notes: notes)
    }

    // MARK: - Signing helpers

    private static func timestamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss'Z'"
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.string(from: Date())
    }

    private static func percentEncode(_ value: String) -> String {
        var allowed = CharacterSet()
        allowed.insert(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_.~")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }

    private static func sign(_ stringToSign: String, secret: String) -> String {
        let key = SymmetricKey(data: Data((secret + "&").utf8))
        let mac = HMAC<Insecure.SHA1>.authenticationCode(for: Data(stringToSign.utf8), using: key)
        return Data(mac).base64EncodedString()
    }
}
