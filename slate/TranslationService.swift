import Foundation
import SwiftUI
import NaturalLanguage
import Combine

/// Tracks successfully translated source characters locally for the status menu.
@MainActor
final class TranslationUsageTracker {
    static let shared = TranslationUsageTracker()

    private struct Entry: Codable {
        let date: Date
        let characters: Int
    }

    private let storageKey = "translation_usage_entries"
    private var entries: [Entry]

    private init() {
        if let data = UserDefaults.standard.data(forKey: storageKey),
           let savedEntries = try? JSONDecoder().decode([Entry].self, from: data) {
            entries = savedEntries
        } else {
            entries = []
        }
    }

    func recordSuccessfulTranslation(_ text: String) {
        let count = text.count
        guard count > 0 else { return }
        entries.append(Entry(date: Date(), characters: count))
        // Keep enough history to cover a full year while bounding local storage.
        let cutoff = Calendar.current.date(byAdding: .year, value: -1, to: Date()) ?? .distantPast
        entries.removeAll { $0.date < cutoff }
        persist()
    }

    func summary() -> (day: Int, week: Int, month: Int) {
        let calendar = Calendar.current
        let now = Date()
        let dayStart = calendar.startOfDay(for: now)
        let weekStart = calendar.dateInterval(of: .weekOfYear, for: now)?.start ?? dayStart
        let monthStart = calendar.dateInterval(of: .month, for: now)?.start ?? dayStart

        func total(since start: Date) -> Int {
            entries.reduce(0) { $0 + ($1.date >= start ? $1.characters : 0) }
        }
        return (total(since: dayStart), total(since: weekStart), total(since: monthStart))
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }
}

@MainActor
final class TranslationService: ObservableObject {
    static let shared = TranslationService()
    
    @Published var inputText: String = ""
    @Published var translatedText: String = ""
    @Published var isTranslating: Bool = false
    @Published var hasSubmitted: Bool = false
    @Published var lastTranslatedInput: String = ""
    @Published var errorMessage: String? = nil
    
    var hasContent: Bool {
        return !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
               !translatedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
               hasSubmitted
    }
    
    @Published var sourceLanguage: AppLanguage = .auto
    @Published var targetLanguage: AppLanguage = .autoSelect
    private var detectedSourceLanguage: AppLanguage? = nil
    private var lastTranslatedPairKey: String = ""
    
    @Published var primaryLanguage: AppLanguage {
        didSet {
            UserDefaults.standard.set(primaryLanguage.id, forKey: "app_primary_language")
        }
    }
    
    @Published var secondaryLanguage: AppLanguage {
        didSet {
            UserDefaults.standard.set(secondaryLanguage.id, forKey: "app_secondary_language")
        }
    }
    
