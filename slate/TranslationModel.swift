import Foundation
import SwiftUI
import NaturalLanguage

public struct AppLanguage: Identifiable, Hashable {
    public let id: String
    private let rawName: String
    public var name: String {
        if id == "auto" {
            return rawName == "自动选择" ? loc("lang_auto_select") : loc("lang_auto")
        }
        return LocalizationManager.shared.languageName(for: id)
    }
    public let localeLanguage: Locale.Language?
    
    public var isChinese: Bool {
        id == "zh-Hans" || id == "zh-Hant"
    }
    
    public init(id: String, name: String, localeLanguage: Locale.Language?) {
        self.id = id
        self.rawName = name
        self.localeLanguage = localeLanguage
    }
    
    public static let auto = AppLanguage(id: "auto", name: "自动检测", localeLanguage: nil)
    public static let autoSelect = AppLanguage(id: "auto", name: "自动选择", localeLanguage: nil)
    public static let simplifiedChinese = AppLanguage(id: "zh-Hans", name: "中文", localeLanguage: Locale.Language(identifier: "zh-Hans"))
    public static let traditionalChinese = AppLanguage(id: "zh-Hant", name: "繁体中文", localeLanguage: Locale.Language(identifier: "zh-Hant"))
    public static let english = AppLanguage(id: "en", name: "英文", localeLanguage: Locale.Language(identifier: "en"))
    public static let japanese = AppLanguage(id: "ja", name: "日文", localeLanguage: Locale.Language(identifier: "ja"))
    public static let korean = AppLanguage(id: "ko", name: "韩文", localeLanguage: Locale.Language(identifier: "ko"))
    public static let french = AppLanguage(id: "fr", name: "法文", localeLanguage: Locale.Language(identifier: "fr"))
    public static let german = AppLanguage(id: "de", name: "德文", localeLanguage: Locale.Language(identifier: "de"))
    public static let spanish = AppLanguage(id: "es", name: "西班牙文", localeLanguage: Locale.Language(identifier: "es"))
    public static let italian = AppLanguage(id: "it", name: "意大利文", localeLanguage: Locale.Language(identifier: "it"))
    public static let portuguese = AppLanguage(id: "pt", name: "葡萄牙文", localeLanguage: Locale.Language(identifier: "pt"))
    public static let russian = AppLanguage(id: "ru", name: "俄文", localeLanguage: Locale.Language(identifier: "ru"))
    public static let arabic = AppLanguage(id: "ar", name: "阿拉伯文", localeLanguage: Locale.Language(identifier: "ar"))
    public static let thai = AppLanguage(id: "th", name: "泰文", localeLanguage: Locale.Language(identifier: "th"))
    public static let vietnamese = AppLanguage(id: "vi", name: "越南文", localeLanguage: Locale.Language(identifier: "vi"))

    public static let sourceLanguages: [AppLanguage] = [
        .auto,
        .simplifiedChinese,
        .english,
        .japanese,
        .korean,
        .french,
        .german,
        .spanish,
        .italian,
        .portuguese,
        .russian,
        .traditionalChinese,
        .arabic,
        .thai,
        .vietnamese
    ]
    
    public static let targetLanguages: [AppLanguage] = [
        .autoSelect,
        .simplifiedChinese,
        .english,
        .japanese,
        .korean,
        .french,
        .german,
        .spanish,
        .italian,
        .portuguese,
        .russian,
        .traditionalChinese,
        .arabic,
        .thai,
        .vietnamese
    ]
    
    public static let concreteTargetLanguages: [AppLanguage] = [
        .simplifiedChinese,
        .english,
        .japanese,
        .korean,
        .french,
        .german,
        .spanish,
        .italian,
        .portuguese,
        .russian,
        .traditionalChinese,
        .arabic,
        .thai,
        .vietnamese
    ]
    
    /// Detects language from given text with priority given to distinctive character scripts
    public static func detectLanguage(for text: String) -> AppLanguage {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .simplifiedChinese }
        
