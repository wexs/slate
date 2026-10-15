import Foundation
import Combine
import SwiftUI

public enum SpeechProvider: String, CaseIterable, Identifiable {
    case system = "system"
    case microsoft = "microsoft"
    
    public var id: String { rawValue }
    
    public var title: String {
        switch self {
        case .system: return "Apple 原生语音"
        case .microsoft: return "微软 Azure 语音"
        }
    }
    
    public var shortName: String {
        switch self {
        case .system: return "Apple 语音"
        case .microsoft: return "微软语音"
        }
    }
    
    public var subtitle: String {
        switch self {
        case .system: return "macOS 系统内置 · 离线神经加速发音"
        case .microsoft: return "Azure 认知服务 · 拟真多语言神经网络人声"
        }
    }
    
    public var icon: String {
        switch self {
        case .system: return "apple.logo"
        case .microsoft: return "waveform"
        }
    }
    
    public var accentColor: Color {
        switch self {
        case .system: return Color.primary
        case .microsoft: return Color(red: 0.0, green: 0.47, blue: 0.83)
        }
    }
    
    public var requiresConfig: Bool {
        switch self {
        case .system: return false
        case .microsoft: return true
        }
    }
    
    @MainActor
    public var isConfigured: Bool {
        switch self {
        case .system: return true
        case .microsoft: return MicrosoftSpeechConfig.shared.isConfigured
        }
    }
}

@MainActor
public final class MicrosoftSpeechConfig: ObservableObject {
    public static let shared = MicrosoftSpeechConfig()
    
    @Published public var apiKey: String {
        didSet {
            UserDefaults.standard.set(apiKey, forKey: "ms_speech_api_key")
        }
    }
    
    @Published public var region: String {
        didSet {
            UserDefaults.standard.set(region, forKey: "ms_speech_region")
        }
    }
    
