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

public struct MicrosoftVoicePreset: Identifiable, Hashable, Codable {
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

// Azure TTS /voices/list API response item
private struct AzureVoiceItem: Decodable {
    let shortName: String      // e.g. "zh-CN-XiaoxiaoNeural"
    let localName: String      // e.g. "晓晓"
    let displayName: String    // e.g. "Xiaoxiao"
    let locale: String         // e.g. "zh-CN"
    let gender: String         // "Female" / "Male"
    let voiceType: String      // "Neural" / "Standard"
    let status: String?        // "GA" / "Preview"
    
    enum CodingKeys: String, CodingKey {
        case shortName = "ShortName"
        case localName = "LocalName"
        case displayName = "DisplayName"
        case locale = "Locale"
        case gender = "Gender"
        case voiceType = "VoiceType"
        case status = "Status"
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
    
    /// Dynamically fetched voices from Azure API, grouped by langId. Empty = use built-in presets.
    @Published public var dynamicVoices: [String: [MicrosoftVoicePreset]] = [:]
    /// Whether a voice list fetch is in progress
    @Published public var isFetchingVoices: Bool = false
    /// Last fetch error message, nil if last fetch succeeded or never run
    @Published public var fetchError: String? = nil
    /// Timestamp of last successful fetch
    @Published public var lastFetchedAt: Date? = nil
    