        var hasHiraganaOrKatakana = false
        var hasHangul = false
        var hasCJK = false
        var hasThai = false
        var hasArabic = false
        var hasCyrillic = false
        var hasLatin = false
        
        for scalar in trimmed.unicodeScalars {
            let val = scalar.value
            if (val >= 0x3040 && val <= 0x309F) || (val >= 0x30A0 && val <= 0x30FF) {
                hasHiraganaOrKatakana = true
            } else if (val >= 0xAC00 && val <= 0xD7AF) || (val >= 0x1100 && val <= 0x11FF) || (val >= 0x3130 && val <= 0x318F) {
                hasHangul = true
            } else if (val >= 0x4E00 && val <= 0x9FFF) || (val >= 0x3400 && val <= 0x4DBF) {
                hasCJK = true
            } else if val >= 0x0E00 && val <= 0x0E7F {
                hasThai = true
            } else if (val >= 0x0600 && val <= 0x06FF) || (val >= 0x0750 && val <= 0x077F) {
                hasArabic = true
            } else if val >= 0x0400 && val <= 0x04FF {
                hasCyrillic = true
            } else if (val >= 0x0041 && val <= 0x005A) || (val >= 0x0061 && val <= 0x007A) {
                hasLatin = true
            }
        }
        
        // Disambiguate scripts with strict priority
        if hasHiraganaOrKatakana {
            return .japanese
        }
        if hasHangul {
            return .korean
        }
        if hasThai {
            return .thai
        }
        if hasArabic {
            return .arabic
        }
        if hasCyrillic {
            return .russian
        }
        if hasCJK {
            return .simplifiedChinese
        }
        
        // For Latin/European scripts and other characters, use Apple NaturalLanguage recognizer
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(trimmed)
        if let dominant = recognizer.dominantLanguage?.rawValue {
            switch dominant {
            case "en": return .english
            case "zh", "zh-Hans": return .simplifiedChinese
            case "zh-Hant": return .traditionalChinese
            case "ja": return .japanese
            case "ko": return .korean
            case "fr": return .french
            case "de": return .german
            case "es": return .spanish
            case "it": return .italian
            case "pt": return .portuguese
            case "ru": return .russian
            case "ar": return .arabic
            case "th": return .thai
            case "vi": return .vietnamese
            default: break
            }
        }
        
        if hasLatin {
            return .english
        }
        
