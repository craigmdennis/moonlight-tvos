//
//  HomeScreen.swift
//  Moonlight TV
//
//  The home screen with its system dialogs and sheets.
//

import SwiftUI
import MoonlightKit

struct HomeScreen: View {
    @ObservedObject var model: HomeModel
    @State private var showSettings = false
    /// True from the moment the drawer starts opening until it has finished closing, so the home
    /// screen doesn't take focus back while the panel is still sliding out.
    @State private var covering = false
    /// Set when the drawer finishes sliding in. tvOS moves a focused row into view, so focus is
    /// handed over after the slide rather than during it, when the row would drift.
    @State private var settingsReady = false
    /// Bumped on each open so the drawer forgets the submenu it was last left in, while it is
    /// still off screen.
    @State private var settingsReset = 0
    @State private var showAdd = false
    @State private var address = ""
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var slide: Animation? {
        reduceMotion ? nil : StreamSettingsPanel.slide
    }

    var body: some View {
        ZStack(alignment: .trailing) {
            ComputersView(
                hosts: model.tiles, addLine: model.addLine, pin: model.pin,
                isCovered: covering,
                onPress: model.press, onMenu: model.menu,
                onAdd: {
                    // Prefilled with the Apple TV's own network, so usually only the last number is typed
                    address = HomeModel.subnetPrefix()
                    showAdd = true
                },
                onSettings: openSettings,
                onFocus: model.focusChanged)
            // Disabled controls can't take focus, which keeps focus inside the panel
            .disabled(covering)

            // Kept mounted and moved by state rather than inserted and removed: SwiftUI dropped
            // the removal transition when the focused panel went away, so closing was a hard cut.
            Color.black.opacity(showSettings ? 0.4 : 0)
                .ignoresSafeArea()
                .allowsHitTesting(false)
                .accessibilityHidden(!showSettings)

            StreamSettingsPanel(resetToken: settingsReset, focusReady: settingsReady,
                                isOpen: covering, close: closeSettings)
                .offset(x: showSettings ? 0 : StreamSettingsPanel.width)
                .allowsHitTesting(showSettings)
                .disabled(!covering)
                .accessibilityHidden(!covering)
        }
        // The drawer runs to the screen edge, not the safe area
        .ignoresSafeArea()
        .alert("Add a Computer", isPresented: $showAdd) {
            TextField("192.168.1.20", text: $address)
                .keyboardType(.URL)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
            Button("Add") { model.addComputer(address) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Enter the computer’s IP address or hostname. You can also type on your iPhone.")
        }
        .confirmationDialog(model.inUseHost.map { "\($0.name) Is in Use" } ?? "", isPresented: present($model.inUseHost), titleVisibility: .visible, presenting: model.inUseHost) { host in
            Button("Watch Alongside") { model.watchAlongside(host.id) }
            Button("Cancel", role: .cancel) {}
        } message: { host in
            Text("\(host.line.text). Watch alongside without interrupting.")
        }
        .alert(model.removeHost.map { "Remove \($0.name)?" } ?? "", isPresented: present($model.removeHost), presenting: model.removeHost) { host in
            Button("Remove", role: .destructive) { model.remove(host.id) }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("To stream from it again, you’ll need to pair it again.")
        }
    }

    private func openSettings() {
        settingsReset += 1
        settingsReady = false
        covering = true
        withAnimation(slide, completionCriteria: .logicallyComplete) {
            showSettings = true
        } completion: {
            // Hand focus over once the panel is where it will stay, so tvOS has nothing to correct
            if showSettings { settingsReady = true }
        }
    }

    private func closeSettings() {
        settingsReady = false
        withAnimation(slide, completionCriteria: .logicallyComplete) {
            showSettings = false
        } completion: {
            // Only hand the screen back once the drawer is off screen, so nothing steals focus
            // while it is still sliding out
            covering = false
        }
    }

    private func present<T>(_ item: Binding<T?>) -> Binding<Bool> {
        Binding(get: { item.wrappedValue != nil }, set: { if !$0 { item.wrappedValue = nil } })
    }
}

/// What people change between sessions, in a panel that slides in from the right. The values are stored
/// under the keys TemporarySettings reads, so the next stream picks them up. Set-once options live in the
/// Settings app.
struct StreamSettingsPanel: View {
    static let slide = Animation.timingCurve(0.2, 0.8, 0.2, 1, duration: 0.32)
    static let width: CGFloat = 740

    /// Bumped by the home screen when the drawer opens, while it is still off screen.
    var resetToken: Int
    /// True once the slide has finished. Focus is taken then, not on appear.
    var focusReady: Bool
    var isOpen: Bool
    var close: () -> Void

    private enum Choice: String {
        case resolution = "Resolution", framerate = "Frame Rate", bitrate = "Bitrate"
    }

    @AppStorage("streamResolution") private var resolution = 4
    @AppStorage("framerate") private var framerate = 60
    @AppStorage("bitrate") private var bitrate = 0
    @AppStorage("enableHdr") private var hdr = false
    @AppStorage("statsOverlay") private var stats = false
    @State private var choosing: Choice?
    @FocusState private var focus: String?

    private func options(_ choice: Choice) -> [(Int, String)] {
        switch choice {
        case .resolution: [(4, "Match TV"), (0, "720p"), (1, "1080p"), (3, "1440p"), (2, "4K")]
        case .framerate: [(30, "30 fps"), (60, "60 fps")]
        case .bitrate: [(0, "Automatic")] + [10, 20, 50, 80, 100, 150].map { ($0 * 1000, "\($0) Mbps") }
        }
    }

