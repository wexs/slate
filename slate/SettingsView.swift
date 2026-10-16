import SwiftUI
import AppKit
import AVFoundation
import Combine

public enum SettingsTab: String, CaseIterable, Identifiable {
    case general = "general"
    case interface = "interface"
    case translation = "translation"
    case shortcuts = "shortcuts"
    case speech = "speech"
    case about = "about"
    
    public var id: String { rawValue }
    
    public var title: String {
        switch self {
        case .general: return loc("tab_general")
        case .interface: return loc("tab_interface")
        case .translation: return loc("tab_translation")
        case .shortcuts: return loc("tab_shortcuts")
        case .speech: return loc("tab_speech")
        case .about: return loc("tab_about")
        }
    }
    
    public var icon: String {
        switch self {
        case .general: return "gearshape"
        case .interface: return "macwindow"
        case .translation: return "globe"
        case .shortcuts: return "command"
        case .speech: return "waveform"
        case .about: return "info.circle"
        }
    }
}

public struct SettingsView: View {
    @Environment(\.colorScheme) private var colorScheme
    private var isDark: Bool { colorScheme == .dark }
    
    @ObservedObject private var locManager = LocalizationManager.shared
    @ObservedObject private var controller = SettingsWindowController.shared
    private var selectedTab: SettingsTab { controller.selectedTab }
    @ObservedObject private var hotKeyManager = GlobalHotKeyManager.shared
    @ObservedObject private var windowManager = WindowManager.shared
    @ObservedObject private var selectionManager = SelectionTranslationManager.shared
    @ObservedObject private var speechManager = SpeechManager.shared
    @ObservedObject private var msSpeechConfig = MicrosoftSpeechConfig.shared
    @ObservedObject private var menuBarManager = MenuBarManager.shared
    @ObservedObject private var translationService = TranslationService.shared
    @ObservedObject private var launchManager = LaunchAtLoginManager.shared
    
    // Translation Configs
    @ObservedObject private var googleConfig = GoogleConfig.shared
    @ObservedObject private var deeplConfig = DeepLConfig.shared
    @ObservedObject private var msTransConfig = MicrosoftConfig.shared
    @ObservedObject private var baiduConfig = BaiduConfig.shared
    @ObservedObject private var alibabaConfig = AlibabaConfig.shared
    @ObservedObject private var volcConfig = VolcengineConfig.shared
    
    // Master-Detail Translation Selection State
    @State private var selectedProviderForEdit: TranslationProvider = .system
    
    // Master-Detail Speech Selection State
    @State private var selectedSpeechProviderForEdit: SpeechProvider = .system
    @State private var testAudioPlayer: AVAudioPlayer? = nil
    
    // Google Inputs
    @State private var inputGoogleKey: String = ""
    @State private var isGoogleKeyVisible: Bool = false
    
    // DeepL Inputs
    @State private var inputDeepLKey: String = ""
    @State private var isDeepLKeyVisible: Bool = false
    
    // Microsoft Translator Inputs
    @State private var inputMsTransKey: String = ""
    @State private var inputMsTransRegion: String = "global"
    @State private var isMsTransKeyVisible: Bool = false
    
    // Baidu Inputs
    @State private var inputBaiduAppId: String = ""
    @State private var inputBaiduSecretKey: String = ""
    @State private var isBaiduKeyVisible: Bool = false
    
    // Alibaba Inputs
    @State private var inputAlibabaKeyId: String = ""
    @State private var inputAlibabaKeySecret: String = ""
    @State private var isAlibabaKeyVisible: Bool = false
    
    // Volcengine Inputs
    @State private var inputAK: String = ""
    @State private var inputSK: String = ""
    @State private var isSKVisible: Bool = false
    
    // Translation Testing State
    @State private var isTesting: Bool = false
    @State private var testSuccess: Bool? = nil
    @State private var testMessage: String = ""
    @State private var showSavedAlert: Bool = false
    
    // Google Speech Config & State
    @ObservedObject private var googleSpeechConfig = GoogleSpeechConfig.shared
    @State private var inputGoogleSpeechKey: String = ""
    @State private var isGoogleSpeechKeyVisible: Bool = false
    @State private var isGoogleSpeechTesting: Bool = false
    @State private var googleSpeechTestSuccess: Bool? = nil
    @State private var googleSpeechTestMessage: String = ""
    @State private var showGoogleSpeechSavedAlert: Bool = false
    
    // Microsoft Speech Testing State
    @State private var inputMsKey: String = ""
    @State private var inputMsRegion: String = "eastasia"
    @State private var isMsKeyVisible: Bool = false
    @State private var isMsTesting: Bool = false
    @State private var msTestSuccess: Bool? = nil
    @State private var msTestMessage: String = ""
    @State private var showMsSavedAlert: Bool = false
    @State private var showVoiceSettingsSheet: Bool = false
    @State private var voiceSheetProvider: SpeechProvider = .system
    
    @AppStorage("app_translation_provider") private var selectedProvider: String = TranslationProvider.system.rawValue
    @AppStorage("app_clear_content_on_open") private var clearContentOnOpen: Bool = true
    
    public init(initialTab: SettingsTab = .general, initialEditingProvider: TranslationProvider? = nil, initialEditingSpeechProvider: SpeechProvider? = nil) {
        if let speechProvider = initialEditingSpeechProvider {
            _selectedSpeechProviderForEdit = State(initialValue: speechProvider)
            _selectedProviderForEdit = State(initialValue: TranslationService.shared.currentProvider)
        } else if let provider = initialEditingProvider {
            _selectedProviderForEdit = State(initialValue: provider)
            _selectedSpeechProviderForEdit = State(initialValue: SpeechManager.shared.currentProvider)
        } else {
            _selectedProviderForEdit = State(initialValue: TranslationService.shared.currentProvider)
            _selectedSpeechProviderForEdit = State(initialValue: SpeechManager.shared.currentProvider)
        }
    }
    
