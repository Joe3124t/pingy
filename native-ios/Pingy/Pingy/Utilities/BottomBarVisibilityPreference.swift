import SwiftUI

private struct BottomBarVisibilityPreferenceKey: PreferenceKey {
    static var defaultValue: Bool = false

    static func reduce(value: inout Bool, nextValue: () -> Bool) {
        value = value || nextValue()
    }
}

extension View {
    func pingyPrefersBottomBarHidden(_ hidden: Bool = true) -> some View {
        preference(key: BottomBarVisibilityPreferenceKey.self, value: hidden)
    }

    func onPingyBottomBarPreferenceChanged(_ perform: @escaping (Bool) -> Void) -> some View {
        onPreferenceChange(BottomBarVisibilityPreferenceKey.self, perform: perform)
    }
}
