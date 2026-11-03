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

/// Tile size: the design's 280 by 396 portrait, scaled up for viewing from the sofa.
enum Tile {
    static let width: CGFloat = 320
    static let height: CGFloat = 452
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

    var symbol: String {
        switch self {
        case .openBigPicture: "gamecontroller"
        case .openDesktop: "display"
        case .quit: "xmark.circle"
        case .testNetwork: "wifi"
        case .removeComputer: "trash"
        }
    }
}

/// Liquid Glass on tvOS 26, a blurred material before it.
struct GlassCapsule: ViewModifier {
    func body(content: Content) -> some View {
        if #available(tvOS 26.0, iOS 26.0, *) {
            content.glassEffect(.regular, in: .capsule)
        } else {
            content.background(.ultraThinMaterial, in: Capsule())
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
                Image(systemName: symbol)
                    .font(.system(size: 28))
                    .foregroundStyle(line.icon == .warning ? Color(hex: 0xFF9F0A) : line.icon == .lockCross ? Color(hex: 0xFF453A) : .white.opacity(0.78))
                    .frame(width: 32, height: 32)
            }
            Text(line.text).font(.system(size: 31)).lineLimit(1)
        }
        .foregroundStyle(.white.opacity(0.78))
        .frame(height: 41, alignment: .leading)
    }
}

/// The pairing PIN, typed into Apollo on the PC.
struct PinView: View {
    let pin: String

    var body: some View {
        HStack(spacing: 14) {
            ForEach(Array(pin.enumerated()), id: \.offset) { _, digit in
                Text(String(digit))
                    .font(.system(size: 56, weight: .bold).monospacedDigit())
                    .frame(width: 76, height: 96)
                    .background(.white.opacity(0.16), in: RoundedRectangle(cornerRadius: 18))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("PIN \(pin.map(String.init).joined(separator: " "))")
    }
}

struct BadgeView: View {
    let badge: Badge
    let busy: Bool

    var body: some View {
        if busy {
            // The design's 40-point glass chip with a small spinner
            ProgressView()
                .scaleEffect(0.55)
                .frame(width: 40, height: 40)
                .modifier(GlassCapsule())
        } else {
            label
        }
    }

    private var label: some View {
        HStack(spacing: 10) {
            switch badge {
            case .notPaired:
                Image(systemName: "lock.fill").font(.system(size: 18))
            case .inUse:
                Image(systemName: "gamecontroller.fill").font(.system(size: 17)).foregroundStyle(Color(hex: badge.hex))
            default:
                Circle().fill(Color(hex: badge.hex)).frame(width: 13, height: 13)
            }
            Text(badge.rawValue).font(.system(size: 22, weight: .semibold))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 16)
        .frame(height: 40)
        .modifier(GlassCapsule())
    }
}

/// The tile's face. The system card button style supplies the focus lift, tilt and shine.
struct HostTileView: View {
    let model: HostTileModel

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Color(hex: model.tintHex)
            if let data = model.tileArt, let image = UIImage(data: data) {
                // Pinned to the tile: a fill-scaled image reports a far larger size, which would
                // push the name out of the tile's bounds and clip it away
                Image(uiImage: image).resizable().scaledToFill()
                    .frame(width: Tile.width, height: Tile.height)
                    .clipped()
            } else {
                Image(systemName: model.state.isPaired ? "desktopcomputer" : "lock.desktopcomputer")
                    .font(.system(size: 90))
                    .foregroundStyle(.white.opacity(0.9))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            LinearGradient(colors: [.clear, .black.opacity(0.75)], startPoint: .center, endPoint: .bottom)
            Text(model.name)
                .font(.system(size: 38, weight: .bold))
                .foregroundStyle(.white)
                .lineLimit(2)
                .shadow(color: .black.opacity(0.6), radius: 5, y: 2)
                .padding(26)
        }
        .overlay(alignment: .topTrailing) {
            BadgeView(badge: model.state.badge, busy: model.state.isBusy).padding(16)
        }
        .frame(width: Tile.width, height: Tile.height)
        .clipped()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(model.name), \(model.state.badge.rawValue). Press to play, hold for options.")
    }
}

/// The one screen: the focused computer's art fills the screen, a status line, and a row of tiles.
/// Press plays; hold opens the system context menu. Dialogs and sheets belong to the app.
public struct ComputersView: View {
    public static let addId = "add"

