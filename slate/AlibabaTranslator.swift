import Foundation
import CryptoKit
import Combine

@MainActor
public final class AlibabaConfig: ObservableObject {
    public static let shared = AlibabaConfig()
    
    @Published public var accessKeyId: String {
        didSet {
            UserDefaults.standard.set(accessKeyId, forKey: "alibaba_translate_access_key_id")
        }
    }
    
    @Published public var accessKeySecret: String {
        didSet {
            UserDefaults.standard.set(accessKeySecret, forKey: "alibaba_translate_access_key_secret")
        }
    }
    
    public var isConfigured: Bool {
        !accessKeyId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !accessKeySecret.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    
    private init() {
        self.accessKeyId = UserDefaults.standard.string(forKey: "alibaba_translate_access_key_id") ?? ""
        self.accessKeySecret = UserDefaults.standard.string(forKey: "alibaba_translate_access_key_secret") ?? ""
    }
    
    public func save(accessKeyId: String, accessKeySecret: String) {
        self.accessKeyId = accessKeyId.trimmingCharacters(in: .whitespacesAndNewlines)
        self.accessKeySecret = accessKeySecret.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

public struct AlibabaTranslator {
    public enum TranslationError: LocalizedError {
        case missingCredentials
        case apiError(code: String, message: String)
        case emptyResult
        case networkError(Error)
        case decodingError
        
        public var errorDescription: String? {
            switch self {
            case .missingCredentials:
                return "未配置阿里翻译 AccessKey ID 或 AccessKey Secret，请前往设置中配置"
            case .apiError(let code, let message):
                return "阿里翻译错误 (\(code)): \(message)"
            case .emptyResult:
                return "阿里翻译未返回有效结果"
            case .networkError(let error):
                return "阿里翻译网络连接失败: \(error.localizedDescription)"
            case .decodingError:
                return "解析阿里翻译响应数据失败"
            }
        }
    }
    
    public static func translate(
        text: String,
        sourceCode: String?,
        targetCode: String,
        accessKeyId: String,
        accessKeySecret: String
    ) async throws -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        
        let trimmedKeyId = accessKeyId.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedKeySec = accessKeySecret.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKeyId.isEmpty && !trimmedKeySec.isEmpty else {
            throw TranslationError.missingCredentials
        }
        
        let dateFormatter = DateFormatter()
        dateFormatter.timeZone = TimeZone(identifier: "UTC")
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss'Z'"
        let timestamp = dateFormatter.string(from: Date())
        
        let sourceLang = (sourceCode == nil || sourceCode?.isEmpty == true || sourceCode == "auto") ? "auto" : sourceCode!
        let targetLang = targetCode
        
        var params: [String: String] = [
            "Format": "JSON",
            "Version": "2018-10-12",
            "AccessKeyId": trimmedKeyId,
            "SignatureMethod": "HMAC-SHA1",
            "Timestamp": timestamp,
            "SignatureVersion": "1.0",
            "SignatureNonce": UUID().uuidString,
            "Action": "TranslateGeneral",
            "FormatType": "text",
            "SourceLanguage": sourceLang,
            "TargetLanguage": targetLang,
            "SourceText": trimmed,
            "Scene": "general"
        ]
        
        let sortedKeys = params.keys.sorted()
        let canonicalizedQueryString = sortedKeys.map { key in
            "\(percentEncode(key))=\(percentEncode(params[key]!))"
        }.joined(separator: "&")
        
        let stringToSign = "POST&%2F&" + percentEncode(canonicalizedQueryString)
        let signKey = trimmedKeySec + "&"
        let signature = hmacSHA1Base64(key: Data(signKey.utf8), data: Data(stringToSign.utf8))
        
        params["Signature"] = signature
        
        guard let url = URL(string: "https://mt.cn-hangzhou.aliyuncs.com/") else {
            throw TranslationError.decodingError
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded; charset=utf-8", forHTTPHeaderField: "Content-Type")
        
        let postBodyString = params.map { key, value in
            "\(percentEncode(key))=\(percentEncode(value))"
        }.joined(separator: "&")
        request.httpBody = Data(postBodyString.utf8)
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
        
        let code = (json["Code"] as? String) ?? "\(httpResponse.statusCode)"
        if code != "200" {
            let message = (json["Message"] as? String) ?? (json["message"] as? String) ?? "未知错误"
            throw TranslationError.apiError(code: code, message: message)
        }
        
        if let dataObj = json["Data"] as? [String: Any],
           let translated = dataObj["Translated"] as? String, !translated.isEmpty {
            return translated
        }
        
        throw TranslationError.emptyResult
    }
    
    public static func testConnection(accessKeyId: String, accessKeySecret: String) async throws -> Bool {
        _ = try await translate(text: "Hello", sourceCode: "en", targetCode: "zh", accessKeyId: accessKeyId, accessKeySecret: accessKeySecret)
        return true
    }
    
    // MARK: - RFC 3986 Percent Encoding
    private static func percentEncode(_ string: String) -> String {
        let unreserved = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_.~"))
        return string.addingPercentEncoding(withAllowedCharacters: unreserved)?
            .replacingOccurrences(of: "*", with: "%2A")
            .replacingOccurrences(of: "+", with: "%20") ?? string
    }
    
    private static func hmacSHA1Base64(key: Data, data: Data) -> String {
        let symmetricKey = SymmetricKey(data: key)
        let mac = HMAC<Insecure.SHA1>.authenticationCode(for: data, using: symmetricKey)
        return Data(mac).base64EncodedString()
    }
}