    /// True when we have a live dynamic list from Azure
    public var hasDynamicVoices: Bool { !dynamicVoices.isEmpty }
    
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
                MicrosoftVoicePreset(id: "zh-CN-XiaoxiaoNeural",            name: "晓晓",   desc: "女声 · 温暖亲切 · 推荐",   locale: "zh-CN"),
                MicrosoftVoicePreset(id: "zh-CN-YunxiNeural",               name: "云希",   desc: "男声 · 阳光自然 · 推荐",   locale: "zh-CN"),
                MicrosoftVoicePreset(id: "zh-CN-YunjianNeural",              name: "云健",   desc: "男声 · 影视解说 · 沉稳",   locale: "zh-CN"),
                MicrosoftVoicePreset(id: "zh-CN-XiaoyiNeural",              name: "晓伊",   desc: "女声 · 温柔甜美",          locale: "zh-CN"),
                MicrosoftVoicePreset(id: "zh-CN-YunyangNeural",             name: "云扬",   desc: "男声 · 专业播音",          locale: "zh-CN"),
                MicrosoftVoicePreset(id: "zh-CN-XiaochenNeural",            name: "晓辰",   desc: "女声 · 活泼清新",          locale: "zh-CN"),
                MicrosoftVoicePreset(id: "zh-CN-XiaohanNeural",             name: "晓涵",   desc: "女声 · 成熟稳重",          locale: "zh-CN"),
                MicrosoftVoicePreset(id: "zh-CN-XiaomengNeural",            name: "晓梦",   desc: "女声 · 梦幻轻盈",          locale: "zh-CN"),
                MicrosoftVoicePreset(id: "zh-CN-XiaomoNeural",              name: "晓墨",   desc: "女声 · 知性大气",          locale: "zh-CN"),
                MicrosoftVoicePreset(id: "zh-CN-XiaoqiuNeural",             name: "晓秋",   desc: "女声 · 沉稳端庄",          locale: "zh-CN"),
                MicrosoftVoicePreset(id: "zh-CN-XiaoruiNeural",             name: "晓睿",   desc: "女声 · 老年感 · 叙述",     locale: "zh-CN"),
                MicrosoftVoicePreset(id: "zh-CN-XiaoshuangNeural",          name: "晓双",   desc: "女声 · 儿童风格",          locale: "zh-CN"),
                MicrosoftVoicePreset(id: "zh-CN-XiaoxuanNeural",            name: "晓萱",   desc: "女声 · 轻松愉悦",          locale: "zh-CN"),
                MicrosoftVoicePreset(id: "zh-CN-XiaoyanNeural",             name: "晓颜",   desc: "女声 · 职场专业",          locale: "zh-CN"),
                MicrosoftVoicePreset(id: "zh-CN-XiaozheNeural",             name: "晓哲",   desc: "男声 · 自信果断",          locale: "zh-CN"),
                MicrosoftVoicePreset(id: "zh-CN-YunjieNeural",              name: "云杰",   desc: "男声 · 激昂有力",          locale: "zh-CN"),
                MicrosoftVoicePreset(id: "zh-CN-YunkanNeural",              name: "云侃",   desc: "男声 · 浑厚磁性",          locale: "zh-CN"),
                MicrosoftVoicePreset(id: "zh-CN-YunzeNeural",               name: "云泽",   desc: "男声 · 沉着冷静",          locale: "zh-CN"),
                MicrosoftVoicePreset(id: "zh-CN-liaoning-XiaobeiNeural",    name: "晓北",   desc: "女声 · 东北话特色",         locale: "zh-CN"),
                MicrosoftVoicePreset(id: "zh-CN-shaanxi-XiaoniNeural",      name: "晓妮",   desc: "女声 · 陕西话特色",         locale: "zh-CN"),
            ]
        case "en":
            return [
                MicrosoftVoicePreset(id: "en-US-JennyNeural",      name: "Jenny",      desc: "美音女声 · 自然亲切 · 推荐", locale: "en-US"),
                MicrosoftVoicePreset(id: "en-US-GuyNeural",         name: "Guy",        desc: "美音男声 · 沉稳自信 · 推荐", locale: "en-US"),
                MicrosoftVoicePreset(id: "en-US-AriaNeural",        name: "Aria",       desc: "美音女声 · 专业新闻",        locale: "en-US"),
                MicrosoftVoicePreset(id: "en-US-DavisNeural",       name: "Davis",      desc: "美音男声 · 随和自然",        locale: "en-US"),
                MicrosoftVoicePreset(id: "en-US-AnaNeural",         name: "Ana",        desc: "美音女声 · 儿童音色",        locale: "en-US"),
                MicrosoftVoicePreset(id: "en-US-AmberNeural",       name: "Amber",      desc: "美音女声 · 温柔平稳",        locale: "en-US"),
                MicrosoftVoicePreset(id: "en-US-AshleyNeural",      name: "Ashley",     desc: "美音女声 · 轻快活泼",        locale: "en-US"),
                MicrosoftVoicePreset(id: "en-US-BrandonNeural",     name: "Brandon",    desc: "美音男声 · 青春活力",        locale: "en-US"),
                MicrosoftVoicePreset(id: "en-US-ChristopherNeural", name: "Christopher",desc: "美音男声 · 稳重专业",        locale: "en-US"),
                MicrosoftVoicePreset(id: "en-US-CoraNeural",        name: "Cora",       desc: "美音女声 · 清晰流畅",        locale: "en-US"),
                MicrosoftVoicePreset(id: "en-US-ElizabethNeural",   name: "Elizabeth",  desc: "美音女声 · 优雅成熟",        locale: "en-US"),
                MicrosoftVoicePreset(id: "en-US-EricNeural",        name: "Eric",       desc: "美音男声 · 亲切随和",        locale: "en-US"),
                MicrosoftVoicePreset(id: "en-US-JacobNeural",       name: "Jacob",      desc: "美音男声 · 年轻自信",        locale: "en-US"),
                MicrosoftVoicePreset(id: "en-US-JaneNeural",        name: "Jane",       desc: "美音女声 · 友善温暖",        locale: "en-US"),
                MicrosoftVoicePreset(id: "en-US-JasonNeural",       name: "Jason",      desc: "美音男声 · 成熟稳健",        locale: "en-US"),
                MicrosoftVoicePreset(id: "en-US-MichelleNeural",    name: "Michelle",   desc: "美音女声 · 专业清晰",        locale: "en-US"),
                MicrosoftVoicePreset(id: "en-US-MonicaNeural",      name: "Monica",     desc: "美音女声 · 亲和力强",        locale: "en-US"),
                MicrosoftVoicePreset(id: "en-US-NancyNeural",       name: "Nancy",      desc: "美音女声 · 活泼开朗",        locale: "en-US"),
                MicrosoftVoicePreset(id: "en-US-RogerNeural",       name: "Roger",      desc: "美音男声 · 自信干练",        locale: "en-US"),
                MicrosoftVoicePreset(id: "en-US-SaraNeural",        name: "Sara",       desc: "美音女声 · 清新自然",        locale: "en-US"),
                MicrosoftVoicePreset(id: "en-US-SteffanNeural",     name: "Steffan",    desc: "美音男声 · 庄重正式",        locale: "en-US"),
                MicrosoftVoicePreset(id: "en-US-TonyNeural",        name: "Tony",       desc: "美音男声 · 阳光开朗",        locale: "en-US"),
                MicrosoftVoicePreset(id: "en-GB-SoniaNeural",       name: "Sonia",      desc: "英音女声 · 优雅纯正",        locale: "en-GB"),
                MicrosoftVoicePreset(id: "en-GB-RyanNeural",        name: "Ryan",       desc: "英音男声 · 沉稳清晰",        locale: "en-GB"),
                MicrosoftVoicePreset(id: "en-GB-LibbyNeural",       name: "Libby",      desc: "英音女声 · 亲切自然",        locale: "en-GB"),
                MicrosoftVoicePreset(id: "en-AU-NatashaNeural",     name: "Natasha",    desc: "澳音女声 · 清新自然",        locale: "en-AU"),
                MicrosoftVoicePreset(id: "en-AU-WilliamNeural",     name: "William",    desc: "澳音男声 · 阳光开朗",        locale: "en-AU"),
                MicrosoftVoicePreset(id: "en-CA-ClaraNeural",       name: "Clara",      desc: "加拿大英音 · 女声",          locale: "en-CA"),
                MicrosoftVoicePreset(id: "en-CA-LiamNeural",        name: "Liam",       desc: "加拿大英音 · 男声",          locale: "en-CA"),
                MicrosoftVoicePreset(id: "en-IN-NeerjaNeural",      name: "Neerja",     desc: "印度英音 · 女声",            locale: "en-IN"),
                MicrosoftVoicePreset(id: "en-IN-PrabhatNeural",     name: "Prabhat",    desc: "印度英音 · 男声",            locale: "en-IN"),
            ]
        case "zh-Hant":
            return [
                MicrosoftVoicePreset(id: "zh-TW-HsiaoChenNeural",  name: "曉臻",   desc: "女聲 · 台灣國語 · 推薦",  locale: "zh-TW"),
                MicrosoftVoicePreset(id: "zh-TW-YunJheNeural",      name: "雲哲",   desc: "男聲 · 台灣國語",         locale: "zh-TW"),
                MicrosoftVoicePreset(id: "zh-TW-HsiaoYuNeural",     name: "曉雨",   desc: "女聲 · 台灣國語 · 活潑",  locale: "zh-TW"),
                MicrosoftVoicePreset(id: "zh-HK-HiuMaanNeural",     name: "曉曼",   desc: "女聲 · 粵語 · 推薦",      locale: "zh-HK"),
                MicrosoftVoicePreset(id: "zh-HK-WanLungNeural",     name: "雲龍",   desc: "男聲 · 粵語",             locale: "zh-HK"),
                MicrosoftVoicePreset(id: "zh-HK-HiuGaaiNeural",     name: "曉佳",   desc: "女聲 · 粵語 · 親切",      locale: "zh-HK"),
            ]
        case "ja":
            return [
                MicrosoftVoicePreset(id: "ja-JP-NanamiNeural",  name: "七海 (Nanami)",  desc: "日本語 · 女性 · 推荐", locale: "ja-JP"),
                MicrosoftVoicePreset(id: "ja-JP-KeitaNeural",   name: "圭太 (Keita)",   desc: "日本語 · 男性 · 推荐", locale: "ja-JP"),
                MicrosoftVoicePreset(id: "ja-JP-AoiNeural",     name: "葵 (Aoi)",       desc: "日本語 · 女性",        locale: "ja-JP"),
                MicrosoftVoicePreset(id: "ja-JP-DaichiNeural",  name: "大地 (Daichi)",  desc: "日本語 · 男性",        locale: "ja-JP"),
                MicrosoftVoicePreset(id: "ja-JP-MayuNeural",    name: "繭 (Mayu)",      desc: "日本語 · 女性",        locale: "ja-JP"),
                MicrosoftVoicePreset(id: "ja-JP-NaokiNeural",   name: "直樹 (Naoki)",   desc: "日本語 · 男性",        locale: "ja-JP"),
                MicrosoftVoicePreset(id: "ja-JP-ShioriNeural",  name: "栞 (Shiori)",    desc: "日本語 · 女性",        locale: "ja-JP"),
                MicrosoftVoicePreset(id: "ja-JP-TomokaNeural",  name: "友香 (Tomoka)",  desc: "日本語 · 女性",        locale: "ja-JP"),
            ]
        case "ko":
            return [
                MicrosoftVoicePreset(id: "ko-KR-SunHiNeural",      name: "선희 (SunHi)",    desc: "한국어 · 여성 · 추천", locale: "ko-KR"),
                MicrosoftVoicePreset(id: "ko-KR-InJoonNeural",      name: "인준 (InJoon)",   desc: "한국어 · 남성 · 추천", locale: "ko-KR"),
                MicrosoftVoicePreset(id: "ko-KR-BongJinNeural",     name: "봉진 (BongJin)",  desc: "한국어 · 남성",        locale: "ko-KR"),
                MicrosoftVoicePreset(id: "ko-KR-GookMinNeural",     name: "국민 (GookMin)",  desc: "한국어 · 남성",        locale: "ko-KR"),
                MicrosoftVoicePreset(id: "ko-KR-JiMinNeural",       name: "지민 (JiMin)",    desc: "한국어 · 여성",        locale: "ko-KR"),
                MicrosoftVoicePreset(id: "ko-KR-SeoHyeonNeural",    name: "서현 (SeoHyeon)", desc: "한국어 · 여성",        locale: "ko-KR"),
                MicrosoftVoicePreset(id: "ko-KR-SoonBokNeural",     name: "순복 (SoonBok)",  desc: "한국어 · 여성",        locale: "ko-KR"),
                MicrosoftVoicePreset(id: "ko-KR-YuJinNeural",       name: "유진 (YuJin)",    desc: "한국어 · 여성",        locale: "ko-KR"),
            ]
        case "fr":
            return [
                MicrosoftVoicePreset(id: "fr-FR-DeniseNeural",      name: "Denise",     desc: "Français · Femme · Recommandé",  locale: "fr-FR"),
                MicrosoftVoicePreset(id: "fr-FR-HenriNeural",       name: "Henri",      desc: "Français · Homme · Recommandé",  locale: "fr-FR"),
                MicrosoftVoicePreset(id: "fr-FR-EloiseNeural",      name: "Eloise",     desc: "Français · Femme",               locale: "fr-FR"),
                MicrosoftVoicePreset(id: "fr-FR-JosephineNeural",   name: "Josephine",  desc: "Français · Femme",               locale: "fr-FR"),
                MicrosoftVoicePreset(id: "fr-FR-YvetteNeural",      name: "Yvette",     desc: "Français · Femme",               locale: "fr-FR"),
                MicrosoftVoicePreset(id: "fr-FR-AlainNeural",       name: "Alain",      desc: "Français · Homme",               locale: "fr-FR"),
                MicrosoftVoicePreset(id: "fr-FR-ClaudeNeural",      name: "Claude",     desc: "Français · Homme",               locale: "fr-FR"),
                MicrosoftVoicePreset(id: "fr-FR-MauriceNeural",     name: "Maurice",    desc: "Français · Homme",               locale: "fr-FR"),
                MicrosoftVoicePreset(id: "fr-CA-SylvieNeural",      name: "Sylvie",     desc: "Français · Canada · Femme",      locale: "fr-CA"),
                MicrosoftVoicePreset(id: "fr-CA-AntoineNeural",     name: "Antoine",    desc: "Français · Canada · Homme",      locale: "fr-CA"),
                MicrosoftVoicePreset(id: "fr-CA-JeanNeural",        name: "Jean",       desc: "Français · Canada · Homme",      locale: "fr-CA"),
            ]
        case "ru":
            return [
                MicrosoftVoicePreset(id: "ru-RU-SvetlanaNeural",    name: "Светлана (Svetlana)", desc: "Русский · Женский · Рекомендовано", locale: "ru-RU"),
                MicrosoftVoicePreset(id: "ru-RU-DmitryNeural",      name: "Дмитрий (Dmitry)",   desc: "Русский · Мужской · Рекомендовано", locale: "ru-RU"),
                MicrosoftVoicePreset(id: "ru-RU-DariyaNeural",      name: "Дарья (Dariya)",     desc: "Русский · Женский",                 locale: "ru-RU"),
            ]
        case "de":
            return [
                MicrosoftVoicePreset(id: "de-DE-KatjaNeural",       name: "Katja",      desc: "Deutsch · Weiblich · Empfohlen", locale: "de-DE"),
                MicrosoftVoicePreset(id: "de-DE-ConradNeural",      name: "Conrad",     desc: "Deutsch · Männlich · Empfohlen", locale: "de-DE"),
                MicrosoftVoicePreset(id: "de-DE-AmalaNeural",       name: "Amala",      desc: "Deutsch · Weiblich",             locale: "de-DE"),
                MicrosoftVoicePreset(id: "de-DE-BerndNeural",       name: "Bernd",      desc: "Deutsch · Männlich",             locale: "de-DE"),
                MicrosoftVoicePreset(id: "de-DE-ChristophNeural",   name: "Christoph",  desc: "Deutsch · Männlich",             locale: "de-DE"),
                MicrosoftVoicePreset(id: "de-DE-GiselaNeural",      name: "Gisela",     desc: "Deutsch · Weiblich",             locale: "de-DE"),
                MicrosoftVoicePreset(id: "de-DE-KlaraNeural",       name: "Klara",      desc: "Deutsch · Weiblich",             locale: "de-DE"),
                MicrosoftVoicePreset(id: "de-DE-KillianNeural",     name: "Killian",    desc: "Deutsch · Männlich",             locale: "de-DE"),
                MicrosoftVoicePreset(id: "de-DE-MajaNeural",        name: "Maja",       desc: "Deutsch · Weiblich",             locale: "de-DE"),
                MicrosoftVoicePreset(id: "de-DE-StefanNeural",      name: "Stefan",     desc: "Deutsch · Männlich",             locale: "de-DE"),
                MicrosoftVoicePreset(id: "de-AT-IngridNeural",      name: "Ingrid",     desc: "Deutsch · Österreich · Weiblich",locale: "de-AT"),
                MicrosoftVoicePreset(id: "de-AT-JonasNeural",       name: "Jonas",      desc: "Deutsch · Österreich · Männlich",locale: "de-AT"),
                MicrosoftVoicePreset(id: "de-CH-LeniNeural",        name: "Leni",       desc: "Deutsch · Schweiz · Weiblich",   locale: "de-CH"),
                MicrosoftVoicePreset(id: "de-CH-JanNeural",         name: "Jan",        desc: "Deutsch · Schweiz · Männlich",   locale: "de-CH"),
            ]
        case "es":
            return [
                MicrosoftVoicePreset(id: "es-ES-ElviraNeural",      name: "Elvira",     desc: "Español · Femenino · Recomendado",   locale: "es-ES"),
                MicrosoftVoicePreset(id: "es-ES-AlvaroNeural",      name: "Álvaro",     desc: "Español · Masculino · Recomendado",  locale: "es-ES"),
                MicrosoftVoicePreset(id: "es-ES-EstrellaNeural",    name: "Estrella",   desc: "Español · Femenino",                 locale: "es-ES"),
                MicrosoftVoicePreset(id: "es-ES-IreneNeural",       name: "Irene",      desc: "Español · Femenino",                 locale: "es-ES"),
                MicrosoftVoicePreset(id: "es-ES-LaiaNeural",        name: "Laia",       desc: "Español · Femenino",                 locale: "es-ES"),
                MicrosoftVoicePreset(id: "es-ES-LiriaNeural",       name: "Liria",      desc: "Español · Femenino",                 locale: "es-ES"),
                MicrosoftVoicePreset(id: "es-ES-ArnauNeural",       name: "Arnau",      desc: "Español · Masculino",                locale: "es-ES"),
                MicrosoftVoicePreset(id: "es-ES-DarioNeural",       name: "Dario",      desc: "Español · Masculino",                locale: "es-ES"),
                MicrosoftVoicePreset(id: "es-ES-EliasNeural",       name: "Elias",      desc: "Español · Masculino",                locale: "es-ES"),
                MicrosoftVoicePreset(id: "es-ES-NilNeural",         name: "Nil",        desc: "Español · Masculino",                locale: "es-ES"),
                MicrosoftVoicePreset(id: "es-MX-DaliaNeural",       name: "Dalia",      desc: "Español · México · Femenino",        locale: "es-MX"),
                MicrosoftVoicePreset(id: "es-MX-JorgeNeural",       name: "Jorge",      desc: "Español · México · Masculino",       locale: "es-MX"),
                MicrosoftVoicePreset(id: "es-MX-BeatrizNeural",     name: "Beatriz",    desc: "Español · México · Femenino",        locale: "es-MX"),
                MicrosoftVoicePreset(id: "es-MX-CarlotaNeural",     name: "Carlota",    desc: "Español · México · Femenino",        locale: "es-MX"),
                MicrosoftVoicePreset(id: "es-AR-ElenaNeural",       name: "Elena",      desc: "Español · Argentina · Femenino",     locale: "es-AR"),
                MicrosoftVoicePreset(id: "es-AR-TomasNeural",       name: "Tomas",      desc: "Español · Argentina · Masculino",    locale: "es-AR"),
            ]
        case "it":
            return [
                MicrosoftVoicePreset(id: "it-IT-ElsaNeural",        name: "Elsa",       desc: "Italiano · Femminile · Consigliato", locale: "it-IT"),
                MicrosoftVoicePreset(id: "it-IT-DiegoNeural",       name: "Diego",      desc: "Italiano · Maschile · Consigliato",  locale: "it-IT"),
                MicrosoftVoicePreset(id: "it-IT-IsabellaNeural",    name: "Isabella",   desc: "Italiano · Femminile",               locale: "it-IT"),
                MicrosoftVoicePreset(id: "it-IT-FiammettaNeural",   name: "Fiammetta",  desc: "Italiano · Femminile",               locale: "it-IT"),
                MicrosoftVoicePreset(id: "it-IT-GaiaNeural",        name: "Gaia",       desc: "Italiano · Femminile",               locale: "it-IT"),
                MicrosoftVoicePreset(id: "it-IT-ImolaNeural",       name: "Imola",      desc: "Italiano · Femminile",               locale: "it-IT"),
                MicrosoftVoicePreset(id: "it-IT-PalmaNeural",       name: "Palma",      desc: "Italiano · Femminile",               locale: "it-IT"),
                MicrosoftVoicePreset(id: "it-IT-BenignoNeural",     name: "Benigno",    desc: "Italiano · Maschile",                locale: "it-IT"),
                MicrosoftVoicePreset(id: "it-IT-CalimeroNeural",    name: "Calimero",   desc: "Italiano · Maschile",                locale: "it-IT"),
                MicrosoftVoicePreset(id: "it-IT-GianniNeural",      name: "Gianni",     desc: "Italiano · Maschile",                locale: "it-IT"),
                MicrosoftVoicePreset(id: "it-IT-LorenzoNeural",     name: "Lorenzo",    desc: "Italiano · Maschile",                locale: "it-IT"),
                MicrosoftVoicePreset(id: "it-IT-NiccoloNeural",     name: "Niccolo",    desc: "Italiano · Maschile",                locale: "it-IT"),
                MicrosoftVoicePreset(id: "it-IT-RinaldoNeural",     name: "Rinaldo",    desc: "Italiano · Maschile",                locale: "it-IT"),
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
        
        // Restore cached dynamic voices
        if let data = UserDefaults.standard.data(forKey: "ms_dynamic_voices_cache"),
           let decoded = try? JSONDecoder().decode([String: [MicrosoftVoicePreset]].self, from: data) {
            self.dynamicVoices = decoded
        }
        if let ts = UserDefaults.standard.object(forKey: "ms_dynamic_voices_timestamp") as? Date {
            self.lastFetchedAt = ts
        }
    }
    
