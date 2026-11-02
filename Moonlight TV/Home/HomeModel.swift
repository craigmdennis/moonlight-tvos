//
//  HomeModel.swift
//  Moonlight TV
//
//  State behind the Apple TV home screen. It drives the Objective-C core
//  (discovery, pairing, Wake-on-LAN, launch) and turns it into the tile models
//  MoonlightKit draws.
//

import AVFoundation
import Combine
import CryptoKit
import UIKit
import VideoToolbox
import MoonlightKit

/// Reads the Apollo fork's endpoints through `HttpManager`, which holds the pairing certificates.
struct HttpManagerHostAPI: HostAPI, @unchecked Sendable {
    let host: TemporaryHost

    private func fetch(_ makeRequest: @escaping (HttpManager) -> URLRequest?) async -> Data {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                let manager = HttpManager(host: host)!
                let response = AppAssetResponse()
                manager.executeRequestSynchronously(HttpRequest(for: response, with: makeRequest(manager)))
                continuation.resume(returning: response.data ?? Data())
            }
        }
    }

    // A host without the Apollo fork answers with a 404 XML document, which fails to decode
    func activity() async throws -> ActivityResponse {
        try JSONDecoder().decode(ActivityResponse.self, from: await fetch { $0.newSteamActivityRequest() })
    }

    // Apollo sends an empty body with its 404
    func art(appId: Int, kind: ArtKind) async throws -> Data? {
        let data = await fetch { $0.newSteamArtRequest(withAppId: String(appId), kind: kind.rawValue) }
        return UIImage(data: data) == nil ? nil : data
    }

    func wallpaper() async throws -> Data? {
        let data = await fetch { $0.newWallpaperRequest() }
        return UIImage(data: data) == nil ? nil : data
    }
}

/// PairManager calls back on its own thread with no way to tell attempts apart,
/// so each attempt gets its own forwarder carrying a generation number.
final class PairForwarder: NSObject, PairCallback {
    weak var model: HomeModel?
    let generation: Int

    init(model: HomeModel, generation: Int) {
        self.model = model
        self.generation = generation
    }

    private func send(_ block: @escaping @MainActor (HomeModel) -> Void) {
        DispatchQueue.main.async { [weak model] in
            if let model { block(model) }
        }
    }

    func startPairing(_ PIN: String!) { let g = generation; send { $0.pairing(g, pin: PIN) } }
    func pairSuccessful(_ serverCert: Data!) { let g = generation; send { $0.pairing(g, succeeded: serverCert) } }
    func pairFailed(_ message: String!) { let g = generation; send { $0.pairing(g, failed: message ?? "") } }
    func alreadyPaired() { let g = generation; send { $0.pairing(g, succeeded: nil) } }
}

@MainActor
final class HomeModel: NSObject, ObservableObject, DiscoveryCallback {
    enum Phase: Equatable {
        case idle, waking, connecting, joining, pairing
        case pairFailed(PairFailure)
        case error(HostError)
    }

    struct Entry {
        var phase = Phase.idle
        var networkTest: String?
        var appNames: [String: String] = [:]
        var lastState: State = .unknown
        var lastFetch: Date?
        var cache: HostCacheSnapshot?
    }

    @Published private(set) var tiles: [HostTileModel] = []
    @Published private(set) var addLine = StatusLine.lookingForComputers
    @Published private(set) var pin: String?
    @Published var inUseHost: HostTileModel?
    @Published var removeHost: HostTileModel?

    /// The view controller starts the stream; the string is the host's id.
    var startStream: ((StreamConfiguration, String) -> Void)?

    private var hosts: [String: TemporaryHost] = [:]
    private var entries: [String: Entry] = [:]
    private var stores: [String: SteamActivityStore] = [:]
    private var discovery: DiscoveryManager!
    private let clientCert: Data
    private let operations = OperationQueue()
    private var timer: Timer?
    private var focusedId: String?
    private var autoPair: Task<Void, Never>?
    private var addQuery: String?
    private var addFailed: String?

    private var pairOperation: PairManager?
    private var pairId: String?
    private var pairGeneration = 0
    private var pinUntil = Date()

