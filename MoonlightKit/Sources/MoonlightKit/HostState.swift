import Foundation

/// Why a pairing attempt failed, as far as Apollo reports it.
public enum PairFailure: Equatable, Sendable {
    case incorrectPIN
    case anotherPairing
    case unknown
}

/// Why a start attempt failed.
public enum HostError: Equatable, Sendable {
    case wakeFailed
    case connectionFailed
    case streamDropped
    case notAllowed
    case noDisplay
    case other
}

/// Every state a host tile can be in. Taking over a stream and sleeping are cut from version 1.
public enum HostCardState: Equatable, Sendable {
    case offline
    case waking
    /// Asked to sleep; waiting to see whether the host goes offline.
    case sleeping
    case online
    case connecting
    case inUse
    /// Joining a stream another device is running ("Watch Alongside").
    case joining
    case notPaired
    case pairing
    case pairingFailed(PairFailure)
    case error(HostError)
}

public enum Badge: String, Equatable, Sendable {
    case online = "Online"
    case offline = "Offline"
    case inUse = "In Use"
    case error = "Error"
    case notPaired = "Not Paired"

    /// Colours from the brief, as hex.
    public var hex: UInt32 {
        switch self {
        case .online: 0x30D158
        case .offline: 0x8E8E93
        case .inUse: 0xBF5AF2
        case .error: 0xFF9F0A
        case .notPaired: 0xFFFFFF
        }
    }
}

public enum PressAction: Equatable, Sendable {
    /// Wake-on-LAN, then start Steam Big Picture.
    case wakeThenStart
    /// Start Steam Big Picture, or resume whatever runs.
    case start
    /// Ask: Watch Alongside or Cancel.
    case askWatchOrCancel
    case startPairing
    /// Nothing to do while something is in progress.
    case none
}

public extension HostCardState {
    var badge: Badge {
        switch self {
        case .offline, .waking: .offline
        case .online, .connecting, .sleeping: .online
        case .inUse, .joining: .inUse
        case .error: .error
        case .notPaired, .pairing, .pairingFailed: .notPaired
        }
    }

    var isPaired: Bool {
        switch self {
        case .notPaired, .pairing, .pairingFailed: false
        default: true
        }
    }

    /// True while a spinner replaces the badge.
    var isBusy: Bool {
        switch self {
        case .waking, .sleeping, .connecting, .joining, .pairing: true
        default: false
        }
    }

    var pressAction: PressAction {
        switch self {
        case .offline: .wakeThenStart
        case .online, .error: .start
        case .inUse: .askWatchOrCancel
        case .notPaired, .pairingFailed: .startPairing
        case .waking, .sleeping, .connecting, .joining, .pairing: .none
        }
    }
}

public enum HoldMenuItem: Hashable, Sendable {
    case openBigPicture
    case openDesktop
    /// Suspends the PC. Offered for a paired host, enabled only while it answers.
    case sleep
    case quit(appName: String)
    case testNetwork
    case removeComputer
}

/// Items of the hold menu. Holding the Add tile opens nothing.
public func holdMenu(for state: HostCardState, runningAppName: String?) -> [HoldMenuItem] {
    guard state.isPaired else { return [.testNetwork, .removeComputer] }
    var items: [HoldMenuItem] = [.openBigPicture, .openDesktop]
    if let name = runningAppName, state == .online || state == .inUse {
        items.append(.quit(appName: name))
    }
    // Kept in the menu for every paired host so the order never changes under the remote,
    // and disabled while the host cannot answer.
    return items + [.sleep, .testNetwork, .removeComputer]
}

/// Whether a hold menu item can be chosen. A disabled item stays visible but is skipped
/// when moving through the menu.
public func isEnabled(_ item: HoldMenuItem, in state: HostCardState) -> Bool {
    switch item {
    case .sleep: state == .online
    default: true
    }
}

/// Maps a `launch` or `resume` failure to a row of the error table. 403 also means "Encryption is
/// mandatory", so the message decides, not the code alone.
public func classifyLaunchFailure(statusCode: Int, message: String) -> HostError {
    if statusCode == 403, message == "Permission denied" { return .notAllowed }
    if statusCode == 503, message.hasPrefix("Failed to initialize video capture/encoding") { return .noDisplay }
    return .other
}
