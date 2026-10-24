import Foundation

/// One option an encoder accepts, as freaccmd describes it under `freaccmd -h <encoder>`.
struct EncoderParameter: Identifiable, Hashable, Codable {
    enum Kind: Hashable, Codable {
        case toggle
        case choice([Choice])
        case range(min: Double, max: Double, minLabel: String?, maxLabel: String?)
    }

    struct Choice: Hashable, Codable, Identifiable {
        let value: String
        let label: String
        var id: String { value }
    }

    /// The argument spec as printed, with `<val>` standing for the value, e.g. `-b <val>` or `--preset=<val>`.
    let spec: String
    let name: String
    let kind: Kind
    let defaultValue: String?

    var id: String { spec }

    var takesValue: Bool { spec.contains("<val>") }

    /// The flag on its own, for display (`-b`, `--preset`).
    var flag: String {
        let head = spec.components(separatedBy: " ").first ?? spec
        return head.replacingOccurrences(of: "=<val>", with: "").replacingOccurrences(of: "<val>", with: "")
    }

    /// Arguments freaccmd expects for this option set to `value`.
    /// Toggles take "on"/"off"; anything else is substituted for `<val>`.
    func arguments(for value: String) -> [String] {
        if case .toggle = kind {
            return value == "on" ? spec.split(separator: " ").map(String.init) : []
        }
        return spec.split(separator: " ").map { $0.replacingOccurrences(of: "<val>", with: value) }
    }
}

struct EncoderInfo: Identifiable, Hashable, Codable {
    let id: String          // freaccmd encoder id, e.g. "lame"
    var name: String        // human name, e.g. "LAME MP3 Encoder"
    var parameters: [EncoderParameter]
}

struct CDDrive: Identifiable, Hashable {
    let number: Int
    let path: String
    let name: String
    var id: Int { number }
}

/// Parses the plain-text output of freaccmd. Every format here comes from
/// fre:ac's src/startconsole.cpp, so the app needs no private interface into fre:ac.
enum FreacHelp {
    /// "fre:ac - free audio converter v1.1.7 (arm64) command line interface" → "1.1.7"
    /// The header isn't always the first line: macOS can print loader warnings ahead of it.
    static func version(fromHelp text: String) -> String? {
        let lines = text.split(separator: "\n")
        let header = lines.first { $0.contains("command line interface") } ?? lines.first { $0.contains("fre:ac") }
        guard let header else { return nil }
        for w in header.split(separator: " ") where w.hasPrefix("v") && w.dropFirst().first?.isNumber == true {
            return String(w.dropFirst())
        }
        return nil
    }

    /// The encoder ids listed after "Encoder <id> can be one of:".
    static func encoderIDs(fromHelp text: String) -> [String] {
        let lines = text.components(separatedBy: "\n")
        guard let start = lines.firstIndex(where: { $0.contains("can be one of:") }) else { return [] }
        var ids: [String] = []
        for line in lines[(start + 1)...] {
            let t = line.trimmingCharacters(in: .whitespaces)
            if t.isEmpty { if ids.isEmpty { continue } else { break } }
            ids += t.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        }
        return ids
    }