    public var body: some View {
        VStack(spacing: 0) {
            // 主内容视图
            Group {
                switch selectedTab {
                case .general:
                    ScrollView {
                        generalSection
                            .padding(.vertical, 32)
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                case .interface:
                    ScrollView {
                        interfaceSection
                            .padding(.vertical, 32)
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                case .translation:
                    translationMasterDetailSection
                case .shortcuts:
                    ScrollView {
                        shortcutsSection
                            .padding(.vertical, 32)
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                case .speech:
                    speechMasterDetailSection
                case .about:
                    ScrollView {
                        aboutSection
                            .padding(.vertical, 32)
                            .padding(.horizontal, 24)
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            
            Divider()
            
            bottomStatusBar
        }
        .frame(width: 780, height: 550)
        .background(Color(NSColor.windowBackgroundColor))
        .sheet(isPresented: $showVoiceSettingsSheet) {
            VoiceSettingsSheetView(provider: voiceSheetProvider)
        }
        .onAppear {
            // Ensure translationService reflects the stored default provider if needed
            if let savedTrans = UserDefaults.standard.string(forKey: "app_translation_provider"),
               let p = TranslationProvider(rawValue: savedTrans),
               p != translationService.currentProvider {
                translationService.setProvider(p)
            }
            
            inputGoogleKey = googleConfig.apiKey
            inputDeepLKey = deeplConfig.authKey
            inputMsTransKey = msTransConfig.apiKey
            inputMsTransRegion = msTransConfig.region
            inputBaiduAppId = baiduConfig.appId
            inputBaiduSecretKey = baiduConfig.secretKey
            inputAlibabaKeyId = alibabaConfig.accessKeyId
            inputAlibabaKeySecret = alibabaConfig.accessKeySecret
            inputAK = volcConfig.accessKey
            inputSK = volcConfig.secretKey
            
            inputGoogleSpeechKey = googleSpeechConfig.apiKey
            inputMsKey = msSpeechConfig.apiKey
            inputMsRegion = msSpeechConfig.region
            selectionManager.checkAccessibilityPermission()
            launchManager.checkStatus()
        }
    }
    
    // MARK: - 底部状态栏
    @ViewBuilder
    private var bottomStatusBar: some View {
        HStack {
            Image(systemName: "lock.shield")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
            
            Text(loc("bottom_status_security"))
                .font(.system(size: 11))
                .foregroundColor(.secondary)
            
            Spacer()
            
            Button {
                if let url = URL(string: "https://github.com/maple-im/slate") {
                    NSWorkspace.shared.open(url)
                }
            } label: {
                Image(systemName: "questionmark.circle")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .help(loc("help_feedback"))
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 9)
        .background(Color(NSColor.windowBackgroundColor))
    }
    
    // MARK: - 1. 通用设置 (Apple 偏好设置经典居中排版：左列右对齐标签，右列左对齐控件)
    @ViewBuilder
    private var generalSection: some View {
        let labelWidth: CGFloat = 170
        let controlWidth: CGFloat = 220
        let rightColumnWidth: CGFloat = 380
        
        VStack(spacing: 20) {
            // 1. 目标语言偏好组
            HStack(alignment: .top, spacing: 14) {
                Text(loc("primary_language"))
                    .font(.system(size: 13))
                    .foregroundColor(.primary)
                    .frame(width: labelWidth, alignment: .trailing)
                    .padding(.top, 4)
                
                VStack(alignment: .leading, spacing: 5) {
                    Picker("", selection: Binding(
                        get: { translationService.primaryLanguage },
                        set: { translationService.setPrimaryLanguage($0) }
                    )) {
                        ForEach(AppLanguage.concreteTargetLanguages) { lang in
                            Text(lang.name).tag(lang)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(width: controlWidth, alignment: .leading)
                    
                    Text(loc("primary_language_desc"))
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(width: rightColumnWidth, alignment: .leading)
            }
            
            HStack(alignment: .top, spacing: 14) {
                Text(loc("secondary_language"))
                    .font(.system(size: 13))
                    .foregroundColor(.primary)
                    .frame(width: labelWidth, alignment: .trailing)
                    .padding(.top, 4)
                
                VStack(alignment: .leading, spacing: 5) {
                    Picker("", selection: Binding(
                        get: { translationService.secondaryLanguage },
                        set: { translationService.setSecondaryLanguage($0) }
                    )) {
                        ForEach(AppLanguage.concreteTargetLanguages) { lang in
                            Text(lang.name).tag(lang)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(width: controlWidth, alignment: .leading)
                    
                    Text(loc("secondary_language_desc"))
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(width: rightColumnWidth, alignment: .leading)
            }
            
            // 组间留白
            Spacer().frame(height: 6)
            
            // 2. 窗口交互行为组
            HStack(alignment: .top, spacing: 14) {
                Text(loc("window_behavior"))
                    .font(.system(size: 13))
                    .foregroundColor(.primary)
                    .frame(width: labelWidth, alignment: .trailing)
                    .padding(.top, 2)
                
                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 3) {
                        Toggle(loc("close_on_focus_lost"), isOn: Binding(
                            get: { windowManager.closeOnClickOutside },
                            set: { windowManager.setAlwaysOnTop(!$0) }
                        ))
                        .toggleStyle(.checkbox)
                        
                        Text(loc("close_on_focus_lost_desc"))
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                            .padding(.leading, 18)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    
                    VStack(alignment: .leading, spacing: 3) {
                        Toggle(loc("clear_on_open"), isOn: $clearContentOnOpen)
                            .toggleStyle(.checkbox)
                        
                        Text(loc("clear_on_open_desc"))
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                            .padding(.leading, 18)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(width: rightColumnWidth, alignment: .leading)
            }
            
            // 组间留白
            Spacer().frame(height: 6)
            
            // 4. 系统启动设置
            HStack(alignment: .top, spacing: 14) {
                Text(loc("launch_at_login"))
                    .font(.system(size: 13))
                    .foregroundColor(.primary)
                    .frame(width: labelWidth, alignment: .trailing)
                    .padding(.top, 2)
                
                VStack(alignment: .leading, spacing: 3) {
                    Toggle(loc("launch_at_login_toggle"), isOn: Binding(
                        get: { launchManager.isEnabled },
                        set: { launchManager.setEnabled($0) }
                    ))
                    .toggleStyle(.checkbox)
                    
                    Text(loc("launch_at_login_desc"))
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .padding(.leading, 18)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(width: rightColumnWidth, alignment: .leading)
            }
        }
        .frame(width: 564, alignment: .center)
    }
    
    // MARK: - 2. 界面设置 (界面语言 / 窗口宽度 / 状态栏图标)
    @ViewBuilder
    private var interfaceSection: some View {
        let labelWidth: CGFloat = 170
        let controlWidth: CGFloat = 220
        let rightColumnWidth: CGFloat = 380
        
        VStack(spacing: 20) {
            // 1. 界面语言偏好组
            HStack(alignment: .top, spacing: 14) {
                Text(loc("app_interface_language"))
                    .font(.system(size: 13))
                    .foregroundColor(.primary)
                    .frame(width: labelWidth, alignment: .trailing)
                    .padding(.top, 4)
                
                VStack(alignment: .leading, spacing: 5) {
                    Picker("", selection: Binding(
                        get: { locManager.selectedLanguage },
                        set: {
                            locManager.setLanguage($0)
                            SettingsWindowController.shared.updateLocalization()
                        }
                    )) {
                        ForEach(AppInterfaceLanguage.allCases) { lang in
                            Text(lang.displayName).tag(lang)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(width: controlWidth, alignment: .leading)
                    
                    Text(loc("app_interface_language_desc"))
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(width: rightColumnWidth, alignment: .leading)
            }
            
            // 组间留白
            Spacer().frame(height: 6)
            
            // 2. 窗口宽度组
            HStack(alignment: .top, spacing: 14) {
                Text(loc("window_width"))
                    .font(.system(size: 13))
                    .foregroundColor(.primary)
                    .frame(width: labelWidth, alignment: .trailing)
                    .padding(.top, 4)
                
                VStack(alignment: .leading, spacing: 5) {
                    Picker("", selection: Binding(
                        get: { windowManager.widthMode },
                        set: { windowManager.setWidthMode($0) }
                    )) {
                        Text(loc("width_standard")).tag(WindowWidthMode.standard)
                        Text(loc("width_wide")).tag(WindowWidthMode.wide)
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(width: controlWidth, alignment: .leading)
                    
                    Text(loc("window_width_desc"))
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(width: rightColumnWidth, alignment: .leading)
            }
            
            // 组间留白
            Spacer().frame(height: 6)
            
            // 3. 状态栏图标组
            HStack(alignment: .top, spacing: 14) {
                Text(loc("menu_bar_icon"))
                    .font(.system(size: 13))
                    .foregroundColor(.primary)
                    .frame(width: labelWidth, alignment: .trailing)
                    .padding(.top, 4)
                
                VStack(alignment: .leading, spacing: 5) {
                    Picker("", selection: Binding(
                        get: { menuBarManager.currentIcon },
                        set: { menuBarManager.setIcon($0) }
                    )) {
                        ForEach(MenuBarIconType.allCases) { icon in
                            Label(icon.title, systemImage: icon.symbolName).tag(icon)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(width: controlWidth, alignment: .leading)
                    
                    Text(loc("menu_bar_icon_desc"))
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(width: rightColumnWidth, alignment: .leading)
            }
        }
        .frame(width: 564, alignment: .center)
    }
    
    // MARK: - 快捷键设置 (Apple 偏好设置经典居中排版：左列右对齐标签，右列左对齐控件)
    @ViewBuilder
    private var shortcutsSection: some View {
        let labelWidth: CGFloat = 170
        let controlWidth: CGFloat = 240
        let rightColumnWidth: CGFloat = 380
        
        VStack(spacing: 22) {
            // 1. 全局呼出快捷键
            HStack(alignment: .top, spacing: 14) {
                Text(loc("shortcut_summon_label"))
                    .font(.system(size: 13))
                    .foregroundColor(.primary)
                    .frame(width: labelWidth, alignment: .trailing)
                    .padding(.top, 4)
                
                VStack(alignment: .leading, spacing: 5) {
                    Picker("", selection: Binding(
                        get: { hotKeyManager.currentShortcut },
                        set: { hotKeyManager.register(shortcut: $0) }
                    )) {
                        ForEach(AppShortcut.presets) { preset in
                            Text(preset.name).tag(preset)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(width: controlWidth, alignment: .leading)
                    
                    Text(loc("shortcut_summon_desc"))
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(width: rightColumnWidth, alignment: .leading)
            }
            
            // 2. 划词翻译快捷键
            HStack(alignment: .top, spacing: 14) {
                Text(loc("shortcut_selection_label"))
                    .font(.system(size: 13))
                    .foregroundColor(.primary)
                    .frame(width: labelWidth, alignment: .trailing)
                    .padding(.top, 4)
                
                VStack(alignment: .leading, spacing: 5) {
                    Picker("", selection: Binding(
                        get: { hotKeyManager.currentSelectionShortcut },
                        set: { hotKeyManager.registerSelectionShortcut(shortcut: $0) }
                    )) {
                        ForEach(AppShortcut.presets) { preset in
                            Text(preset.name).tag(preset)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(width: controlWidth, alignment: .leading)
                    
                    Text(loc("shortcut_selection_desc"))
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    
                    // 权限状态徽标
                    HStack(spacing: 5) {
                        Circle()
                            .fill(selectionManager.isAccessibilityTrusted ? Color.green : Color.orange)
                            .frame(width: 6, height: 6)
                        
                        Text(selectionManager.isAccessibilityTrusted ? loc("accessibility_ready") : loc("accessibility_needed"))
                            .font(.system(size: 11))
                            .foregroundColor(selectionManager.isAccessibilityTrusted ? .secondary : .orange)
                        
                        if !selectionManager.isAccessibilityTrusted {
                            Button(loc("btn_authorize")) {
                                selectionManager.requestAccessibilityPermission()
                            }
                            .buttonStyle(.link)
                            .font(.system(size: 11))
                        }
                    }
                    .padding(.top, 2)
                }
                .frame(width: rightColumnWidth, alignment: .leading)
            }
            
            // 3. 截图 OCR 快捷键
            HStack(alignment: .top, spacing: 14) {
                Text(loc("shortcut_ocr_label"))
                    .font(.system(size: 13))
                    .foregroundColor(.primary)
                    .frame(width: labelWidth, alignment: .trailing)
                    .padding(.top, 4)
                
                VStack(alignment: .leading, spacing: 5) {
                    Picker("", selection: Binding(
                        get: { hotKeyManager.currentOcrShortcut },
                        set: { hotKeyManager.registerOcrShortcut(shortcut: $0) }
                    )) {
                        ForEach(AppShortcut.presets) { preset in
                            Text(preset.name).tag(preset)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(width: controlWidth, alignment: .leading)
                    
                    Text(loc("shortcut_ocr_desc"))
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(width: rightColumnWidth, alignment: .leading)
            }
            
            // 组间留白
            Spacer().frame(height: 8)
            
            // 底部操作与提示说明 (贴合 Safari 截图 2 下方细则排版)
            HStack(alignment: .top, spacing: 14) {
                Text(loc("shortcut_tips_header"))
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .frame(width: labelWidth, alignment: .trailing)
                
                VStack(alignment: .leading, spacing: 6) {
                    Text(loc("shortcut_tip_1"))
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    Text(loc("shortcut_tip_2"))
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    Text(loc("shortcut_tip_3"))
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                .frame(width: rightColumnWidth, alignment: .leading)
            }
        }
        .frame(width: 564, alignment: .center)
    }
    
    // MARK: - 2. 翻译服务 (类似 Safari Preferences 的 Master-Detail 排版)
    @ViewBuilder
    private var translationMasterDetailSection: some View {
        HStack(spacing: 16) {
            // 左侧服务商列表 (Master)
            VStack(alignment: .leading, spacing: 6) {
                Text(loc("provider_list_title"))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.top, 4)
                
                ScrollView {
                    VStack(spacing: 3) {
                        ForEach(TranslationProvider.allCases) { provider in
                            let isSelectedForEdit = selectedProviderForEdit == provider
                            let isDefault = translationService.currentProvider == provider
                            
                            Button {
                                selectedProviderForEdit = provider
                                testSuccess = nil
                                testMessage = ""
                            } label: {
                                HStack(spacing: 9) {
                                    // 品牌小图标（无底色，无多余边距，25%圆角完整显示）
                                    ProviderIconView(provider: provider, size: 24, isSelected: isSelectedForEdit)
                                    
                                    // 标题
                                    Text(provider.title)
                                        .font(.system(size: 13, weight: isSelectedForEdit ? .semibold : .medium))
                                        .foregroundColor(isSelectedForEdit ? .white : .primary)
                                        .lineLimit(1)
                                    
                                    Spacer(minLength: 4)
                                    
                                    // 状态/默认标记
                                    if isDefault {
                                        Image(systemName: "checkmark.circle.fill")
                                            .font(.system(size: 12, weight: .semibold))
                                            .foregroundColor(isSelectedForEdit ? .white : .green)
                                    } else if !provider.requiresConfig {
                                        Text(loc("badge_free_config"))
                                            .font(.system(size: 9))
                                            .foregroundColor(isSelectedForEdit ? .white.opacity(0.85) : .secondary)
                                    } else if !provider.isConfigured {
                                        Circle()
                                            .fill(isSelectedForEdit ? Color.white.opacity(0.7) : Color.orange)
                                            .frame(width: 5, height: 5)
                                    }
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 7)
                                .background(
                                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                                        .fill(isSelectedForEdit ? Color.accentColor : Color.clear)
                                )
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(8)
            .frame(width: 200)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color(NSColor.controlBackgroundColor).opacity(0.5))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color.gray.opacity(0.16), lineWidth: 1)
            )
            
            // 右侧详情编辑区 (Detail Editor)
            VStack(alignment: .leading, spacing: 0) {
                ScrollView {
                    providerDetailEditor(selectedProviderForEdit)
                        .padding(20)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color(NSColor.controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color.gray.opacity(0.18), lineWidth: 1)
            )
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }
    
    // MARK: - 右侧服务商详情编辑器
    @ViewBuilder
    private func providerDetailEditor(_ provider: TranslationProvider) -> some View {
        let isDefault = translationService.currentProvider == provider
        
        VStack(alignment: .leading, spacing: 16) {
            // 顶栏：图标、标题、副标题与设为默认按钮
            HStack(spacing: 12) {
                ProviderIconView(provider: provider, size: 38)
                
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(provider.title)
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.primary)
                        
                        if !provider.requiresConfig {
                            Text(loc("badge_free_ready"))
                                .font(.system(size: 10, weight: .medium))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(Color.blue.opacity(0.12)))
                                .foregroundColor(.blue)
                        } else if provider.isConfigured {
                            HStack(spacing: 3) {
                                Circle().fill(Color.green).frame(width: 5, height: 5)
                                Text(loc("badge_ready"))
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundColor(.green)
                            }
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.green.opacity(0.12)))
                        } else {
                            HStack(spacing: 3) {
                                Circle().fill(Color.orange).frame(width: 5, height: 5)
                                Text(loc("badge_need_config"))
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundColor(.orange)
                            }
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.orange.opacity(0.12)))
                        }
                    }
                    
                    Text(provider.subtitle)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                // 设为默认引擎
                if isDefault {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                            .font(.system(size: 13))
                        Text(loc("default_engine_active"))
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.green)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(Color.green.opacity(0.12)))
                } else {
                    Button(loc("btn_set_default")) {
                        selectedProvider = provider.rawValue
                        translationService.setProvider(provider)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.regular)
                }
            }
            
            Divider()
            
            // 核心输入表单
            switch provider {
            case .system:
                systemDetailForm
            case .google:
                googleDetailForm
            case .deepl:
                deeplDetailForm
            case .microsoft:
                microsoftDetailForm
            case .baidu:
                baiduDetailForm
            case .alibaba:
                alibabaDetailForm
            case .volcengine:
                volcengineDetailForm
            }
            
            Divider()
            
            // 动作按钮栏 (测试连接、保存、前往官网)
            HStack(spacing: 12) {
                Button {
                    testCurrentProvider(provider)
                } label: {
                    HStack(spacing: 5) {
                        if isTesting {
                            ProgressView()
                                .controlSize(.small)
                        }
                        Text(isTesting ? loc("btn_testing") : loc("btn_test_conn"))
                    }
                }
                .disabled(isTesting)
                
                if provider != .system {
                    Button(loc("btn_save_config")) {
                        saveCurrentProvider(provider)
                    }
                    .buttonStyle(.borderedProminent)
                    
                    if showSavedAlert {
                        Text(loc("alert_saved"))
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.green)
                            .transition(.opacity)
                    }
                }
                
                Spacer()
                
                if provider != .system {
                    Button(loc("btn_get_key_website")) {
                        openPortalForProvider(provider)
                    }
                    .buttonStyle(.link)
                    .font(.system(size: 12))
                }
            }
            
            // 测试结果反馈面板
            if let success = testSuccess {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: success ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundColor(success ? .green : .red)
                        .padding(.top, 1)
                    Text(testMessage)
                        .font(.system(size: 12))
                        .foregroundColor(success ? .green : .red)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(success ? Color.green.opacity(0.08) : Color.red.opacity(0.08))
                )
            }
        }
    }
    
    @ViewBuilder
    private var systemDetailForm: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(loc("system_form_title"), systemImage: "internaldrive")
                .font(.system(size: 13, weight: .semibold))
            Text(loc("system_form_desc"))
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .lineSpacing(3)
            
            HStack(spacing: 8) {
                Image(systemName: "checkmark.shield.fill")
                    .foregroundColor(.green)
                    .font(.system(size: 14))
                Text(loc("system_form_features"))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.secondary)
            }
            .padding(.top, 4)
        }
    }
    
    // MARK: - 各引擎二级页面的输入表单
    @ViewBuilder
    private var googleDetailForm: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(loc("google_form_mode_title"))
                    .font(.system(size: 13, weight: .semibold))
                Text(loc("google_form_mode_desc"))
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .lineSpacing(3)
            }
            
            VStack(alignment: .leading, spacing: 6) {
                Text(loc("google_form_key_label"))
                    .font(.system(size: 12, weight: .medium))
                
                HStack(spacing: 8) {
                    if isGoogleKeyVisible {
                        TextField(loc("google_form_placeholder"), text: $inputGoogleKey)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 12, design: .monospaced))
                    } else {
                        SecureField(loc("google_form_placeholder"), text: $inputGoogleKey)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 12, design: .monospaced))
                    }
                    
                    Button {
                        isGoogleKeyVisible.toggle()
                    } label: {
                        Image(systemName: isGoogleKeyVisible ? "eye.slash" : "eye")
                    }
                    .help(isGoogleKeyVisible ? loc("btn_hide_key") : loc("btn_show_key"))
                    
                    Button {
                        if let paste = NSPasteboard.general.string(forType: .string) {
                            inputGoogleKey = paste.trimmingCharacters(in: .whitespacesAndNewlines)
                        }
                    } label: {
                        Image(systemName: "doc.on.clipboard")
                    }
                    .help(loc("btn_paste_clipboard"))
                }
            }
        }
    }
    
    @ViewBuilder
    private var deeplDetailForm: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(loc("deepl_form_title"))
                    .font(.system(size: 13, weight: .semibold))
                Text(loc("deepl_form_desc"))
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
            
            VStack(alignment: .leading, spacing: 6) {
                Text(loc("deepl_form_key_label"))
                    .font(.system(size: 12, weight: .medium))
                
                HStack(spacing: 8) {
                    if isDeepLKeyVisible {
                        TextField(loc("deepl_form_placeholder"), text: $inputDeepLKey)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 12, design: .monospaced))
                    } else {
                        SecureField(loc("deepl_form_placeholder"), text: $inputDeepLKey)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 12, design: .monospaced))
                    }
                    
                    Button {
                        isDeepLKeyVisible.toggle()
                    } label: {
                        Image(systemName: isDeepLKeyVisible ? "eye.slash" : "eye")
                    }
                    .help(isDeepLKeyVisible ? loc("btn_hide_key") : loc("btn_show_key"))
                    
                    Button {
                        if let paste = NSPasteboard.general.string(forType: .string) {
                            inputDeepLKey = paste.trimmingCharacters(in: .whitespacesAndNewlines)
                        }
                    } label: {
                        Image(systemName: "doc.on.clipboard")
                    }
                    .help(loc("btn_paste_clipboard"))
                }
            }
        }
    }
    
    @ViewBuilder
    private var microsoftDetailForm: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(loc("ms_trans_form_title"))
                    .font(.system(size: 13, weight: .semibold))
                Text(loc("ms_trans_form_desc"))
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
            
            VStack(alignment: .leading, spacing: 6) {
                Text(loc("api_key_subscription"))
                    .font(.system(size: 12, weight: .medium))
                
                HStack(spacing: 8) {
                    if isMsTransKeyVisible {
                        TextField(loc("ms_trans_placeholder"), text: $inputMsTransKey)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 12, design: .monospaced))
                    } else {
                        SecureField(loc("ms_trans_placeholder"), text: $inputMsTransKey)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 12, design: .monospaced))
                    }
                    
                    Button {
                        isMsTransKeyVisible.toggle()
                    } label: {
                        Image(systemName: isMsTransKeyVisible ? "eye.slash" : "eye")
                    }
                    .help(isMsTransKeyVisible ? loc("btn_hide_key") : loc("btn_show_key"))
                    
                    Button {
                        if let paste = NSPasteboard.general.string(forType: .string) {
                            inputMsTransKey = paste.trimmingCharacters(in: .whitespacesAndNewlines)
                        }
                    } label: {
                        Image(systemName: "doc.on.clipboard")
                    }
                    .help(loc("btn_paste_clipboard"))
                }
            }
            
            VStack(alignment: .leading, spacing: 6) {
                Text(loc("region_label"))
                    .font(.system(size: 12, weight: .medium))
                TextField(loc("ms_trans_region_placeholder"), text: $inputMsTransRegion)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12, design: .monospaced))
            }
        }
    }
    
