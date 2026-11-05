import Foundation

/// Looks up `key` in this target's Localizable.strings. Keys are the English
/// strings, so a missing translation falls back to English verbatim; format
/// arguments are rendered with the user's locale.
func tr(_ key: String, _ args: CVarArg...) -> String {
    let format = NSLocalizedString(key, bundle: .module, comment: "")
    guard !args.isEmpty else { return format }
    return String(format: format, locale: .current, arguments: args)
}
