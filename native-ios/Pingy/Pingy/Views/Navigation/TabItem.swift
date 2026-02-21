import SwiftUI

enum PingyRootTab: String, CaseIterable, Identifiable {
    case contacts
    case calls
    case chats
    case status
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .contacts:
            return "Contacts"
        case .calls:
            return "Calls"
        case .chats:
            return "Chats"
        case .status:
            return "Status"
        case .settings:
            return "Settings"
        }
    }

    var icon: String {
        switch self {
        case .contacts:
            return "person.2.fill"
        case .calls:
            return "phone.fill"
        case .chats:
            return "bubble.left.and.bubble.right.fill"
        case .status:
            return "circle.dashed.inset.filled"
        case .settings:
            return "gearshape.fill"
        }
    }

    var isPrimary: Bool {
        self == .chats
    }
}

struct TabItem: View {
    let tab: PingyRootTab
    let isSelected: Bool
    let unreadCount: Int
    let parallaxX: CGFloat
    let onTap: () -> Void

    @GestureState private var isPressed = false

    var body: some View {
        Button {
            PingyHaptics.softTap()
            onTap()
        } label: {
            VStack(spacing: 4) {
                Image(systemName: tab.icon)
                    .font(.system(size: tab.isPrimary ? 17 : 15, weight: .bold))
                    .scaleEffect(isSelected ? 1.1 : 1.0)
                    .animation(.spring(response: 0.3, dampingFraction: 0.82), value: isSelected)

                Text(LocalizedStringKey(tab.title))
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, tab.isPrimary ? 9 : 8)
            .foregroundStyle(isSelected ? PingyTheme.primaryStrong : PingyTheme.textSecondary)
            .offset(x: parallaxX)
            .overlay(alignment: .topTrailing) {
                if tab == .chats, unreadCount > 0 {
                    Text("\(min(99, unreadCount))")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2.5)
                        .background(Color.red)
                        .clipShape(Capsule())
                        .offset(x: -8, y: 3)
                        .scaleEffect(unreadCount > 0 ? 1 : 0.85)
                        .animation(.spring(response: 0.28, dampingFraction: 0.72), value: unreadCount)
                }
            }
        }
        .buttonStyle(.plain)
        .scaleEffect(isPressed ? 0.96 : 1)
        .animation(.spring(response: 0.24, dampingFraction: 0.72), value: isPressed)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .updating($isPressed) { _, state, _ in
                    state = true
                }
        )
    }
}
