import Foundation

public enum StatusIcon: Equatable, Sendable {
    case none, clock, controller, spinner, warning, lock, lockCross, plus
}

/// The single line above the row. One line, a dot divider between what happened and what to do next.
public struct StatusLine: Equatable, Sendable {
    public var icon: StatusIcon
    public var text: String

    public init(_ icon: StatusIcon, _ text: String) {
        self.icon = icon
        self.text = text
    }

    public static let addComputer = StatusLine(.plus, "Add a computer by entering its IP address or hostname")
    public static let lookingForComputers = StatusLine(.spinner, "Looking for computers on your network · Press OK to add manually")
    public static func lookingFor(_ address: String) -> StatusLine { StatusLine(.spinner, "Looking for \(address)…") }
    public static func notFound(_ address: String) -> StatusLine {
        StatusLine(.warning, "Couldn’t find a computer at \(address) · Check the address and try again")
    }
}

/// What the status line needs to know about one host.
public struct HostSnapshot: Equatable, Sendable {
    public var name: String
    public var state: HostCardState
    public var activity: ActivityResponse?
    /// Device streaming to the host. Empty or absent when Apollo withholds it.
    public var activeClient: String?
    /// Name of the Apollo app that runs, used when Steam reports no running game.
    public var currentAppName: String?
    public var pinSecondsLeft: Int?
    /// Result of the last Test Network or a failed one-off action, shown until it expires.
    public var notice: String?

    public init(
        name: String, state: HostCardState, activity: ActivityResponse? = nil, activeClient: String? = nil,
        currentAppName: String? = nil, pinSecondsLeft: Int? = nil, notice: String? = nil
    ) {
        self.name = name
        self.state = state
        self.activity = activity
        self.activeClient = activeClient
        self.currentAppName = currentAppName
        self.pinSecondsLeft = pinSecondsLeft
        self.notice = notice
    }
}

public func errorText(_ error: HostError) -> String {
    switch error {
    case .wakeFailed: "Couldn’t wake the PC · Check that Wake-on-LAN is turned on"
    case .connectionFailed: "Couldn’t connect to the PC · Press OK to try again"
    case .streamDropped: "The stream ended unexpectedly · Press OK to reconnect"
    case .notAllowed: "Apollo hasn’t allowed this Apple TV to start apps · Change it in Apollo on the PC"
    case .noDisplay: "The PC has no display to stream · Turn on a virtual display in Apollo"
    case .other: "Couldn’t reach this computer · Press OK to try again"
    }
}

public func statusLine(for host: HostSnapshot, now: Date = Date(), locale: Locale = Locale(identifier: "en_US")) -> StatusLine {
    switch host.state {
    case .waking: return StatusLine(.spinner, "Waking \(host.name)…")
    case .sleeping: return StatusLine(.spinner, "Sleeping…")
    case .connecting: return StatusLine(.spinner, "Starting Steam Big Picture…")
    case .joining: return StatusLine(.spinner, "Joining the stream…")
    case .pairing:
        return StatusLine(.spinner, "Enter the PIN in Apollo on the PC · New PIN in \(clockText(seconds: host.pinSecondsLeft ?? 0))")
    case .pairingFailed(let reason):
        let why = switch reason {
        case .incorrectPIN: "Incorrect PIN"
        case .anotherPairing: "The PC is pairing with another device"
        case .unknown: "Pairing didn’t finish"
        }
        return StatusLine(.lockCross, "\(why) · Press OK to try again")
    case .notPaired: return StatusLine(.lock, "Found on your network · Not paired with this Apple TV yet")
    case .error(let e): return StatusLine(.warning, errorText(e))
    case .offline, .online, .inUse:
        if let notice = host.notice { return StatusLine(.none, notice) }
        if host.state == .inUse { return inUseLine(host) }
        return activityLine(host.activity, now: now, locale: locale)
    }
}

private func inUseLine(_ host: HostSnapshot) -> StatusLine {
    var game: String?
    if case .activity(let a)? = host.activity { game = a.runningName }
    game = game ?? host.currentAppName
    let device = host.activeClient.flatMap { $0.isEmpty ? nil : $0 }
    switch (game, device) {
    case let (g?, d?): return StatusLine(.controller, "Currently playing \(g) · \(d)")
    case let (g?, nil): return StatusLine(.controller, "Currently playing \(g)")
    case let (nil, d?): return StatusLine(.controller, "In use by \(d)")
    case (nil, nil): return StatusLine(.controller, "In use by another device")
    }
}

private func activityLine(_ activity: ActivityResponse?, now: Date, locale: Locale) -> StatusLine {
    switch activity {
    case .activity(let a)?:
        guard let game = a.lastPlayed else { return StatusLine(.none, "") }
        return StatusLine(.clock, "Last played \(game.name) · \(relativeWhen(game.playedAt, now: now, locale: locale))")
    case .noSteam?: return StatusLine(.none, "No Steam library on this PC")
    case .withheld?, nil: return StatusLine(.none, "")
    }
}