    /// Parses `freaccmd -h <id>`.
    static func encoder(id: String, fromHelp text: String) -> EncoderInfo {
        var name = id
        var params: [EncoderParameter] = []
        // A selection being collected: its continuation lines add more choices.
        var pending: (spec: String, name: String, choices: [EncoderParameter.Choice], def: String?)?

        func flush() {
            if let p = pending {
                params.append(EncoderParameter(spec: p.spec, name: p.name, kind: .choice(p.choices), defaultValue: p.def))
            }
            pending = nil
        }

        for raw in text.components(separatedBy: "\n") {
            let line = raw.replacingOccurrences(of: "\r", with: "")
            if line.hasPrefix("Options for ") {
                name = String(line.dropFirst("Options for ".count)).trimmingCharacters(in: CharacterSet(charactersIn: ": "))
                continue
            }
            guard line.hasPrefix("\t") else { flush(); continue }
            let body = line.dropFirst()
            if body.hasPrefix("\t") || body.hasPrefix(" ") {
                // Continuation of a selection list.
                let t = body.trimmingCharacters(in: .whitespaces)
                if !t.isEmpty, pending != nil {
                    let (choice, isDefault) = parseChoice(t)
                    pending!.choices.append(choice)
                    if isDefault { pending!.def = choice.value }
                }
                continue
            }
            flush()
            guard let tab = body.firstIndex(of: "\t") else { continue }
            let spec = String(body[..<tab]).trimmingCharacters(in: .whitespaces)
            let rest = body[tab...].trimmingCharacters(in: CharacterSet(charactersIn: "\t "))
            if rest.isEmpty || rest.hasPrefix("no options for") || spec.isEmpty { continue }

            guard let colon = rest.range(of: ": ") else {
                params.append(EncoderParameter(spec: spec, name: rest, kind: .toggle, defaultValue: nil))
                continue
            }
            let pname = String(rest[..<colon.lowerBound])
            let values = String(rest[colon.upperBound...])
            if let range = parseRange(values) {
                params.append(EncoderParameter(spec: spec, name: pname,
                                               kind: .range(min: range.min, max: range.max, minLabel: range.minLabel, maxLabel: range.maxLabel),
                                               defaultValue: range.def))
            } else {
                let (choice, isDefault) = parseChoice(values)
                pending = (spec, pname, [choice], isDefault ? choice.value : nil)
            }
        }
        flush()
        return EncoderInfo(id: id, name: name, parameters: params)
    }

    /// "value (alias), default" → choice + whether it's the default.
    static func parseChoice(_ s: String) -> (EncoderParameter.Choice, Bool) {
        var t = s
        var isDefault = false
        if t.hasSuffix(", default") { isDefault = true; t = String(t.dropLast(", default".count)) }
        if t.hasSuffix(")"), let open = t.range(of: " (") {
            let value = String(t[..<open.lowerBound])
            let alias = String(t[open.upperBound..<t.index(before: t.endIndex)])
            return (.init(value: value, label: alias), isDefault)
        }
        return (.init(value: t, label: t), isDefault)
    }

    /// "min (alias) - max (alias), default x" → numbers, aliases and default.
    static func parseRange(_ s: String) -> (min: Double, max: Double, minLabel: String?, maxLabel: String?, def: String?)? {
        var t = s
        var def: String?
        if let r = t.range(of: ", default ") {
            def = String(t[r.upperBound...])
            t = String(t[..<r.lowerBound])
        }
        // Split on " - " that sits between two numbers (aliases may contain dashes).
        let pattern = #"^(-?[0-9]+(?:\.[0-9]+)?)(?: \((.*?)\))? - (-?[0-9]+(?:\.[0-9]+)?)(?: \((.*)\))?$"#
        guard let re = try? NSRegularExpression(pattern: pattern),
              let m = re.firstMatch(in: t, range: NSRange(t.startIndex..., in: t)) else { return nil }
        func group(_ i: Int) -> String? {
            guard let r = Range(m.range(at: i), in: t) else { return nil }
            return String(t[r])
        }
        guard let lo = group(1).flatMap(Double.init), let hi = group(3).flatMap(Double.init) else { return nil }
        return (lo, hi, group(2), group(4), def)
    }

    /// Parses `freaccmd --list-drives`.
    static func drives(fromList text: String) -> [CDDrive] {
        var result: [CDDrive] = []
        for line in text.components(separatedBy: "\n") where line.hasPrefix("\t") {
            let fields = line.split(separator: "\t").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            guard fields.count >= 2, let n = Int(fields[0]) else { continue }
            result.append(CDDrive(number: n, path: fields[1], name: fields.count > 2 ? fields[2...].joined(separator: " ") : fields[1]))
        }
        return result
    }
}
