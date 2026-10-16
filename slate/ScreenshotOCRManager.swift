import AppKit
import Vision
import Foundation
import Combine

@MainActor
public final class ScreenshotOCRManager: ObservableObject {
    public static let shared = ScreenshotOCRManager()
    
    @Published public var isCapturing: Bool = false
    
    private init() {}
    
    /// Triggers interactive screen crop and recognizes text with Apple Vision OCR
    public func performScreenshotOCR() {
        guard !isCapturing else { return }
        isCapturing = true
        
        // If Slate window is currently visible, hide it first so it doesn't block the screen
        if WindowManager.shared.isWindowVisible {
            WindowManager.shared.hideWindow()
        }
        
        let tempFilePath = (NSTemporaryDirectory() as NSString).appendingPathComponent("slate_ocr_\(UUID().uuidString).png")
        let tempUrl = URL(fileURLWithPath: tempFilePath)
        
        Task.detached(priority: .userInitiated) {
            // Small delay to ensure any dismissing animations settle
            try? await Task.sleep(nanoseconds: 120_000_000) // 120ms
            
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
            // -i: interactive capture (rectangular selection)
            // -x: mute screenshot sound
            process.arguments = ["-i", "-x", tempFilePath]
            
            do {
                try process.run()
                process.waitUntilExit()
            } catch {
                print("Failed to run screencapture: \(error)")
                await MainActor.run { ScreenshotOCRManager.shared.isCapturing = false }
                return
            }
            
            // If the user cancelled via Esc or clicked away without dragging, the file won't exist
            guard FileManager.default.fileExists(atPath: tempFilePath) else {
                await MainActor.run { ScreenshotOCRManager.shared.isCapturing = false }
                return
            }
            
            defer {
                try? FileManager.default.removeItem(at: tempUrl)
            }
            
            guard let image = NSImage(contentsOf: tempUrl),
                  let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
                await MainActor.run { ScreenshotOCRManager.shared.isCapturing = false }
                return
            }
            
            let recognizedText = await Self.recognizeText(from: cgImage)
            
            await MainActor.run {
                ScreenshotOCRManager.shared.isCapturing = false
                if let text = recognizedText, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    let finalText: String
                    if UserDefaults.standard.bool(forKey: "app_smart_line_break_merge") {
                        finalText = TextProcessingUtils.smartMergeLineBreaks(text)
                    } else {
                        finalText = text
                    }
                    WindowManager.shared.showWindow(withInitialText: finalText, autoTranslate: true)
                }
            }
        }
    }
    
    /// Uses Apple's native on-device Vision framework to recognize text
    private static func recognizeText(from cgImage: CGImage) async -> String? {
        return await withCheckedContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                guard error == nil, let observations = request.results as? [VNRecognizedTextObservation] else {
                    continuation.resume(returning: nil)
                    return
                }
                
                // Sort observations vertically from top to bottom, then horizontally left to right
                // In Vision boundingBox, y=0 is bottom and y=1 is top
                let sortedObservations = observations.sorted { obs1, obs2 in
                    let y1 = obs1.boundingBox.origin.y
                    let y2 = obs2.boundingBox.origin.y
                    // If vertical difference is noticeable, the higher element comes first
                    if abs(y1 - y2) > 0.025 {
                        return y1 > y2
                    }
                    return obs1.boundingBox.origin.x < obs2.boundingBox.origin.x
                }
                
                let lines = sortedObservations.compactMap { $0.topCandidates(1).first?.string }
                let result = lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
                continuation.resume(returning: result.isEmpty ? nil : result)
            }
            
            request.recognitionLevel = .accurate
            request.recognitionLanguages = [
                "zh-Hans", "zh-Hant", "en-US", "ja-JP", "ko-KR",
                "fr-FR", "de-DE", "es-ES", "ru-RU", "it-IT", "pt-BR"
            ]
            request.usesLanguageCorrection = true
            
            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(returning: nil)
            }
        }
    }
}

