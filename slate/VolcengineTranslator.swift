import Foundation
import CryptoKit
import Combine

@MainActor
public final class VolcengineConfig: ObservableObject {
    public static let shared = VolcengineConfig()
    
    @Published public var accessKey: String {
        didSet {
            UserDefaults.standard.set(accessKey, forKey: "volcengine_access_key")
        }
    }
    
    @Published public var secretKey: String {
        didSet {
            UserDefaults.standard.set(secretKey, forKey: "volcengine_secret_key")
        }
    }
    
    public var isConfigured: Bool {
        !accessKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !secretKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    
    private init() {
        self.accessKey = UserDefaults.standard.string(forKey: "volcengine_access_key") ?? ""
        self.secretKey = UserDefaults.standard.string(forKey: "volcengine_secret_key") ?? ""
    }
    
    public func save(accessKey: String, secretKey: String) {
        self.accessKey = accessKey.trimmingCharacters(in: .whitespacesAndNewlines)
        self.secretKey = secretKey.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

public struct VolcengineTranslator {
    public enum TranslationError: LocalizedError {
        case missingCredentials
        case apiError(code: String, message: String)
        case emptyResult
        case networkError(Error)
        case decodingError
        
        public var errorDescription: String? {
            switch self {
            case .missingCredentials:
                return "未配置火山翻译密钥，请前往设置配置 AccessKey 与 SecretKey"
            case .apiError(let code, let message):
                return "火山翻译错误 (\(code)): \(message)"
            case .emptyResult:
                return "火山翻译未返回有效结果"
            case .networkError(let error):
                return "网络连接失败: \(error.localizedDescription)"
            case .decodingError:
                return "解析火山翻译响应数据失败"
            }
        }
    }
    
    private static let host = "translate.volcengineapi.com"
    private static let path = "/"
    private static let query = "Action=TranslateText&Version=2020-06-01"
    private static let region = "cn-north-1"
    private static let service = "translate"
    
    public static func translate(
        text: String,
        sourceCode: String?,
        targetCode: String,
        accessKey: String,
        secretKey: String
    ) async throws -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        guard !accessKey.isEmpty && !secretKey.isEmpty else {
            throw TranslationError.missingCredentials
        }
        
        var bodyDict: [String: Any] = [
            "TargetLanguage": targetCode,
            "TextList": [trimmed]
        ]
        if let source = sourceCode, !source.isEmpty {
            bodyDict["SourceLanguage"] = source
        }
        
        let bodyData = try JSONSerialization.data(withJSONObject: bodyDict, options: [])
        let request = try buildSignedRequest(
            bodyData: bodyData,
            accessKey: accessKey,
            secretKey: secretKey
        )
        
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw TranslationError.networkError(error)
        }
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw TranslationError.decodingError
        }
        
        // Parse JSON response
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw TranslationError.decodingError
        }
        
        // Check for ResponseMetadata.Error
        if let metadata = json["ResponseMetadata"] as? [String: Any],
           let errorObj = metadata["Error"] as? [String: Any] {
            let code = (errorObj["Code"] as? String) ?? "UnknownCode"
            let message = (errorObj["Message"] as? String) ?? "未知错误"
            throw TranslationError.apiError(code: code, message: message)
        }
        
        // Check HTTP status code
        if httpResponse.statusCode != 200 {
            throw TranslationError.apiError(code: "\(httpResponse.statusCode)", message: "HTTP 状态码异常")
        }
        
        // Extract translation
        guard let translationList = json["TranslationList"] as? [[String: Any]],
              let firstItem = translationList.first,
              let translatedText = firstItem["Translation"] as? String else {
            throw TranslationError.emptyResult
        }
        
        return translatedText
    }
    
    public static func testConnection(accessKey: String, secretKey: String) async throws -> Bool {
        _ = try await translate(
            text: "Hello",
            sourceCode: "en",
            targetCode: "zh",
            accessKey: accessKey,
            secretKey: secretKey
        )
        return true
    }
    
    // MARK: - Volcengine V4 Signature
    private static func buildSignedRequest(
        bodyData: Data,
        accessKey: String,
        secretKey: String
    ) throws -> URLRequest {
        let date = Date()
        
        let dateFormatter = DateFormatter()
        dateFormatter.timeZone = TimeZone(identifier: "UTC")
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        let xDate = dateFormatter.string(from: date)
        
        let shortDateFormatter = DateFormatter()
        shortDateFormatter.timeZone = TimeZone(identifier: "UTC")
        shortDateFormatter.locale = Locale(identifier: "en_US_POSIX")
        shortDateFormatter.dateFormat = "yyyyMMdd"
        let shortDate = shortDateFormatter.string(from: date)
        
        let payloadHash = sha256Hex(bodyData)
        let canonicalHeaders = "content-type:application/json\nhost:\(host)\nx-content-sha256:\(payloadHash)\nx-date:\(xDate)\n"
        let signedHeaders = "content-type;host;x-content-sha256;x-date"
        let canonicalRequest = "POST\n\(path)\n\(query)\n\(canonicalHeaders)\n\(signedHeaders)\n\(payloadHash)"
        let canonicalRequestHash = sha256Hex(Data(canonicalRequest.utf8))
        
        let credentialScope = "\(shortDate)/\(region)/\(service)/request"
        let stringToSign = "HMAC-SHA256\n\(xDate)\n\(credentialScope)\n\(canonicalRequestHash)"
        
        let kDate = hmacSHA256(key: Data(secretKey.utf8), data: Data(shortDate.utf8))
        let kRegion = hmacSHA256(key: kDate, data: Data(region.utf8))
        let kService = hmacSHA256(key: kRegion, data: Data(service.utf8))
        let kSigning = hmacSHA256(key: kService, data: Data("request".utf8))
        let signature = hmacSHA256Hex(key: kSigning, data: Data(stringToSign.utf8))
        
        let authHeader = "HMAC-SHA256 Credential=\(accessKey)/\(credentialScope), SignedHeaders=\(signedHeaders), Signature=\(signature)"
        
        guard let url = URL(string: "https://\(host)\(path)?\(query)") else {
            throw TranslationError.decodingError
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(host, forHTTPHeaderField: "Host")
        request.setValue(xDate, forHTTPHeaderField: "X-Date")
        request.setValue(payloadHash, forHTTPHeaderField: "X-Content-Sha256")
        request.setValue(authHeader, forHTTPHeaderField: "Authorization")
        request.httpBody = bodyData
        request.timeoutInterval = 10
        
        return request
    }
    
    private static func sha256Hex(_ data: Data) -> String {
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
    
    private static func hmacSHA256(key: Data, data: Data) -> Data {
        let symmetricKey = SymmetricKey(data: key)
        let mac = HMAC<SHA256>.authenticationCode(for: data, using: symmetricKey)
        return Data(mac)
    }
    
    private static func hmacSHA256Hex(key: Data, data: Data) -> String {
        return hmacSHA256(key: key, data: data).map { String(format: "%02x", $0) }.joined()
    }
}
