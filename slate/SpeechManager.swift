import Foundation
import AVFoundation
import NaturalLanguage
import Combine

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
    
    override private init() {
        let savedProvider = UserDefaults.standard.string(forKey: "app_speech_provider") ?? "system"
        self.currentProvider = SpeechProvider(rawValue: savedProvider) ?? .system
        super.init()
        systemSynthesizer.delegate = self
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
    
    /// Speaks text using the current speech provider (macOS native or Microsoft Azure)
    public func speak(text: String, languageCode: String? = nil) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        
        // Stop any current playback
        stop()
        
        if currentProvider == .microsoft && MicrosoftSpeechConfig.shared.isConfigured {
            speakWithMicrosoft(text: trimmed, languageCode: languageCode)
        } else {
            speakWithSystem(text: trimmed, languageCode: languageCode)
        }
    }
    
    // MARK: - 1. Microsoft Azure Speech Synthesis
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
                    apiKey: apiKey,
                    region: region
                )
                
                guard !Task.isCancelled else { return }
                
                let player = try AVAudioPlayer(data: audioData)
                player.delegate = self
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
    
    // MARK: - 2. macOS Native Speech Synthesis
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
        
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
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
        let allVoices = AVSpeechSynthesisVoice.speechVoices()
        
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