    private static let wakeTimeout: TimeInterval = 60
    // The pair request's own timeout (EXTRA_LONG_TIMEOUT_SEC); the brief leaves the real lifetime open
    private static let pinLife: TimeInterval = 180
    private static let steamRefresh: TimeInterval = 60
    private static let cacheDirectory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("SteamActivity")

    override init() {
        CryptoManager.generateKeyPairUsingSSL()
        _ = IdManager.getUniqueId()
        clientCert = CryptoManager.readCertFromFile()
        super.init()
        for case let host as TemporaryHost in DataManager().getHosts() {
            if host.activeAddress == nil {
                host.activeAddress = host.localAddress ?? host.externalAddress ?? host.address ?? host.ipv6Address
            }
            hosts[host.uuid] = host
        }
        discovery = DiscoveryManager(hosts: Array(hosts.values), andCallback: self)
        rebuild()
    }

    // MARK: Lifecycle

    func appeared() {
        // Back from a stream: anything still starting has finished, unless the stream reported a failure
        for (id, entry) in entries where entry.phase == .connecting || entry.phase == .joining {
            entries[id]?.phase = .idle
        }
        for id in entries.keys {
            entries[id]?.lastFetch = nil
        }
        discovery.resetDiscoveryState()
        if pairOperation == nil {
            discovery.startDiscovery()
        }
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        tick()
    }

    func disappeared() {
        timer?.invalidate()
        timer = nil
        discovery.stopDiscovery()
    }

    nonisolated func updateAllHosts(_ hostList: [Any]!) {
        let found = (hostList ?? []).compactMap { $0 as? TemporaryHost }
        DispatchQueue.main.async {
            self.hosts = Dictionary(found.filter { !$0.uuid.isEmpty }.map { ($0.uuid, $0) }, uniquingKeysWith: { a, _ in a })
            self.rebuild()
        }
    }

    private func tick() {
        for (id, host) in hosts {
            guard var entry = entries[id] else { continue }
            let cameOnline = host.state == .online && entry.lastState != .online
            entry.lastState = host.state
            let foreground = entry.lastFetch == nil
            let stale = foreground || Date().timeIntervalSince(entry.lastFetch!) >= Self.steamRefresh
            entries[id] = entry
            if host.state == .online, isPaired(host), cameOnline || stale {
                // The wallpaper is large, so only when the PC comes online or the app returns
                refreshSteam(id, wallpaper: cameOnline || foreground)
            }
        }
        rebuild()
    }

    // MARK: Building tiles

    private func isPaired(_ host: TemporaryHost) -> Bool {
        host.pairState == .paired || (host.pairState == .unknown && host.serverCert != nil)
    }

    private func appRunning(_ host: TemporaryHost) -> Bool {
        host.currentGame != nil && host.currentGame != "0"
    }

    private func cardState(_ host: TemporaryHost, _ entry: Entry) -> HostCardState {
        switch entry.phase {
        case .waking: return .waking
        case .connecting: return .connecting
        case .joining: return .joining
        case .pairing: return .pairing
        case .pairFailed(let reason): return .pairingFailed(reason)
        case .error(let error): return .error(error)
        case .idle:
            if !isPaired(host) { return .notPaired }
            guard host.state == .online else { return .offline }
            // In Use only while another device streams; an app left running from an
            // earlier session of this TV just resumes
            return host.activeStreamClient != nil ? .inUse : .online
        }
    }

    private static let palette: [UInt32] = [0x3A5BA0, 0x2E7A68, 0x4A4A52, 0x2E3440, 0x3A3A44]