    private func binding(_ choice: Choice) -> Binding<Int> {
        switch choice {
        case .resolution: $resolution
        case .framerate: $framerate
        case .bitrate: $bitrate
        }
    }

    private func valueText(_ choice: Choice) -> String {
        options(choice).first { $0.0 == binding(choice).wrappedValue }?.1 ?? options(choice)[0].1
    }

    var body: some View {
        // Only the column lives here; HomeScreen draws the scrim so it can fade while this slides.
        VStack(alignment: .leading, spacing: 6) {
            Text(choosing?.rawValue ?? "Stream Settings")
                .font(.system(size: 46, weight: .bold))
                .padding(.leading, 24)
                .padding(.bottom, 22)

            if let choosing {
                ForEach(options(choosing), id: \.0) { value, label in
                    Button {
                        binding(choosing).wrappedValue = value
                        showList(returningTo: choosing)
                    } label: {
                        PanelRow(title: label, trailingSymbol: binding(choosing).wrappedValue == value ? "checkmark" : nil)
                    }
                    .buttonStyle(PanelRowStyle())
                    .focused($focus, equals: label)
                }
            } else {
                ForEach([Choice.resolution, .framerate, .bitrate], id: \.self) { choice in
                    Button { open(choice) } label: { PanelRow(title: choice.rawValue, value: valueText(choice)) }
                        .buttonStyle(PanelRowStyle())
                        .focused($focus, equals: choice.rawValue)
                }
                // tvOS has no switches: On/Off rows flip when selected
                Button { hdr.toggle() } label: { PanelRow(title: "HDR", value: hdr ? "On" : "Off") }
                    .buttonStyle(PanelRowStyle())
                Button { stats.toggle() } label: { PanelRow(title: "Statistics Overlay", value: stats ? "On" : "Off") }
                    .buttonStyle(PanelRowStyle())

                Spacer()
                Rectangle().fill(.white.opacity(0.12)).frame(height: 2).padding(.horizontal, 24).padding(.bottom, 10)
                Button {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                } label: {
                    PanelRow(title: "More in Settings", trailingSymbol: "arrow.up.right")
                }
                .buttonStyle(PanelRowStyle())
                Text("Codec, audio, controllers and other set-once options are in the Apple TV Settings app.")
                    .font(.system(size: 23))
                    .foregroundStyle(Color(white: 0.92, opacity: 0.6))
                    .padding(.horizontal, 24)
                    .padding(.top, 14)
            }
        }
        .padding(.top, 80)
        .padding(.horizontal, 64)
        .padding(.bottom, 72)
        .frame(width: Self.width, alignment: .topLeading)
        .frame(maxHeight: .infinity, alignment: .top)
        // A live material re-blurs this 740-wide column against the moving backdrop on every frame
        // of the slide. A painted surface looks the same over the dark home screen and doesn't.
        // The shadow sits on the painted surface, not the panel, so moving focus between rows
        // doesn't redraw a full-screen blur.
        .background {
            LinearGradient(colors: [Color(white: 0.16), Color(white: 0.11)],
                           startPoint: .top, endPoint: .bottom)
                .overlay(alignment: .leading) {
                    Rectangle().fill(.white.opacity(0.07)).frame(width: 1)
                }
                .shadow(color: .black.opacity(isOpen ? 0.4 : 0), radius: 28, x: -18)
        }
        .focusSection()
        // Flush with the screen edge; the column is 740 wide, so the slide moves it by its own
        // width rather than the screen's
        .ignoresSafeArea()
        .onExitCommand {
            // Menu goes back from a list of choices, then closes the panel
            if let choosing {
                showList(returningTo: choosing)
            } else {
                close()
            }
        }
        // tvOS pulls a focused row into view. Taking focus while the panel is still sliding in
        // makes the row animate on its own, drifting outside the panel, so wait for the slide.
        // On close the focus ring leaves with the panel rather than jumping to another row.
        .onChange(of: focusReady) { _, ready in
            if ready { focus = Choice.resolution.rawValue }
        }
        // Reset to the root while the drawer is off screen, so it never flashes the last submenu
        .onChange(of: resetToken) { _, _ in
            choosing = nil
        }
    }

    private func open(_ choice: Choice) {
        // Same update as the row swap: tvOS would otherwise focus the top row for a frame,
        // then jump to the current value
        choosing = choice
        focus = valueText(choice)
    }

    private func showList(returningTo choice: Choice) {
        choosing = nil
        focus = choice.rawValue
    }
}

/// A panel row: white with black text when focused, and it doesn't grow.
private struct PanelRowStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        PanelRowBackground(label: configuration.label)
    }
}

private struct PanelRowBackground<Label: View>: View {
    let label: Label
    @Environment(\.isFocused) private var focused

    var body: some View {
        label
            .foregroundStyle(focused ? Color.black : Color.white)
            .padding(.horizontal, 24)
            .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
            .background {
                // Draw the focused card once and fade it in, instead of animating an 18-point
                // shadow on every focus move
                RoundedRectangle(cornerRadius: 16)
                    .fill(.white)
                    .shadow(color: .black.opacity(0.45), radius: 18, y: 16)
                    .opacity(focused ? 1 : 0)
            }
            .animation(.easeOut(duration: 0.15), value: focused)
    }
}

private struct PanelRow: View {
    var title: String
    var value: String? = nil
    var trailingSymbol: String? = nil

    var body: some View {
        HStack {
            Text(title).font(.system(size: 31, weight: .medium))
            Spacer()
            if let value {
                Text(value).font(.system(size: 31)).opacity(0.6)
            }
            if let trailingSymbol {
                Image(systemName: trailingSymbol).font(.system(size: 26, weight: .semibold))
            }
        }
    }
}