    /// Persist dynamic voices to UserDefaults so they survive app restarts
    func persistDynamicVoices() {
        if let data = try? JSONEncoder().encode(dynamicVoices) {
            UserDefaults.standard.set(data, forKey: "ms_dynamic_voices_cache")
        }
        UserDefaults.standard.set(lastFetchedAt, forKey: "ms_dynamic_voices_timestamp")
    }
    
    /// Maps an Azure locale string to our internal langId
    public static func langId(for locale: String) -> String? {
        let l = locale.lowercased()
        if l.hasPrefix("zh-cn") || l.hasPrefix("zh-hans") { return "zh-Hans" }
        if l.hasPrefix("zh-tw") || l.hasPrefix("zh-hk") || l.hasPrefix("zh-hant") { return "zh-Hant" }
        if l.hasPrefix("en-") || l == "en" { return "en" }
        if l.hasPrefix("ja-") || l == "ja" { return "ja" }
        if l.hasPrefix("ko-") || l == "ko" { return "ko" }
        if l.hasPrefix("fr-") || l == "fr" { return "fr" }
        if l.hasPrefix("ru-") || l == "ru" { return "ru" }
        if l.hasPrefix("de-") || l == "de" { return "de" }
        if l.hasPrefix("es-") || l == "es" { return "es" }
        if l.hasPrefix("it-") || l == "it" { return "it" }
        return nil
    }
    