    @ViewBuilder
    private var baiduDetailForm: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(loc("baidu_form_title"))
                    .font(.system(size: 13, weight: .semibold))
                Text(loc("baidu_form_desc"))
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
            
            VStack(alignment: .leading, spacing: 6) {
                Text(loc("baidu_appid_label"))
                    .font(.system(size: 12, weight: .medium))
                
                HStack(spacing: 8) {
                    TextField(loc("baidu_appid_placeholder"), text: $inputBaiduAppId)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12, design: .monospaced))
                    
                    Button {
                        if let paste = NSPasteboard.general.string(forType: .string) {
                            inputBaiduAppId = paste.trimmingCharacters(in: .whitespacesAndNewlines)
                        }
                    } label: {
                        Image(systemName: "doc.on.clipboard")
                    }
                    .help(loc("btn_paste_clipboard"))
                }
            }
            
            VStack(alignment: .leading, spacing: 6) {
                Text(loc("secret_key_label"))
                    .font(.system(size: 12, weight: .medium))
                
                HStack(spacing: 8) {
                    if isBaiduKeyVisible {
                        TextField(loc("baidu_secret_placeholder"), text: $inputBaiduSecretKey)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 12, design: .monospaced))
                    } else {
                        SecureField(loc("baidu_secret_placeholder"), text: $inputBaiduSecretKey)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 12, design: .monospaced))
                    }
                    
                    Button {
                        isBaiduKeyVisible.toggle()
                    } label: {
                        Image(systemName: isBaiduKeyVisible ? "eye.slash" : "eye")
                    }
                    .help(isBaiduKeyVisible ? loc("btn_hide_key") : loc("btn_show_key"))
                    
                    Button {
                        if let paste = NSPasteboard.general.string(forType: .string) {
                            inputBaiduSecretKey = paste.trimmingCharacters(in: .whitespacesAndNewlines)
                        }
                    } label: {
                        Image(systemName: "doc.on.clipboard")
                    }
                    .help(loc("btn_paste_clipboard"))
                }
            }
        }
    }
    
    @ViewBuilder
    private var alibabaDetailForm: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(loc("alibaba_form_title"))
                    .font(.system(size: 13, weight: .semibold))
                Text(loc("alibaba_form_desc"))
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
            
            VStack(alignment: .leading, spacing: 6) {
                Text("AccessKey ID")
                    .font(.system(size: 12, weight: .medium))
                
                HStack(spacing: 8) {
                    TextField("LTAI...", text: $inputAlibabaKeyId)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12, design: .monospaced))
                    
                    Button {
                        if let paste = NSPasteboard.general.string(forType: .string) {
                            inputAlibabaKeyId = paste.trimmingCharacters(in: .whitespacesAndNewlines)
                        }
                    } label: {
                        Image(systemName: "doc.on.clipboard")
                    }
                    .help(loc("btn_paste_clipboard"))
                }
            }
            
            VStack(alignment: .leading, spacing: 6) {
                Text("AccessKey Secret")
                    .font(.system(size: 12, weight: .medium))
                
                HStack(spacing: 8) {
                    if isAlibabaKeyVisible {
                        TextField(loc("alibaba_secret_placeholder"), text: $inputAlibabaKeySecret)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 12, design: .monospaced))
                    } else {
                        SecureField(loc("alibaba_secret_placeholder"), text: $inputAlibabaKeySecret)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 12, design: .monospaced))
                    }
                    
                    Button {
                        isAlibabaKeyVisible.toggle()
                    } label: {
                        Image(systemName: isAlibabaKeyVisible ? "eye.slash" : "eye")
                    }
                    .help(isAlibabaKeyVisible ? loc("btn_hide_key") : loc("btn_show_key"))
                    
                    Button {
                        if let paste = NSPasteboard.general.string(forType: .string) {
                            inputAlibabaKeySecret = paste.trimmingCharacters(in: .whitespacesAndNewlines)
                        }
                    } label: {
                        Image(systemName: "doc.on.clipboard")
                    }
                    .help(loc("btn_paste_clipboard"))
                }
            }
        }
    }
    
    @ViewBuilder
    private var volcengineDetailForm: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(loc("volcengine_form_title"))
                    .font(.system(size: 13, weight: .semibold))
                Text(loc("volcengine_form_desc"))
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
            
            VStack(alignment: .leading, spacing: 6) {
                Text("AccessKey ID (AK)")
                    .font(.system(size: 12, weight: .medium))
                
                HStack(spacing: 8) {
                    TextField("AKLT...", text: $inputAK)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12, design: .monospaced))
                    
                    Button {
                        if let paste = NSPasteboard.general.string(forType: .string) {
                            inputAK = paste.trimmingCharacters(in: .whitespacesAndNewlines)
                        }
                    } label: {
                        Image(systemName: "doc.on.clipboard")
                    }
                    .help(loc("btn_paste_clipboard"))
                }
            }
            
            VStack(alignment: .leading, spacing: 6) {
                Text("Secret Access Key (SK)")
                    .font(.system(size: 12, weight: .medium))
                
                HStack(spacing: 8) {
                    if isSKVisible {
                        TextField(loc("volcengine_secret_placeholder"), text: $inputSK)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 12, design: .monospaced))
                    } else {
                        SecureField(loc("volcengine_secret_placeholder"), text: $inputSK)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 12, design: .monospaced))
                    }
                    
                    Button {
                        isSKVisible.toggle()
                    } label: {
                        Image(systemName: isSKVisible ? "eye.slash" : "eye")
                    }
                    .help(isSKVisible ? loc("btn_hide_key") : loc("btn_show_key"))
                    
                    Button {
                        if let paste = NSPasteboard.general.string(forType: .string) {
                            inputSK = paste.trimmingCharacters(in: .whitespacesAndNewlines)
                        }
                    } label: {
                        Image(systemName: "doc.on.clipboard")
                    }
                    .help(loc("btn_paste_clipboard"))
                }
            }
        }
    }
    
    // MARK: - 3. 语音合成 (Master-Detail 排版，与翻译服务保持一致)
    @ViewBuilder
    private var speechMasterDetailSection: some View {
        HStack(spacing: 16) {
            // 左侧语音引擎列表 (Master)
            VStack(alignment: .leading, spacing: 6) {
                Text(loc("speech_list_title"))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.top, 4)
                
                ScrollView {
                    VStack(spacing: 3) {
                        ForEach(SpeechProvider.allCases) { provider in
                            let isSelectedForEdit = selectedSpeechProviderForEdit == provider
                            let isDefault = speechManager.currentProvider == provider
                            
                            Button {
                                selectedSpeechProviderForEdit = provider
                                msTestSuccess = nil
                                msTestMessage = ""
                            } label: {
                                HStack(spacing: 9) {
                                    // 品牌小图标（无底色，无多余边距，25%圆角完整显示）
                                    SpeechProviderIconView(provider: provider, size: 24, isSelected: isSelectedForEdit)
                                    
                                    // 标题
                                    Text(provider.title)
                                        .font(.system(size: 13, weight: isSelectedForEdit ? .semibold : .medium))
                                        .foregroundColor(isSelectedForEdit ? .white : .primary)
                                        .lineLimit(1)
                                    
                                    Spacer(minLength: 4)
                                    
                                    // 状态/默认标记
                                    if isDefault {
                                        Image(systemName: "checkmark.circle.fill")
                                            .font(.system(size: 12, weight: .semibold))
                                            .foregroundColor(isSelectedForEdit ? .white : .green)
                                    } else if !provider.requiresConfig {
                                        Text(loc("badge_free_config"))
                                            .font(.system(size: 9))
                                            .foregroundColor(isSelectedForEdit ? .white.opacity(0.85) : .secondary)
                                    } else if !provider.isConfigured {
                                        Circle()
                                            .fill(isSelectedForEdit ? Color.white.opacity(0.7) : Color.orange)
                                            .frame(width: 5, height: 5)
                                    }
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 7)
                                .background(
                                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                                        .fill(isSelectedForEdit ? Color.accentColor : Color.clear)
                                )
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(8)
            .frame(width: 200)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color(NSColor.controlBackgroundColor).opacity(0.5))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color.gray.opacity(0.16), lineWidth: 1)
            )
            
            // 右侧详情编辑区 (Detail Editor)
            VStack(alignment: .leading, spacing: 0) {
                ScrollView {
                    speechDetailEditor(selectedSpeechProviderForEdit)
                        .padding(20)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color(NSColor.controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color.gray.opacity(0.18), lineWidth: 1)
            )
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }
    
    // MARK: - 右侧语音引擎详情编辑器
    @ViewBuilder
    private func speechDetailEditor(_ provider: SpeechProvider) -> some View {
        let isDefault = speechManager.currentProvider == provider
        
        VStack(alignment: .leading, spacing: 16) {
            // 顶栏：图标、标题、副标题与设为默认按钮
            HStack(spacing: 12) {
                SpeechProviderIconView(provider: provider, size: 38)
                
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(provider.title)
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.primary)
                        
                        if !provider.requiresConfig {
                            Text(loc("badge_free_ready"))
                                .font(.system(size: 10, weight: .medium))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(Color.blue.opacity(0.12)))
                                .foregroundColor(.blue)
                        } else if provider.isConfigured {
                            HStack(spacing: 3) {
                                Circle().fill(Color.green).frame(width: 5, height: 5)
                                Text(loc("badge_ready"))
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundColor(.green)
                            }
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.green.opacity(0.12)))
                        } else {
                            HStack(spacing: 3) {
                                Circle().fill(Color.orange).frame(width: 5, height: 5)
                                Text(loc("badge_need_config"))
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundColor(.orange)
                            }
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.orange.opacity(0.12)))
                        }
                    }
                    
                    Text(provider.subtitle)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                // 设为默认引擎
                if isDefault {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                            .font(.system(size: 13))
                        Text(loc("default_engine_active"))
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.green)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(Color.green.opacity(0.12)))
                } else {
                    Button(loc("btn_set_default")) {
                        speechManager.setProvider(provider)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.regular)
                }
            }
            
            Divider()
            
            // 引擎对应配置与试听
            switch provider {
            case .system:
                systemSpeechEditor
            case .google:
                googleSpeechEditor
            case .microsoft:
                microsoftSpeechEditor
            }
        }
    }
    
    // MARK: - Apple 原生语音配置与试听
    @ViewBuilder
    private var systemSpeechEditor: some View {
        VStack(spacing: 0) {
            Divider()
            
            HStack {
                Text(loc("speed_rate"))
                    .font(.system(size: 13))
                
                Spacer()
                
                Picker("", selection: Binding(
                    get: { speechManager.speechRate },
                    set: { speechManager.setRate($0) }
                )) {
                    ForEach(SpeedRateOption.options) { opt in
                        Text(opt.label).tag(opt.rate)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 85)
            }
            .padding(.vertical, 8)
            
            Divider()
            
            HStack {
                Text(loc("voice_choose_label"))
                    .font(.system(size: 13))
                
                Spacer()
                
                Button(loc("btn_configure_voice")) {
                    voiceSheetProvider = .system
                    showVoiceSettingsSheet = true
                }
                .controlSize(.regular)
            }
            .padding(.vertical, 8)
            
            Divider()
        }
    }
    
    // MARK: - Google 语音配置与试听
    @ViewBuilder
    private var googleSpeechEditor: some View {
        VStack(alignment: .leading, spacing: 14) {
            // 说明横幅：免费模式与可选 Cloud TTS
            VStack(alignment: .leading, spacing: 6) {
                Text(loc("google_speech_mode_title"))
                    .font(.system(size: 13, weight: .semibold))
                Text(loc("google_speech_mode_desc"))
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .lineSpacing(2)
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.blue.opacity(0.06)))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.blue.opacity(0.18), lineWidth: 1))
            
            // 选填的 Google Cloud Text-to-Speech API Key
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(loc("google_speech_key_label"))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.secondary)
                    
                    Spacer()
                    
                    if !inputGoogleSpeechKey.isEmpty {
                        Button(loc("btn_clear")) {
                            inputGoogleSpeechKey = ""
                        }
                        .buttonStyle(.link)
                        .font(.system(size: 11))
                    }
                }
                
                HStack {
                    if isGoogleSpeechKeyVisible {
                        TextField(loc("google_speech_placeholder"), text: $inputGoogleSpeechKey)
                            .textFieldStyle(.plain)
                    } else {
                        SecureField(loc("google_speech_placeholder"), text: $inputGoogleSpeechKey)
                            .textFieldStyle(.plain)
                    }
                    
                    Button {
                        isGoogleSpeechKeyVisible.toggle()
                    } label: {
                        Image(systemName: isGoogleSpeechKeyVisible ? "eye.slash" : "eye")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    
                    Button {
                        if let clip = NSPasteboard.general.string(forType: .string) {
                            inputGoogleSpeechKey = clip.trimmingCharacters(in: .whitespacesAndNewlines)
                        }
                    } label: {
                        Image(systemName: "doc.on.clipboard")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help(loc("btn_paste_clipboard"))
                }
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color(NSColor.textBackgroundColor)))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.gray.opacity(0.2), lineWidth: 1))
            }
            
            // 动作按钮栏：测试发音、保存、前往控制台
            HStack(spacing: 12) {
                Button {
                    testGoogleSpeech()
                } label: {
                    HStack(spacing: 4) {
                        if isGoogleSpeechTesting {
                            ProgressView()
                                .controlSize(.small)
                        }
                        Text(isGoogleSpeechTesting ? loc("btn_testing") : loc("btn_test_conn"))
                    }
                }
                .disabled(isGoogleSpeechTesting)
                
                Button(loc("btn_save_config")) {
                    saveGoogleSpeechKeys()
                }
                .buttonStyle(.borderedProminent)
                
                if showGoogleSpeechSavedAlert {
                    Text(loc("alert_saved"))
                        .font(.system(size: 12))
                        .foregroundColor(.green)
                        .transition(.opacity)
                }
                
                Spacer()
                
                Button(loc("btn_get_google_key")) {
                    if let url = URL(string: "https://console.cloud.google.com/apis/credentials") {
                        NSWorkspace.shared.open(url)
                    }
                }
                .buttonStyle(.link)
                .font(.system(size: 12))
            }
            
            if let success = googleSpeechTestSuccess {
                HStack(spacing: 8) {
                    Image(systemName: success ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundColor(success ? .green : .red)
                    Text(googleSpeechTestMessage)
                        .font(.system(size: 12))
                        .foregroundColor(success ? .green : .red)
                }
                .padding(.top, 4)
            }
            
            // 语速设置行（统一简洁样式）
            VStack(spacing: 0) {
                Divider()
                
                HStack {
                    Text(loc("speed_rate"))
                        .font(.system(size: 13))
                    
                    Spacer()
                    
                    Picker("", selection: Binding(
                        get: { speechManager.speechRate },
                        set: { speechManager.setRate($0) }
                    )) {
                        ForEach(SpeedRateOption.options) { opt in
                            Text(opt.label).tag(opt.rate)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(width: 85)
                }
                .padding(.vertical, 8)
                
                Divider()
            }
        }
    }
    
    // MARK: - 微软 Azure 语音配置与试听
    @ViewBuilder
    private var microsoftSpeechEditor: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Subscription Key
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(loc("api_key_subscription"))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.secondary)
                    
                    Spacer()
                    
                    if !inputMsKey.isEmpty {
                        Button(loc("btn_clear")) {
                            inputMsKey = ""
                        }
                        .buttonStyle(.link)
                        .font(.system(size: 11))
                    }
                }
                
                HStack {
                    if isMsKeyVisible {
                        TextField(loc("ms_speech_key_placeholder"), text: $inputMsKey)
                            .textFieldStyle(.plain)
                    } else {
                        SecureField(loc("ms_speech_key_placeholder"), text: $inputMsKey)
                            .textFieldStyle(.plain)
                    }
                    
                    Button {
                        isMsKeyVisible.toggle()
                    } label: {
                        Image(systemName: isMsKeyVisible ? "eye.slash" : "eye")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    
                    Button {
                        if let clip = NSPasteboard.general.string(forType: .string) {
                            inputMsKey = clip.trimmingCharacters(in: .whitespacesAndNewlines)
                        }
                    } label: {
                        Image(systemName: "doc.on.clipboard")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help(loc("btn_paste_clipboard"))
                }
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color(NSColor.textBackgroundColor)))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.gray.opacity(0.2), lineWidth: 1))
            }
            
            // Region Selection
            VStack(alignment: .leading, spacing: 6) {
                Text(loc("region_label"))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.secondary)
                
                HStack(spacing: 12) {
                    Picker(loc("preset_region"), selection: $inputMsRegion) {
                        ForEach(MicrosoftSpeechConfig.regionPresets, id: \.id) { preset in
                            Text(preset.name).tag(preset.id)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(width: 250)
                    
                    TextField(loc("manual_region_placeholder"), text: $inputMsRegion)
                        .textFieldStyle(.roundedBorder)
                }
            }
            
            // 测试连接与保存按钮
            HStack(spacing: 12) {
                Button {
                    testMicrosoftSpeech()
                } label: {
                    HStack(spacing: 4) {
                        if isMsTesting {
                            ProgressView()
                                .controlSize(.small)
                        }
                        Text(isMsTesting ? loc("btn_testing") : loc("btn_test_conn"))
                    }
                }
                .disabled(inputMsKey.isEmpty || inputMsRegion.isEmpty || isMsTesting)
                
                Button(loc("btn_save_config")) {
                    saveMicrosoftSpeechKeys()
                }
                .buttonStyle(.borderedProminent)
                .disabled(inputMsKey.isEmpty || inputMsRegion.isEmpty)
                
                if showMsSavedAlert {
                    Text(loc("alert_saved"))
                        .font(.system(size: 12))
                        .foregroundColor(.green)
                        .transition(.opacity)
                }
                
                Spacer()
                
                Button(loc("btn_get_azure_key")) {
                    if let url = URL(string: "https://portal.azure.com/") {
                        NSWorkspace.shared.open(url)
                    }
                }
                .buttonStyle(.link)
                .font(.system(size: 12))
            }
            
            if let success = msTestSuccess {
                HStack(spacing: 8) {
                    Image(systemName: success ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundColor(success ? .green : .red)
                    Text(msTestMessage)
                        .font(.system(size: 12))
                        .foregroundColor(success ? .green : .red)
                }
                .padding(.top, 4)
            }
            
            // 语速与声音设置行（统一简洁样式）
            VStack(spacing: 0) {
                Divider()
                
                HStack {
                    Text(loc("speed_rate"))
                        .font(.system(size: 13))
                    
                    Spacer()
                    
                    Picker("", selection: Binding(
                        get: { speechManager.speechRate },
                        set: { speechManager.setRate($0) }
                    )) {
                        ForEach(SpeedRateOption.options) { opt in
                            Text(opt.label).tag(opt.rate)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(width: 85)
                }
                .padding(.vertical, 8)
                
                Divider()
                
                HStack {
                    Text(loc("voice_choose_label"))
                        .font(.system(size: 13))
                    
                    Spacer()
                    
                    Button(loc("btn_configure_voice")) {
                        voiceSheetProvider = .microsoft
                        showVoiceSettingsSheet = true
                    }
                    .controlSize(.regular)
                }
                .padding(.vertical, 8)
                
                Divider()
            }
            .padding(.top, 4)
        }
    }
    
    // MARK: - 4. 关于软件 (Apple 偏好设置经典居中排版与精简文案)
    private var aboutSection: some View {
        VStack(spacing: 26) {
            // 1. App 图标与应用标题
            VStack(spacing: 12) {
                if let appIcon = NSImage(named: "AppIcon") ?? NSImage(named: "NSApplicationIcon") ?? NSApplication.shared.applicationIconImage {
                    Image(nsImage: appIcon)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 76, height: 76)
                        .shadow(color: Color.black.opacity(isDark ? 0.45 : 0.16), radius: 10, y: 5)
                } else {
                    ZStack {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [Color.blue, Color.indigo],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 76, height: 76)
                            .shadow(color: Color.blue.opacity(0.35), radius: 12, y: 5)
                        
                        Image(systemName: "character.bubble")
                            .font(.system(size: 36))
                            .foregroundColor(.white)
                    }
                }
                
                VStack(spacing: 4) {
                    Text(loc("about_app_name"))
                        .font(.system(size: 22, weight: .bold))
                        .foregroundColor(.primary)
                    
                    Text(loc("about_version_format", "1.0.0", "1"))
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                }
                
                Text(loc("about_tagline"))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.secondary)
                    .padding(.top, 2)
            }
            
            // 3. 快捷动作按钮
            HStack(spacing: 12) {
                Button {
                    if let url = URL(string: "https://github.com/maple-im/slate") {
                        NSWorkspace.shared.open(url)
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "link")
                            .font(.system(size: 11))
                        Text(loc("about_github"))
                            .font(.system(size: 12, weight: .medium))
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
                
                Button {
                    if let url = URL(string: "https://github.com/maple-im/slate/releases") {
                        NSWorkspace.shared.open(url)
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.system(size: 11))
                        Text(loc("about_check_updates"))
                            .font(.system(size: 12, weight: .medium))
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
            }
            .padding(.top, 4)
            
            // 4. 底部版权与设计声明
            VStack(spacing: 4) {
                Text("Designed for Maple")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary.opacity(0.8))
                
                Text("© 2026 Slate. All rights reserved.")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary.opacity(0.6))
            }
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }
    
    @ViewBuilder
    private func aboutFeatureCard(icon: String, title: String, desc: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundColor(.accentColor)
                .frame(width: 22, height: 22)
                .padding(.top, 2)
            
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.primary)
                Text(desc)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .lineLimit(2)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(NSColor.controlBackgroundColor).opacity(0.6))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.secondary.opacity(0.12), lineWidth: 0.75)
        )
    }
    
    // MARK: - 翻译连接测试与保存
    private func testCurrentProvider(_ provider: TranslationProvider) {
        isTesting = true
        testSuccess = nil
        testMessage = ""
        
        Task {
            do {
                switch provider {
                case .system:
                    await MainActor.run {
                        self.isTesting = false
                        self.testSuccess = true
                        self.testMessage = loc("test_msg_system")
                    }
                case .google:
                    _ = try await GoogleTranslator.testConnection(apiKey: inputGoogleKey)
                    await MainActor.run {
                        self.isTesting = false
                        self.testSuccess = true
                        self.testMessage = loc("test_msg_success", provider.title)
                    }
                case .deepl:
                    _ = try await DeepLTranslator.testConnection(authKey: inputDeepLKey)
                    await MainActor.run {
                        self.isTesting = false
                        self.testSuccess = true
                        self.testMessage = loc("test_msg_success", provider.title)
                    }
                case .microsoft:
                    _ = try await MicrosoftTranslator.testConnection(apiKey: inputMsTransKey, region: inputMsTransRegion)
                    await MainActor.run {
                        self.isTesting = false
                        self.testSuccess = true
                        self.testMessage = loc("test_msg_success", provider.title)
                    }
                case .baidu:
                    _ = try await BaiduTranslator.testConnection(appId: inputBaiduAppId, secretKey: inputBaiduSecretKey)
                    await MainActor.run {
                        self.isTesting = false
                        self.testSuccess = true
                        self.testMessage = loc("test_msg_success", provider.title)
                    }
                case .alibaba:
                    _ = try await AlibabaTranslator.testConnection(accessKeyId: inputAlibabaKeyId, accessKeySecret: inputAlibabaKeySecret)
                    await MainActor.run {
                        self.isTesting = false
                        self.testSuccess = true
                        self.testMessage = loc("test_msg_success", provider.title)
                    }
                case .volcengine:
                    _ = try await VolcengineTranslator.testConnection(accessKey: inputAK, secretKey: inputSK)
                    await MainActor.run {
                        self.isTesting = false
                        self.testSuccess = true
                        self.testMessage = loc("test_msg_success", provider.title)
                    }
                }
            } catch {
                await MainActor.run {
                    self.isTesting = false
                    self.testSuccess = false
                    self.testMessage = error.localizedDescription
                }
            }
        }
    }
    
    private func saveCurrentProvider(_ provider: TranslationProvider) {
        switch provider {
        case .system:
            break
        case .google:
            googleConfig.save(apiKey: inputGoogleKey)
        case .deepl:
            deeplConfig.save(authKey: inputDeepLKey)
        case .microsoft:
            msTransConfig.save(apiKey: inputMsTransKey, region: inputMsTransRegion)
        case .baidu:
            baiduConfig.save(appId: inputBaiduAppId, secretKey: inputBaiduSecretKey)
        case .alibaba:
            alibabaConfig.save(accessKeyId: inputAlibabaKeyId, accessKeySecret: inputAlibabaKeySecret)
        case .volcengine:
            volcConfig.save(accessKey: inputAK, secretKey: inputSK)
        }
        
        withAnimation {
            showSavedAlert = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation {
                showSavedAlert = false
            }
        }
    }
    
    private func openPortalForProvider(_ provider: TranslationProvider) {
        let urlString: String
        switch provider {
        case .system:
            return
        case .google:
            urlString = "https://console.cloud.google.com/apis/credentials"
        case .deepl:
            urlString = "https://www.deepl.com/your-account/keys"
        case .microsoft:
            urlString = "https://portal.azure.com/"
        case .baidu:
            urlString = "https://fanyi-api.baidu.com/manage/developer"
        case .alibaba:
            urlString = "https://ram.console.aliyun.com/manage/ak"
        case .volcengine:
            urlString = "https://console.volcengine.com/iam/keymanage/"
        }
        
        if let url = URL(string: urlString) {
            NSWorkspace.shared.open(url)
        }
    }
    
    private func testGoogleSpeech() {
        let key = inputGoogleSpeechKey.trimmingCharacters(in: .whitespacesAndNewlines)
        isGoogleSpeechTesting = true
        googleSpeechTestSuccess = nil
        googleSpeechTestMessage = ""
        
        Task {
            do {
                let audioData = try await GoogleSpeechSynthesizer.testConnection(apiKey: key)
                await MainActor.run {
                    self.isGoogleSpeechTesting = false
                    self.googleSpeechTestSuccess = true
                    self.googleSpeechTestMessage = loc("test_msg_speech_success")
                    
                    if let player = try? AVAudioPlayer(data: audioData) {
                        player.enableRate = true
                        player.rate = Float(speechManager.speechRate)
                        player.prepareToPlay()
                        self.testAudioPlayer = player
                        player.play()
                    }
                }
            } catch {
                await MainActor.run {
                    self.isGoogleSpeechTesting = false
                    self.googleSpeechTestSuccess = false
                    self.googleSpeechTestMessage = error.localizedDescription
                }
            }
        }
    }
    
    private func saveGoogleSpeechKeys() {
        googleSpeechConfig.save(apiKey: inputGoogleSpeechKey)
        withAnimation {
            showGoogleSpeechSavedAlert = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation {
                showGoogleSpeechSavedAlert = false
            }
        }
    }
    
    private func testMicrosoftSpeech() {
        let key = inputMsKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let region = inputMsRegion.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty && !region.isEmpty else { return }
        
        isMsTesting = true
        msTestSuccess = nil
        msTestMessage = ""
        
        Task {
            do {
                let audioData = try await MicrosoftSpeechSynthesizer.testConnection(apiKey: key, region: region, rate: speechManager.speechRate)
                await MainActor.run {
                    self.isMsTesting = false
                    self.msTestSuccess = true
                    self.msTestMessage = loc("test_msg_speech_success")
                    
                    if let player = try? AVAudioPlayer(data: audioData) {
                        player.prepareToPlay()
                        self.testAudioPlayer = player
                        player.play()
                    }
                }
            } catch {
                await MainActor.run {
                    self.isMsTesting = false
                    self.msTestSuccess = false
                    self.msTestMessage = error.localizedDescription
                }
            }
        }
    }
    
    private func saveMicrosoftSpeechKeys() {
        msSpeechConfig.save(apiKey: inputMsKey, region: inputMsRegion)
        withAnimation {
            showMsSavedAlert = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation {
                showMsSavedAlert = false
            }
        }
    }
}

