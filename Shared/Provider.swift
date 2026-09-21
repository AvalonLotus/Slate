import Foundation

/// 認得出來的服務。認人的規則只寫這一次：條目名稱裡的字，或值的開頭。
/// `slate check` 靠它決定去打哪個端點，編輯畫面靠它把管理頁填進網址欄。
enum Provider: String, CaseIterable {
    case openai
    case anthropic
    case gemini
    case github
    case meta
    case unsplash
    case pexels
    case pixabay
    case gnews
    case newsapi
    case fred
    case bea

    /// 申請與管理這把金鑰的頁面。
    var consoleURL: String {
        switch self {
        case .openai: return "https://platform.openai.com/api-keys"
        case .anthropic: return "https://console.anthropic.com/settings/keys"
        case .gemini: return "https://aistudio.google.com/app/apikey"
        case .github: return "https://github.com/settings/tokens"
        case .meta: return "https://developers.facebook.com/tools/explorer/"
        case .unsplash: return "https://unsplash.com/oauth/applications"
        case .pexels: return "https://www.pexels.com/api/"
        case .pixabay: return "https://pixabay.com/api/docs/"
        case .gnews: return "https://gnews.io/dashboard"
        case .newsapi: return "https://newsapi.org/account"
        case .fred: return "https://fredaccount.stlouisfed.org/apikeys"
        case .bea: return "https://apps.bea.gov/API/signup/"
        }
    }

    /// 順序就是判斷順序，第一個對上的贏。
    static func match(name: String, value: String) -> Provider? {
        let key = name.lowercased()
        let raw = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return allCases.first { $0.matches(key: key, value: raw) }
    }

    private func matches(key: String, value: String) -> Bool {
        switch self {
        case .openai:
            return key.contains("openai") || value.hasPrefix("sk-proj-")
                || value.hasPrefix("sk-svcacct")
        case .anthropic:
            return key.contains("anthropic") || value.hasPrefix("sk-ant-")
        case .gemini:
            return key.contains("gemini") || key.contains("google ai")
        case .github:
            return key.contains("github") || value.hasPrefix("ghp_")
                || value.hasPrefix("github_pat_")
        case .meta:
            return key.contains("meta") || value.hasPrefix("EAA")
        case .unsplash:
            return key.contains("unsplash")
        case .pexels:
            return key.contains("pexels")
        case .pixabay:
            return key.contains("pixabay")
        case .gnews:
            return key.contains("gnews")
        case .newsapi:
            return key.contains("news api") || key.contains("newsapi")
        case .fred:
            return key.contains("fred")
        case .bea:
            return key.contains("bea")
        }
    }
}
