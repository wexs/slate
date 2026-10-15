import Foundation
import Combine

@MainActor
public final class DeepLConfig: ObservableObject {
    public static let shared = DeepLConfig()
    
    @Published public var authKey: String {
        didSet {
            UserDefaults.standard.set(authKey, forKey: "deepl_auth_key")
        }
    }
    
    public var isConfigured: Bool {
        !authKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    
    public var isFreeAccount: Bool {
        authKey.trimmingCharacters(in: .whitespacesAndNewlines).hasSuffix(":fx")
    }
    
    private init() {
        self.authKey = UserDefaults.standard.string(forKey: "deepl_auth_key") ?? ""
    }
    
    public func save(authKey: String) {
        self.authKey = authKey.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

public struct DeepLTranslator {
    public enum TranslationError: LocalizedError {
        case missingCredentials
        case apiError(statusCode: Int, message: String)
        case emptyResult
        case networkError(Error)
        case decodingError
        
        public var errorDescription: String? {
            switch self {
            case .missingCredentials:
                return "未配置 DeepL API Key，请前往设置中填写"
            case .apiError(let statusCode, let message):
                return "DeepL 翻译错误 (\(statusCode)): \(message)"
            case .emptyResult:
                return "DeepL 翻译未返回有效结果"
            case .networkError(let error):
                return "DeepL 网络连接失败: \(error.localizedDescription)"
            case .decodingError:
                return "解析 DeepL 响应数据失败"
            }
        }
    }
    
    public static func translate(
        text: String,
        sourceCode: String?,
        targetCode: String,
        authKey: String
    ) async throws -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        
        let trimmedKey = authKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else {
            throw TranslationError.missingCredentials
        }
        
        let endpoint = trimmedKey.hasSuffix(":fx")
            ? "https://api-free.deepl.com/v2/translate"
            : "https://api.deepl.com/v2/translate"
            
        guard let url = URL(string: endpoint) else {
            throw TranslationError.decodingError
        }
        
        var bodyDict: [String: Any] = [
            "text": [trimmed],
            "target_lang": targetCode.uppercased()
        ]
        
        if let source = sourceCode, !source.isEmpty, source.lowercased() != "auto" {
            bodyDict["source_lang"] = source.uppercased()
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("DeepL-Auth-Key \(trimmedKey)", forHTTPHeaderField: "Authorization")
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
            let errorMsg = String(data: data, encoding: .utf8) ?? "未知响应"
            throw TranslationError.apiError(statusCode: httpResponse.statusCode, message: errorMsg)
        }
        
        if httpResponse.statusCode != 200 {
            let message = (json["message"] as? String) ?? String(data: data, encoding: .utf8) ?? "HTTP 错误"
            throw TranslationError.apiError(statusCode: httpResponse.statusCode, message: message)
        }
        
        if let translations = json["translations"] as? [[String: Any]],
           let first = translations.first,
           let translatedText = first["text"] as? String {
            return translatedText
        }
        
        throw TranslationError.emptyResult
    }
    
    public static func testConnection(authKey: String) async throws -> Bool {
        _ = try await translate(text: "Hello", sourceCode: "EN", targetCode: "ZH", authKey: authKey)
        return true
    }
}