// MARK: - 声音选择弹窗 (精选 10 种常用语言，支持多语种人声设置与试听)
public struct VoiceSettingsSheetView: View {
    let provider: SpeechProvider
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var locManager = LocalizationManager.shared
    @ObservedObject private var speechManager = SpeechManager.shared
    @ObservedObject private var msSpeechConfig = MicrosoftSpeechConfig.shared
    
    // 预载缓存数据，避免在动画和重绘过程中重复调用系统 IPC 引起卡顿
    private let systemVoicesMap: [String: [SystemVoiceOption]]
    private let msVoicesMap: [String: [MicrosoftVoicePreset]]
    
    public init(provider: SpeechProvider) {
        self.provider = provider
        var sysMap: [String: [SystemVoiceOption]] = [:]
        var msMap: [String: [MicrosoftVoicePreset]] = [:]
        for entry in SpeechLanguageEntry.standardLanguages {
            sysMap[entry.id] = SpeechManager.shared.availableSystemVoices(for: entry)
            msMap[entry.id] = MicrosoftSpeechConfig.voicePresets(for: entry.id)
        }
        self.systemVoicesMap = sysMap
        self.msVoicesMap = msMap
    }
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // 顶栏标题
            Text(loc("voice_sheet_title"))
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(.primary)
                .padding(.top, 2)
            