    private func rebuild() {
        for id in hosts.keys where entries[id] == nil {
            entries[id] = Entry()
            Task { await loadCache(id) }
        }
        for id in entries.keys where hosts[id] == nil {
            entries[id] = nil
        }

        // Computers not paired yet go last, just before Add Computer
        let sorted = hosts.values.sorted { a, b in
            if isPaired(a) != isPaired(b) { return isPaired(a) }
            return a.compareName(b) == .orderedAscending
        }

        let pinLeft = max(0, Int(pinUntil.timeIntervalSinceNow.rounded(.up)))
        tiles = sorted.map { host in
            let entry = entries[host.uuid] ?? Entry()
            let state = cardState(host, entry)
            let paired = isPaired(host)
            let runningApp = appRunning(host) ? entry.appNames[host.currentGame ?? ""] ?? "Running App" : nil
            let snapshot = HostSnapshot(name: host.name, state: state, activity: entry.cache?.activity,
                                        activeClient: host.activeStreamClient, currentAppName: runningApp,
                                        pinSecondsLeft: pairId == host.uuid ? pinLeft : nil, networkTest: entry.networkTest)
            let hash = host.uuid.unicodeScalars.reduce(0) { $0 + Int($1.value) }
            return HostTileModel(id: host.uuid, name: host.name, state: state,
                                 tintHex: Self.palette[hash % Self.palette.count],
                                 backdrop: paired ? entry.cache?.hero ?? entry.cache?.wallpaper : nil,
                                 tileArt: paired ? entry.cache?.hero : nil,
                                 line: statusLine(for: snapshot),
                                 menu: holdMenu(for: state, runningAppName: runningApp))
        }

        if let query = addQuery {
            addLine = .lookingFor(query)
        } else if let failed = addFailed {
            addLine = .notFound(failed)
        } else {
            addLine = hosts.isEmpty ? .lookingForComputers : .addComputer
        }
        pin = pairId != nil && pinLeft > 0 ? pin : nil
    }

    private func store(_ id: String) -> SteamActivityStore? {
        guard let host = hosts[id] else { return nil }
        if let store = stores[id] { return store }
        // The id comes from the host's own reply, so it never names a folder directly
        let folder = SHA256.hash(data: Data(id.utf8)).map { String(format: "%02x", $0) }.joined()
        let store = SteamActivityStore(hostID: folder, directory: Self.cacheDirectory, api: HttpManagerHostAPI(host: host), cdn: URLSessionCDN())
        stores[id] = store
        return store
    }

    private func loadCache(_ id: String) async {
        guard let store = store(id) else { return }
        let snapshot = await store.snapshot()
        entries[id]?.cache = snapshot
        rebuild()
    }

    private func refreshSteam(_ id: String, wallpaper: Bool) {
        guard let store = store(id) else { return }
        entries[id]?.lastFetch = Date()
        Task {
            let snapshot = await store.refresh(includeWallpaper: wallpaper)
            entries[id]?.cache = snapshot
            rebuild()
        }
    }

    // MARK: Focus and pairing

    func focusChanged(_ id: String?) {
        guard id != focusedId else { return }
        let previous = focusedId
        focusedId = id

        // Moving off a computer that is pairing cancels the request
        if let previous, previous == pairId {
            cancelPairing()
        }

        // Resting on an unpaired computer starts pairing, so its PIN is on screen
        autoPair?.cancel()
        guard let id, let host = hosts[id], !isPaired(host), entries[id]?.phase == .idle else { return }
        autoPair = Task {
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled, focusedId == id, entries[id]?.phase == .idle else { return }
            startPairing(id)
        }
    }

    private func startPairing(_ id: String) {
        guard let host = hosts[id], host.state == .online, pairOperation == nil else { return }
        entries[id]?.phase = .pairing
        pairId = id
        pin = nil
        pinUntil = Date().addingTimeInterval(Self.pinLife)
        pairGeneration += 1

        let operation = PairManager(manager: HttpManager(host: host), clientCert: clientCert, callback: PairForwarder(model: self, generation: pairGeneration))!
        pairOperation = operation
        // Polling the server while pairing confuses it, so discovery pauses meanwhile
        let discovery = discovery!
        let queue = operations
        DispatchQueue.global().async {
            discovery.stopDiscoveryBlocking()
            queue.addOperation(operation)
        }
        rebuild()
    }

    private func endPairing() {
        pairOperation = nil
        pairId = nil
        pin = nil
        discovery.startDiscovery()
    }

