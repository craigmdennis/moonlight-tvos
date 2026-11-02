import Foundation

/// One Steam game as Apollo reports it. `at` is Unix seconds.
public struct Game: Codable, Equatable, Sendable {
    public let appId: Int
    public let name: String
    public let at: Int

    public init(appId: Int, name: String, at: Int) {
        self.appId = appId
        self.name = name
        self.at = at
    }

    public var playedAt: Date { Date(timeIntervalSince1970: TimeInterval(at)) }
}

/// The full body of `GET /moonlight/steam`.
public struct SteamActivity: Codable, Equatable, Sendable {
    public var version: Int
    public var steamInstalled: Bool
    /// 64-bit Steam ID. Never shown in the interface.
    public var account: String?
    public var runningAppId: Int?
    public var runningName: String?
    public var lastPlayed: Game?
    public var recent: [Game]
    public var updatedAt: Int

    public init(
        version: Int = 1, steamInstalled: Bool = true, account: String? = nil,
        runningAppId: Int? = nil, runningName: String? = nil, lastPlayed: Game? = nil,
        recent: [Game] = [], updatedAt: Int = 0
    ) {
        self.version = version
        self.steamInstalled = steamInstalled
        self.account = account
        self.runningAppId = runningAppId
        self.runningName = runningName
        self.lastPlayed = lastPlayed
        self.recent = recent
        self.updatedAt = updatedAt
    }
}

/// Apollo answers with one of three shapes.
public enum ActivityResponse: Equatable, Sendable {
    /// The host switch or this client's permission withholds activity: `{"version":1,"sharing":false}`.
    case withheld
    /// Steam is not installed: `{"version":1,"steamInstalled":false}`.
    case noSteam
    case activity(SteamActivity)
}

extension ActivityResponse: Codable {
    private struct Probe: Decodable {
        var sharing: Bool?
        var steamInstalled: Bool?
    }

    public init(from decoder: Decoder) throws {
        let probe = try Probe(from: decoder)
        if probe.sharing == false {
            self = .withheld
        } else if probe.steamInstalled == false {
            self = .noSteam
        } else {
            self = .activity(try SteamActivity(from: decoder))
        }
    }

    public func encode(to encoder: Encoder) throws {
        switch self {
        case .withheld:
            var c = encoder.container(keyedBy: AnyKey.self)
            try c.encode(1, forKey: AnyKey("version"))
            try c.encode(false, forKey: AnyKey("sharing"))
        case .noSteam:
            var c = encoder.container(keyedBy: AnyKey.self)
            try c.encode(1, forKey: AnyKey("version"))
            try c.encode(false, forKey: AnyKey("steamInstalled"))
        case .activity(let a):
            try a.encode(to: encoder)
        }
    }
}

private struct AnyKey: CodingKey {
    var stringValue: String
    var intValue: Int? { nil }
    init(_ s: String) { stringValue = s }
    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { nil }
}