        return .simplifiedChinese
    }
    
    public var volcengineCode: String? {
        switch id {
        case "auto": return nil
        case "zh-Hans": return "zh"
        case "zh-Hant": return "zh-Hant"
        case "en": return "en"
        case "ja": return "ja"
        case "ko": return "ko"
        case "fr": return "fr"
        case "de": return "de"
        case "es": return "es"
        case "it": return "it"
        case "pt": return "pt"
        case "ru": return "ru"
        case "ar": return "ar"
        case "th": return "th"
        case "vi": return "vi"
        default: return id
        }
    }
    
    public var googleCode: String? {
        switch id {
        case "auto": return "auto"
        case "zh-Hans": return "zh-CN"
        case "zh-Hant": return "zh-TW"
        case "en": return "en"
        case "ja": return "ja"
        case "ko": return "ko"
        case "fr": return "fr"
        case "de": return "de"
        case "es": return "es"
        case "it": return "it"
        case "pt": return "pt"
        case "ru": return "ru"
        case "ar": return "ar"
        case "th": return "th"
        case "vi": return "vi"
        default: return id
        }
    }
    
    public var deeplCode: String? {
        switch id {
        case "auto": return nil
        case "zh-Hans": return "ZH"
        case "zh-Hant": return "ZH"
        case "en": return "EN-US"
        case "ja": return "JA"
        case "ko": return "KO"
        case "fr": return "FR"
        case "de": return "DE"
        case "es": return "ES"
        case "it": return "IT"
        case "pt": return "PT-PT"
        case "ru": return "RU"
        case "ar": return "AR"
        default: return id.uppercased()
        }
    }
    
    public var deeplSourceCode: String? {
        switch id {
        case "auto": return nil
        case "zh-Hans", "zh-Hant": return "ZH"
        case "en": return "EN"
        case "ja": return "JA"
        case "ko": return "KO"
        case "fr": return "FR"
        case "de": return "DE"
        case "es": return "ES"
        case "it": return "IT"
        case "pt": return "PT"
        case "ru": return "RU"
        case "ar": return "AR"
        default: return id.uppercased()
        }
    }
    
    public var microsoftCode: String? {
        switch id {
        case "auto": return nil
        case "zh-Hans": return "zh-Hans"
        case "zh-Hant": return "zh-Hant"
        case "en": return "en"
        case "ja": return "ja"
        case "ko": return "ko"
        case "fr": return "fr"
        case "de": return "de"
        case "es": return "es"
        case "it": return "it"
        case "pt": return "pt"
        case "ru": return "ru"
        case "ar": return "ar"
        case "th": return "th"
        case "vi": return "vi"
        default: return id
        }
    }
    
    public var baiduCode: String? {
        switch id {
        case "auto": return "auto"
        case "zh-Hans": return "zh"
        case "zh-Hant": return "cht"
        case "en": return "en"
        case "ja": return "jp"
        case "ko": return "kor"
        case "fr": return "fra"
        case "de": return "de"
        case "es": return "spa"
        case "it": return "it"
        case "pt": return "pt"
        case "ru": return "ru"
        case "ar": return "ara"
        case "th": return "th"
        case "vi": return "vie"
        default: return id
        }
    }
    

    public var alibabaCode: String? {
        switch id {
        case "auto": return "auto"
        case "zh-Hans": return "zh"
        case "zh-Hant": return "zh-tw"
        case "en": return "en"
        case "ja": return "ja"
        case "ko": return "ko"
        case "fr": return "fr"
        case "de": return "de"
        case "es": return "es"
        case "it": return "it"
        case "pt": return "pt"
        case "ru": return "ru"
        case "ar": return "ar"
        case "th": return "th"
        case "vi": return "vi"
        default: return id
        }
    }
    
    public var papagoCode: String? {
        switch id {
        case "auto": return "auto"
        case "zh-Hans": return "zh-CN"
        case "zh-Hant": return "zh-TW"
        case "en": return "en"
        case "ja": return "ja"
        case "ko": return "ko"
        case "fr": return "fr"
        case "de": return "de"
        case "es": return "es"
        case "it": return "it"
        case "pt": return "pt"
        case "ru": return "ru"
        case "th": return "th"
        case "vi": return "vi"
        default: return nil
        }
    }
    
    public var bcp47Code: String? {
        switch id {
        case "auto": return nil
        case "zh-Hans": return "zh-CN"
        case "zh-Hant": return "zh-TW"
        case "en": return "en-US"
        case "ja": return "ja-JP"
        case "ko": return "ko-KR"
        case "fr": return "fr-FR"
        case "de": return "de-DE"
        case "es": return "es-ES"
        case "it": return "it-IT"
        case "pt": return "pt-BR"
        case "ru": return "ru-RU"
        case "ar": return "ar-SA"
        case "th": return "th-TH"
        case "vi": return "vi-VN"
        default: return id
        }
    }
}

public enum TranslationProvider: String, CaseIterable, Identifiable {
    case system = "system"
    case google = "google"
    case deepl = "deepl"
    case microsoft = "microsoft"
    case papago = "papago"
    case baidu = "baidu"
    case alibaba = "alibaba"
    case volcengine = "volcengine"
    
    public var id: String { rawValue }
    
