import Foundation

public enum TextProcessingUtils {
    
    /// Checks if a character belongs to CJK (Chinese, Japanese, Korean) ideographs, kana, hangul, or fullwidth punctuation.
    public static func isCJK(_ character: Character) -> Bool {
        guard let scalar = character.unicodeScalars.first, character.unicodeScalars.count == 1 else { return false }
        let v = scalar.value
        return (0x4E00...0x9FFF).contains(v) || // CJK Unified Ideographs
               (0x3400...0x4DBF).contains(v) || // CJK Extension A
               (0x20000...0x2A6DF).contains(v) || // CJK Extension B
               (0x3040...0x309F).contains(v) || // Hiragana
               (0x30A0...0x30FF).contains(v) || // Katakana
               (0xAC00...0xD7AF).contains(v) || // Hangul Syllables
               (0x3000...0x303F).contains(v) || // CJK Symbols and Punctuation (e.g. ，。！？)
               (0xFF00...0xFFEF).contains(v)    // Halfwidth and Fullwidth Forms
    }
    
    /// Checks if a line is a list item, markdown heading, or blockquote that should retain its leading newline.
    public static func isListItemOrHeader(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return false }
        
        // Markdown headings (# Title, ## Subtitle)
        if trimmed.hasPrefix("#") {
            let afterHash = trimmed.drop(while: { $0 == "#" })
            if afterHash.hasPrefix(" ") { return true }
        }
        
        // Blockquotes (> Quote)
        if trimmed.hasPrefix(">") { return true }
        
        // Bullets: - , * , + , • , · , ◦ , ▪
        let bulletPrefixes = ["- ", "* ", "+ ", "• ", "· ", "◦ ", "▪ "]
        for prefix in bulletPrefixes {
            if trimmed.hasPrefix(prefix) { return true }
        }
        
        // Numbered lists: "1. ", "2) ", "(1) ", "a. ", "b) "
        let pattern = #"^(\d+[\.\)]|\([0-9a-zA-Z]+\)|[a-zA-Z][\.\)])\s+"#
        if trimmed.range(of: pattern, options: .regularExpression) != nil {
            return true
        }
        
        return false
    }
    
    /// Checks if a line ends with a colon, which typically introduces an enumeration or quoted block.
    public static func endsWithColon(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        return trimmed.hasSuffix(":") || trimmed.hasSuffix("：")
    }
    
    /// Smartly merges soft line breaks within paragraphs caused by narrow layout wrapping, OCR, or PDF copying.
    /// Preserves true paragraph breaks (double newlines) and list items.
    public static func smartMergeLineBreaks(_ text: String) -> String {
        guard !text.isEmpty else { return text }
        
        // Normalize line breaks: \r\n and \r to \n
        let normalized = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        
        guard normalized.contains("\n") else { return normalized }
        
        // Split text by genuine paragraph breaks (2 or more newlines, possibly containing whitespace)
        let paragraphRegex = try? NSRegularExpression(pattern: #"\n\s*\n+"#)
        let nsString = normalized as NSString
        let fullRange = NSRange(location: 0, length: nsString.length)
        
        var paragraphSplitRanges: [NSRange] = []
        paragraphRegex?.enumerateMatches(in: normalized, options: [], range: fullRange) { match, _, _ in
            if let r = match?.range {
                paragraphSplitRanges.append(r)
            }
        }
        
        var paragraphSubstrings: [String] = []
        if paragraphSplitRanges.isEmpty {
            paragraphSubstrings = [normalized]
        } else {
            var lastIndex = 0
            for r in paragraphSplitRanges {
                let paraRange = NSRange(location: lastIndex, length: r.location - lastIndex)
                paragraphSubstrings.append(nsString.substring(with: paraRange))
                lastIndex = r.location + r.length
            }
            if lastIndex < nsString.length {
                let tailRange = NSRange(location: lastIndex, length: nsString.length - lastIndex)
                paragraphSubstrings.append(nsString.substring(with: tailRange))
            }
        }
        
        let processedParagraphs = paragraphSubstrings.map { para -> String in
            let rawLines = para.components(separatedBy: "\n")
            guard rawLines.count > 1 else { return para }
            
            var result = ""
            for rawLine in rawLines {
                let currentLine = rawLine.trimmingCharacters(in: .whitespaces)
                guard !currentLine.isEmpty else { continue }
                
                if result.isEmpty {
                    result = currentLine
                    continue
                }
                
                // If current line is a list item or heading, or previous line ended with colon, keep newline
                if isListItemOrHeader(currentLine) || endsWithColon(result) {
                    result += "\n" + currentLine
                    continue
                }
                
                // Check word hyphenation at line break (e.g. "inter-" + "national")
                if result.hasSuffix("-") || result.hasSuffix("‐") {
                    let beforeHyphen = result.dropLast()
                    if let lastChar = beforeHyphen.last, lastChar.isLetter,
                       let firstChar = currentLine.first, firstChar.isLetter {
                        // Drop soft hyphen when merging wrapped word
                        result = String(beforeHyphen) + currentLine
                        continue
                    }
                }
                
                guard let lastChar = result.last, let firstChar = currentLine.first else {
                    result += " " + currentLine
                    continue
                }
                
                // For CJK to CJK, merge without space
                if isCJK(lastChar) && isCJK(firstChar) {
                    result += currentLine
                } else {
                    // Western/Alphanumeric: join with a single space
                    result += " " + currentLine
                }
            }
            return result
        }
        
        return processedParagraphs.joined(separator: "\n\n")
    }
}
