import Foundation

/// The server menu: Auto first, then every line fastest first, then the untested ones, then the failed ones.
public enum ServerRows {
    public struct Row: Equatable {
        public let id: String?          // nil = Auto
        public let text: String
        public init(id: String?, text: String) { self.id = id; self.text = text }
    }

    public static func rows(_ candidates: [AutoSelect.Candidate], nameOf: (String) -> String,
                            auto: String, untested: String, failed: String) -> [Row] {
        func rank(_ c: AutoSelect.Candidate) -> (Int, Int64, Int) {
            if c.delayMs > 0 { return (0, c.delayMs, c.order) }
            if c.delayMs == 0 { return (1, 0, c.order) }
            return (2, 0, c.order)
        }
        let sorted = candidates.sorted { rank($0) < rank($1) }
        var out = [Row(id: nil, text: auto)]
        for c in sorted {
            let ping: String
            if c.delayMs > 0 { ping = "\(c.delayMs) ms" } else if c.delayMs == 0 { ping = untested } else { ping = failed }
            out.append(Row(id: c.id, text: "\(ping)  ·  \(LineName.display(nameOf(c.id)))"))
        }
        return out
    }

    /// What the closed menu shows: the pinned line's name, or "Auto · <the line Auto picked>", with the line's last
    /// delay in brackets when it has one — the Android ServerPicker.currentLabel.
    public static func currentLabel(pinned: Bool, currentName: String?, delayMs: Int64 = 0, auto: String, autoPicked: (String) -> String) -> String {
        let line = currentName.map { delayMs > 0 ? "\(LineName.display($0)) (\(delayMs) ms)" : LineName.display($0) }
        if pinned, let n = line { return n }
        if let n = line { return autoPicked(n) }
        return auto
    }
}