            // 10 种语言卡片容器
            VStack(spacing: 0) {
                ForEach(Array(SpeechLanguageEntry.standardLanguages.enumerated()), id: \.element.id) { index, entry in
                    if index > 0 {
                        Divider()
                    }
                    
                    languageRow(entry)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color(NSColor.controlBackgroundColor).opacity(0.55))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color.secondary.opacity(0.15), lineWidth: 0.8)
            )
            
            // 底部 "好" 按钮
            HStack {
                Spacer()
                Button(loc("voice_done_btn")) {
                    speechManager.stop()
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .controlSize(.regular)
                .frame(minWidth: 68)
            }
            .padding(.top, 4)
        }
        .padding(20)
        .frame(width: 520)
    }
    
    @ViewBuilder
    private func languageRow(_ entry: SpeechLanguageEntry) -> some View {
        HStack(spacing: 12) {
            Text(entry.name)
                .font(.system(size: 13))
                .frame(width: 75, alignment: .leading)
            
            if provider == .system {
                let voices = systemVoicesMap[entry.id] ?? []
                let selectedId = speechManager.systemVoiceId(for: entry.id)
                
                Picker("", selection: Binding(
                    get: {
                        if voices.contains(where: { $0.id == selectedId }) {
                            return selectedId
                        }
                        return voices.first?.id ?? ""
                    },
                    set: { newId in
                        speechManager.setSystemVoiceId(newId, for: entry.id)
                    }
                )) {
                    ForEach(voices) { v in
                        Text(v.displayName).tag(v.id)
                    }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: .infinity)
            } else if provider == .google {
                HStack {
                    Text("Google 多语言标准自然音色")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                let msPresets = msVoicesMap[entry.id] ?? []
                let selectedMs = msSpeechConfig.voice(for: entry.id)
                
                Picker("", selection: Binding(
                    get: {
                        if msPresets.contains(where: { $0.id == selectedMs }) {
                            return selectedMs
                        }
                        return msPresets.first?.id ?? ""
                    },
                    set: { newVoice in
                        msSpeechConfig.setVoice(newVoice, for: entry.id)
                    }
                )) {
                    ForEach(msPresets) { p in
                        Text("\(p.name) \(p.locale)").tag(p.id)
                    }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: .infinity)
            }
            
            Button(loc("voice_test_btn")) {
                speechManager.speak(text: entry.sampleText, languageCode: entry.code)
            }
            .controlSize(.regular)
        }
    }
}

