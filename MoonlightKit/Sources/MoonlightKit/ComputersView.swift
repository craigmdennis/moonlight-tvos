#if canImport(SwiftUI) && canImport(UIKit)
import SwiftUI
import UIKit

/// Everything one tile and the backdrop need. The app builds these from the host store and the cache.
public struct HostTileModel: Identifiable, Equatable, Sendable {
    public let id: String
    public var name: String
    public var state: HostCardState
    public var tintHex: UInt32
    /// Hero from the cache, else the wallpaper. Already chosen by `backdropSources`.
    public var backdrop: Data?
    /// Game art for the tile itself. Never the wallpaper.
    public var tileArt: Data?
    public var line: StatusLine
    public var menu: [HoldMenuItem]

    public init(id: String, name: String, state: HostCardState, tintHex: UInt32, backdrop: Data? = nil,
                tileArt: Data? = nil, line: StatusLine, menu: [HoldMenuItem]) {
        self.id = id; self.name = name; self.state = state; self.tintHex = tintHex
        self.backdrop = backdrop; self.tileArt = tileArt; self.line = line; self.menu = menu
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
    }
}

extension StatusIcon {
    var symbol: String? {
        switch self {
        case .none, .spinner: nil
        case .clock: "clock.fill"
        case .controller: "gamecontroller.fill"
        case .warning: "exclamationmark.triangle.fill"
        case .lock: "lock.fill"
        case .lockCross: "lock.fill"
        case .plus: "plus.circle.fill"
        }
    }
}

extension HoldMenuItem {
    var title: String {
        switch self {
        case .openBigPicture: "Open Steam Big Picture"
        case .openDesktop: "Open Desktop"
        case .quit(let app): "Quit \(app)"
        case .testNetwork: "Test Network"
        case .removeComputer: "Remove Computer"
        }
    }
}

/// One line with a 32-point icon or spinner in front. Never two lines.
struct StatusLineView: View {
    let line: StatusLine

    var body: some View {
        HStack(spacing: 14) {
            if line.icon == .spinner {
                ProgressView().frame(width: 32, height: 32)
            } else if let symbol = line.icon.symbol {
                Image(systemName: symbol).font(.system(size: 28)).frame(width: 32, height: 32)
            }
            Text(line.text).font(.system(size: 31)).lineLimit(1)
        }
        .foregroundStyle(.white.opacity(0.78))
        .frame(height: 41, alignment: .leading)
    }
}

struct BadgeView: View {
    let badge: Badge
    let busy: Bool

    var body: some View {
        Group {
            if busy {
                ProgressView().frame(width: 32, height: 32)
            } else {
                HStack(spacing: 8) {
                    Circle().fill(Color(hex: badge.hex)).frame(width: 14, height: 14)
                    Text(badge.rawValue).font(.system(size: 23, weight: .semibold))
                }
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
        .background(.ultraThinMaterial, in: Capsule())
    }
}

struct HostTileView: View {
    let model: HostTileModel
    @Environment(\.isFocused) private var focused

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ZStack(alignment: .topTrailing) {
                RoundedRectangle(cornerRadius: 22).fill(Color(hex: model.tintHex))
                if let data = model.tileArt, let image = UIImage(data: data) {
                    Image(uiImage: image).resizable().scaledToFill()
                } else {
                    Image(systemName: model.state.isPaired ? "desktopcomputer" : "lock.desktopcomputer")
                        .font(.system(size: 96)).foregroundStyle(.white.opacity(0.85))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                BadgeView(badge: model.state.badge, busy: model.state.isBusy).padding(16)
            }
            .frame(width: 280, height: 396)
            .clipShape(RoundedRectangle(cornerRadius: 22))
            .overlay(RoundedRectangle(cornerRadius: 22).stroke(.white, lineWidth: focused ? 4 : 0))
            .scaleEffect(focused ? 1.08 : 1)
            .shadow(color: .black.opacity(focused ? 0.7 : 0), radius: 30, y: 24)
            Text(model.name).font(.system(size: 29, weight: .medium)).lineLimit(1).frame(width: 280, alignment: .leading)
        }
        .opacity(focused ? 1 : 0.7)
    }
}

/// The one screen: the focused host's art fills the screen, a status line, and a row of tiles.
/// Press plays; hold opens the menu. Settings, dialogs, and pairing are separate views.
public struct ComputersView: View {
    public let hosts: [HostTileModel]
    public var onPress: (String) -> Void
    public var onMenu: (String, HoldMenuItem) -> Void
    @FocusState private var focus: String?

    public init(hosts: [HostTileModel], onPress: @escaping (String) -> Void, onMenu: @escaping (String, HoldMenuItem) -> Void) {
        self.hosts = hosts; self.onPress = onPress; self.onMenu = onMenu
    }

    private var focused: HostTileModel? { hosts.first { $0.id == focus } ?? hosts.first }

    public var body: some View {
        ZStack(alignment: .bottomLeading) {
            backdrop
            VStack(alignment: .leading, spacing: 24) {
                if let line = focused?.line { StatusLineView(line: line) }
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 30) {
                        ForEach(hosts) { host in
                            Button { onPress(host.id) } label: { HostTileView(model: host) }
                                .buttonStyle(.plain)
                                .focused($focus, equals: host.id)
                                .contextMenu {
                                    ForEach(Array(host.menu.enumerated()), id: \.offset) { _, item in
                                        Button(item.title, role: item == .removeComputer ? .destructive : nil) { onMenu(host.id, item) }
                                    }
                                }
                        }
                    }
                    .padding(.vertical, 40)
                }
            }
            .padding(.horizontal, 80).padding(.bottom, 60)
        }
        .ignoresSafeArea()
        .animation(.easeOut(duration: 0.3), value: focused?.id)
    }

    @ViewBuilder private var backdrop: some View {
        if let host = focused {
            ZStack {
                Color(hex: host.tintHex)
                if let data = host.backdrop, let image = UIImage(data: data) {
                    Image(uiImage: image).resizable().scaledToFill()
                } else {
                    Image(systemName: host.state.isPaired ? "desktopcomputer" : "lock.desktopcomputer")
                        .font(.system(size: 260)).foregroundStyle(.white.opacity(0.25))
                }
                LinearGradient(colors: [.clear, .black.opacity(0.7)], startPoint: .center, endPoint: .bottom)
            }
            .id(host.id)
            .transition(.opacity)
        }
    }
}
#endif