    private func cancelPairing() {
        if let id = pairId, entries[id]?.phase == .pairing {
            entries[id]?.phase = .idle
        }
        pairGeneration += 1
        pairOperation?.cancel()
        endPairing()
        rebuild()
    }

    func pairing(_ generation: Int, pin newPin: String) {
        guard generation == pairGeneration else { return }
        pin = newPin
        pinUntil = Date().addingTimeInterval(Self.pinLife)
        rebuild()
    }

    func pairing(_ generation: Int, succeeded cert: Data?) {
        guard generation == pairGeneration, let id = pairId, let host = hosts[id] else { return }
        endPairing()
        if let cert {
            host.serverCert = cert
        }
        host.pairState = .paired
        entries[id]?.phase = .idle
        DataManager().update(host)
        refreshSteam(id, wallpaper: true)
        rebuild()
    }

    func pairing(_ generation: Int, failed message: String) {
        guard generation == pairGeneration, let id = pairId else { return }
        endPairing()

        // The PIN expired unanswered: show a fresh one while the tile keeps focus
        if message.lowercased().contains("timed out"), focusedId == id {
            entries[id]?.phase = .idle
            startPairing(id)
            return
        }
        let reason: PairFailure = message == "Incorrect PIN" ? .incorrectPIN : message.contains("already in progress") ? .anotherPairing : .unknown
        entries[id]?.phase = .pairFailed(reason)
        rebuild()
    }

    // MARK: Actions

    func press(_ id: String) {
        guard let host = hosts[id], let entry = entries[id] else { return }
        switch cardState(host, entry).pressAction {
        case .wakeThenStart: wake(id, desktop: false)
        case .start: connect(id, desktop: false, viewOnly: false)
        case .askWatchOrCancel: inUseHost = tiles.first { $0.id == id }
        case .startPairing:
            entries[id]?.phase = .idle
            startPairing(id)
        case .none: break
        }
    }

    func menu(_ id: String, _ item: HoldMenuItem) {
        guard let host = hosts[id] else { return }
        switch item {
        case .openBigPicture, .openDesktop:
            let desktop = item == .openDesktop
            if host.state == .online {
                connect(id, desktop: desktop, viewOnly: false)
            } else {
                wake(id, desktop: desktop)
            }
        case .quit: quit(id)
        case .testNetwork: testNetwork(id)
        case .removeComputer: removeHost = tiles.first { $0.id == id }
        }
    }

    func watchAlongside(_ id: String) {
        connect(id, desktop: false, viewOnly: true)
    }

    private func fail(_ id: String, _ error: HostError) {
        entries[id]?.phase = .error(error)
        rebuild()
    }

    private func wake(_ id: String, desktop: Bool) {
        guard let host = hosts[id] else { return }
        // A host never seen online has no MAC address to wake
        guard let mac = host.mac, mac != "00:00:00:00:00:00" else { return fail(id, .wakeFailed) }
        entries[id]?.phase = .waking
        rebuild()
        DispatchQueue.global().async { WakeOnLanManager.wake(host) }

        // Discovery keeps polling the host, so this only watches its state
        Task {
            let deadline = Date().addingTimeInterval(Self.wakeTimeout)
            while Date() < deadline {
                try? await Task.sleep(for: .seconds(1))
                guard entries[id]?.phase == .waking else { return }
                if host.state == .online {
                    connect(id, desktop: desktop, viewOnly: false)
                    return
                }
            }
            if entries[id]?.phase == .waking { fail(id, .wakeFailed) }
        }
    }

