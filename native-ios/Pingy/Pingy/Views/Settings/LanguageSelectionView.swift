import SwiftUI

struct LanguageSelectionView: View {
    @AppStorage("pingy.v3.language") private var appLanguage = "System"

    private let options = ["System", "English", "Arabic"]

    var body: some View {
        List {
            Section {
                ForEach(options, id: \.self) { option in
                    Button {
                        withAnimation(.spring(response: 0.26, dampingFraction: 0.82)) {
                            appLanguage = option
                        }
                        PingyHaptics.softTap()
                    } label: {
                        HStack {
                            Text(LocalizedStringKey(option))
                                .font(.system(size: 17, weight: .medium, design: .rounded))
                                .foregroundStyle(PingyTheme.textPrimary)
                            Spacer()
                            if appLanguage == option {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundStyle(PingyTheme.primaryStrong)
                            }
                        }
                        .padding(.vertical, 6)
                    }
                    .buttonStyle(.plain)
                }
            } footer: {
                Text("Language changes apply instantly across the app.")
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(PingyTheme.background.ignoresSafeArea())
        .navigationTitle(String(localized: "App language"))
    }
}
