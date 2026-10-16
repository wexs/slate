import Foundation
import Combine
import NaturalLanguage

@MainActor
public final class GoogleSpeechConfig: ObservableObject {
    public static let shared = GoogleSpeechConfig()
    
    @Published public var apiKey: String {
        didSet {
            UserDefaults.standard.set(apiKey, forKey: "google_speech_api_key")
        }
    }
    
    /// Google Speech works immediately out of the box in free mode, or uses private Google Cloud API key if provided
    public var isConfigured: Bool {
        true
    }
    
    public var hasCustomKey: Bool {
        !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    
    private init() {
        self.apiKey = UserDefaults.standard.string(forKey: "google_speech_api_key") ?? ""
    }
    
    public func save(apiKey: String) {
        self.apiKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

public struct GoogleSpeechSynthesizer {
    public enum SpeechError: LocalizedError {
        case emptyInput
        case invalidUrl
        case networkError(Error)
        case apiError(String)
        case invalidAudioData
        
        public var errorDescription: String? {
            switch self {
            case .emptyInput:
                return "朗读内容为空"
            case .invalidUrl:
                return "Google 语音请求地址无效"
            case .networkError(let error):
                return "Google 语音网络连接失败: \(error.localizedDescription)"
            case .apiError(let message):
                return "Google 语音服务错误: \(message)"
            case .invalidAudioData:
                return "未能获取有效的 Google 语音音频数据"
            }
        }
    }
    
    /// Synthesizes text into audio MP3 data using either Google Cloud Text-to-Speech API (if API key is present) or free web TTS
    public static func synthesize(
        text: String,
        languageCode: String? = nil,
        rate: Double = 1.0,
        apiKey: String = ""
    ) async throws -> Data {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw SpeechError.emptyInput
        }
        
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedLang = resolveLanguageCode(for: trimmed, requestedCode: languageCode)
        
        if !trimmedKey.isEmpty {
            do {
                return try await synthesizeWithCloudAPI(text: trimmed, languageCode: resolvedLang, rate: rate, apiKey: trimmedKey)
            } catch {
                // If Cloud TTS fails, fall back gracefully to free web endpoint
                print("Google Cloud TTS API failed: \(error.localizedDescription), falling back to free TTS web service.")
                return try await synthesizeWithFreeWeb(text: trimmed, languageCode: resolvedLang)
            }
        } else {
            return try await synthesizeWithFreeWeb(text: trimmed, languageCode: resolvedLang)
        }
    }
    
    /// Tests connection by synthesizing a short greeting audio
    public static func testConnection(apiKey: String = "") async throws -> Data {
        let testPhrase = "Hello! Google Speech is ready to speak."
        return try await synthesize(text: testPhrase, languageCode: "en-US", rate: 1.0, apiKey: apiKey)
    }
    
    // MARK: - 1. Google Cloud Text-to-Speech API
    private static func synthesizeWithCloudAPI(
        text: String,
        languageCode: String,
        rate: Double,
        apiKey: String
    ) async throws -> Data {
        guard let url = URL(string: "https://texttospeech.googleapis.com/v1/text:synthesize?key=\(apiKey)") else {
            throw SpeechError.invalidUrl
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 15
        
        let bcp47Code = formatCloudBCP47(languageCode)
        let payload: [String: Any] = [
            "input": [
                "text": text
            ],
            "voice": [
                "languageCode": bcp47Code
            ],
            "audioConfig": [
                "audioEncoding": "MP3",
                "speakingRate": max(0.5, min(2.0, rate))
            ]
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: payload, options: [])
        
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw SpeechError.networkError(error)
        }
        
        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let errObj = json["error"] as? [String: Any],
               let message = errObj["message"] as? String {
                throw SpeechError.apiError("(\(httpResponse.statusCode)) \(message)")
            }
            throw SpeechError.apiError("HTTP \(httpResponse.statusCode)")
        }
        
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let audioBase64 = json["audioContent"] as? String,
              let audioData = Data(base64Encoded: audioBase64),
              !audioData.isEmpty else {
            throw SpeechError.invalidAudioData
        }
        
        return audioData
    }
    
    // MARK: - 2. Free Web Google TTS
    private static func synthesizeWithFreeWeb(
        text: String,
        languageCode: String
    ) async throws -> Data {
        let chunks = splitTextIntoChunks(text, maxLength: 150)
        guard !chunks.isEmpty else {
            throw SpeechError.emptyInput
        }
        
        var combinedAudio = Data()
        for chunk in chunks {
            let chunkData = try await fetchSingleFreeChunk(chunk, languageCode: languageCode)
            combinedAudio.append(chunkData)
        }
        
        guard !combinedAudio.isEmpty else {
            throw SpeechError.invalidAudioData
        }
        
        return combinedAudio
    }
    
    private static func fetchSingleFreeChunk(
        _ text: String,
        languageCode: String
    ) async throws -> Data {
        guard var components = URLComponents(string: "https://translate.google.com/translate_tts") else {
            throw SpeechError.invalidUrl
        }
        
        components.queryItems = [
            URLQueryItem(name: "ie", value: "UTF-8"),
            URLQueryItem(name: "client", value: "tw-ob"),
            URLQueryItem(name: "tl", value: languageCode),
            URLQueryItem(name: "q", value: text)
        ]
        
        guard let url = components.url else {
            throw SpeechError.invalidUrl
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 12
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko)", forHTTPHeaderField: "User-Agent")
        request.setValue("https://translate.google.com/", forHTTPHeaderField: "Referer")
        
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw SpeechError.networkError(error)
        }
        
        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
            throw SpeechError.apiError("HTTP \(httpResponse.statusCode)")
        }
        