// MARK: - Custom Settings Window
@MainActor
public final class SettingsWindow: NSWindow {
    override public var canBecomeMain: Bool { true }
    override public var canBecomeKey: Bool { true }
}

// MARK: - Settings Window Controller
@MainActor
public final class SettingsWindowController: NSObject, NSWindowDelegate, NSToolbarDelegate, ObservableObject {
    public static let shared = SettingsWindowController()
    
    public var window: SettingsWindow?
    private var toolbar: NSToolbar?
    
    @Published public var selectedTab: SettingsTab = .general
    
    override private init() {
        super.init()
    }
    
    public func updateLocalization() {
        if let items = toolbar?.items {
            for item in items {
                if let tab = SettingsTab(rawValue: item.itemIdentifier.rawValue) {
                    item.label = tab.title
                    item.paletteLabel = tab.title
                    item.toolTip = tab.title
                }
            }
        }
    }
    
    public func selectTab(_ tab: SettingsTab) {
        withAnimation(.easeInOut(duration: 0.15)) {
            self.selectedTab = tab
        }
        toolbar?.selectedItemIdentifier = NSToolbarItem.Identifier(tab.rawValue)
    }
    
    public func showWindow(tab: SettingsTab = .general, provider: TranslationProvider? = nil, speechProvider: SpeechProvider? = nil) {
        if WindowManager.shared.closeOnClickOutside {
            WindowManager.shared.hideWindow()
        }
        
        let targetTab: SettingsTab
        if speechProvider != nil {
            targetTab = .speech
        } else if provider != nil {
            targetTab = .translation
        } else {
            targetTab = tab
        }
        
        selectTab(targetTab)
        
        if let win = window {
            win.toolbarStyle = .preference
            win.title = "Slate"
            win.titleVisibility = .visible
            win.contentView = NSHostingView(rootView: SettingsView(initialTab: targetTab, initialEditingProvider: provider, initialEditingSpeechProvider: speechProvider))
            updateLocalization()
            win.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        
        let settingsView = SettingsView(initialTab: targetTab, initialEditingProvider: provider, initialEditingSpeechProvider: speechProvider)
        let hostingView = NSHostingView(rootView: settingsView)
        
        let win = SettingsWindow(
            contentRect: NSRect(x: 0, y: 0, width: 780, height: 550),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        win.toolbarStyle = .preference
        win.title = loc("settings_window_title")
        win.titleVisibility = .visible
        win.contentView = hostingView
        win.isReleasedWhenClosed = false
        win.center()
        win.delegate = self
        
        // Native macOS Settings Toolbar
        let tb = NSToolbar(identifier: "SlateSettingsToolbar")
        tb.delegate = self
        tb.allowsUserCustomization = false
        tb.autosavesConfiguration = false
        tb.displayMode = .iconAndLabel
        tb.selectedItemIdentifier = NSToolbarItem.Identifier(targetTab.rawValue)
        
        if #available(macOS 13.0, *) {
            tb.centeredItemIdentifiers = Set(SettingsTab.allCases.map { NSToolbarItem.Identifier($0.rawValue) })
        }
        
        win.toolbar = tb
        self.toolbar = tb
        self.window = win
        
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    public func closeWindow() {
        window?.orderOut(nil)
        window = nil
        toolbar = nil
    }
    
    nonisolated public func windowWillClose(_ notification: Notification) {
        Task { @MainActor in
            self.window = nil
            self.toolbar = nil
        }
    }
    
    // MARK: - NSToolbarDelegate
    
    public func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        return [.flexibleSpace] + SettingsTab.allCases.map { NSToolbarItem.Identifier($0.rawValue) }
    }
    
    public func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        return [.flexibleSpace] + SettingsTab.allCases.map { NSToolbarItem.Identifier($0.rawValue) } + [.flexibleSpace]
    }
    