    /// Distance from the screen edge to the row and the hero, equal on the left and the bottom.
    private static let margin: CGFloat = 80
    /// Room above and below the tiles inside the scroll view, so a focused card can grow.
    private static let rowInset: CGFloat = 40

    public let hosts: [HostTileModel]
    public let addLine: StatusLine
    public let pin: String?
    /// True while the settings panel covers the screen and these controls are disabled.
    public var isCovered: Bool
    public var onPress: (String) -> Void
    public var onMenu: (String, HoldMenuItem) -> Void
    public var onAdd: () -> Void
    public var onSettings: () -> Void
    public var onFocus: (String?) -> Void

    @FocusState private var focus: String?
    /// The tile the hero describes. It stays put while focus is up on Settings.
    @State private var heroId: String?
    /// Where the incoming hero starts, 80 points from the direction focus travelled.
    @State private var heroShift: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(hosts: [HostTileModel], addLine: StatusLine, pin: String?,
                isCovered: Bool = false,
                onPress: @escaping (String) -> Void, onMenu: @escaping (String, HoldMenuItem) -> Void,
                onAdd: @escaping () -> Void, onSettings: @escaping () -> Void, onFocus: @escaping (String?) -> Void) {
        self.hosts = hosts; self.addLine = addLine; self.pin = pin; self.isCovered = isCovered
        self.onPress = onPress; self.onMenu = onMenu; self.onAdd = onAdd; self.onSettings = onSettings; self.onFocus = onFocus
    }

    private var heroHost: HostTileModel? {
        let id = heroId ?? hosts.first?.id
        return hosts.first { $0.id == id }
    }

    private var heroLine: StatusLine {
        heroId == Self.addId || hosts.isEmpty ? addLine : heroHost?.line ?? addLine
    }

