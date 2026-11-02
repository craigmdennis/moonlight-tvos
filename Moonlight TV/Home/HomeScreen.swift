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
    @State private var showAdd = false
    @State private var address = ""

    var body: some View {
        ComputersView(
            hosts: model.tiles, addLine: model.addLine, pin: model.pin,
            onPress: model.press, onMenu: model.menu,
            onAdd: {
                // Prefilled with the Apple TV's own network, so usually only the last number is typed
                address = HomeModel.subnetPrefix()
                showAdd = true
            },
            onSettings: { showSettings = true },
            onFocus: model.focusChanged)
        .sheet(isPresented: $showSettings) {
            StreamSettingsView()
        }
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

    private func present<T>(_ item: Binding<T?>) -> Binding<Bool> {
        Binding(get: { item.wrappedValue != nil }, set: { if !$0 { item.wrappedValue = nil } })
    }
}

/// What people change between sessions. The values are stored under the keys TemporarySettings reads,
/// so the next stream picks them up. Set-once options live in the Settings app.
struct StreamSettingsView: View {
    @AppStorage("streamResolution") private var resolution = 4
    @AppStorage("framerate") private var framerate = 60
    @AppStorage("bitrate") private var bitrate = 0
    @AppStorage("enableHdr") private var hdr = false
    @AppStorage("statsOverlay") private var stats = false

    var body: some View {
        NavigationStack {
            Form {
                Picker("Resolution", selection: $resolution) {
                    Text("Match TV").tag(4)
                    Text("720p").tag(0)
                    Text("1080p").tag(1)
                    Text("1440p").tag(3)
                    Text("4K").tag(2)
                }
                Picker("Frame Rate", selection: $framerate) {
                    Text("30 fps").tag(30)
                    Text("60 fps").tag(60)
                }
                Picker("Bitrate", selection: $bitrate) {
                    Text("Automatic").tag(0)
                    ForEach([10, 20, 50, 80, 100, 150], id: \.self) { mbps in
                        Text("\(mbps) Mbps").tag(mbps * 1000)
                    }
                }
                Toggle("HDR", isOn: $hdr)
                Toggle("Statistics Overlay", isOn: $stats)
                Section {
                    Button("More in Settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    }
                } footer: {
                    Text("Codec, audio, controllers and other set-once options are in the Apple TV Settings app.")
                }
            }
            .navigationTitle("Stream Settings")
        }
    }
}