    /// Returns dynamic voices if available, otherwise falls back to built-in presets
    public func voices(for langId: String) -> [MicrosoftVoicePreset] {
        if let dynamic = dynamicVoices[langId], !dynamic.isEmpty {
            return dynamic
        }
        return Self.voicePresets(for: langId)
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
            else if voice.contains("en-CA") { xmlLang = "en-CA" }
            else if voice.contains("en-IN") { xmlLang = "en-IN" }
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
        case "de", "de-de", "de-at", "de-ch":
            let v = MicrosoftSpeechConfig.defaultVoice(for: "de")
            let xml: String
            if v.contains("de-AT") { xml = "de-AT" }
            else if v.contains("de-CH") { xml = "de-CH" }
            else { xml = "de-DE" }
            return (v, xml)
        case "es", "es-es", "es-mx", "es-ar":
            let v = MicrosoftSpeechConfig.defaultVoice(for: "es")
            let xml: String
            if v.contains("es-MX") { xml = "es-MX" }
            else if v.contains("es-AR") { xml = "es-AR" }
            else { xml = "es-ES" }
            return (v, xml)
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
            // Extract the locale tag directly from the voice ID (e.g. "en-US-JennyNeural" → "en-US")
            let components = explicitVoice.split(separator: "-")
            let lang: String
            if components.count >= 2 {
                let part1 = String(components[0])   // e.g. "zh", "en", "de"
                let part2 = String(components[1])   // e.g. "CN", "US", "DE"
                // Some voices have 3-part locale like "zh-CN-liaoning-XiaobeiNeural"; part1+part2 is always the locale
                lang = "\(part1)-\(part2)"
            } else {
                lang = "zh-CN"
            }
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
    
    /// Fetches the full voice list from Azure, updates MicrosoftSpeechConfig.shared.dynamicVoices.
    /// Filters to only Neural/GA voices for the 10 supported language groups.
    @MainActor
    public static func fetchVoiceList(apiKey: String, region: String) async throws {
        let config = MicrosoftSpeechConfig.shared
        let cleanKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanRegion = region.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        
        guard !cleanKey.isEmpty, !cleanRegion.isEmpty else {
            throw SpeechError.missingCredentials
        }
        guard let url = URL(string: "https://\(cleanRegion).tts.speech.microsoft.com/cognitiveservices/voices/list") else {
            throw SpeechError.invalidEndpoint
        }
        
        config.isFetchingVoices = true
        config.fetchError = nil
        defer { config.isFetchingVoices = false }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(cleanKey, forHTTPHeaderField: "Ocp-Apim-Subscription-Key")
        request.setValue("Slate-macOS", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 15.0
        
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            config.fetchError = "网络请求失败: \(error.localizedDescription)"
            throw SpeechError.networkError(error)
        }
        
        guard let httpResponse = response as? HTTPURLResponse else {
            let err = SpeechError.networkError(NSError(domain: "Network", code: -1))
            config.fetchError = err.errorDescription
            throw err
        }
        guard httpResponse.statusCode == 200 else {
            if httpResponse.statusCode == 401 {
                config.fetchError = SpeechError.unauthorized.errorDescription
                throw SpeechError.unauthorized
            }
            let msg = String(data: data, encoding: .utf8) ?? "HTTP \(httpResponse.statusCode)"
            let err = SpeechError.httpError(statusCode: httpResponse.statusCode, message: msg)
            config.fetchError = err.errorDescription
            throw err
        }
        
        let items = try JSONDecoder().decode([AzureVoiceItem].self, from: data)
        
        // Group into our 10 lang buckets, keeping only Neural voices
        var grouped: [String: [MicrosoftVoicePreset]] = [:]
        for item in items {
            guard item.voiceType == "Neural" else { continue }
            guard let langId = MicrosoftSpeechConfig.langId(for: item.locale) else { continue }
            
            // Display name: prefer LocalName if non-ASCII (Chinese/Japanese/Korean), else DisplayName
            let hasNonASCII = item.localName.unicodeScalars.contains { $0.value > 127 }
            let displayName = hasNonASCII ? "\(item.localName) (\(item.displayName))" : item.displayName
            let genderDesc = item.gender == "Female" ? "女声" : "男声"
            
            let preset = MicrosoftVoicePreset(
                id: item.shortName,
                name: displayName,
                desc: "\(genderDesc) · \(item.locale)",
                locale: item.locale
            )
            grouped[langId, default: []].append(preset)
        }
        
        // Sort: female-first within each group, then alphabetically by name
        for langId in grouped.keys {
            grouped[langId]?.sort {
                let aF = $0.desc.hasPrefix("女")
                let bF = $1.desc.hasPrefix("女")
                if aF != bF { return aF }
                return $0.name.localizedStandardCompare($1.name) == .orderedAscending
            }
        }
        
        config.dynamicVoices = grouped
        config.lastFetchedAt = Date()
        config.fetchError = nil
        config.persistDynamicVoices()
    }
}