    public var title: String {
        switch self {
        case .system: return loc("provider_system")
        case .google: return loc("provider_google")
        case .deepl: return loc("provider_deepl")
        case .microsoft: return loc("provider_microsoft")
        case .papago: return loc("provider_papago")
        case .baidu: return loc("provider_baidu")
        case .alibaba: return loc("provider_alibaba")
        case .volcengine: return loc("provider_volcengine")
        }
    }
    
    public var shortName: String {
        switch self {
        case .system: return loc("provider_short_system")
        case .google: return loc("provider_short_google")
        case .deepl: return loc("provider_short_deepl")
        case .microsoft: return loc("provider_short_microsoft")
        case .papago: return loc("provider_short_papago")
        case .baidu: return loc("provider_short_baidu")
        case .alibaba: return loc("provider_short_alibaba")
        case .volcengine: return loc("provider_short_volcengine")
        }
    }
    
    public var subtitle: String {
        switch self {
        case .system: return loc("provider_system_sub")
        case .google: return loc("provider_google_sub")
        case .deepl: return loc("provider_deepl_sub")
        case .microsoft: return loc("provider_microsoft_sub")
        case .papago: return loc("provider_papago_sub")
        case .baidu: return loc("provider_baidu_sub")
        case .alibaba: return loc("provider_alibaba_sub")
        case .volcengine: return loc("provider_volcengine_sub")
        }
    }
    
    public var icon: String {
        switch self {
        case .system: return "bolt.horizontal.fill"
        case .google: return "globe.americas.fill"
        case .deepl: return "text.book.closed.fill"
        case .microsoft: return "square.grid.2x2.fill"
        case .papago: return "bird.fill"
        case .baidu: return "pawprint.fill"
        case .alibaba: return "cube.box.fill"
        case .volcengine: return "flame.fill"
        }
    }
    
    public var assetImageName: String? {
        switch self {
        case .system: return nil
        case .google: return "google"
        case .deepl: return "deepl"
        case .microsoft: return "Microsoft"
        case .papago: return "naver"
        case .baidu: return "baidu"
        case .alibaba: return "alibaba"
        case .volcengine: return "huoshan"
        }
    }
    
    public var accentColor: Color {
        switch self {
        case .system: return Color(red: 0.12, green: 0.53, blue: 0.90)
        case .google: return Color(red: 0.26, green: 0.52, blue: 0.96)
        case .deepl: return Color(red: 0.10, green: 0.35, blue: 0.60)
        case .microsoft: return Color(red: 0.0, green: 0.47, blue: 0.83)
        case .papago: return Color(red: 0.08, green: 0.77, blue: 0.42)
        case .baidu: return Color(red: 0.16, green: 0.28, blue: 0.94)
        case .alibaba: return Color(red: 1.0, green: 0.42, blue: 0.0)
        case .volcengine: return Color(red: 0.94, green: 0.25, blue: 0.26)
        }
    }
    
    public var requiresConfig: Bool {
        switch self {
        case .system, .google: return false
        default: return true
        }
    }
    
    @MainActor
    public var isConfigured: Bool {
        switch self {
        case .system:
            return true
        case .google:
            return true
        case .deepl:
            return DeepLConfig.shared.isConfigured
        case .microsoft:
            return MicrosoftConfig.shared.isConfigured
        case .papago:
            return PapagoConfig.shared.isConfigured
        case .baidu:
            return BaiduConfig.shared.isConfigured
        case .alibaba:
            return AlibabaConfig.shared.isConfigured
        case .volcengine:
            return VolcengineConfig.shared.isConfigured
        }
    }
}

public extension Image {
    static func brandIcon(_ name: String) -> Image {
        if NSImage(named: name) != nil {
            return Image(name)
        }
        if NSImage(named: "brandicon/\(name)") != nil {
            return Image("brandicon/\(name)")
        }
        return Image(name)
    }
}

public struct ProviderIconView: View {
    let provider: TranslationProvider
    var size: CGFloat = 16
    var isSelected: Bool = false
    
    public init(provider: TranslationProvider, size: CGFloat = 16, isSelected: Bool = false) {
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

