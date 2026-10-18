import Foundation
import SwiftUI
import Combine

@MainActor
public final class FontSizeManager: ObservableObject {
    public static let shared = FontSizeManager()
    
    public static let availableSizes: [CGFloat] = [14, 16, 18, 20, 22]
    public static let defaultSize: CGFloat = 16
    
    @Published public var currentSize: CGFloat {
        didSet {
            UserDefaults.standard.set(currentSize, forKey: "app_font_size")
        }
    }
    
    public var stepIndex: Int {
        FontSizeManager.availableSizes.firstIndex(of: currentSize) ?? 1
    }
    
    private init() {
        let saved = UserDefaults.standard.double(forKey: "app_font_size")
        if saved > 0 && FontSizeManager.availableSizes.contains(CGFloat(saved)) {
            self.currentSize = CGFloat(saved)
        } else {
            self.currentSize = FontSizeManager.defaultSize
        }
    }
    
    public func setStepIndex(_ index: Int) {
        let clamped = max(0, min(FontSizeManager.availableSizes.count - 1, index))
        let target = FontSizeManager.availableSizes[clamped]
        guard currentSize != target else { return }
        currentSize = target
    }
    
    public func setSize(_ size: CGFloat) {
        guard FontSizeManager.availableSizes.contains(size) && currentSize != size else { return }
        currentSize = size
    }
    
    @discardableResult
    public func increase() -> Bool {
        guard let idx = FontSizeManager.availableSizes.firstIndex(of: currentSize),
              idx < FontSizeManager.availableSizes.count - 1 else { return false }
        currentSize = FontSizeManager.availableSizes[idx + 1]
        return true
    }
    
    @discardableResult
    public func decrease() -> Bool {
        guard let idx = FontSizeManager.availableSizes.firstIndex(of: currentSize),
              idx > 0 else { return false }
        currentSize = FontSizeManager.availableSizes[idx - 1]
        return true
    }
    
    public func resetToDefault() {
        guard currentSize != FontSizeManager.defaultSize else { return }
        currentSize = FontSizeManager.defaultSize
    }
}
