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
            
            let recognizedText = Self.recognizeText(from: cgImage)
            
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
                } else {
                    WindowManager.shared.showWindow()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                        NotificationCenter.default.post(name: NSNotification.Name("ScreenshotOCRFailed"), object: nil)
                    }
                }
            }
        }
    }
    
    /// Uses Apple's native on-device Vision framework to recognize text.
    /// Russian is a targeted second pass so it doesn't become the default for other languages.
    private nonisolated static func recognizeText(from cgImage: CGImage) -> String? {
        let commonLanguages = [
            "zh-Hans", "zh-Hant", "en-US", "ja-JP", "ko-KR",
            "fr-FR", "de-DE", "es-ES", "ru-RU", "it-IT", "pt-BR"
        ]

        guard let firstPass = recognizePass(from: cgImage, languages: commonLanguages) else {
            // If broad recognition found nothing, still give Russian a chance.
            return recognizePass(from: cgImage, languages: ["ru-RU"])?.text
        }

        guard shouldRetryForRussian(firstPass.text) else { return firstPass.text }
        guard let russianPass = recognizePass(from: cgImage, languages: ["ru-RU"]),
              containsCyrillic(russianPass.text) else {
            return firstPass.text
        }

        // Avoid replacing a reasonably complete result with a tiny or much less certain
        // Russian-only guess. Confidence is compared alongside recognized text length.
        let firstLength = max(1, meaningfulCharacterCount(firstPass.text))
        let russianLength = meaningfulCharacterCount(russianPass.text)
        let isComparableInLength = Double(russianLength) >= Double(firstLength) * 0.65
        let isComparableInConfidence = russianPass.confidence >= firstPass.confidence - 0.10

        return isComparableInLength && isComparableInConfidence ? russianPass.text : firstPass.text
    }

    private struct OCRPassResult {
        let text: String
        let confidence: Float
    }

    private nonisolated static func recognizePass(from cgImage: CGImage, languages: [String]) -> OCRPassResult? {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = languages
        request.usesLanguageCorrection = true

        do {
            try VNImageRequestHandler(cgImage: cgImage, options: [:]).perform([request])
        } catch {
            print("Screenshot OCR failed for languages \(languages): \(error)")
            return nil
        }

        guard let observations = request.results, !observations.isEmpty else { return nil }

        // Sort observations vertically from top to bottom, then horizontally left to right.
        // In Vision boundingBox, y=0 is bottom and y=1 is top.
        let sortedObservations = observations.sorted { obs1, obs2 in
            let y1 = obs1.boundingBox.origin.y
            let y2 = obs2.boundingBox.origin.y
            if abs(y1 - y2) > 0.025 { return y1 > y2 }
            return obs1.boundingBox.origin.x < obs2.boundingBox.origin.x
        }

        let candidates = sortedObservations.compactMap { $0.topCandidates(1).first }
        let text = candidates.map(\.string).joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }

        let averageConfidence = candidates.reduce(Float.zero) { $0 + $1.confidence } / Float(candidates.count)
        return OCRPassResult(text: text, confidence: averageConfidence)
    }

    private nonisolated static func shouldRetryForRussian(_ text: String) -> Bool {
        let cyrillicCount = text.unicodeScalars.filter(isCyrillic).count
        let latinLetters = text.unicodeScalars.filter { CharacterSet.letters.contains($0) && !isCyrillic($0) }
        let latinCount = latinLetters.count

        // Mixed Cyrillic/Latin often means Vision chose look-alike Latin glyphs in Russian.
        if cyrillicCount > 0 && latinCount > 0 {
            return Double(latinCount) / Double(cyrillicCount + latinCount) >= 0.12
        }

        // Some Russian screenshots are misread entirely as Latin homoglyphs, leaving no
        // Cyrillic signal. Retry when most Latin letters are visually shared with Cyrillic.
        guard latinCount >= 8 else { return false }
        let cyrillicLookalikes = CharacterSet(charactersIn: "ABCEHKMOPTXYabceopxy")
        let lookalikeCount = latinLetters.filter { cyrillicLookalikes.contains($0) }.count
        return Double(lookalikeCount) / Double(latinCount) >= 0.70
    }

    private nonisolated static func containsCyrillic(_ text: String) -> Bool {
        text.unicodeScalars.contains(where: isCyrillic)
    }

    private nonisolated static func isCyrillic(_ scalar: UnicodeScalar) -> Bool {
        (0x0400...0x04FF).contains(scalar.value) || (0x0500...0x052F).contains(scalar.value)
    }

    private nonisolated static func meaningfulCharacterCount(_ text: String) -> Int {
        text.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }.count
    }
}

