import Foundation
import CryptoKit
import Combine

@MainActor
public final class BaiduConfig: ObservableObject {
    public static let shared = BaiduConfig()
    
    @Published public var appId: String {
        didSet {
            UserDefaults.standard.set(appId, forKey: "baidu_translate_app_id")
        }
    }
    
    @Published public var secretKey: String {
        didSet {
            UserDefaults.standard.set(secretKey, forKey: "baidu_translate_secret_key")
        }
    }
    
    public var isConfigured: Bool {
        !appId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !secretKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    
    private init() {
        self.appId = UserDefaults.standard.string(forKey: "baidu_translate_app_id") ?? ""
        self.secretKey = UserDefaults.standard.string(forKey: "baidu_translate_secret_key") ?? ""
    }
    
    public func save(appId: String, secretKey: String) {
        self.appId = appId.trimmingCharacters(in: .whitespacesAndNewlines)
        self.secretKey = secretKey.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

public struct BaiduTranslator {
    public enum TranslationError: LocalizedError {
        case missingCredentials
        case apiError(code: String, message: String)
        case emptyResult
        case networkError(Error)
        case decodingError
        
        public var errorDescription: String? {
            switch self {
            case .missingCredentials:
                return "未配置百度翻译 AppID 或密钥，请前往设置中填写"
            case .apiError(let code, let message):
                return "百度翻译错误 (\(code)): \(message)"
            case .emptyResult:
                return "百度翻译未返回有效结果"
            case .networkError(let error):
                return "百度翻译网络连接失败: \(error.localizedDescription)"
            case .decodingError:
                return "解析百度翻译响应数据失败"
            }
        }
    }
    
    public static func translate(
        text: String,
        sourceCode: String?,
        targetCode: String,
        appId: String,
        secretKey: String
    ) async throws -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        
        let trimmedAppId = appId.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedKey = secretKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedAppId.isEmpty && !trimmedKey.isEmpty else {
            throw TranslationError.missingCredentials
        }
        
        let salt = String(Int.random(in: 100000...999999))
        let signStr = "\(trimmedAppId)\(trimmed)\(salt)\(trimmedKey)"
        let sign = Insecure.MD5.hash(data: Data(signStr.utf8)).map { String(format: "%02x", $0) }.joined()
        
        let fromLang = (sourceCode == nil || sourceCode?.isEmpty == true || sourceCode == "auto") ? "auto" : sourceCode!
        let toLang = targetCode
        
        let components = URLComponents(string: "https://fanyi-api.baidu.com/api/trans/vip/translate")
        let queryParams = [
            "q": trimmed,
            "from": fromLang,
            "to": toLang,
            "appid": trimmedAppId,
            "salt": salt,
            "sign": sign
        ]
        
        // Use POST with form url-encoded body for unicode safety and large payloads
        guard let url = components?.url else {
            throw TranslationError.decodingError
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded; charset=utf-8", forHTTPHeaderField: "Content-Type")
        
        let allowedCharset = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
        let bodyString = queryParams.compactMap { key, value in
            let escapedKey = key.addingPercentEncoding(withAllowedCharacters: allowedCharset) ?? key
            let escapedValue = value.addingPercentEncoding(withAllowedCharacters: allowedCharset) ?? value
            return "\(escapedKey)=\(escapedValue)"
        }.joined(separator: "&")
        
        request.httpBody = Data(bodyString.utf8)
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
        
        if let errorCode = json["error_code"] as? String, errorCode != "52000" {
            let errorMsg = (json["error_msg"] as? String) ?? "未知错误"
            throw TranslationError.apiError(code: errorCode, message: errorMsg)
        }
        
        if httpResponse.statusCode != 200 {
            throw TranslationError.apiError(code: "\(httpResponse.statusCode)", message: "HTTP 状态码异常")
        }
        
        if let transResult = json["trans_result"] as? [[String: Any]], !transResult.isEmpty {
            let translatedParts = transResult.compactMap { $0["dst"] as? String }
            if !translatedParts.isEmpty {
                return translatedParts.joined(separator: "\n")
            }
        }
        
        throw TranslationError.emptyResult
    }
    
    public static func testConnection(appId: String, secretKey: String) async throws -> Bool {
        _ = try await translate(text: "Hello", sourceCode: "en", targetCode: "zh", appId: appId, secretKey: secretKey)
        return true
    }
}
