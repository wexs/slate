import Foundation
import AVFoundation
import NaturalLanguage
import Combine

public struct SystemVoiceOption: Identifiable, Hashable {
    public let id: String
    public let name: String
    public let language: String
    public let displayName: String
    public let isEnhanced: Bool
    
    public init(id: String, name: String, language: String, displayName: String, isEnhanced: Bool) {
        self.id = id
        self.name = name
        self.language = language
        self.displayName = displayName
        self.isEnhanced = isEnhanced
    }
}

public struct SpeedRateOption: Identifiable, Hashable {
    public let rate: Double
    public let label: String
    
    public var id: Double { rate }
    
    public init(rate: Double, label: String) {
        self.rate = rate
        self.label = label
    }
    
    public static let options: [SpeedRateOption] = [
        SpeedRateOption(rate: 0.5, label: "0.5 倍"),
        SpeedRateOption(rate: 0.75, label: "0.75 倍"),
        SpeedRateOption(rate: 1.0, label: "1 倍"),
        SpeedRateOption(rate: 1.25, label: "1.25 倍"),
        SpeedRateOption(rate: 1.5, label: "1.5 倍"),
        SpeedRateOption(rate: 1.75, label: "1.75 倍"),
        SpeedRateOption(rate: 2.0, label: "2 倍")
    ]
    
    public static var allOptions: [SpeedRateOption] { options }
}

public typealias SpeechRateOption = SpeedRateOption

public struct SpeechLanguageEntry: Identifiable, Hashable {
    public let id: String
    private let rawName: String
    public var name: String {
        LocalizationManager.shared.languageName(for: id)
    }
    public let code: String
    public let defaultVoiceName: String
    public let sampleText: String
    
    public init(id: String, name: String, code: String, defaultVoiceName: String, sampleText: String) {
        self.id = id
        self.rawName = name
        self.code = code
        self.defaultVoiceName = defaultVoiceName
        self.sampleText = sampleText
    }
    
    public static let standardLanguages: [SpeechLanguageEntry] = [
        SpeechLanguageEntry(id: "zh-Hans", name: "中文简体", code: "zh-CN", defaultVoiceName: "婷婷", sampleText: "你好，这是中文语音试听。"),
        SpeechLanguageEntry(id: "en", name: "英语", code: "en-US", defaultVoiceName: "Samantha", sampleText: "Hello, this is English voice preview."),
        SpeechLanguageEntry(id: "zh-Hant", name: "中文繁体", code: "zh-TW", defaultVoiceName: "婷婷", sampleText: "您好，這是繁體中文語音試聽。"),
        SpeechLanguageEntry(id: "ja", name: "日语", code: "ja-JP", defaultVoiceName: "Kyoko", sampleText: "こんにちは、これは日本語の音声プレビューです。"),
        SpeechLanguageEntry(id: "ko", name: "韩语", code: "ko-KR", defaultVoiceName: "Yuna", sampleText: "안녕하세요, 한국어 음성 미리보기입니다."),
        SpeechLanguageEntry(id: "fr", name: "法语", code: "fr-FR", defaultVoiceName: "Amélie", sampleText: "Bonjour, ceci est un aperçu vocal en français."),
        SpeechLanguageEntry(id: "ru", name: "俄语", code: "ru-RU", defaultVoiceName: "Milena", sampleText: "Здравствуйте, это образец русской речи."),
        SpeechLanguageEntry(id: "de", name: "德语", code: "de-DE", defaultVoiceName: "Anna", sampleText: "Hallo, dies ist eine deutsche Sprachprobe."),
        SpeechLanguageEntry(id: "es", name: "西班牙语", code: "es-ES", defaultVoiceName: "Mónica", sampleText: "Hola, esta es una prueba de voz en español."),
        SpeechLanguageEntry(id: "it", name: "意大利语", code: "it-IT", defaultVoiceName: "Alice", sampleText: "Ciao, questa è una prova vocale in italiano.")
    ]
}

@MainActor
public final class SpeechManager: NSObject, ObservableObject, AVSpeechSynthesizerDelegate, AVAudioPlayerDelegate {
    public static let shared = SpeechManager()
    
    private let systemSynthesizer = AVSpeechSynthesizer()
    private var audioPlayer: AVAudioPlayer?
    private var speechTask: Task<Void, Never>?
    
