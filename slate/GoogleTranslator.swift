import Foundation
import Combine

@MainActor
public final class GoogleConfig: ObservableObject {
    public static let shared = GoogleConfig()
    
    @Published public var apiKey: String {
        didSet {
            UserDefaults.standard.set(apiKey, forKey: "google_translate_api_key")
        }
    }
    
    // Google translation can run in free mode even without an API key, or use private Cloud API key if set
    public var isConfigured: Bool {
        true
    }
    
    public var hasCustomKey: Bool {
        !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    
    private init() {
        self.apiKey = UserDefaults.standard.string(forKey: "google_translate_api_key") ?? ""
    }
    
    public func save(apiKey: String) {
        self.apiKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

public struct GoogleTranslator {
    public enum TranslationError: LocalizedError {
        case emptyResult
        case networkError(Error)
        case apiError(String)
        case decodingError
        
        public var errorDescription: String? {
            switch self {
            case .emptyResult:
                return "Google 翻译未返回有效结果"
            case .networkError(let error):
                return "Google 翻译网络连接失败: \(error.localizedDescription)"
            case .apiError(let message):
                return "Google 翻译接口错误: \(message)"
            case .decodingError:
                return "解析 Google 翻译响应失败"
            }
        }
    }
    
    public static func translate(
        text: String,
        sourceCode: String?,
        targetCode: String,
        apiKey: String
    ) async throws -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedKey.isEmpty {
            return try await translateWithCloudAPI(text: trimmed, sourceCode: sourceCode, targetCode: targetCode, apiKey: trimmedKey)
        } else {
            return try await translateWithFreeWeb(text: trimmed, sourceCode: sourceCode, targetCode: targetCode)
        }
    }
    
    private static func translateWithFreeWeb(
        text: String,
        sourceCode: String?,
        targetCode: String
    ) async throws -> String {
        let sl = (sourceCode == nil || sourceCode == "auto") ? "auto" : sourceCode!
        let tl = targetCode
        
        guard let encodedText = text.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://translate.googleapis.com/translate_a/single?client=gtx&sl=\(sl)&tl=\(tl)&dt=t&q=\(encodedText)") else {
            throw TranslationError.apiError("URL 编码错误")
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 10
        
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw TranslationError.networkError(error)
        }
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw TranslationError.apiError("HTTP 状态码: \(code)")
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
    
    private static func translateWithCloudAPI(
        text: String,
        sourceCode: String?,
        targetCode: String,
        apiKey: String
    ) async throws -> String {
        guard let url = URL(string: "https://translation.googleapis.com/language/translate/v2?key=\(apiKey)") else {
            throw TranslationError.apiError("Google Cloud API URL 异常")
        }
        
        var bodyDict: [String: Any] = [
            "q": [text],
            "target": targetCode,
            "format": "text"
        ]
        if let sl = sourceCode, sl != "auto" {
            bodyDict["source"] = sl
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: bodyDict)
        request.timeoutInterval = 10
        
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw TranslationError.networkError(error)
        }
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw TranslationError.decodingError
        }
        
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw TranslationError.decodingError
        }
        
        if let errorObj = json["error"] as? [String: Any],
           let message = errorObj["message"] as? String {
            throw TranslationError.apiError(message)
        }
        
        if httpResponse.statusCode != 200 {
            throw TranslationError.apiError("HTTP 状态码: \(httpResponse.statusCode)")
        }
        
        if let dataObj = json["data"] as? [String: Any],
           let translations = dataObj["translations"] as? [[String: Any]],
           let first = translations.first,
           let translatedText = first["translatedText"] as? String {
            return translatedText
        }
        
        throw TranslationError.emptyResult
    }
    
    public static func testConnection(apiKey: String) async throws -> Bool {
        _ = try await translate(text: "Hello", sourceCode: "en", targetCode: "zh-CN", apiKey: apiKey)
        return true
    }
}
