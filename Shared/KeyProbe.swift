import Foundation

/// Asks each provider whether a key still authenticates. The cheapest
/// authenticated endpoint is used in every case — a listing or an identity
/// call — so a check costs nothing and changes nothing.
enum KeyProbe {
    enum Verdict: String {
        case valid          // the provider accepted the credential
        case invalid        // the provider rejected it: revoked, wrong, expired
        case unknown        // reachable but the answer was not conclusive
        case unsupported    // no probe is defined for this provider
        case skipped        // passwords and IDs have nothing to call

        var label: String {
            switch self {
            case .valid: return "有效"
            case .invalid: return "失效"
            case .unknown: return "無法判斷"
            case .unsupported: return "未支援"
            case .skipped: return "不適用"
            }
        }
    }

    /// Matched on the entry name, which is what the owner called it, falling
    /// back to the shape of the value for tokens that announce themselves.
    private static func request(name: String, secret: String) -> URLRequest? {
        let key = name.lowercased()
        let value = secret.trimmingCharacters(in: .whitespacesAndNewlines)

        func get(_ string: String, _ headers: [String: String] = [:]) -> URLRequest? {
            guard let url = URL(string: string) else { return nil }
            var request = URLRequest(url: url)
            request.timeoutInterval = 12
            headers.forEach { request.setValue($1, forHTTPHeaderField: $0) }
            return request
        }

        let escaped = value.addingPercentEncoding(
            withAllowedCharacters: .urlQueryAllowed
        ) ?? value

        if key.contains("openai") || value.hasPrefix("sk-proj-") || value.hasPrefix("sk-svcacct") {
            return get("https://api.openai.com/v1/models", ["Authorization": "Bearer \(value)"])
        }
        if key.contains("anthropic") || value.hasPrefix("sk-ant-") {
            return get("https://api.anthropic.com/v1/models", [
                "x-api-key": value, "anthropic-version": "2023-06-01",
            ])
        }
        if key.contains("gemini") || key.contains("google ai") {
            return get("https://generativelanguage.googleapis.com/v1beta/models?key=\(escaped)")
        }
        if key.contains("github") || value.hasPrefix("ghp_") || value.hasPrefix("github_pat_") {
            return get("https://api.github.com/user", ["Authorization": "Bearer \(value)"])
        }
        if key.contains("meta") || value.hasPrefix("EAA") {
            let token = value.components(separatedBy: .newlines)
                .first(where: { $0.hasPrefix("EAA") }) ?? value
            let safe = token.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? token
            return get("https://graph.facebook.com/v21.0/me?access_token=\(safe)")
        }
        if key.contains("unsplash") {
            return get("https://api.unsplash.com/photos?per_page=1", [
                "Authorization": "Client-ID \(value)",
            ])
        }
        if key.contains("pexels") {
            return get("https://api.pexels.com/v1/curated?per_page=1", ["Authorization": value])
        }
        if key.contains("pixabay") {
            return get("https://pixabay.com/api/?key=\(escaped)&q=sky&per_page=3")
        }
        if key.contains("gnews") {
            return get("https://gnews.io/api/v4/top-headlines?max=1&token=\(escaped)")
        }
        if key.contains("news api") || key == "news api" || key.contains("newsapi") {
            return get("https://newsapi.org/v2/top-headlines?country=us&pageSize=1&apiKey=\(escaped)")
        }
        if key.contains("fred") {
            return get("https://api.stlouisfed.org/fred/series?series_id=GNPCA&file_type=json&api_key=\(escaped)")
        }
        if key.contains("bea") {
            return get("https://apps.bea.gov/api/data?method=GETDATASETLIST&ResultFormat=JSON&UserID=\(escaped)")
        }
        return nil
    }

    static func check(name: String, kind: String, secret: String) async -> Verdict {
        guard kind == ItemKind.apiKey.rawValue || kind == ItemKind.token.rawValue else {
            return .skipped
        }
        guard let request = request(name: name, secret: secret) else { return .unsupported }

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { return .unknown }
            switch http.statusCode {
            case 200...299:
                // Some providers answer 200 with the rejection in the body.
                let body = String(data: data, encoding: .utf8)?.lowercased() ?? ""
                if body.contains("\"status\":\"error\"") || body.contains("invalid api key") {
                    return .invalid
                }
                return .valid
            case 401, 403:
                return .invalid
            case 429:
                // Throttled, which means the credential itself was accepted.
                return .valid
            default:
                return .unknown
            }
        } catch {
            return .unknown
        }
    }
}
