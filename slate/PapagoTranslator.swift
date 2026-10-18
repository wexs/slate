import Foundation
import Combine

@MainActor
public final class PapagoConfig: ObservableObject {
    public static let shared = PapagoConfig()
    
    @Published public var clientId: String {
        didSet {
            UserDefaults.standard.set(clientId, forKey: "papago_translate_client_id")
        }
    }
    
    @Published public var clientSecret: String {
        didSet {
            UserDefaults.standard.set(clientSecret, forKey: "papago_translate_client_secret")
        }
    }
    
    public var isConfigured: Bool {
        !clientId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !clientSecret.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    
    private init() {
        self.clientId = UserDefaults.standard.string(forKey: "papago_translate_client_id") ?? ""
        self.clientSecret = UserDefaults.standard.string(forKey: "papago_translate_client_secret") ?? ""
    }
    
    public func save(clientId: String, clientSecret: String) {
        self.clientId = clientId.trimmingCharacters(in: .whitespacesAndNewlines)
        self.clientSecret = clientSecret.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

public struct PapagoTranslator {
    public enum TranslationError: LocalizedError {
        case missingCredentials
        case apiError(code: String, message: String)
        case unsupportedLanguagePair(source: String, target: String)
        case emptyResult
        case networkError(Error)
        case decodingError
        
        public var errorDescription: String? {
            switch self {
            case .missingCredentials:
                return loc("papago_err_missing_credentials")
            case .apiError(let code, let message):
                return "Papago (\(code)): \(message)"
            case .unsupportedLanguagePair(let source, let target):
                return "Papago 暂不支持 \(source) 到 \(target) 的互译"
            case .emptyResult:
                return loc("papago_err_empty_result")
            case .networkError(let error):
                return "\(loc("network_error")): \(error.localizedDescription)"
            case .decodingError:
                return loc("decode_error")
            }
        }
    }
    
    public static func translate(
        text: String,
        sourceCode: String?,
        targetCode: String,
        clientId: String,
        clientSecret: String
    ) async throws -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        
        let trimmedId = clientId.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedSecret = clientSecret.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedId.isEmpty && !trimmedSecret.isEmpty else {
            throw TranslationError.missingCredentials
        }
        
        let fromLang = (sourceCode == nil || sourceCode?.isEmpty == true || sourceCode == "auto") ? "auto" : sourceCode!
        let toLang = targetCode
        
        // 1. Try NAVER Cloud Platform endpoint first (Standard)
        do {
            return try await executeRequest(
                endpoint: "https://papago.apigw.ntruss.com/nmt/v1/translation",
                headers: [
                    "X-NCP-APIGW-API-KEY-ID": trimmedId,
                    "X-NCP-APIGW-API-KEY": trimmedSecret
                ],
                text: trimmed,
                source: fromLang,
                target: toLang
            )
        } catch let TranslationError.apiError(code, _) where code == "401" || code == "403" || code == "010" || code == "024" {
            // 2. Fallback to NAVER Developers legacy endpoint in case user created credentials on openapi.naver.com
            return try await executeRequest(
                endpoint: "https://openapi.naver.com/v1/papago/n2mt",
                headers: [
                    "X-Naver-Client-Id": trimmedId,
                    "X-Naver-Client-Secret": trimmedSecret
                ],
                text: trimmed,
                source: fromLang,
                target: toLang
            )
        }
    }
    
    private static func executeRequest(
        endpoint: String,
        headers: [String: String],
        text: String,
        source: String,
        target: String
    ) async throws -> String {
        guard let url = URL(string: endpoint) else {
            throw TranslationError.decodingError
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded; charset=UTF-8", forHTTPHeaderField: "Content-Type")
        for (key, val) in headers {
            request.setValue(val, forHTTPHeaderField: key)
        }
        request.timeoutInterval = 10
        
        let allowedCharset = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
        let params: [(String, String)] = [
            ("source", source),
            ("target", target),
            ("text", text)
        ]
        let bodyString = params.compactMap { key, value in
            let escapedKey = key.addingPercentEncoding(withAllowedCharacters: allowedCharset) ?? key
            let escapedVal = value.addingPercentEncoding(withAllowedCharacters: allowedCharset) ?? value
            return "\(escapedKey)=\(escapedVal)"
        }.joined(separator: "&")
        
        request.httpBody = Data(bodyString.utf8)
        
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw TranslationError.networkError(error)
        }
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw TranslationError.decodingError
        }
        
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        
        if httpResponse.statusCode != 200 {
            if let json = json {
                if let errObj = json["error"] as? [String: Any] {
                    let code = (errObj["errorCode"] as? String) ?? "\(httpResponse.statusCode)"
                    let msg = (errObj["message"] as? String) ?? "API 错误"
                    throw TranslationError.apiError(code: code, message: msg)
                }
                if let msg = json["errorMessage"] as? String {
                    let code = (json["errorCode"] as? String) ?? "\(httpResponse.statusCode)"
                    throw TranslationError.apiError(code: code, message: msg)
                }
            }
            throw TranslationError.apiError(code: "\(httpResponse.statusCode)", message: "HTTP 响应错误")
        }
        
        if let json = json,
           let message = json["message"] as? [String: Any],
           let result = message["result"] as? [String: Any],
           let translatedText = result["translatedText"] as? String,
           !translatedText.isEmpty {
            return translatedText
        }
        
        throw TranslationError.emptyResult
    }
    
    public static func testConnection(clientId: String, clientSecret: String) async throws -> Bool {
        _ = try await translate(
            text: "Hello",
            sourceCode: "en",
            targetCode: "ko",
            clientId: clientId,
            clientSecret: clientSecret
        )
        return true
    }
}