    public var isConfigured: Bool {
        !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !region.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    
    public static let regionPresets: [(id: String, name: String)] = [
        ("eastasia", "东亚 (香港 - eastasia)"),
        ("southeastasia", "东南亚 (新加坡 - southeastasia)"),
        ("eastus", "美国东部 (弗吉尼亚 - eastus)"),
        ("eastus2", "美国东部2 (弗吉尼亚 - eastus2)"),
        ("westus", "美国西部 (加利福尼亚 - westus)"),
        ("japaneast", "日本东部 (东京 - japaneast)"),
        ("koreacentral", "韩国中部 (首尔 - koreacentral)"),
        ("westeurope", "西欧 (荷兰 - westeurope)"),
        ("centralus", "美国中部 (爱荷华 - centralus)")
    ]
    
    private init() {
        self.apiKey = UserDefaults.standard.string(forKey: "ms_speech_api_key") ?? ""
        self.region = UserDefaults.standard.string(forKey: "ms_speech_region") ?? "eastasia"
    }
    
    public func save(apiKey: String, region: String) {
        self.apiKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        self.region = region.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

public struct MicrosoftSpeechSynthesizer {
    public enum SpeechError: LocalizedError {
        case missingCredentials
        case invalidEndpoint
        case unauthorized
        case httpError(statusCode: Int, message: String)
        case emptyAudio
        case networkError(Error)
        
        public var errorDescription: String? {
            switch self {
            case .missingCredentials:
                return "请先配置微软语音 API Key 与 Region"
            case .invalidEndpoint:
                return "服务区域 (Region) 地址无效"
            case .unauthorized:
                return "API Key 无效或未授权，请检查密钥是否正确"
            case .httpError(let code, let msg):
                return "微软语音请求错误 (\(code)): \(msg)"
            case .emptyAudio:
                return "微软语音未返回有效音频数据"
            case .networkError(let error):
                return "网络请求失败: \(error.localizedDescription)"
            }
        }
    }
    
    /// Maps language code to Azure Neural voice name and XML language tag
    private static func resolveVoice(for languageCode: String?, text: String) -> (voiceName: String, xmlLang: String) {
        var hasCJK = false
        var hasHiraganaOrKatakana = false
        var hasHangul = false
        for s in text.unicodeScalars {
            let val = s.value
            if (val >= 0x4E00 && val <= 0x9FFF) || (val >= 0x3400 && val <= 0x4DBF) {
                hasCJK = true
            } else if (val >= 0x3040 && val <= 0x309F) || (val >= 0x30A0 && val <= 0x30FF) {
                hasHiraganaOrKatakana = true
            } else if (val >= 0xAC00 && val <= 0xD7AF) || (val >= 0x1100 && val <= 0x11FF) || (val >= 0x3130 && val <= 0x318F) {
                hasHangul = true
            }
        }
        
        var code = (languageCode ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        
        // Correct script mismatch: if text has Chinese/CJK characters but requested non-Chinese voice
        if hasCJK && !hasHiraganaOrKatakana && !code.hasPrefix("zh") {
            code = "zh-cn"
        } else if hasHiraganaOrKatakana && !code.hasPrefix("ja") {
            code = "ja-jp"
        } else if hasHangul && !code.hasPrefix("ko") {
            code = "ko-kr"
        }
        
        switch code {
        case "zh", "zh-hans", "zh-cn":
            return ("zh-CN-XiaoxiaoNeural", "zh-CN")
        case "zh-hant", "zh-tw", "zh-hk":
            return ("zh-TW-HsiaoChenNeural", "zh-TW")
        case "en", "en-us", "en-gb":
            return ("en-US-JennyNeural", "en-US")
        case "ja", "ja-jp":
            return ("ja-JP-NanamiNeural", "ja-JP")
        case "ko", "ko-kr":
            return ("ko-KR-SunHiNeural", "ko-KR")
        case "fr", "fr-fr":
            return ("fr-FR-DeniseNeural", "fr-FR")
        case "de", "de-de":
            return ("de-DE-KatjaNeural", "de-DE")
        case "es", "es-es":
            return ("es-ES-ElviraNeural", "es-ES")
        case "it", "it-it":
            return ("it-IT-ElsaNeural", "it-IT")
        case "pt", "pt-br", "pt-pt":
            return ("pt-BR-FranciscaNeural", "pt-BR")
        case "ru", "ru-ru":
            return ("ru-RU-SvetlanaNeural", "ru-RU")
        case "ar", "ar-sa":
            return ("ar-SA-ZariyahNeural", "ar-SA")
        case "th", "th-th":
            return ("th-TH-PremwadeeNeural", "th-TH")
        case "vi", "vi-vn":
            return ("vi-VN-HoaiMyNeural", "vi-VN")
        default:
            if hasCJK {
                return ("zh-CN-XiaoxiaoNeural", "zh-CN")
            } else {
                return ("en-US-JennyNeural", "en-US")
            }
        }
    }
    
    /// Synthesizes text to MP3 audio Data using Microsoft Azure Speech REST API
    public static func synthesize(
        text: String,
        languageCode: String?,
        apiKey: String,
        region: String
    ) async throws -> Data {
        let cleanKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanRegion = region.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        
        guard !cleanKey.isEmpty, !cleanRegion.isEmpty else {
            throw SpeechError.missingCredentials
        }
        
        guard let url = URL(string: "https://\(cleanRegion).tts.speech.microsoft.com/cognitiveservices/v1") else {
            throw SpeechError.invalidEndpoint
        }
        
        let (voiceName, xmlLang) = resolveVoice(for: languageCode, text: text)
        
        // XML Escape special characters
        let escapedText = text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
        
        let ssml = """
        <speak version='1.0' xmlns='http://www.w3.org/2001/10/synthesis' xml:lang='\(xmlLang)'>
            <voice name='\(voiceName)'>\(escapedText)</voice>
        </speak>
        """
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(cleanKey, forHTTPHeaderField: "Ocp-Apim-Subscription-Key")
        request.setValue("application/ssml+xml", forHTTPHeaderField: "Content-Type")
        request.setValue("audio-24khz-48kbitrate-mono-mp3", forHTTPHeaderField: "X-Microsoft-OutputFormat")
        request.setValue("Slate-macOS", forHTTPHeaderField: "User-Agent")
        request.httpBody = ssml.data(using: .utf8)
        request.timeoutInterval = 12.0
        
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw SpeechError.networkError(error)
        }
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw SpeechError.networkError(NSError(domain: "Network", code: -1, userInfo: [NSLocalizedDescriptionKey: "无效的网络响应"]))
        }
        
        if httpResponse.statusCode == 200 {
            guard !data.isEmpty else {
                throw SpeechError.emptyAudio
            }
            return data
        } else if httpResponse.statusCode == 401 {
            throw SpeechError.unauthorized
        } else {
            let errorText = String(data: data, encoding: .utf8) ?? "HTTP \(httpResponse.statusCode)"
            throw SpeechError.httpError(statusCode: httpResponse.statusCode, message: errorText)
        }
    }
    
    /// Tests connection and audio synthesis
    public static func testConnection(apiKey: String, region: String) async throws -> Data {
        return try await synthesize(
            text: "您好，这是微软语音合成测试。",
            languageCode: "zh-CN",
            apiKey: apiKey,
            region: region
        )
    }
}