        guard !data.isEmpty else {
            throw SpeechError.invalidAudioData
        }
        
        return data
    }
    
    // MARK: - Chunking & Language Helpers
    private static func splitTextIntoChunks(_ text: String, maxLength: Int) -> [String] {
        if text.count <= maxLength {
            return [text]
        }
        
        var chunks: [String] = []
        var currentChunk = ""
        
        let sentences = text.components(separatedBy: CharacterSet(charactersIn: "。！？\n.!?\r"))
        for sentence in sentences {
            let trimmed = sentence.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            
            if (currentChunk.count + trimmed.count + 1) <= maxLength {
                if currentChunk.isEmpty {
                    currentChunk = trimmed
                } else {
                    currentChunk += " " + trimmed
                }
            } else {
                if !currentChunk.isEmpty {
                    chunks.append(currentChunk)
                    currentChunk = ""
                }
                
                if trimmed.count <= maxLength {
                    currentChunk = trimmed
                } else {
                    // Force slice overly long sentences
                    var remaining = trimmed
                    while remaining.count > maxLength {
                        let index = remaining.index(remaining.startIndex, offsetBy: maxLength)
                        let part = String(remaining[..<index])
                        chunks.append(part)
                        remaining = String(remaining[index...])
                    }
                    if !remaining.isEmpty {
                        currentChunk = remaining
                    }
                }
            }
        }
        
        if !currentChunk.isEmpty {
            chunks.append(currentChunk)
        }
        
        return chunks.isEmpty ? [text] : chunks
    }
    
    public static func resolveLanguageCode(for text: String, requestedCode: String?) -> String {
        if let req = requestedCode, !req.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let lower = req.lowercased()
            if lower.hasPrefix("zh-hant") || lower.hasPrefix("zh-tw") || lower.hasPrefix("zh-hk") {
                return "zh-TW"
            }
            if lower.hasPrefix("zh") {
                return "zh-CN"
            }
            if lower.hasPrefix("en") {
                return "en"
            }
            if lower.hasPrefix("ja") {
                return "ja"
            }
            if lower.hasPrefix("ko") {
                return "ko"
            }
            if lower.hasPrefix("ru") {
                return "ru"
            }
            if lower.hasPrefix("es") {
                return "es"
            }
            if lower.hasPrefix("fr") {
                return "fr"
            }
            if lower.hasPrefix("de") {
                return "de"
            }
            if lower.hasPrefix("it") {
                return "it"
            }
            return req
        }
        
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        guard let dominant = recognizer.dominantLanguage else {
            return "zh-CN"
        }
        
        switch dominant {
        case .simplifiedChinese: return "zh-CN"
        case .traditionalChinese: return "zh-TW"
        case .english: return "en"
        case .japanese: return "ja"
        case .korean: return "ko"
        case .russian: return "ru"
        case .spanish: return "es"
        case .french: return "fr"
        case .german: return "de"
        case .italian: return "it"
        default: return dominant.rawValue
        }
    }
    
    private static func formatCloudBCP47(_ langCode: String) -> String {
        switch langCode.lowercased() {
        case "zh-cn", "zh": return "zh-CN"
        case "zh-tw", "zh-hk": return "zh-TW"
        case "en", "en-us": return "en-US"
        case "ja": return "ja-JP"
        case "ko": return "ko-KR"
        case "ru": return "ru-RU"
        case "es": return "es-ES"
        case "fr": return "fr-FR"
        case "de": return "de-DE"
        case "it": return "it-IT"
        default: return langCode
        }
    }
}
