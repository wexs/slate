import Foundation
import Combine
import SwiftUI

public enum SpeechProvider: String, CaseIterable, Identifiable {
    case system = "system"
    case google = "google"
    case microsoft = "microsoft"
    
    public var id: String { rawValue }
    
    public var title: String {
        switch self {
        case .system: return loc("speech_system")
        case .google: return loc("speech_google")
        case .microsoft: return loc("speech_microsoft")
        }
    }
    
    public var shortName: String {
        switch self {
        case .system: return loc("speech_short_system")
        case .google: return loc("speech_short_google")
        case .microsoft: return loc("speech_short_microsoft")
        }
    }
    
    public var subtitle: String {
        switch self {
        case .system: return loc("speech_system_sub")
        case .google: return loc("speech_google_sub")
        case .microsoft: return loc("speech_microsoft_sub")
        }
    }
    
    public var icon: String {
        switch self {
        case .system: return "apple.logo"
        case .google: return "globe.americas.fill"
        case .microsoft: return "waveform"
        }
    }
    
    public var assetImageName: String? {
        switch self {
        case .system: return "appletranslate"
        case .google: return "google"
        case .microsoft: return "Microsoft"
        }
    }
    
    public var accentColor: Color {
        switch self {
        case .system: return Color.primary
        case .google: return Color(red: 0.26, green: 0.52, blue: 0.96)
        case .microsoft: return Color(red: 0.0, green: 0.47, blue: 0.83)
        }
    }
    
    public var requiresConfig: Bool {
        switch self {
        case .system, .google: return false
        case .microsoft: return true
        }
    }
    
    @MainActor
    public var isConfigured: Bool {
        switch self {
        case .system: return true
        case .google: return true
        case .microsoft: return MicrosoftSpeechConfig.shared.isConfigured
        }
    }
}

public struct SpeechProviderIconView: View {
    let provider: SpeechProvider
    var size: CGFloat = 16
    var isSelected: Bool = false
    
    public init(provider: SpeechProvider, size: CGFloat = 16, isSelected: Bool = false) {
        self.provider = provider
        self.size = size
        self.isSelected = isSelected
    }
    
    public var body: some View {
        let cornerRadius = size * 0.25
        if let asset = provider.assetImageName {
            Image.brandIcon(asset)
                .resizable()
                .scaledToFit()
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        } else {
            Image(systemName: provider.icon)
                .font(.system(size: size * 0.8))
                .foregroundColor(isSelected ? .white : provider.accentColor)
                .frame(width: size, height: size)
        }
    }
}

public struct MicrosoftVoicePreset: Identifiable, Hashable {
    public let id: String
    public let name: String
    public let desc: String
    public let locale: String
    
