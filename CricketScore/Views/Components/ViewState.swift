import SwiftUI

/// Drop-in for `@State`.
///
/// In the macOS 26 SDK `@State` is implemented as a compiler macro whose plugin ships
/// with Xcode but not with the standalone Command Line Tools. Wrapping `SwiftUI.State`
/// in a `DynamicProperty` gives identical behaviour and builds with either toolchain.
@propertyWrapper
struct ViewState<Value>: DynamicProperty {
    private let storage: State<Value>

    init(wrappedValue: Value) {
        storage = State(initialValue: wrappedValue)
    }

    var wrappedValue: Value {
        get { storage.wrappedValue }
        nonmutating set { storage.wrappedValue = newValue }
    }

    var projectedValue: Binding<Value> { storage.projectedValue }
}