    public func toolbarSelectableItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        return SettingsTab.allCases.map { NSToolbarItem.Identifier($0.rawValue) }
    }
    
    public func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        if itemIdentifier == .flexibleSpace {
            return NSToolbarItem(itemIdentifier: itemIdentifier)
        }
        
        guard let tab = SettingsTab(rawValue: itemIdentifier.rawValue) else { return nil }
        
        let item = NSToolbarItem(itemIdentifier: itemIdentifier)
        item.label = tab.title
        item.paletteLabel = tab.title
        item.toolTip = tab.title
        let config = NSImage.SymbolConfiguration(pointSize: 19, weight: .regular)
        item.image = NSImage(systemSymbolName: tab.icon, accessibilityDescription: tab.title)?.withSymbolConfiguration(config)
        item.target = self
        item.action = #selector(toolbarItemClicked(_:))
        return item
    }
    
    @objc private func toolbarItemClicked(_ sender: NSToolbarItem) {
        guard let tab = SettingsTab(rawValue: sender.itemIdentifier.rawValue) else { return }
        selectTab(tab)
    }
}

// MARK: - Backward Compatibility Bridge
@MainActor
public final class APISettingsWindowController {
    public static let shared = APISettingsWindowController()
    
    public func showWindow(provider: TranslationProvider? = nil) {
        SettingsWindowController.shared.showWindow(tab: .translation, provider: provider)
    }
}
