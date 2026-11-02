import Foundation

public enum ArtKind: String, Sendable {
    case hero, logo, capsule
}

/// Where the full-screen backdrop can come from, in the order the client tries them.
public enum BackdropSource: Equatable, Sendable {
    case apollo(appId: Int, kind: ArtKind)
    case steamCDN(URL)
    /// The signed-in user's desktop wallpaper. Backdrop only, never the tile.
    case wallpaper
    /// The host colour with the desktopcomputer symbol.
    case colourAndSymbol
    /// One generic image bundled with the app, for hosts that have not paired.
    case bundledGeneric
}

/// Steam's content delivery network addresses for an app. Newer games use hashed paths, so a 404 is expected for some.
public func steamCDNURLs(appId: Int, kind: ArtKind) -> [URL] {
    let base = "https://cdn.cloudflare.steamstatic.com/steam/apps/\(appId)/"
    let files: [String] = switch kind {
    case .hero: ["library_hero.jpg"]
    case .logo: ["logo.png"]
    case .capsule: ["library_600x900.jpg", "header.jpg"]
    }
    return files.compactMap { URL(string: base + $0) }
}

public func backdropSources(paired: Bool, activity: ActivityResponse?) -> [BackdropSource] {
    guard paired else { return [.bundledGeneric] }
    switch activity {
    case .activity(let a)? where a.lastPlayed != nil:
        let id = a.lastPlayed!.appId
        return [.apollo(appId: id, kind: .hero)]
            + steamCDNURLs(appId: id, kind: .hero).map(BackdropSource.steamCDN)
            + [.apollo(appId: id, kind: .capsule)]
            + steamCDNURLs(appId: id, kind: .capsule).map(BackdropSource.steamCDN)
            + [.wallpaper, .colourAndSymbol]
    case .withheld?:
        return [.colourAndSymbol]
    default:
        return [.wallpaper, .colourAndSymbol]
    }
}
