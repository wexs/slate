import Foundation
import Combine

@MainActor
public final class MicrosoftConfig: ObservableObject {
    public static let shared = MicrosoftConfig()
    
    @Published public var apiKey: String {
        didSet {
            UserDefaults.standard.set(apiKey, forKey: "microsoft_translate_api_key")
        }
    }
    
    @Published public var region: String {
        didSet {
            UserDefaults.standard.set(region, forKey: "microsoft_translate_region")
        }
    }
    
    public var isConfigured: Bool {
        !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    
    private init() {
        self.apiKey = UserDefaults.standard.string(forKey: "microsoft_translate_api_key") ?? ""
        self.region = UserDefaults.standard.string(forKey: "microsoft_translate_region") ?? "global"
    }
    
    public func save(apiKey: String, region: String) {
        self.apiKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedRegion = region.trimmingCharacters(in: .whitespacesAndNewlines)
        self.region = trimmedRegion.isEmpty ? "global" : trimmedRegion
    }
}

public struct MicrosoftTranslator {
    public enum TranslationError: LocalizedError {
        case missingCredentials
        case apiError(statusCode: Int, message: String)
        case emptyResult
        case networkError(Error)
        case decodingError
        
        public var errorDescription: String? {
            switch self {
            case .missingCredentials:
                return "未配置微软翻译密钥，请前往设置配置 API 密钥"
            case .apiError(let statusCode, let message):
                return "微软翻译错误 (\(statusCode)): \(message)"
            case .emptyResult:
                return "微软翻译未返回有效结果"
            case .networkError(let error):
                return "微软翻译网络连接失败: \(error.localizedDescription)"
            case .decodingError:
                return "解析微软翻译响应数据失败"
            }
        }
    }
    
    public static func translate(
        text: String,
        sourceCode: String?,
        targetCode: String,
        apiKey: String,
        region: String = "global"
    ) async throws -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else {
            throw TranslationError.missingCredentials
        }
        
        var queryItems = [
            URLQueryItem(name: "api-version", value: "3.0"),
            URLQueryItem(name: "to", value: targetCode)
        ]
        if let source = sourceCode, !source.isEmpty, source.lowercased() != "auto" {
            queryItems.append(URLQueryItem(name: "from", value: source))
        }
        
        var components = URLComponents(string: "https://api.cognitive.microsofttranslator.com/translate")
        components?.queryItems = queryItems
        
        guard let url = components?.url else {
            throw TranslationError.decodingError
        }
        
        let bodyArray: [[String: String]] = [["Text": trimmed]]
        let bodyData = try JSONSerialization.data(withJSONObject: bodyArray)
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(trimmedKey, forHTTPHeaderField: "Ocp-Apim-Subscription-Key")
        let trimmedRegion = region.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedRegion.isEmpty {
            request.setValue(trimmedRegion, forHTTPHeaderField: "Ocp-Apim-Subscription-Region")
        }
        request.setValue("application/json; charset=UTF-8", forHTTPHeaderField: "Content-Type")
        request.httpBody = bodyData
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
        
        if httpResponse.statusCode != 200 {
            if let errorObj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let errorDetails = errorObj["error"] as? [String: Any],
               let message = errorDetails["message"] as? String {
                throw TranslationError.apiError(statusCode: httpResponse.statusCode, message: message)
            }
            let rawMsg = String(data: data, encoding: .utf8) ?? "未知错误"
            throw TranslationError.apiError(statusCode: httpResponse.statusCode, message: rawMsg)
        }
        
        guard let jsonArray = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
              let firstItem = jsonArray.first,
              let translations = firstItem["translations"] as? [[String: Any]],
              let firstTrans = translations.first,
              let translatedText = firstTrans["text"] as? String else {
            throw TranslationError.emptyResult
        }
        
        return translatedText
    }
    
    public static func testConnection(apiKey: String, region: String) async throws -> Bool {
        _ = try await translate(text: "Hello", sourceCode: "en", targetCode: "zh-Hans", apiKey: apiKey, region: region)
        return true
    }
}
