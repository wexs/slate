import Foundation
import CryptoKit
import Combine

@MainActor
public final class TencentConfig: ObservableObject {
    public static let shared = TencentConfig()
    
    @Published public var secretId: String {
        didSet {
            UserDefaults.standard.set(secretId, forKey: "tencent_translate_secret_id")
        }
    }
    
    @Published public var secretKey: String {
        didSet {
            UserDefaults.standard.set(secretKey, forKey: "tencent_translate_secret_key")
        }
    }
    
    @Published public var region: String {
        didSet {
            UserDefaults.standard.set(region, forKey: "tencent_translate_region")
        }
    }
    
    public var isConfigured: Bool {
        !secretId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !secretKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    
    private init() {
        self.secretId = UserDefaults.standard.string(forKey: "tencent_translate_secret_id") ?? ""
        self.secretKey = UserDefaults.standard.string(forKey: "tencent_translate_secret_key") ?? ""
        self.region = UserDefaults.standard.string(forKey: "tencent_translate_region") ?? "ap-guangzhou"
    }
    
    public func save(secretId: String, secretKey: String, region: String = "ap-guangzhou") {
        self.secretId = secretId.trimmingCharacters(in: .whitespacesAndNewlines)
        self.secretKey = secretKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedReg = region.trimmingCharacters(in: .whitespacesAndNewlines)
        self.region = trimmedReg.isEmpty ? "ap-guangzhou" : trimmedReg
    }
}

public struct TencentTranslator {
    public enum TranslationError: LocalizedError {
        case missingCredentials
        case apiError(code: String, message: String)
        case emptyResult
        case networkError(Error)
        case decodingError
        
        public var errorDescription: String? {
            switch self {
            case .missingCredentials:
                return "未配置腾讯翻译 SecretId 或 SecretKey，请前往设置中配置"
            case .apiError(let code, let message):
                return "腾讯翻译错误 (\(code)): \(message)"
            case .emptyResult:
                return "腾讯翻译未返回有效结果"
            case .networkError(let error):
                return "腾讯翻译网络连接失败: \(error.localizedDescription)"
            case .decodingError:
                return "解析腾讯翻译响应数据失败"
            }
        }
    }
    
    private static let host = "tmt.tencentcloudapi.com"
    private static let service = "tmt"
    private static let action = "TextTranslate"
    private static let version = "2018-03-21"
    
    public static func translate(
        text: String,
        sourceCode: String?,
        targetCode: String,
        secretId: String,
        secretKey: String,
        region: String = "ap-guangzhou"
    ) async throws -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        
        let trimmedId = secretId.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedKey = secretKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedId.isEmpty && !trimmedKey.isEmpty else {
            throw TranslationError.missingCredentials
        }
        
        let sourceLang = (sourceCode == nil || sourceCode?.isEmpty == true || sourceCode == "auto") ? "auto" : sourceCode!
        let targetLang = targetCode
        
        let bodyDict: [String: Any] = [
            "SourceText": trimmed,
            "Source": sourceLang,
            "Target": targetLang,
            "ProjectId": 0
        ]
        
        let bodyData = try JSONSerialization.data(withJSONObject: bodyDict)
        let request = try buildSignedRequest(
            bodyData: bodyData,
            secretId: trimmedId,
            secretKey: trimmedKey,
            region: region.isEmpty ? "ap-guangzhou" : region
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
        
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let resp = json["Response"] as? [String: Any] else {
            throw TranslationError.decodingError
        }
        
        if let errorObj = resp["Error"] as? [String: Any] {
            let code = (errorObj["Code"] as? String) ?? "UnknownCode"
            let message = (errorObj["Message"] as? String) ?? "未知错误"
            throw TranslationError.apiError(code: code, message: message)
        }
        
        if httpResponse.statusCode != 200 {
            throw TranslationError.apiError(code: "\(httpResponse.statusCode)", message: "HTTP 状态码异常")
        }
        
        if let targetText = resp["TargetText"] as? String, !targetText.isEmpty {
            return targetText
        }
        
        throw TranslationError.emptyResult
    }
    
    public static func testConnection(secretId: String, secretKey: String, region: String = "ap-guangzhou") async throws -> Bool {
        _ = try await translate(text: "Hello", sourceCode: "en", targetCode: "zh", secretId: secretId, secretKey: secretKey, region: region)
        return true
    }
    
    // MARK: - TC3-HMAC-SHA256 Signing
    private static func buildSignedRequest(
        bodyData: Data,
        secretId: String,
        secretKey: String,
        region: String
    ) throws -> URLRequest {
        let date = Date()
        let timestamp = Int(date.timeIntervalSince1970)
        
        let dateFormatter = DateFormatter()
        dateFormatter.timeZone = TimeZone(identifier: "UTC")
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let dateString = dateFormatter.string(from: date)
        
        let payloadHash = sha256Hex(bodyData)
        let canonicalHeaders = "content-type:application/json; charset=utf-8\nhost:\(host)\nx-tc-action:\(action.lowercased())\n"
        let signedHeaders = "content-type;host;x-tc-action"
        let canonicalRequest = "POST\n/\n\n\(canonicalHeaders)\n\(signedHeaders)\n\(payloadHash)"
        let canonicalRequestHash = sha256Hex(Data(canonicalRequest.utf8))
        
        let credentialScope = "\(dateString)/\(service)/tc3_request"
        let stringToSign = "TC3-HMAC-SHA256\n\(timestamp)\n\(credentialScope)\n\(canonicalRequestHash)"
        
        let secretDate = hmacSHA256(key: Data("TC3\(secretKey)".utf8), data: Data(dateString.utf8))
        let secretService = hmacSHA256(key: secretDate, data: Data(service.utf8))
        let secretSigning = hmacSHA256(key: secretService, data: Data("tc3_request".utf8))
        let signature = hmacSHA256Hex(key: secretSigning, data: Data(stringToSign.utf8))
        
        let authorization = "TC3-HMAC-SHA256 Credential=\(secretId)/\(credentialScope), SignedHeaders=\(signedHeaders), Signature=\(signature)"
        
        guard let url = URL(string: "https://\(host)") else {
            throw TranslationError.decodingError
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.setValue(host, forHTTPHeaderField: "Host")
        request.setValue(action, forHTTPHeaderField: "X-TC-Action")
        request.setValue(version, forHTTPHeaderField: "X-TC-Version")
        request.setValue(String(timestamp), forHTTPHeaderField: "X-TC-Timestamp")
        request.setValue(region, forHTTPHeaderField: "X-TC-Region")
        request.setValue(authorization, forHTTPHeaderField: "Authorization")
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