    @Published public var isSpeaking: Bool = false
    @Published public var speakingText: String? = nil
    @Published public var currentProvider: SpeechProvider {
        didSet {
            UserDefaults.standard.set(currentProvider.rawValue, forKey: "app_speech_provider")
        }
    }
    
    /// Speech playback rate multiplier (0.5x to 2.0x, default 1.0x)
    @Published public var speechRate: Double {
        didSet {
            UserDefaults.standard.set(speechRate, forKey: "app_speech_rate")
        }
    }
    
    /// Stored voice IDs per language identifier (e.g. ["zh-Hans": "com.apple...", "en": "com.apple..."])
    @Published public var systemVoices: [String: String] {
        didSet {
            UserDefaults.standard.set(systemVoices, forKey: "speech_system_voices_map")
        }
    }
    
    /// Selected macOS system voice identifier for Chinese (empty string = auto/default)
    @Published public var systemChineseVoiceId: String {
        didSet {
            UserDefaults.standard.set(systemChineseVoiceId, forKey: "speech_system_zh_voice")
        }
    }
    
    /// Selected macOS system voice identifier for English (empty string = auto/default)
    @Published public var systemEnglishVoiceId: String {
        didSet {
            UserDefaults.standard.set(systemEnglishVoiceId, forKey: "speech_system_en_voice")
        }
    }
    
    private var cachedAllVoices: [AVSpeechSynthesisVoice]? = nil
    private var cachedVoicesByLanguage: [String: [SystemVoiceOption]] = [:]
    
    override private init() {
        let savedProvider = UserDefaults.standard.string(forKey: "app_speech_provider") ?? "system"
        self.currentProvider = SpeechProvider(rawValue: savedProvider) ?? .system
        
        let savedRate = UserDefaults.standard.double(forKey: "app_speech_rate")
        self.speechRate = savedRate > 0.1 ? savedRate : 1.0
        
        if let savedMap = UserDefaults.standard.dictionary(forKey: "speech_system_voices_map") as? [String: String] {
            self.systemVoices = savedMap
        } else {
            self.systemVoices = [:]
        }
        
        self.systemChineseVoiceId = UserDefaults.standard.string(forKey: "speech_system_zh_voice") ?? ""
        self.systemEnglishVoiceId = UserDefaults.standard.string(forKey: "speech_system_en_voice") ?? ""
        
        super.init()
        systemSynthesizer.delegate = self
        
        // Pre-warm the system voice cache in background so settings sheets open and close with zero delay
        Task.detached(priority: .utility) {
            let voices = AVSpeechSynthesisVoice.speechVoices()
            await MainActor.run {
                SpeechManager.shared.cachedAllVoices = voices
                for entry in SpeechLanguageEntry.standardLanguages {
                    _ = SpeechManager.shared.availableSystemVoices(for: entry)
                }
            }
        }
    }
    
    public func allSystemVoices() -> [AVSpeechSynthesisVoice] {
        if let cached = cachedAllVoices {
            return cached
        }
        let voices = AVSpeechSynthesisVoice.speechVoices()
        self.cachedAllVoices = voices
        return voices
    }
    
    public func clearVoiceCache() {
        self.cachedAllVoices = nil
        self.cachedVoicesByLanguage.removeAll()
    }
    
    public func setRate(_ rate: Double) {
        self.speechRate = min(max(rate, 0.5), 2.0)
    }
    
    public var currentRateLabel: String {
        if let match = SpeedRateOption.options.first(where: { abs($0.rate - speechRate) < 0.01 }) {
            return match.label
        }
        return String(format: "%.2f 倍", speechRate)
    }
    
    public func systemVoiceId(for langId: String) -> String {
        if let custom = systemVoices[langId], !custom.isEmpty {
            return custom
        }
        if langId == "zh-Hans" && !systemChineseVoiceId.isEmpty { return systemChineseVoiceId }
        if langId == "en" && !systemEnglishVoiceId.isEmpty { return systemEnglishVoiceId }
        
        if let langEntry = SpeechLanguageEntry.standardLanguages.first(where: { $0.id == langId }) {
            let available = availableSystemVoices(for: langEntry)
            if let matched = available.first(where: { $0.name.localizedCaseInsensitiveContains(langEntry.defaultVoiceName) }) {
                return matched.id
            }
            if let first = available.first {
                return first.id
            }
        }
        return ""
    }
    
    public func setSystemVoiceId(_ voiceId: String, for langId: String) {
        systemVoices[langId] = voiceId
        if langId == "zh-Hans" { systemChineseVoiceId = voiceId }
        if langId == "en" { systemEnglishVoiceId = voiceId }
    }
    
