import Foundation
import SwiftUI
import Translation
import NaturalLanguage
import Combine

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
            if currentProvider != .system {
                configuration = nil
            } else {
                setupConfiguration()
            }
            let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty && (hasSubmitted || !translatedText.isEmpty) {
                submitTranslation()
            }
        }
    }
    
    @Published var configuration: TranslationSession.Configuration?
    
    private var translationTask: Task<Void, Never>?
    
    private struct LanguageState {
        let source: AppLanguage
        let target: AppLanguage
        let primary: AppLanguage
        let secondary: AppLanguage
    }
    
    private var previousLanguageState: LanguageState?
    private var isUserSwitchingLanguage: Bool = false
    
    private func recordLanguageStateForRollback() {
        if previousLanguageState == nil {
            previousLanguageState = LanguageState(
                source: sourceLanguage,
                target: targetLanguage,
                primary: primaryLanguage,
                secondary: secondaryLanguage
            )
        }
        isUserSwitchingLanguage = true
    }
    
    func rollbackToPreviousLanguage() {
        let previous = self.previousLanguageState
        self.previousLanguageState = nil
        self.isUserSwitchingLanguage = false
        
        if let previous = previous {
            self.sourceLanguage = previous.source
            self.targetLanguage = previous.target
            self.primaryLanguage = previous.primary
            self.secondaryLanguage = previous.secondary
        } else {
            if self.targetLanguage.id != "zh-Hans" && self.targetLanguage.id != "en" && self.targetLanguage.id != "auto" {
                self.targetLanguage = self.primaryLanguage.isChinese ? .english : .simplifiedChinese
            }
            if self.sourceLanguage.id != "zh-Hans" && self.sourceLanguage.id != "en" && self.sourceLanguage.id != "auto" {
                self.sourceLanguage = .auto
            }
            if self.primaryLanguage.id != "zh-Hans" && self.primaryLanguage.id != "en" {
                self.primaryLanguage = .simplifiedChinese
            }
            if self.secondaryLanguage.id != "zh-Hans" && self.secondaryLanguage.id != "en" {
                self.secondaryLanguage = .english
            }
        }
        
        self.detectedSourceLanguage = nil
        self.isTranslating = false
        self.errorMessage = nil
        self.setupConfiguration()
        
        let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        if hasSubmitted && !trimmed.isEmpty {
            submitTranslation()
        }
    }
    
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
        
        if self.currentProvider == .system {
            setupConfiguration()
        }
    }
    
    func setProvider(_ provider: TranslationProvider) {
        guard provider != currentProvider else { return }
        currentProvider = provider
    }
    
    func setupConfiguration() {
        guard currentProvider == .system else {
            if self.configuration != nil {
                self.configuration = nil
            }
            return
        }
        
        let pair = resolveLanguagePair(for: inputText)
        if let config = self.configuration,
           config.source == pair.source,
           config.target == pair.target {
            return
        }
        
        self.configuration = TranslationSession.Configuration(
            source: pair.source,
            target: pair.target
        )
    }
    
    func handleSession(_ session: TranslationSession) async {
        guard currentProvider == .system else { return }
        
        let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard hasSubmitted && !trimmed.isEmpty else {
            let pair = resolveLanguagePair(for: inputText)
            let availability = LanguageAvailability()
            let initialStatus = await availability.status(from: pair.source, to: pair.target)
            
            // 1. If already installed, quietly prewarm the model
            if initialStatus == .installed {
                self.previousLanguageState = nil
                self.isUserSwitchingLanguage = false
                try? await session.prepareTranslation()
                return
            }
            
            // 2. If NOT installed:
            // ONLY trigger download sheet if user explicitly clicked dropdown to switch language!
            // When opening window, focusing, or typing, NEVER pop up the download sheet!
            if self.isUserSwitchingLanguage {
                self.isUserSwitchingLanguage = false
                do {
                    try await session.prepareTranslation()
                    let status = await availability.status(from: pair.source, to: pair.target)
                    if status == .installed {
                        self.previousLanguageState = nil
                    } else {
                        // User dismissed or clicked Done without downloading
                        rollbackToPreviousLanguage()
                    }
                } catch {
                    // User cancelled or download failed
                    rollbackToPreviousLanguage()
                }
            } else {
                // Not a user-initiated switch, but current language is uninstalled:
                // Immediately roll back to a known-installed language without prompting!
                rollbackToPreviousLanguage()
            }
            return
        }
        
        do {
            let response = try await session.translate(trimmed)
            guard !Task.isCancelled else { return }
            
            self.translatedText = response.targetText
            self.lastTranslatedInput = trimmed
            self.isTranslating = false
            self.errorMessage = nil
            self.previousLanguageState = nil
            self.isUserSwitchingLanguage = false
        } catch is CancellationError {
            // Task cancelled (e.g. view disappeared or user cancelled download prompt)
            if self.previousLanguageState != nil {
                rollbackToPreviousLanguage()
            }
            return
        } catch {
            guard !Task.isCancelled else { return }
            self.isTranslating = false
            if self.previousLanguageState != nil {
                rollbackToPreviousLanguage()
            } else {
                let nsError = error as NSError
                if nsError.domain == NSCocoaErrorDomain && nsError.code == NSUserCancelledError {
                    rollbackToPreviousLanguage()
                } else if case TranslationError.notInstalled = error {
                    rollbackToPreviousLanguage()
                } else {
                    self.errorMessage = error.localizedDescription
                }
            }
        }
    }
    
    public func invalidateActiveSession() {
        self.translationTask?.cancel()
        if self.isTranslating && self.currentProvider == .system {
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
        recordLanguageStateForRollback()
        primaryLanguage = lang
        if secondaryLanguage.id == lang.id {
            secondaryLanguage = (lang.id == "en" ? .simplifiedChinese : .english)
        }
        if hasSubmitted && !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            submitTranslation()
        } else {
            setupConfiguration()
        }
    }
    
    public func setSecondaryLanguage(_ lang: AppLanguage) {
        guard lang != secondaryLanguage else { return }
        recordLanguageStateForRollback()
        secondaryLanguage = lang
        if primaryLanguage.id == lang.id {
            primaryLanguage = (lang.id == "zh-Hans" ? .english : .simplifiedChinese)
        }
        if hasSubmitted && !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            submitTranslation()
        } else {
            setupConfiguration()
        }
    }
    
    public func adjustLanguagesIfNeeded(for text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            if detectedSourceLanguage != nil {
                detectedSourceLanguage = nil
                if currentProvider == .system {
                    setupConfiguration()
                }
            }
            return
        }
        
        let detected = AppLanguage.detectLanguage(for: trimmed)
        guard detected != self.detectedSourceLanguage else { return }
        self.detectedSourceLanguage = detected
        
        if currentProvider == .system {
            setupConfiguration()
        }
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
        isUserSwitchingLanguage = false
        if currentProvider == .system {
            setupConfiguration()
        }
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
            
            if self.currentProvider == .system {
                self.triggerSystemTranslation(for: trimmed)
            } else {
                self.performRemoteTranslation(for: trimmed, provider: self.currentProvider)
            }
        }
    }
    
    // MARK: - Remote Translation Dispatch
    private func performRemoteTranslation(for text: String, provider: TranslationProvider) {
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
                    return
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
    
    // MARK: - Apple System Translation
    private func triggerSystemTranslation(for text: String) {
        guard currentProvider == .system else { return }
        let pair = resolveLanguagePair(for: text)
        
        if let config = configuration,
           config.source == pair.source,
           config.target == pair.target {
            configuration?.invalidate()
        } else {
            configuration = TranslationSession.Configuration(
                source: pair.source,
                target: pair.target
            )
        }
    }
    
    func swapLanguages() {
        recordLanguageStateForRollback()
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
        } else {
            setupConfiguration()
        }
    }
    
    func setSource(_ lang: AppLanguage) {
        guard lang != sourceLanguage else { return }
        recordLanguageStateForRollback()
        sourceLanguage = lang
        if sourceLanguage.id != "auto" && sourceLanguage == targetLanguage {
            targetLanguage = (sourceLanguage.id == primaryLanguage.id ? secondaryLanguage : primaryLanguage)
        }
        if hasSubmitted && !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            submitTranslation()
        } else {
            setupConfiguration()
        }
    }
    
    func setTarget(_ lang: AppLanguage) {
        guard lang != targetLanguage else { return }
        recordLanguageStateForRollback()
        targetLanguage = lang
        if sourceLanguage.id != "auto" && sourceLanguage == targetLanguage {
            sourceLanguage = (targetLanguage.id == primaryLanguage.id ? secondaryLanguage : primaryLanguage)
        }
        if hasSubmitted && !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            submitTranslation()
        } else {
            setupConfiguration()
        }
    }
    
    func resolveLanguagePair(for text: String) -> (source: Locale.Language, target: Locale.Language) {
        let effSource = effectiveSourceLanguage
        let sourceLocale = effSource.localeLanguage ?? Locale.Language(identifier: "en")
        let effTarget = effectiveTargetLanguage
        var targetLocale = effTarget.localeLanguage ?? (primaryLanguage.localeLanguage ?? Locale.Language(identifier: "zh-Hans"))
        
        // Ensure source and target are not identical
        if sourceLocale.languageCode == targetLocale.languageCode {
            if sourceLocale.languageCode?.identifier == primaryLanguage.localeLanguage?.languageCode?.identifier {
                targetLocale = secondaryLanguage.localeLanguage ?? Locale.Language(identifier: "en")
            } else {
                targetLocale = primaryLanguage.localeLanguage ?? Locale.Language(identifier: "zh-Hans")
            }
        }
        
        return (sourceLocale, targetLocale)
    }
}