    private func connect(_ id: String, desktop: Bool, viewOnly: Bool) {
        guard let host = hosts[id] else { return }
        entries[id]?.phase = viewOnly ? .joining : .connecting
        entries[id]?.networkTest = nil
        rebuild()

        let discovery = discovery!
        DispatchQueue.global().async {
            discovery.pauseDiscovery(for: host)
            let response = ConnectionHelper.getAppList(for: host)
            discovery.resumeDiscovery(for: host)
            let apps = (response?.getAppList() as? Set<TemporaryApp>) ?? []
            let ok = response?.isStatusOk() ?? false
            let message = response?.statusMessage ?? ""
            DispatchQueue.main.async {
                guard self.entries[id]?.phase == .connecting || self.entries[id]?.phase == .joining else { return }
                guard ok, !apps.isEmpty else {
                    return self.fail(id, message == "Permission denied" ? .notAllowed : .other)
                }
                self.entries[id]?.appNames = Dictionary(apps.compactMap { app in app.id.map { ($0, app.name ?? "") } }, uniquingKeysWith: { a, _ in a })
                let app = Self.appToStream(Array(apps), host: host, desktop: desktop)
                self.startStream?(Self.streamConfig(host: host, app: app, viewOnly: viewOnly), id)
            }
        }
    }

    /// No app list on screen: Play starts Steam Big Picture, or resumes whatever already runs
    private static func appToStream(_ apps: [TemporaryApp], host: TemporaryHost, desktop: Bool) -> TemporaryApp {
        let sorted = apps.sorted { $0.compareName($1) == .orderedAscending }
        if let running = sorted.first(where: { $0.id == host.currentGame && host.currentGame != "0" }) {
            return running
        }
        let wanted = desktop ? "Desktop" : "Steam Big Picture"
        return sorted.first { $0.name?.caseInsensitiveCompare(wanted) == .orderedSame } ?? sorted[0]
    }

    private static func streamConfig(host: TemporaryHost, app: TemporaryApp, viewOnly: Bool) -> StreamConfiguration {
        let config = StreamConfiguration()
        let settings = DataManager().getSettings()!
        config.host = host.activeAddress
        config.httpsPort = host.httpsPort
        config.appID = app.id
        config.appName = app.name
        config.serverCert = host.serverCert
        config.viewOnly = viewOnly
        config.frameRate = min(settings.framerate.int32Value, Int32(UIScreen.main.maximumFramesPerSecond))
        config.width = settings.width.int32Value
        config.height = settings.height.int32Value

        // Don't allow streaming 4K on the Apple TV HD
        var system = utsname()
        uname(&system)
        let machine = withUnsafeBytes(of: &system.machine) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
        if machine == "AppleTV5,3", config.height >= 2160 {
            config.width = 1920
            config.height = 1080
        }

        config.bitRate = settings.bitrate.int32Value
        config.optimizeGameSettings = settings.optimizeGames
        config.playAudioOnPC = settings.playAudioOnPC
        config.useFramePacing = settings.useFramePacing
        config.swapABXYButtons = settings.swapABXYButtons
        config.multiController = settings.multiController
        config.gamepadMask = ControllerSupport.getConnectedGamepadMask(config)

        let channels = min(settings.audioConfig.intValue, AVAudioSession.sharedInstance().maximumOutputNumberOfChannels)
        // AUDIO_CONFIGURATION_* in Limelight.h, which Swift can't import: (mask << 16) | (channels << 8) | 0xCA
        func audio(_ count: Int32, _ mask: Int32) -> Int32 { (mask << 16) | (count << 8) | 0xCA }
        config.audioConfiguration = channels >= 8 ? audio(8, 0x63F) : channels >= 6 ? audio(6, 0x3F) : audio(2, 0x3)
        config.serverCodecModeSupport = host.serverCodecModeSupport

        // TemporarySettings' codec enum is anonymous, so read the stored value: 1 is H.264, 3 is AV1
        let codec = UserDefaults.standard.integer(forKey: "preferredCodec")
        var formats = VIDEO_FORMAT_H264
        let hevc = VTIsHardwareDecodeSupported(kCMVideoCodecType_HEVC)
        if codec != 1, hevc {
            formats |= VIDEO_FORMAT_H265
        }
        if codec == 3, VTIsHardwareDecodeSupported(kCMVideoCodecType_AV1) {
            formats |= VIDEO_FORMAT_AV1_MAIN8
        }
        if settings.enableHdr, hevc, AVPlayer.availableHDRModes.contains(.hdr10) {
            formats |= VIDEO_FORMAT_H265 | VIDEO_FORMAT_H265_MAIN10
            if formats & VIDEO_FORMAT_MASK_AV1 != 0 {
                formats |= VIDEO_FORMAT_AV1_MAIN10
            }
        }
        config.supportedVideoFormats = Int32(formats)
        return config
    }