    public func availableSystemVoices(for langEntry: SpeechLanguageEntry) -> [SystemVoiceOption] {
        if let cached = cachedVoicesByLanguage[langEntry.id] {
            return cached
        }
        
        let all = allSystemVoices()
        let codePrefix = langEntry.id.contains("-") ? String(langEntry.id.split(separator: "-").first!) : langEntry.id
        
        var matches = all.filter { v in
            let vLang = v.language.replacingOccurrences(of: "_", with: "-").lowercased()
            if langEntry.id == "zh-Hans" {
                return vLang.hasPrefix("zh") && (vLang.contains("cn") || vLang.contains("hans") || (!vLang.contains("tw") && !vLang.contains("hk")))
            } else if langEntry.id == "zh-Hant" {
                return vLang.hasPrefix("zh") && (vLang.contains("tw") || vLang.contains("hk") || vLang.contains("hant"))
            } else {
                return vLang.hasPrefix(codePrefix.lowercased())
            }
        }
        
        // If zh-Hant has no specific TW/HK voices installed, include all Chinese voices as fallback (matching Image 2 where zh-Hant displays 婷婷 zh-CN)
        if matches.isEmpty && langEntry.id == "zh-Hant" {
            matches = all.filter { $0.language.replacingOccurrences(of: "_", with: "-").lowercased().hasPrefix("zh") }
        }
        
        if matches.isEmpty {
            let cleanCode = langEntry.code.replacingOccurrences(of: "_", with: "-")
            let fallback = [SystemVoiceOption(
                id: "\(langEntry.code)-default",
                name: langEntry.defaultVoiceName,
                language: cleanCode,
                displayName: "\(langEntry.defaultVoiceName) \(cleanCode)",
                isEnhanced: false
            )]
            cachedVoicesByLanguage[langEntry.id] = fallback
            return fallback
        }
        
        var seen = Set<String>()
        var options: [SystemVoiceOption] = []
        for v in matches {
            if seen.contains(v.identifier) { continue }
            seen.insert(v.identifier)
            let cleanLang = v.language.replacingOccurrences(of: "_", with: "-")
            options.append(SystemVoiceOption(
                id: v.identifier,
                name: v.name,
                language: cleanLang,
                displayName: "\(v.name) \(cleanLang)",
                isEnhanced: v.quality == .enhanced || v.quality == .premium
            ))
        }
        
        let sorted = options.sorted {
            let nameA = $0.name.lowercased()
            let nameB = $1.name.lowercased()
            let pref = langEntry.defaultVoiceName.lowercased()
            let aIsPref = nameA.contains(pref)
            let bIsPref = nameB.contains(pref)
            if aIsPref != bIsPref { return aIsPref }
            return $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending
        }
        
        cachedVoicesByLanguage[langEntry.id] = sorted
        return sorted
    }
    
    public func availableSystemVoices(for prefix: String) -> [SystemVoiceOption] {
        let all = allSystemVoices()
        let filtered = all.filter { voice in
            let code = voice.language.replacingOccurrences(of: "_", with: "-").lowercased()
            return code.hasPrefix(prefix.lowercased())
        }
        
        var seen = Set<String>()
        var result: [SystemVoiceOption] = []
        for v in filtered {
            if seen.contains(v.identifier) { continue }
            seen.insert(v.identifier)
            
            let isEnhanced = v.quality == .enhanced || v.quality == .premium
            var display = v.name
            if v.quality == .enhanced {
                display += " (增强版)"
            } else if v.quality == .premium {
                display += " (高级版)"
            }
            
            let langLower = v.language.replacingOccurrences(of: "_", with: "-").lowercased()
            if langLower == "zh-hk" {
                display += " · 粤语"
            } else if langLower == "zh-tw" {
                display += " · 台湾"
            } else if langLower == "en-gb" {
                display += " · 英音"
            } else if langLower == "en-au" {
                display += " · 澳音"
            } else if langLower == "en-in" {
                display += " · 印音"
            }
            
            result.append(SystemVoiceOption(
                id: v.identifier,
                name: v.name,
                language: v.language,
                displayName: display,
                isEnhanced: isEnhanced
            ))
        }
        
        return result.sorted {
            if $0.isEnhanced && !$1.isEnhanced { return true }
            if !$0.isEnhanced && $1.isEnhanced { return false }
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }
    
    public func setProvider(_ provider: SpeechProvider) {
        guard provider != currentProvider else { return }
        currentProvider = provider
    }
    
    /// Toggles speech playback: stops if currently reading the same text, or starts reading
    public func toggleSpeak(text: String, languageCode: String? = nil) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        
        if isSpeaking && speakingText == trimmed {
            stop()
            return
        }
        
        speak(text: trimmed, languageCode: languageCode)
    }
    