    public init(id: String, name: String, desc: String, locale: String) {
        self.id = id
        self.name = name
        self.desc = desc
        self.locale = locale
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
    
    @Published public var msVoices: [String: String] {
        didSet {
            UserDefaults.standard.set(msVoices, forKey: "ms_speech_voices_map")
        }
    }
    
    @Published public var chineseVoice: String {
        didSet {
            UserDefaults.standard.set(chineseVoice, forKey: "ms_speech_zh_voice")
        }
    }
    
    @Published public var englishVoice: String {
        didSet {
            UserDefaults.standard.set(englishVoice, forKey: "ms_speech_en_voice")
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
    
    public static func voicePresets(for langId: String) -> [MicrosoftVoicePreset] {
        switch langId {
        case "zh-Hans":
            return [
                MicrosoftVoicePreset(id: "zh-CN-XiaoxiaoNeural", name: "晓晓", desc: "女声 · 温暖亲切 · 推荐", locale: "zh-CN"),
                MicrosoftVoicePreset(id: "zh-CN-YunxiNeural", name: "云希", desc: "男声 · 阳光自然 · 推荐", locale: "zh-CN"),
                MicrosoftVoicePreset(id: "zh-CN-YunjianNeural", name: "云健", desc: "男声 · 影视解说 · 沉稳", locale: "zh-CN"),
                MicrosoftVoicePreset(id: "zh-CN-XiaoyiNeural", name: "晓伊", desc: "女声 · 温柔甜美", locale: "zh-CN"),
                MicrosoftVoicePreset(id: "zh-CN-YunyangNeural", name: "云扬", desc: "男声 · 专业播音", locale: "zh-CN"),
                MicrosoftVoicePreset(id: "zh-CN-liaoning-XiaobeiNeural", name: "晓北", desc: "女声 · 东北话特色", locale: "zh-CN")
            ]
        case "en":
            return [
                MicrosoftVoicePreset(id: "en-US-JennyNeural", name: "Jenny", desc: "美音女声 · 自然亲切 · 推荐", locale: "en-US"),
                MicrosoftVoicePreset(id: "en-US-GuyNeural", name: "Guy", desc: "美音男声 · 沉稳自信 · 推荐", locale: "en-US"),
                MicrosoftVoicePreset(id: "en-US-AriaNeural", name: "Aria", desc: "美音女声 · 专业新闻", locale: "en-US"),
                MicrosoftVoicePreset(id: "en-GB-SoniaNeural", name: "Sonia", desc: "英音女声 · 优雅纯正", locale: "en-GB"),
                MicrosoftVoicePreset(id: "en-AU-NatashaNeural", name: "Natasha", desc: "澳音女声 · 清新自然", locale: "en-AU")
            ]
        case "zh-Hant":
            return [
                MicrosoftVoicePreset(id: "zh-TW-HsiaoChenNeural", name: "曉臻", desc: "女聲 · 台灣國語", locale: "zh-TW"),
                MicrosoftVoicePreset(id: "zh-TW-YunJheNeural", name: "雲哲", desc: "男聲 · 台灣國語", locale: "zh-TW"),
                MicrosoftVoicePreset(id: "zh-HK-HiuMaanNeural", name: "曉曼", desc: "女聲 · 粵語", locale: "zh-HK"),
                MicrosoftVoicePreset(id: "zh-HK-WanLungNeural", name: "雲龍", desc: "男聲 · 粵語", locale: "zh-HK")
            ]
        case "ja":
            return [
                MicrosoftVoicePreset(id: "ja-JP-NanamiNeural", name: "七海 (Nanami)", desc: "日本語 · 女性", locale: "ja-JP"),
                MicrosoftVoicePreset(id: "ja-JP-KeitaNeural", name: "圭太 (Keita)", desc: "日本語 · 男性", locale: "ja-JP"),
                MicrosoftVoicePreset(id: "ja-JP-AoiNeural", name: "葵 (Aoi)", desc: "日本語 · 女性", locale: "ja-JP")
            ]
        case "ko":
            return [
                MicrosoftVoicePreset(id: "ko-KR-SunHiNeural", name: "선희 (SunHi)", desc: "한국어 · 여성", locale: "ko-KR"),
                MicrosoftVoicePreset(id: "ko-KR-InJoonNeural", name: "인준 (InJoon)", desc: "한국어 · 남성", locale: "ko-KR"),
                MicrosoftVoicePreset(id: "ko-KR-BongJinNeural", name: "봉진 (BongJin)", desc: "한국어 · 남성", locale: "ko-KR")
            ]
        case "fr":
            return [
                MicrosoftVoicePreset(id: "fr-FR-DeniseNeural", name: "Denise", desc: "Français · Femme", locale: "fr-FR"),
                MicrosoftVoicePreset(id: "fr-FR-HenriNeural", name: "Henri", desc: "Français · Homme", locale: "fr-FR"),
                MicrosoftVoicePreset(id: "fr-CA-SylvieNeural", name: "Sylvie", desc: "Français · Canada", locale: "fr-CA")
            ]
        case "ru":
            return [
                MicrosoftVoicePreset(id: "ru-RU-SvetlanaNeural", name: "Светлана (Svetlana)", desc: "Русский · Женский", locale: "ru-RU"),
                MicrosoftVoicePreset(id: "ru-RU-DmitryNeural", name: "Дмитрий (Dmitry)", desc: "Русский · Мужской", locale: "ru-RU")
            ]
        case "de":
            return [
                MicrosoftVoicePreset(id: "de-DE-KatjaNeural", name: "Katja", desc: "Deutsch · Weiblich", locale: "de-DE"),
                MicrosoftVoicePreset(id: "de-DE-ConradNeural", name: "Conrad", desc: "Deutsch · Männlich", locale: "de-DE"),
                MicrosoftVoicePreset(id: "de-DE-AmalaNeural", name: "Amala", desc: "Deutsch · Weiblich", locale: "de-DE")
            ]
        case "es":
            return [
                MicrosoftVoicePreset(id: "es-ES-ElviraNeural", name: "Elvira", desc: "Español · Femenino", locale: "es-ES"),
                MicrosoftVoicePreset(id: "es-ES-AlvaroNeural", name: "Álvaro", desc: "Español · Masculino", locale: "es-ES")
            ]
        case "it":
            return [
                MicrosoftVoicePreset(id: "it-IT-ElsaNeural", name: "Elsa", desc: "Italiano · Femminile", locale: "it-IT"),
                MicrosoftVoicePreset(id: "it-IT-IsabellaNeural", name: "Isabella", desc: "Italiano · Femminile", locale: "it-IT"),
                MicrosoftVoicePreset(id: "it-IT-DiegoNeural", name: "Diego", desc: "Italiano · Maschile", locale: "it-IT")
            ]
        default:
            return []
        }
    }
    
    public static var chineseVoicePresets: [MicrosoftVoicePreset] { voicePresets(for: "zh-Hans") }
    public static var englishVoicePresets: [MicrosoftVoicePreset] { voicePresets(for: "en") }
    
    private init() {
        self.apiKey = UserDefaults.standard.string(forKey: "ms_speech_api_key") ?? ""
        self.region = UserDefaults.standard.string(forKey: "ms_speech_region") ?? "eastasia"
        if let savedMap = UserDefaults.standard.dictionary(forKey: "ms_speech_voices_map") as? [String: String] {
            self.msVoices = savedMap
        } else {
            self.msVoices = [:]
        }
        self.chineseVoice = UserDefaults.standard.string(forKey: "ms_speech_zh_voice") ?? "zh-CN-XiaoxiaoNeural"
        self.englishVoice = UserDefaults.standard.string(forKey: "ms_speech_en_voice") ?? "en-US-JennyNeural"
    }
    
    public static func defaultVoice(for langId: String) -> String {
        if let map = UserDefaults.standard.dictionary(forKey: "ms_speech_voices_map") as? [String: String],
           let custom = map[langId], !custom.isEmpty {
            return custom
        }
        if langId == "zh-Hans", let zh = UserDefaults.standard.string(forKey: "ms_speech_zh_voice"), !zh.isEmpty {
            return zh
        }
        if langId == "en", let en = UserDefaults.standard.string(forKey: "ms_speech_en_voice"), !en.isEmpty {
            return en
        }
        return voicePresets(for: langId).first?.id ?? "zh-CN-XiaoxiaoNeural"
    }
    
    public func voice(for langId: String) -> String {
        if let custom = msVoices[langId], !custom.isEmpty {
            return custom
        }
        if langId == "zh-Hans" && !chineseVoice.isEmpty { return chineseVoice }
        if langId == "en" && !englishVoice.isEmpty { return englishVoice }
        return Self.defaultVoice(for: langId)
    }
    
    public func setVoice(_ voiceName: String, for langId: String) {
        msVoices[langId] = voiceName
        if langId == "zh-Hans" { chineseVoice = voiceName }
        if langId == "en" { englishVoice = voiceName }
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
        
        if code.hasPrefix("zh-tw") || code.hasPrefix("zh-hk") || code == "zh-hant" {
            let voice = MicrosoftSpeechConfig.defaultVoice(for: "zh-Hant")
            let xmlLang = voice.contains("zh-HK") ? "zh-HK" : "zh-TW"
            return (voice, xmlLang)
        } else if code.hasPrefix("zh") {
            let voice = MicrosoftSpeechConfig.defaultVoice(for: "zh-Hans")
            return (voice, "zh-CN")
        } else if code.hasPrefix("en") {
            let voice = MicrosoftSpeechConfig.defaultVoice(for: "en")
            let xmlLang: String
            if voice.contains("en-GB") { xmlLang = "en-GB" }
            else if voice.contains("en-AU") { xmlLang = "en-AU" }
            else { xmlLang = "en-US" }
            return (voice, xmlLang)
        }
        
        switch code {
        case "ja", "ja-jp":
            return (MicrosoftSpeechConfig.defaultVoice(for: "ja"), "ja-JP")
        case "ko", "ko-kr":
            return (MicrosoftSpeechConfig.defaultVoice(for: "ko"), "ko-KR")
        case "fr", "fr-fr", "fr-ca":
            let v = MicrosoftSpeechConfig.defaultVoice(for: "fr")
            let xml = v.contains("fr-CA") ? "fr-CA" : "fr-FR"
            return (v, xml)
        case "de", "de-de":
            return (MicrosoftSpeechConfig.defaultVoice(for: "de"), "de-DE")
        case "es", "es-es":
            return (MicrosoftSpeechConfig.defaultVoice(for: "es"), "es-ES")
        case "it", "it-it":
            return (MicrosoftSpeechConfig.defaultVoice(for: "it"), "it-IT")
        case "ru", "ru-ru":
            return (MicrosoftSpeechConfig.defaultVoice(for: "ru"), "ru-RU")
        case "pt", "pt-br", "pt-pt":
            return ("pt-BR-FranciscaNeural", "pt-BR")
        case "ar", "ar-sa":
            return ("ar-SA-ZariyahNeural", "ar-SA")
        case "th", "th-th":
            return ("th-TH-PremwadeeNeural", "th-TH")
        case "vi", "vi-vn":
            return ("vi-VN-HoaiMyNeural", "vi-VN")
        default:
            if hasCJK {
                return (MicrosoftSpeechConfig.defaultVoice(for: "zh-Hans"), "zh-CN")
            } else {
                return (MicrosoftSpeechConfig.defaultVoice(for: "en"), "en-US")
            }
        }
    }
    
    /// Synthesizes text to MP3 audio Data using Microsoft Azure Speech REST API
    public static func synthesize(
        text: String,
        languageCode: String?,
        voiceName: String? = nil,
        rate: Double = 1.0,
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
        
        let (resolvedVoice, xmlLang): (String, String)
        if let explicitVoice = voiceName, !explicitVoice.isEmpty {
            let lang: String
            if explicitVoice.contains("zh-TW") { lang = "zh-TW" }
            else if explicitVoice.contains("zh-HK") { lang = "zh-HK" }
            else if explicitVoice.contains("zh") { lang = "zh-CN" }
            else if explicitVoice.contains("en-GB") { lang = "en-GB" }
            else if explicitVoice.contains("en-AU") { lang = "en-AU" }
            else if explicitVoice.contains("en") { lang = "en-US" }
            else { lang = "zh-CN" }
            resolvedVoice = explicitVoice
            xmlLang = lang
        } else {
            let res = resolveVoice(for: languageCode, text: text)
            resolvedVoice = res.voiceName
            xmlLang = res.xmlLang
        }
        
        // XML Escape special characters
        let escapedText = text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
        
        let ratePercent = Int(round((rate - 1.0) * 100))
        let rateStr = ratePercent >= 0 ? "+\(ratePercent)%" : "\(ratePercent)%"
        
        let ssml = """
        <speak version='1.0' xmlns='http://www.w3.org/2001/10/synthesis' xml:lang='\(xmlLang)'>
            <voice name='\(resolvedVoice)'>
                <prosody rate='\(rateStr)'>\(escapedText)</prosody>
            </voice>
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
    public static func testConnection(apiKey: String, region: String, rate: Double = 1.0) async throws -> Data {
        return try await synthesize(
            text: "您好，这是微软智能语音合成测试。",
            languageCode: "zh-CN",
            rate: rate,
            apiKey: apiKey,
            region: region
        )
    }
}
