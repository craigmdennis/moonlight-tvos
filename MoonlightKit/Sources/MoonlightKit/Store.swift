import Foundation

/// What the client asks of a paired host. The app adapts `HttpManager` to this; tests use a fake.
public protocol HostAPI: Sendable {
    /// `GET /moonlight/steam`.
    func activity() async throws -> ActivityResponse
    /// `GET /moonlight/steam/art/{appId}/{kind}`. `nil` on 404.
    func art(appId: Int, kind: ArtKind) async throws -> Data?
    /// `GET /moonlight/wallpaper`. `nil` on 404.
    func wallpaper() async throws -> Data?
}

/// Steam's content delivery network. `nil` on 404.
public protocol ArtCDN: Sendable {
    func data(from url: URL) async throws -> Data?
}

/// What a tile draws from, read from the cache. An asleep host looks the same as when last seen.
public struct HostCacheSnapshot: Equatable, Sendable {
    public var activity: ActivityResponse?
    public var fetchedAt: Date?
    public var hero: Data?
    public var wallpaper: Data?
}

/// Files for one host: the last activity JSON, the hero, the wallpaper, and the fetch time.
struct HostCacheFiles {
    let dir: URL

    private struct Meta: Codable {
        var fetchedAt: Date?
        var heroAppId: Int?
    }

    private var activityURL: URL { dir.appendingPathComponent("activity.json") }
    private var heroURL: URL { dir.appendingPathComponent("hero.img") }
    private var wallpaperURL: URL { dir.appendingPathComponent("wallpaper.img") }
    private var metaURL: URL { dir.appendingPathComponent("meta.json") }

    private func meta() -> Meta {
        (try? Data(contentsOf: metaURL)).flatMap { try? JSONDecoder.iso.decode(Meta.self, from: $0) } ?? Meta()
    }

    private func saveMeta(_ m: Meta) throws {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try JSONEncoder.iso.encode(m).write(to: metaURL, options: .atomic)
    }

    var heroAppId: Int? { meta().heroAppId }

    func snapshot() -> HostCacheSnapshot {
        HostCacheSnapshot(
            activity: (try? Data(contentsOf: activityURL)).flatMap { try? JSONDecoder().decode(ActivityResponse.self, from: $0) },
            fetchedAt: meta().fetchedAt,
            hero: try? Data(contentsOf: heroURL),
            wallpaper: try? Data(contentsOf: wallpaperURL))
    }

    func save(activity: ActivityResponse, at date: Date) throws {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try JSONEncoder().encode(activity).write(to: activityURL, options: .atomic)
        var m = meta()
        m.fetchedAt = date
        try saveMeta(m)
    }

    func saveHero(_ data: Data?, appId: Int?) throws {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        if let data {
            try data.write(to: heroURL, options: .atomic)
        } else {
            try? FileManager.default.removeItem(at: heroURL)
        }
        var m = meta()
        m.heroAppId = data == nil ? nil : appId
        try saveMeta(m)
    }

    func saveWallpaper(_ data: Data?) throws {
        if let data {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try data.write(to: wallpaperURL, options: .atomic)
        } else {
            try? FileManager.default.removeItem(at: wallpaperURL)
        }
    }

    func remove() {
        try? FileManager.default.removeItem(at: dir)
    }
}

private extension JSONEncoder {
    static var iso: JSONEncoder { let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601; return e }
}

private extension JSONDecoder {
    static var iso: JSONDecoder { let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601; return d }
}

/// Fetches Steam activity for one host and keeps the last answer on disk.
///
/// A failed fetch changes nothing. The cache is kept until the host is removed or reports a different game.
public actor SteamActivityStore {
    private let files: HostCacheFiles
    private let api: HostAPI
    private let cdn: ArtCDN
    private let now: @Sendable () -> Date

    public init(hostID: String, directory: URL, api: HostAPI, cdn: ArtCDN, now: @escaping @Sendable () -> Date = { Date() }) {
        self.files = HostCacheFiles(dir: directory.appendingPathComponent(hostID, isDirectory: true))
        self.api = api
        self.cdn = cdn
        self.now = now
    }

    public func snapshot() -> HostCacheSnapshot { files.snapshot() }

    /// Remove everything cached for this host.
    public func remove() { files.remove() }

    /// Fetch the activity and, when it changed, the art.
    /// - Parameter includeWallpaper: fetch the wallpaper too. Callers pass `true` when a host comes online or
    ///   the app returns to the foreground, not on the 60-second tick, because the file can be large.
    @discardableResult
    public func refresh(includeWallpaper: Bool) async -> HostCacheSnapshot {
        guard let response = try? await api.activity() else { return files.snapshot() }
        do {
            try files.save(activity: response, at: now())
            switch response {
            case .withheld:
                // The owner withholds activity from this client, so keep nothing.
                try files.saveHero(nil, appId: nil)
                try files.saveWallpaper(nil)
            case .noSteam:
                try files.saveHero(nil, appId: nil)
                if includeWallpaper { try await refreshWallpaper() }
            case .activity(let a):
                if let game = a.lastPlayed {
                    if files.heroAppId != game.appId || files.snapshot().hero == nil {
                        try files.saveHero(await fetchHero(appId: game.appId), appId: game.appId)
                    }
                    if includeWallpaper, files.snapshot().hero == nil { try await refreshWallpaper() }
                } else {
                    try files.saveHero(nil, appId: nil)
                    if includeWallpaper { try await refreshWallpaper() }
                }
            }
        } catch {
            // A write failure leaves whatever was cached.
        }
        return files.snapshot()
    }

    private func refreshWallpaper() async throws {
        if let data = try? await api.wallpaper() { try files.saveWallpaper(data) }
    }

    /// Apollo's copy first, then Steam's content delivery network. The capsule or header image stands in for a missing hero.
    private func fetchHero(appId: Int) async -> Data? {
        for kind in [ArtKind.hero, .capsule] {
            if let data = (try? await api.art(appId: appId, kind: kind)) ?? nil { return data }
            for url in steamCDNURLs(appId: appId, kind: kind) {
                if let data = (try? await cdn.data(from: url)) ?? nil { return data }
            }
        }
        return nil
    }
}