    /// Speaks text using the current speech provider (macOS native, Google Speech, or Microsoft Azure)
    public func speak(text: String, languageCode: String? = nil) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        
        // Stop any current playback
        stop()
        
        if currentProvider == .microsoft && MicrosoftSpeechConfig.shared.isConfigured {
            speakWithMicrosoft(text: trimmed, languageCode: languageCode)
        } else if currentProvider == .google {
            speakWithGoogle(text: trimmed, languageCode: languageCode)
        } else {
            speakWithSystem(text: trimmed, languageCode: languageCode)
        }
    }
    
    // MARK: - 1. Google Speech Synthesis
    private func speakWithGoogle(text: String, languageCode: String?) {
        let apiKey = GoogleSpeechConfig.shared.apiKey
        
        self.speakingText = text
        self.isSpeaking = true
        
        speechTask = Task { [weak self] in
            guard let self = self else { return }
            do {
                let audioData = try await GoogleSpeechSynthesizer.synthesize(
                    text: text,
                    languageCode: languageCode,
                    rate: self.speechRate,
                    apiKey: apiKey
                )
                
                guard !Task.isCancelled else { return }
                
                let player = try AVAudioPlayer(data: audioData)
                player.delegate = self
                player.enableRate = true
                player.rate = Float(self.speechRate)
                player.prepareToPlay()
                self.audioPlayer = player
                player.play()
            } catch {
                guard !Task.isCancelled else { return }
                print("Google Speech synthesis failed: \(error.localizedDescription), falling back to system speech.")
                // Fall back to system speech
                self.speakWithSystem(text: text, languageCode: languageCode)
            }
        }
    }
    
    // MARK: - 2. Microsoft Azure Speech Synthesis
    private func speakWithMicrosoft(text: String, languageCode: String?) {
        let apiKey = MicrosoftSpeechConfig.shared.apiKey
        let region = MicrosoftSpeechConfig.shared.region
        
        self.speakingText = text
        self.isSpeaking = true
        
        speechTask = Task { [weak self] in
            guard let self = self else { return }
            do {
                let audioData = try await MicrosoftSpeechSynthesizer.synthesize(
                    text: text,
                    languageCode: languageCode,
                    rate: self.speechRate,
                    apiKey: apiKey,
                    region: region
                )
                
                guard !Task.isCancelled else { return }
                
                let player = try AVAudioPlayer(data: audioData)
                player.delegate = self
                player.enableRate = true
                player.rate = Float(self.speechRate)
                player.prepareToPlay()
                self.audioPlayer = player
                player.play()
            } catch {
                guard !Task.isCancelled else { return }
                print("Microsoft Speech synthesis failed: \(error.localizedDescription), falling back to system speech.")
                // Fall back to system speech
                self.speakWithSystem(text: text, languageCode: languageCode)
            }
        }
    }
    
    // MARK: - 3. macOS Native Speech Synthesis
    private func speakWithSystem(text: String, languageCode: String?) {
        // Stop any currently ongoing speech immediately
        systemSynthesizer.stopSpeaking(at: .immediate)
        
        let utterance = AVSpeechUtterance(string: text)
        let resolvedCode = resolveSpeechLanguage(for: text, requestedCode: languageCode)
        
        if let voice = findVoice(for: resolvedCode) {
            utterance.voice = voice
        } else {
            utterance.voice = AVSpeechSynthesisVoice(language: resolvedCode) ??
                              AVSpeechSynthesisVoice(language: resolvedCode.replacingOccurrences(of: "-", with: "_")) ??
                              AVSpeechSynthesisVoice(language: "zh-CN")
        }
        
        let baseRate = AVSpeechUtteranceDefaultSpeechRate
        let calculatedRate = Float(speechRate) * baseRate
        utterance.rate = min(max(calculatedRate, AVSpeechUtteranceMinimumSpeechRate), AVSpeechUtteranceMaximumSpeechRate)
        utterance.volume = 1.0
        
        self.speakingText = text
        self.isSpeaking = true
        systemSynthesizer.speak(utterance)
    }
    
    private func resolveSpeechLanguage(for text: String, requestedCode: String?) -> String {
        var hasCJK = false
        var hasHiraganaOrKatakana = false
        var hasHangul = false
        var hasThai = false
        var hasArabic = false
        var hasCyrillic = false
        
        for scalar in text.unicodeScalars {
            let val = scalar.value
            if (val >= 0x4E00 && val <= 0x9FFF) || (val >= 0x3400 && val <= 0x4DBF) {
                hasCJK = true
            } else if (val >= 0x3040 && val <= 0x309F) || (val >= 0x30A0 && val <= 0x30FF) {
                hasHiraganaOrKatakana = true
            } else if (val >= 0xAC00 && val <= 0xD7AF) || (val >= 0x1100 && val <= 0x11FF) || (val >= 0x3130 && val <= 0x318F) {
                hasHangul = true
            } else if val >= 0x0E00 && val <= 0x0E7F {
                hasThai = true
            } else if (val >= 0x0600 && val <= 0x06FF) || (val >= 0x0750 && val <= 0x077F) {
                hasArabic = true
            } else if val >= 0x0400 && val <= 0x04FF {
                hasCyrillic = true
            }
        }
        
        let cleanRequested = requestedCode?.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "_", with: "-").lowercased()
        
        // Safeguard: If text is Chinese (CJK without Japanese Kana), FORCE Chinese language code!
        if hasCJK && !hasHiraganaOrKatakana {
            if let req = cleanRequested, req.hasPrefix("zh") {
                return req
            }
            return "zh-CN"
        }
        
        // If text is Japanese Kana, FORCE Japanese:
        if hasHiraganaOrKatakana {
            return "ja-JP"
        }
        
        // If text is Korean Hangul, FORCE Korean:
        if hasHangul {
            return "ko-KR"
        }
        
        if hasThai {
            return "th-TH"
        }
        
        if hasArabic {
            return "ar-SA"
        }
        
        if hasCyrillic {
            return "ru-RU"
        }
        
        if let req = cleanRequested, !req.isEmpty {
            return req
        }
        
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        if let dominant = recognizer.dominantLanguage?.rawValue {
            return dominant
        }
        
        return "zh-CN"
    }
    
    /// Stops any ongoing speech synthesis or audio playback immediately
    public func stop() {
        speechTask?.cancel()
        speechTask = nil
        
        systemSynthesizer.stopSpeaking(at: .immediate)
        
        if let player = audioPlayer, player.isPlaying {
            player.stop()
        }
        audioPlayer = nil
        
        self.isSpeaking = false
        self.speakingText = nil
    }
    
    private func findVoice(for languageCode: String?) -> AVSpeechSynthesisVoice? {
        guard let code = languageCode?.trimmingCharacters(in: .whitespacesAndNewlines), !code.isEmpty else {
            return nil
        }
        
        let normalized = code.replacingOccurrences(of: "_", with: "-").lowercased()
        let allVoices = allSystemVoices()
        
        // 0. User custom voice selection for all supported languages
        let matchedEntry = SpeechLanguageEntry.standardLanguages.first { entry in
            let entryCode = entry.code.lowercased()
            let entryId = entry.id.lowercased()
            return normalized == entryCode || normalized == entryId ||
                   normalized.hasPrefix(entryId + "-") ||
                   (entryId == "zh-hans" && (normalized == "zh" || normalized == "zh-cn")) ||
                   (entryId == "zh-hant" && (normalized == "zh-tw" || normalized == "zh-hk")) ||
                   (entryId == "en" && (normalized.hasPrefix("en-") || normalized == "en")) ||
                   (entryId == "ja" && (normalized.hasPrefix("ja-") || normalized == "ja")) ||
                   (entryId == "ko" && (normalized.hasPrefix("ko-") || normalized == "ko")) ||
                   (entryId == "fr" && (normalized.hasPrefix("fr-") || normalized == "fr")) ||
                   (entryId == "ru" && (normalized.hasPrefix("ru-") || normalized == "ru")) ||
                   (entryId == "de" && (normalized.hasPrefix("de-") || normalized == "de")) ||
                   (entryId == "es" && (normalized.hasPrefix("es-") || normalized == "es")) ||
                   (entryId == "it" && (normalized.hasPrefix("it-") || normalized == "it"))
        }
        
        if let entry = matchedEntry {
            let selectedVoiceId = systemVoiceId(for: entry.id)
            if !selectedVoiceId.isEmpty, let customVoice = allVoices.first(where: { $0.identifier == selectedVoiceId }) {
                return customVoice
            }
        }
        
        // 1. Special prioritization for Chinese voices
        if normalized.hasPrefix("zh") {
            // Prioritize Tingting (婷婷) which is standard macOS Chinese voice
            if let tingting = allVoices.first(where: {
                $0.name.localizedCaseInsensitiveContains("tingting") ||
                $0.name.contains("婷婷") ||
                $0.identifier.localizedCaseInsensitiveContains("tingting")
            }) {
                return tingting
            }
            
            // Next try exact zh-cn or zh_cn match
            if let zhCN = allVoices.first(where: {
                let lang = $0.language.replacingOccurrences(of: "_", with: "-").lowercased()
                return lang == normalized || lang == "zh-cn"
            }) {
                return zhCN
            }
            
            // Any zh voice
            if let anyZh = allVoices.first(where: {
                let lang = $0.language.replacingOccurrences(of: "_", with: "-").lowercased()
                return lang.hasPrefix("zh")
            }) {
                return anyZh
            }
            
            if let v = AVSpeechSynthesisVoice(language: "zh-CN") ?? AVSpeechSynthesisVoice(language: "zh_CN") {
                return v
            }
        }
        
        // 2. Direct match with language initializer
        if let voice = AVSpeechSynthesisVoice(language: code) {
            return voice
        }
        if let voice = AVSpeechSynthesisVoice(language: normalized) {
            return voice
        }
        if let voice = AVSpeechSynthesisVoice(language: normalized.replacingOccurrences(of: "-", with: "_")) {
            return voice
        }
        
        // 3. Exact match in all available voices (normalizing underscore to hyphen)
        if let match = allVoices.first(where: {
            $0.language.replacingOccurrences(of: "_", with: "-").lowercased() == normalized
        }) {
            return match
        }
        
        // 4. Prefix match (e.g., "en" matches "en-US", "ja" matches "ja-JP")
        let prefix = normalized.contains("-") ? String(normalized.split(separator: "-").first ?? "") : normalized
        if !prefix.isEmpty {
            if let match = allVoices.first(where: {
                let lang = $0.language.replacingOccurrences(of: "_", with: "-").lowercased()
                return lang.hasPrefix(prefix + "-") || lang == prefix
            }) {
                return match
            }
        }
        
        // 5. Mapped fallback
        let mapped: String? = {
            switch normalized {
            case "zh", "zh-hans", "zh-cn": return "zh-CN"
            case "zh-hant", "zh-tw", "zh-hk": return "zh-TW"
            case "en", "en-us", "en-gb": return "en-US"
            case "ja", "ja-jp": return "ja-JP"
            case "ko", "ko-kr": return "ko-KR"
            case "fr", "fr-fr": return "fr-FR"
            case "de", "de-de": return "de-DE"
            case "es", "es-es": return "es-ES"
            case "it", "it-it": return "it-IT"
            case "pt", "pt-br", "pt-pt": return "pt-BR"
            case "ru", "ru-ru": return "ru-RU"
            case "ar", "ar-sa": return "ar-SA"
            case "th", "th-th": return "th-TH"
            case "vi", "vi-vn": return "vi-VN"
            default: return nil
            }
        }()
        
        if let mapped = mapped {
            if let voice = AVSpeechSynthesisVoice(language: mapped) {
                return voice
            }
            let mappedLower = mapped.lowercased()
            if let match = allVoices.first(where: {
                $0.language.replacingOccurrences(of: "_", with: "-").lowercased() == mappedLower
            }) {
                return match
            }
        }
        
        return nil
    }
    
    // MARK: - AVSpeechSynthesizerDelegate
    nonisolated public func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in
            self.isSpeaking = false
            self.speakingText = nil
        }
    }
    
    nonisolated public func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in
            self.isSpeaking = false
            self.speakingText = nil
        }
    }
    
    // MARK: - AVAudioPlayerDelegate
    nonisolated public func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            self.isSpeaking = false
            self.speakingText = nil
            self.audioPlayer = nil
        }
    }
    
    nonisolated public func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        Task { @MainActor in
            self.isSpeaking = false
            self.speakingText = nil
            self.audioPlayer = nil
        }
    }
}
