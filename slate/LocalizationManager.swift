import Foundation
import SwiftUI
import Combine

public enum AppInterfaceLanguage: String, CaseIterable, Identifiable {
    case system = "system"
    case en = "en"
    case ja = "ja"
    case ko = "ko"
    case ru = "ru"
    case es = "es"
    case fr = "fr"
    case zhHans = "zh-Hans"
    case zhHant = "zh-Hant"
    
    public var id: String { rawValue }
    
    public var displayName: String {
        switch self {
        case .system: return LocalizationManager.shared.t("lang_system")
        case .en: return "English"
        case .ja: return "日本語"
        case .ko: return "한국어"
        case .ru: return "Русский"
        case .es: return "Español"
        case .fr: return "Français"
        case .zhHans: return "简体中文"
        case .zhHant: return "繁體中文"
        }
    }
}

@MainActor
public final class LocalizationManager: ObservableObject {
    public static let shared = LocalizationManager()
    
    @Published public private(set) var selectedLanguage: AppInterfaceLanguage
    @Published public private(set) var currentResolvedLanguage: String = "zh-Hans"
    
    private init() {
        let saved = UserDefaults.standard.string(forKey: "app_interface_language") ?? "system"
        let initialLang = AppInterfaceLanguage(rawValue: saved) ?? .system
        self.selectedLanguage = initialLang
        self.currentResolvedLanguage = Self.resolveSystemLanguage(for: initialLang)
    }
    
    public func setLanguage(_ language: AppInterfaceLanguage) {
        guard language != selectedLanguage else { return }
        selectedLanguage = language
        UserDefaults.standard.set(language.rawValue, forKey: "app_interface_language")
        currentResolvedLanguage = Self.resolveSystemLanguage(for: language)
        SettingsWindowController.shared.updateLocalization()
    }
    
    public static func resolveSystemLanguage(for language: AppInterfaceLanguage) -> String {
        if language != .system {
            return language.rawValue
        }
        
        for pref in Locale.preferredLanguages {
            let lower = pref.lowercased()
            if lower.hasPrefix("zh-hant") || lower.hasPrefix("zh-tw") || lower.hasPrefix("zh-hk") || lower.hasPrefix("zh-mo") {
                return "zh-Hant"
            }
            if lower.hasPrefix("zh") {
                return "zh-Hans"
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
            if lower.hasPrefix("en") {
                return "en"
            }
        }
        return "zh-Hans"
    }
    
    public func languageName(for id: String) -> String {
        switch id {
        case "auto": return t("lang_auto")
        case "zh-Hans": return t("lang_zh_Hans")
        case "zh-Hant": return t("lang_zh_Hant")
        case "en": return t("lang_en")
        case "ja": return t("lang_ja")
        case "ko": return t("lang_ko")
        case "fr": return t("lang_fr")
        case "de": return t("lang_de")
        case "es": return t("lang_es")
        case "it": return t("lang_it")
        case "pt": return t("lang_pt")
        case "ru": return t("lang_ru")
        case "ar": return t("lang_ar")
        case "th": return t("lang_th")
        case "vi": return t("lang_vi")
        default: return id
        }
    }

    // MARK: - String Catalog Lookup
    public func t(_ key: String) -> String {
        for language in [currentResolvedLanguage, "zh-Hans", "en"] {
            if let value = LocalizableCatalog.string(for: key, language: language), !value.isEmpty {
                return value
            }
        }
        return key
    }

    public func t(_ key: String, _ args: CVarArg...) -> String {
        let formatStr = t(key)
        return String(format: formatStr, locale: Locale(identifier: currentResolvedLanguage), arguments: args)
    }

    private func localizedString(_ key: String, language: String) -> String {
        LocalizableCatalog.string(for: key, language: language) ?? key
    }
}

// Global convenience accessor
public func loc(_ key: String) -> String {
    LocalizationManager.shared.t(key)
}

public func loc(_ key: String, _ args: CVarArg...) -> String {
    let formatStr = LocalizationManager.shared.t(key)
    return String(format: formatStr, locale: Locale(identifier: LocalizationManager.shared.currentResolvedLanguage), arguments: args)
}