    public var effectiveSourceLanguage: AppLanguage {
        if sourceLanguage.id != "auto" {
            return sourceLanguage
        }
        if let detected = detectedSourceLanguage {
            return detected
        }
        let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            return AppLanguage.detectLanguage(for: trimmed)
        }
        return .english
    }
    
    public var effectiveTargetLanguage: AppLanguage {
        if targetLanguage.id != "auto" {
            return targetLanguage
        }
        
        let effSource = effectiveSourceLanguage
        let isSourcePrimary: Bool
        if primaryLanguage.isChinese {
            isSourcePrimary = effSource.isChinese
        } else {
            isSourcePrimary = (effSource.id == primaryLanguage.id)
        }
        
        // When input is primary language, translate to secondary; otherwise translate to primary
        if isSourcePrimary {
            return secondaryLanguage
        } else {
            return primaryLanguage
        }
    }
    
    @Published var currentProvider: TranslationProvider {
        didSet {
            UserDefaults.standard.set(currentProvider.rawValue, forKey: "app_translation_provider")
            let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty && (hasSubmitted || !translatedText.isEmpty) {
                submitTranslation()
            }
        }
    }
    
    private var translationTask: Task<Void, Never>?
    
    init() {
        let savedProvider = UserDefaults.standard.string(forKey: "app_translation_provider") ?? "system"
        self.currentProvider = TranslationProvider(rawValue: savedProvider) ?? .system
        
        let primaryId = UserDefaults.standard.string(forKey: "app_primary_language") ?? "zh-Hans"
        let primary = AppLanguage.concreteTargetLanguages.first(where: { $0.id == primaryId }) ?? .simplifiedChinese
        self.primaryLanguage = primary
        
        let secondaryId = UserDefaults.standard.string(forKey: "app_secondary_language") ?? "en"
        let secondary = AppLanguage.concreteTargetLanguages.first(where: { $0.id == secondaryId }) ?? .english
        self.secondaryLanguage = secondary
        
        self.sourceLanguage = .auto
        self.targetLanguage = .autoSelect
    }
    
    func setProvider(_ provider: TranslationProvider) {
        guard provider != currentProvider else { return }
        currentProvider = provider
    }
    
    public func invalidateActiveSession() {
        self.translationTask?.cancel()
        if self.isTranslating {
            self.isTranslating = false
        }
    }
    
    func onInputChanged(_ newText: String) {
        let trimmed = newText.trimmingCharacters(in: .whitespacesAndNewlines)
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            if trimmed.isEmpty {
                self.clearContent()
            } else {
                self.adjustLanguagesIfNeeded(for: trimmed)
            }
        }
    }
    
    public func setPrimaryLanguage(_ lang: AppLanguage) {
        guard lang != primaryLanguage else { return }
        primaryLanguage = lang
        if secondaryLanguage.id == lang.id {
            secondaryLanguage = (lang.id == "en" ? .simplifiedChinese : .english)
        }
        if hasSubmitted && !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            submitTranslation()
        }
    }
    
    public func setSecondaryLanguage(_ lang: AppLanguage) {
        guard lang != secondaryLanguage else { return }
        secondaryLanguage = lang
        if primaryLanguage.id == lang.id {
            primaryLanguage = (lang.id == "zh-Hans" ? .english : .simplifiedChinese)
        }
        if hasSubmitted && !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            submitTranslation()
        }
    }
    
    public func adjustLanguagesIfNeeded(for text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            if detectedSourceLanguage != nil {
                detectedSourceLanguage = nil
            }
            return
        }
        
        let detected = AppLanguage.detectLanguage(for: trimmed)
        guard detected != self.detectedSourceLanguage else { return }
        self.detectedSourceLanguage = detected
    }
    
    func clearContent() {
        translationTask?.cancel()
        SpeechManager.shared.stop()
        inputText = ""
        translatedText = ""
        lastTranslatedInput = ""
        lastTranslatedPairKey = ""
        detectedSourceLanguage = nil
        hasSubmitted = false
        isTranslating = false
        errorMessage = nil
    }
    
    func submitTranslation(onAlreadyTranslatedCopy: (() -> Void)? = nil) {
        var rawInput = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rawInput.isEmpty else { return }
        
        if UserDefaults.standard.bool(forKey: "app_smart_line_break_merge") {
            let processed = TextProcessingUtils.smartMergeLineBreaks(rawInput)
            if processed != rawInput {
                rawInput = processed
                self.inputText = processed
            }
        }
        
        let trimmed = rawInput
        let currentPairKey = "\(currentProvider.rawValue)_\(effectiveSourceLanguage.id)_\(effectiveTargetLanguage.id)"
        
        // If already translated for the same input, same provider, and same pair, copy to clipboard
        if hasSubmitted && !translatedText.isEmpty && trimmed == lastTranslatedInput && currentPairKey == lastTranslatedPairKey {
            DispatchQueue.main.async {
                onAlreadyTranslatedCopy?()
            }
            return
        }
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            var rawInput = self.inputText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !rawInput.isEmpty else { return }
            
            if UserDefaults.standard.bool(forKey: "app_smart_line_break_merge") {
                let processed = TextProcessingUtils.smartMergeLineBreaks(rawInput)
                if processed != rawInput {
                    rawInput = processed
                    self.inputText = processed
                }
            }
            let trimmed = rawInput
            
            self.adjustLanguagesIfNeeded(for: trimmed)
            let currentPairKey = "\(self.currentProvider.rawValue)_\(self.effectiveSourceLanguage.id)_\(self.effectiveTargetLanguage.id)"
            
            self.lastTranslatedPairKey = currentPairKey
            self.hasSubmitted = true
            self.isTranslating = true
            self.errorMessage = nil
            
            self.performTranslation(for: trimmed, provider: self.currentProvider)
        }
    }
    
    // MARK: - Translation Dispatch
    private func performTranslation(for text: String, provider: TranslationProvider) {
        translationTask?.cancel()
        
        // Check credentials if required
        if provider.requiresConfig && !provider.isConfigured {
            self.isTranslating = false
            self.errorMessage = LocalizationManager.shared.t("service_not_configured_prompt", provider.title)
            return
        }
        
        translationTask = Task { [weak self] in
            guard let self = self else { return }
            do {
                let result: String
                switch provider {
                case .system:
                    result = try await BuiltinOnlineTranslator.translate(
                        text: text,
                        source: self.effectiveSourceLanguage,
                        target: self.effectiveTargetLanguage
                    )
                case .google:
                    let pair = self.resolveGoogleLanguagePair(for: text)
                    result = try await GoogleTranslator.translate(
                        text: text,
                        sourceCode: pair.source,
                        targetCode: pair.target,
                        apiKey: GoogleConfig.shared.apiKey
                    )
                case .deepl:
                    let pair = self.resolveDeepLLanguagePair(for: text)
                    result = try await DeepLTranslator.translate(
                        text: text,
                        sourceCode: pair.source,
                        targetCode: pair.target,
                        authKey: DeepLConfig.shared.authKey
                    )
                case .microsoft:
                    let pair = self.resolveMicrosoftLanguagePair(for: text)
                    result = try await MicrosoftTranslator.translate(
                        text: text,
                        sourceCode: pair.source,
                        targetCode: pair.target,
                        apiKey: MicrosoftConfig.shared.apiKey,
                        region: MicrosoftConfig.shared.region
                    )
                case .papago:
                    let pair = self.resolvePapagoLanguagePair(for: text)
                    result = try await PapagoTranslator.translate(
                        text: text,
                        sourceCode: pair.source,
                        targetCode: pair.target,
                        clientId: PapagoConfig.shared.clientId,
                        clientSecret: PapagoConfig.shared.clientSecret
                    )
                case .baidu:
                    let pair = self.resolveBaiduLanguagePair(for: text)
                    result = try await BaiduTranslator.translate(
                        text: text,
                        sourceCode: pair.source,
                        targetCode: pair.target,
                        appId: BaiduConfig.shared.appId,
                        secretKey: BaiduConfig.shared.secretKey
                    )
                case .alibaba:
                    let pair = self.resolveAlibabaLanguagePair(for: text)
                    result = try await AlibabaTranslator.translate(
                        text: text,
                        sourceCode: pair.source,
                        targetCode: pair.target,
                        accessKeyId: AlibabaConfig.shared.accessKeyId,
                        accessKeySecret: AlibabaConfig.shared.accessKeySecret
                    )
                case .volcengine:
                    let pair = self.resolveVolcengineLanguagePair(for: text)
                    result = try await VolcengineTranslator.translate(
                        text: text,
                        sourceCode: pair.source,
                        targetCode: pair.target,
                        accessKey: VolcengineConfig.shared.accessKey,
                        secretKey: VolcengineConfig.shared.secretKey
                    )
                }
                
                guard !Task.isCancelled else { return }
                self.translatedText = result
                self.lastTranslatedInput = text
                TranslationUsageTracker.shared.recordSuccessfulTranslation(text)
                self.isTranslating = false
                self.errorMessage = nil
            } catch {
                guard !Task.isCancelled else { return }
                if (error as? CancellationError) != nil { return }
                self.isTranslating = false
                self.errorMessage = error.localizedDescription
            }
        }
    }
    
    // MARK: - Language Pair Resolvers
    public func resolveGoogleLanguagePair(for text: String) -> (source: String, target: String) {
        let sourceCode = (sourceLanguage.id == "auto" ? "auto" : (sourceLanguage.googleCode ?? "auto"))
        let targetCode = effectiveTargetLanguage.googleCode ?? "zh-CN"
        return (sourceCode, targetCode)
    }
    
    public func resolveDeepLLanguagePair(for text: String) -> (source: String?, target: String) {
        let sourceCode = (sourceLanguage.id == "auto" ? nil : sourceLanguage.deeplSourceCode)
        let targetCode = effectiveTargetLanguage.deeplCode ?? "ZH"
        return (sourceCode, targetCode)
    }
    
    public func resolveMicrosoftLanguagePair(for text: String) -> (source: String?, target: String) {
        let sourceCode = (sourceLanguage.id == "auto" ? nil : sourceLanguage.microsoftCode)
        let targetCode = effectiveTargetLanguage.microsoftCode ?? "zh-Hans"
        return (sourceCode, targetCode)
    }
    
    public func resolvePapagoLanguagePair(for text: String) -> (source: String, target: String) {
        let sourceCode = (sourceLanguage.id == "auto" ? "auto" : (sourceLanguage.papagoCode ?? "auto"))
        let targetCode = effectiveTargetLanguage.papagoCode ?? (primaryLanguage.papagoCode ?? "ko")
        return (sourceCode, targetCode)
    }
    
    public func resolveBaiduLanguagePair(for text: String) -> (source: String, target: String) {
        let sourceCode = (sourceLanguage.id == "auto" ? "auto" : (sourceLanguage.baiduCode ?? "auto"))
        let targetCode = effectiveTargetLanguage.baiduCode ?? "zh"
        return (sourceCode, targetCode)
    }
    
    public func resolveAlibabaLanguagePair(for text: String) -> (source: String, target: String) {
        let sourceCode = (sourceLanguage.id == "auto" ? "auto" : (sourceLanguage.alibabaCode ?? "auto"))
        let targetCode = effectiveTargetLanguage.alibabaCode ?? "zh"
        return (sourceCode, targetCode)
    }
    
    public func resolveVolcengineLanguagePair(for text: String) -> (source: String?, target: String) {
        let sourceCode = (sourceLanguage.id == "auto" ? nil : sourceLanguage.volcengineCode)
        let targetCode = effectiveTargetLanguage.volcengineCode ?? "zh"
        return (sourceCode, targetCode)
    }
    
    func swapLanguages() {
        if sourceLanguage.id == "auto" && targetLanguage.id == "auto" {
            let curSource = effectiveSourceLanguage
            let curTarget = effectiveTargetLanguage
            sourceLanguage = curTarget
            targetLanguage = curSource
        } else if sourceLanguage.id == "auto" {
            let currentSource = effectiveSourceLanguage
            let currentTarget = targetLanguage
            sourceLanguage = currentTarget
            targetLanguage = currentSource
        } else if targetLanguage.id == "auto" {
            let currentSource = sourceLanguage
            let currentTarget = effectiveTargetLanguage
            sourceLanguage = currentTarget
            targetLanguage = currentSource
        } else {
            let oldSource = sourceLanguage
            let oldTarget = targetLanguage
            sourceLanguage = oldTarget
            targetLanguage = oldSource
        }
        
        if hasSubmitted && !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            submitTranslation()
        }
    }
    
    func setSource(_ lang: AppLanguage) {
        guard lang != sourceLanguage else { return }
        sourceLanguage = lang
        if sourceLanguage.id != "auto" && sourceLanguage == targetLanguage {
            targetLanguage = (sourceLanguage.id == primaryLanguage.id ? secondaryLanguage : primaryLanguage)
        }
        if hasSubmitted && !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            submitTranslation()
        }
    }
    
    func setTarget(_ lang: AppLanguage) {
        guard lang != targetLanguage else { return }
        targetLanguage = lang
        if sourceLanguage.id != "auto" && sourceLanguage == targetLanguage {
            sourceLanguage = (targetLanguage.id == primaryLanguage.id ? secondaryLanguage : primaryLanguage)
        }
        if hasSubmitted && !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            submitTranslation()
        }
    }
}
