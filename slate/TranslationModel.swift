import Foundation
import SwiftUI
import NaturalLanguage

public struct AppLanguage: Identifiable, Hashable {
    public let id: String
    public let name: String
    public let localeLanguage: Locale.Language?
    
    public var isChinese: Bool {
        id == "zh-Hans" || id == "zh-Hant"
    }
    
    public init(id: String, name: String, localeLanguage: Locale.Language?) {
        self.id = id
        self.name = name
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
    
    public var tencentCode: String? {
        switch id {
        case "auto": return "auto"
        case "zh-Hans": return "zh"
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
    case baidu = "baidu"
    case tencent = "tencent"
    case alibaba = "alibaba"
    case volcengine = "volcengine"
    
    public var id: String { rawValue }
    
    public var title: String {
        switch self {
        case .system: return "Apple 原生翻译"
        case .google: return "Google 翻译"
        case .deepl: return "DeepL 翻译"
        case .microsoft: return "Microsoft 翻译"
        case .baidu: return "百度翻译"
        case .tencent: return "腾讯翻译君"
        case .alibaba: return "阿里翻译"
        case .volcengine: return "火山翻译"
        }
    }
    
    public var shortName: String {
        switch self {
        case .system: return "Apple"
        case .google: return "Google"
        case .deepl: return "DeepL"
        case .microsoft: return "微软"
        case .baidu: return "百度"
        case .tencent: return "腾讯"
        case .alibaba: return "阿里"
        case .volcengine: return "火山"
        }
    }
    
    public var subtitle: String {
        switch self {
        case .system: return "macOS 系统内置 · 离线/神经加速"
        case .google: return "免配置即用 · 全球多语言覆盖"
        case .deepl: return "DeepL 引擎 · 自然流畅的高质翻译"
        case .microsoft: return "Azure 认知服务 · 微软翻译技术"
        case .baidu: return "百度翻译开放平台 · 老牌引擎"
        case .tencent: return "腾讯云 TMT · 翻译君智能引擎"
        case .alibaba: return "阿里云机器翻译 · 达摩院技术加持"
        case .volcengine: return "火山引擎 · 字节跳动前沿翻译模型"
        }
    }
    
    public var icon: String {
        switch self {
        case .system: return "apple.logo"
        case .google: return "globe.americas.fill"
        case .deepl: return "text.book.closed.fill"
        case .microsoft: return "square.grid.2x2.fill"
        case .baidu: return "pawprint.fill"
        case .tencent: return "bubble.left.and.bubble.right.fill"
        case .alibaba: return "cube.box.fill"
        case .volcengine: return "flame.fill"
        }
    }
    
    public var accentColor: Color {
        switch self {
        case .system: return Color.primary
        case .google: return Color(red: 0.26, green: 0.52, blue: 0.96)
        case .deepl: return Color(red: 0.10, green: 0.35, blue: 0.60)
        case .microsoft: return Color(red: 0.0, green: 0.47, blue: 0.83)
        case .baidu: return Color(red: 0.16, green: 0.28, blue: 0.94)
        case .tencent: return Color(red: 0.0, green: 0.58, blue: 0.78)
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
        case .baidu:
            return BaiduConfig.shared.isConfigured
        case .tencent:
            return TencentConfig.shared.isConfigured
        case .alibaba:
            return AlibabaConfig.shared.isConfigured
        case .volcengine:
            return VolcengineConfig.shared.isConfigured
        }
    }
}
