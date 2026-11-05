import SwiftUI

/// SwiftUI's `State` property wrapper under another name. From the macOS 27
/// SDK on, `@State` resolves to a macro whose implementation (SwiftUIMacros)
/// ships only with Xcode, so with the Command Line Tools alone every `@State`
/// fails to build. Attributes spelled through this alias skip the macro and
/// use the property wrapper, which behaves as `@State` did before.
/// Use `@ViewState` instead of `@State` in views.
typealias ViewState = SwiftUI.State
