import SwiftUI

struct DiscordRailView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var railModel: DiscordRailModel

    var body: some View {
        ZStack {
            if railModel.items.isEmpty {
                ProgressView()
                    .controlSize(.small)
                    .tint(accentColor)
                    .accessibilityLabel("Loading Discord servers")
            } else {
                ScrollView(.vertical) {
                    LazyVStack(spacing: 9) {
                        ForEach(directMessageItems) { item in
                            railButton(for: item)
                        }

                        if !directMessageItems.isEmpty, !remainingItems.isEmpty {
                            Capsule()
                                .fill(.white.opacity(0.16))
                                .frame(width: 32, height: 1)
                                .padding(.vertical, 2)
                                .accessibilityHidden(true)
                        }

                        ForEach(remainingItems) { item in
                            railButton(for: item)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 12)
                }
                .scrollIndicators(.hidden)
            }
        }
        .background(railBackground)
        .overlay {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .strokeBorder(.white.opacity(0.12), lineWidth: 0.75)
        }
        .glassEffect(.regular, in: .rect(cornerRadius: 28))
        .preferredColorScheme(preferredColorScheme)
    }

    private var directMessageItems: [DiscordRailItem] {
        railModel.items.filter { $0.kind == .directMessages }
    }

    private var remainingItems: [DiscordRailItem] {
        railModel.items.filter { $0.kind != .directMessages }
    }

    private func railButton(for item: DiscordRailItem) -> some View {
        Button {
            railModel.activate(id: item.id)
        } label: {
            ZStack {
                RoundedRectangle(
                    cornerRadius: item.isSelected ? 17 : 24,
                    style: .continuous
                )
                .fill(item.isSelected ? accentColor.opacity(0.30) : .white.opacity(0.08))

                railIcon(for: item)
                    .padding(item.kind == .action ? 13 : 0)
            }
            .frame(width: 52, height: 52)
            .overlay(alignment: .leading) {
                if item.isSelected || (item.hasUnread && (item.mentionCount ?? 0) == 0) {
                    Capsule()
                        .fill(item.isSelected ? accentColor : Color.white.opacity(0.92))
                        .frame(width: 4, height: item.isSelected ? 30 : 9)
                        .offset(x: -8)
                }
            }
            .overlay(alignment: .topTrailing) {
                if let count = item.mentionCount, count > 0 {
                    Text(count > 99 ? "99+" : String(count))
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5)
                        .frame(minWidth: 18, minHeight: 18)
                        .background(.red, in: Capsule())
                        .offset(x: 5, y: -5)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(item.title)
        .accessibilityLabel(item.title)
        .accessibilityValue(accessibilityValue(for: item))
    }

    @ViewBuilder
    private func railIcon(for item: DiscordRailItem) -> some View {
        if let iconURL = item.iconURL, item.kind != .action {
            AsyncImage(url: iconURL) { phase in
                switch phase {
                case let .success(image):
                    image
                        .resizable()
                        .scaledToFill()
                case .empty:
                    ProgressView()
                        .controlSize(.small)
                case .failure:
                    fallbackIcon(for: item)
                @unknown default:
                    fallbackIcon(for: item)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 17, style: .continuous))
        } else {
            fallbackIcon(for: item)
        }
    }

    private func fallbackIcon(for item: DiscordRailItem) -> some View {
        Image(systemName: fallbackSymbol(for: item.kind))
            .font(.system(size: item.kind == .action ? 22 : 19, weight: .semibold))
            .foregroundStyle(item.kind == .action ? accentColor : Color.white.opacity(0.92))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func fallbackSymbol(for kind: DiscordRailItem.Kind) -> String {
        switch kind {
        case .directMessages: "bubble.left.and.bubble.right.fill"
        case .server: "person.2.fill"
        case .action: "plus"
        }
    }

    private func accessibilityValue(for item: DiscordRailItem) -> String {
        if let count = item.mentionCount, count > 0 {
            return "\(count) unread mention\(count == 1 ? "" : "s")"
        }
        if item.hasUnread { return "Unread" }
        if item.isSelected { return "Selected" }
        return ""
    }

    private var railBackground: some ShapeStyle {
        if settings.themeColorScheme == .light {
            return Color.white.opacity(settings.visualTheme == .oled ? 0.92 : 0.64)
        }
        return Color.black.opacity(settings.visualTheme == .oled ? 0.82 : 0.50)
    }

    private var preferredColorScheme: ColorScheme? {
        switch settings.themeColorScheme {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }

    private var accentColor: Color {
        let descriptor = settings.themeAccent.colorDescriptor
        return Color(
            red: descriptor.redUnit,
            green: descriptor.greenUnit,
            blue: descriptor.blueUnit
        )
    }
}