    func streamFailed(_ id: String, kind: String, message: String?) {
        // Apollo reports these as 403 "Permission denied" and 503 with its capture message
        let message = message ?? ""
        let error: HostError = kind == "dropped" ? .streamDropped
            : message == "Permission denied" ? .notAllowed
            : message.hasPrefix("Failed to initialize video capture") ? .noDisplay
            : .connectionFailed
        fail(id, error)
    }

    private func quit(_ id: String) {
        guard let host = hosts[id] else { return }
        let discovery = discovery!
        DispatchQueue.global().async {
            let manager = HttpManager(host: host)!
            let response = HttpResponse()
            discovery.pauseDiscovery(for: host)
            manager.executeRequestSynchronously(HttpRequest(for: response, with: manager.newQuitAppRequest()))
            discovery.resumeDiscovery(for: host)
            let ok = response.isStatusOk()
            let message = response.statusMessage ?? ""
            DispatchQueue.main.async {
                if ok {
                    host.currentGame = "0"
                    host.activeStreamClient = nil
                    self.rebuild()
                } else {
                    self.fail(id, message == "Permission denied" ? .notAllowed : .other)
                }
            }
        }
    }

    /// Moonlight's port test against its own test servers; the result shows in the status line
    private func testNetwork(_ id: String) {
        DispatchQueue.global().async {
            let result = LiTestClientConnectivity("ios.conntest.moonlight-stream.org", 443, UInt32(ML_PORT_FLAG_ALL))
            var text: String
            if result == 0 {
                text = "Network test: This network isn’t blocking Moonlight"
            } else if result == ML_TEST_RESULT_INCONCLUSIVE {
                text = "Network test: Couldn’t reach the test servers · Check your internet connection"
            } else {
                var ports = [CChar](repeating: 0, count: 512)
                LiStringifyPortFlags(result, ", ", &ports, Int32(ports.count))
                text = "Network test: This network blocks \(String(cString: ports))"
            }
            DispatchQueue.main.async {
                self.entries[id]?.networkTest = text
                self.rebuild()
                Task {
                    try? await Task.sleep(for: .seconds(5))
                    if self.entries[id]?.networkTest == text {
                        self.entries[id]?.networkTest = nil
                        self.rebuild()
                    }
                }
            }
        }
    }

    func remove(_ id: String) {
        guard let host = hosts[id] else { return }
        if pairId == id { cancelPairing() }
        discovery.removeHost(fromDiscovery: host)
        DataManager().remove(host)
        let store = stores.removeValue(forKey: id)
        Task { await store?.remove() }
        hosts[id] = nil
        rebuild()
    }

    /// The Apple TV's own network, so usually only the last number needs typing
    static func subnetPrefix() -> String {
        var addresses: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&addresses) == 0, let first = addresses else { return "" }
        defer { freeifaddrs(addresses) }
        for pointer in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let a = pointer.pointee
            guard let address = a.ifa_addr, address.pointee.sa_family == UInt8(AF_INET),
                  String(cString: a.ifa_name).hasPrefix("en") else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            getnameinfo(address, socklen_t(address.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST)
            let ip = String(cString: host)
            if let dot = ip.lastIndex(of: ".") {
                return String(ip[...dot])
            }
        }
        return ""
    }

    func addComputer(_ address: String) {
        let address = address.trimmingCharacters(in: .whitespaces)
        guard !address.isEmpty else { return }
        addQuery = address
        addFailed = nil
        rebuild()
        let discovery = discovery!
        DispatchQueue.global(qos: .userInitiated).async {
            discovery.discoverHost(address) { host, _ in
                DispatchQueue.main.async {
                    guard self.addQuery == address else { return }
                    self.addQuery = nil
                    if let host, !host.uuid.isEmpty {
                        self.hosts[host.uuid] = host
                        DataManager().update(host)
                    } else {
                        self.addFailed = address
                    }
                    self.rebuild()
                }
            }
        }
    }
}