    public var body: some View {
        ZStack(alignment: .topLeading) {
            LinearGradient(stops: [.init(color: Color(hex: 0x101013).opacity(0.94), location: 0),
                                   .init(color: Color(hex: 0x101013).opacity(0.72), location: 0.42),
                                   .init(color: Color(hex: 0x101013).opacity(0.15), location: 0.78)],
                           startPoint: .leading, endPoint: .trailing)
            LinearGradient(stops: [.init(color: .clear, location: 0.48), .init(color: Color(hex: 0x101013).opacity(0.95), location: 0.85)],
                           startPoint: .top, endPoint: .bottom)

            VStack(alignment: .leading, spacing: 30) {
                if !heroLine.text.isEmpty {
                    StatusLineView(line: heroLine)
                }
                if let pin, heroHost?.state == .pairing, heroId != Self.addId {
                    PinView(pin: pin)
                }
            }
            .padding(.leading, Self.margin)
            .padding(.top, Self.margin)
            .id(heroId)
            .transition(.opacity)

            VStack(spacing: 0) {
                HStack {
                    Spacer()
                    Button(action: onSettings) {
                        Image(systemName: "gearshape.fill").font(.system(size: 38))
                    }
                    .buttonBorderShape(.circle)
                    .accessibilityLabel("Settings")
                    .focused($focus, equals: "settings")
                }
                .padding(.top, 60)
                .padding(.trailing, Self.margin)
                .focusSection()

                Spacer()

                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 30) {
                        ForEach(hosts) { host in
                            Button { onPress(host.id) } label: { HostTileView(model: host) }
                                .buttonStyle(.card)
                                .focused($focus, equals: host.id)
                                .contextMenu {
                                    ForEach(host.menu.filter { $0 != .removeComputer }, id: \.self) { item in
                                        Button {
                                            onMenu(host.id, item)
                                        } label: {
                                            Label(item.title, systemImage: item.symbol)
                                        }
                                    }
                                    if host.menu.contains(.removeComputer) {
                                        // A system menu divider keeps Remove apart from everything else
                                        Divider()
                                        Button(role: .destructive) {
                                            onMenu(host.id, .removeComputer)
                                        } label: {
                                            Label(HoldMenuItem.removeComputer.title, systemImage: HoldMenuItem.removeComputer.symbol)
                                        }
                                    }
                                }
                        }
                        Button(action: onAdd) {
                            Image(systemName: "plus.circle.fill")
                                .font(.system(size: 54))
                                .foregroundStyle(.white.opacity(0.85))
                                .frame(width: Tile.width, height: Tile.height)
                                .background(Color(hex: 0x101013).opacity(0.4))
                        }
                        .buttonStyle(.card)
                        .accessibilityLabel("Add Computer")
                        .focused($focus, equals: Self.addId)
                    }
                    .padding(.horizontal, Self.margin)
                    .padding(.vertical, Self.rowInset)
                }
                // Only as tall as the tiles, so the spacer above pushes the row to the bottom
                .frame(height: Tile.height + Self.rowInset * 2)
                .scrollClipDisabled()
                .focusSection()
                // The inset above is inside the scroll view, so take it off the margin to make
                // the gap below the tiles match the gap to the left of them
                .padding(.bottom, Self.margin - Self.rowInset)
            }
        }
        .ignoresSafeArea()
        // The backdrop is painted behind everything and given the screen's size, so a hero image
        // can never widen this stack and push the tiles off the screen.
        .background { backdrop }
        .animation(.easeOut(duration: 0.3), value: heroId)
        .onChange(of: focus) { _, newValue in
            // Focus going to the settings panel (or nowhere) isn't moving off this computer.
            // Reporting nil here would cancel a pairing request whose PIN is still on screen.
            guard let newValue else { return }
            if newValue != "settings" {
                moveHero(to: newValue)
            }
            onFocus(newValue == "settings" ? heroId : newValue)
        }
        .onChange(of: isCovered) { _, covered in
            // Disabling these controls drops focus, and tvOS doesn't always give it back when they
            // return, which leaves the remote doing nothing. Put it back on the gear button.
            guard !covered else { return }
            DispatchQueue.main.async { focus = "settings" }
        }
    }

    /// The hero cross-fades and shifts 80 points when focus moves, per the brief. With Reduce
    /// Motion it only cross-fades.
    private func moveHero(to id: String) {
        guard id != heroId else { return }
        guard !reduceMotion else {
            heroId = id
            return
        }
        heroShift = direction(to: id) * 80
        heroId = id
        // Let the new hero land offset, then slide it home: the fade is 0.3 s, the shift 0.45 s
        DispatchQueue.main.async {
            withAnimation(.easeOut(duration: 0.45)) { heroShift = 0 }
        }
    }

    /// Which way focus travelled along the row, so the incoming hero enters from that side.
    private func direction(to id: String) -> CGFloat {
        guard let from = heroId else { return 0 }
        let order = hosts.map(\.id) + [Self.addId]
        guard let a = order.firstIndex(of: from), let b = order.firstIndex(of: id) else { return 0 }
        return b > a ? 1 : (b < a ? -1 : 0)
    }

    /// Painter, not a layout child: GeometryReader pins it to the proposed size and clipping keeps a
    /// fill-scaled hero from spilling out, so only the art moves when focus changes.
    @ViewBuilder private var backdrop: some View {
        GeometryReader { proxy in
            ZStack {
                Color(hex: heroHost.map { $0.tintHex } ?? 0x101013)
                if heroId != Self.addId, let data = heroHost?.backdrop, let image = UIImage(data: data) {
                    Image(uiImage: image).resizable().scaledToFill()
                        // 80 points of slack each side, so the entry shift never shows an edge
                        .frame(width: proxy.size.width + 160, height: proxy.size.height)
                        .offset(x: heroShift)
                        .animation(.easeOut(duration: 0.45), value: heroShift)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .clipped()
        }
        .id(heroId == Self.addId ? nil : heroHost?.id)
        .transition(.opacity)
        .animation(.easeInOut(duration: 0.3), value: heroHost?.id)
    }
}
#endif
