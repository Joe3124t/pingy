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
            VStack(spacing: 3) {
                Image(systemName: tab.icon)
                    .font(
                        .system(
                            size: tab.isPrimary
                                ? (isSelected ? 24 : 22)
                                : (isSelected ? 20 : 18),
                            weight: .semibold
                        )
                    )
                    .scaleEffect(
                        tab.isPrimary
                            ? (isSelected ? 1.12 : 1.05)
                            : (isSelected ? 1.08 : 1.0)
                    )
                    .animation(.spring(response: 0.3, dampingFraction: 0.82), value: isSelected)

                Text(LocalizedStringKey(tab.title))
                    .font(.system(size: 11, weight: isSelected ? .bold : .semibold, design: .rounded))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .foregroundStyle(
                isSelected
                    ? Color.white
                    : (tab.isPrimary ? Color.white.opacity(0.86) : Color.white.opacity(0.74))
            )
            .offset(x: parallaxX)
            .shadow(
                color: tab.isPrimary && isSelected
                    ? Color(red: 0.13, green: 0.86, blue: 0.78).opacity(0.36)
                    : Color.clear,
                radius: 10,
                y: 3
            )
            .overlay(alignment: .topTrailing) {
                if tab == .chats, unreadCount > 0 {
                    Text("\(min(99, unreadCount))")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(.black.opacity(0.9))
                        .padding(.horizontal, 5.5)
                        .padding(.vertical, 2)
                        .background(Color(red: 0.14, green: 0.84, blue: 0.39))
                        .clipShape(Circle())
                        .offset(x: -10, y: 2)
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
