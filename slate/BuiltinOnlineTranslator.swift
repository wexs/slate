import Foundation

public struct BuiltinOnlineTranslator {
    public enum TranslationError: LocalizedError {
        case emptyResult
        case networkError(Error)
        case apiError(String)
        case decodingError
        
        public var errorDescription: String? {
            switch self {
            case .emptyResult:
                return "在线翻译未返回有效结果"
            case .networkError(let error):
                return "在线翻译网络连接失败: \(error.localizedDescription)"
            case .apiError(let message):
                return "在线翻译接口错误: \(message)"
            case .decodingError:
                return "解析在线翻译响应失败"
            }
        }
    }
    
    public static func translate(
        text: String,
        source: AppLanguage,
        target: AppLanguage
    ) async throws -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        
        // 1. Try Microsoft Edge Translation Endpoint first (ultra-fast, zero-config, supports China & global)
        do {
            let edgeFrom = (source.id == "auto") ? "" : (source.microsoftCode ?? "")
            let edgeTo = target.microsoftCode ?? "zh-Hans"
            return try await translateWithEdge(text: trimmed, from: edgeFrom, to: edgeTo)
        } catch {
            // 2. Fallback to Google Web Translation
            let googleFrom = (source.id == "auto") ? "auto" : (source.googleCode ?? "auto")
            let googleTo = target.googleCode ?? "zh-CN"
            do {
                return try await translateWithGoogleWeb(text: trimmed, from: googleFrom, to: googleTo)
            } catch {
                throw error
            }
        }
    }
    
    private static func translateWithEdge(text: String, from: String, to: String) async throws -> String {
        guard let url = URL(string: "https://edge.microsoft.com/translate/translatetext?from=\(from)&to=\(to)") else {
            throw TranslationError.apiError("Invalid URL")
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36 Edg/120.0.0.0", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 8
        
        let jsonBody = try JSONSerialization.data(withJSONObject: [text])
        request.httpBody = jsonBody
        
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw TranslationError.networkError(error)
        }
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw TranslationError.apiError("HTTP status \(code)")
        }
        
        struct EdgeResponseItem: Decodable {
            struct TranslationItem: Decodable {
                let text: String
            }
            let translations: [TranslationItem]
        }
        
        guard let items = try? JSONDecoder().decode([EdgeResponseItem].self, from: data),
              let firstItem = items.first,
              let firstTranslation = firstItem.translations.first,
              !firstTranslation.text.isEmpty else {
            throw TranslationError.emptyResult
        }
        
        return firstTranslation.text
    }
    
    private static func translateWithGoogleWeb(text: String, from: String, to: String) async throws -> String {
        guard let encodedText = text.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://translate.googleapis.com/translate_a/single?client=gtx&sl=\(from)&tl=\(to)&dt=t&q=\(encodedText)") else {
            throw TranslationError.apiError("Invalid Google URL")
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 8
        
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw TranslationError.networkError(error)
        }
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw TranslationError.apiError("HTTP status \(code)")
        }
        
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [Any],
              let sentences = json.first as? [Any] else {
            throw TranslationError.decodingError
        }
        
        var fullTranslated = ""
        for item in sentences {
            if let tuple = item as? [Any], let part = tuple.first as? String {
                fullTranslated += part
            }
        }
        
        guard !fullTranslated.isEmpty else {
            throw TranslationError.emptyResult
        }
        
        return fullTranslated
    }
    
    public static func testConnection() async throws -> String {
        return try await translate(text: "Hello", source: .english, target: .simplifiedChinese)
    }
}
