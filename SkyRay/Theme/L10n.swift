import Foundation

func L(_ key: String) -> String { NSLocalizedString(key, comment: "") }

func L(_ key: String, _ args: CVarArg...) -> String { String(format: NSLocalizedString(key, comment: ""), arguments: args) }

/// The app's language as iOS resolved it (the per-app setting in Settings wins).
var appLanguage: String { Bundle.main.preferredLocalizations.first ?? "en" }
