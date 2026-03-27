import Foundation

/// Minimal TOML parser for yalyric config files.
/// Supports: [sections], key = "string", key = 123, key = 1.5, key = true/false, # comments.
/// Does NOT support: arrays, inline tables, multi-line strings, datetime.
enum TOMLParser {

    /// Parse a TOML string into a nested dictionary: [section: [key: value]]
    /// Top-level keys go under section ""
    static func parse(_ text: String) -> [String: [String: Any]] {
        var result: [String: [String: Any]] = [:]
        var currentSection = ""

        for rawLine in text.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)

            // Skip empty lines and comments
            if line.isEmpty || line.hasPrefix("#") { continue }

            // Section header: [section]
            if line.hasPrefix("[") && line.hasSuffix("]") {
                currentSection = String(line.dropFirst().dropLast())
                    .trimmingCharacters(in: .whitespaces)
                continue
            }

            // Key = value
            guard let eqIndex = line.firstIndex(of: "=") else { continue }
            let key = line[line.startIndex..<eqIndex].trimmingCharacters(in: .whitespaces)
            var value = line[line.index(after: eqIndex)...].trimmingCharacters(in: .whitespaces)

            // Strip inline comment
            if value.hasPrefix("\"") {
                // For quoted strings, find closing quote first, then strip comment after it
                if let closeQuote = value.dropFirst().firstIndex(of: "\"") {
                    let afterQuote = value.index(after: closeQuote)
                    if afterQuote < value.endIndex {
                        value = String(value[value.startIndex...closeQuote])
                    }
                }
            } else {
                if let commentIndex = value.firstIndex(of: "#") {
                    value = String(value[value.startIndex..<commentIndex])
                        .trimmingCharacters(in: .whitespaces)
                }
            }

            guard !key.isEmpty, !value.isEmpty else { continue }

            let parsed = parseValue(value)
            result[currentSection, default: [:]][key] = parsed
        }

        return result
    }

    private static func parseValue(_ value: String) -> Any {
        // Boolean
        if value == "true" { return true }
        if value == "false" { return false }

        // Quoted string
        if value.hasPrefix("\"") && value.hasSuffix("\"") && value.count >= 2 {
            return String(value.dropFirst().dropLast())
        }

        // Integer (no decimal point)
        if !value.contains("."), let intVal = Int(value) {
            return intVal
        }

        // Double
        if let doubleVal = Double(value) {
            return doubleVal
        }

        // Unquoted string fallback
        return value
    }

    /// Serialize a nested dictionary back to TOML string.
    static func serialize(_ data: [String: [String: Any]], comments: [String: String] = [:]) -> String {
        var lines: [String] = []
        lines.append("# yalyric configuration")
        lines.append("# ~/.config/yalyric/config.toml")
        lines.append("")

        // Sort sections for consistent output
        let sections = data.keys.sorted()
        for section in sections {
            guard let pairs = data[section], !pairs.isEmpty else { continue }

            if !section.isEmpty {
                if let comment = comments[section] {
                    lines.append("# \(comment)")
                }
                lines.append("[\(section)]")
            }

            for (key, value) in pairs.sorted(by: { $0.key < $1.key }) {
                lines.append("\(key) = \(serializeValue(value))")
            }
            lines.append("")
        }

        return lines.joined(separator: "\n")
    }

    private static func serializeValue(_ value: Any) -> String {
        switch value {
        case let b as Bool: return b ? "true" : "false"
        case let i as Int: return "\(i)"
        case let d as Double:
            // Always include decimal point so it parses back as Double
            let s = String(format: "%g", d)
            return s.contains(".") ? s : s + ".0"
        case let s as String: return "\"\(s)\""
        default: return "\"\(value)\""
        }
    }
}
