import Foundation
import Testing
@testable import MoonlightKit

@Suite struct ActivityResponseTests {
    @Test func decodesTheFullObject() throws {
        let json = """
        {"version":1,"steamInstalled":true,"account":"76561198000000000","runningAppId":null,"runningName":null,
         "lastPlayed":{"appId":100,"name":"Control Resonant","at":1793500000},
         "recent":[{"appId":100,"name":"Control Resonant","at":1793500000}],"updatedAt":1793540000}
        """
        let r = try JSONDecoder().decode(ActivityResponse.self, from: Data(json.utf8))
        guard case .activity(let a) = r else { Issue.record("expected activity"); return }
        #expect(a.lastPlayed == Game(appId: 100, name: "Control Resonant", at: 1_793_500_000))
        #expect(a.runningAppId == nil)
        #expect(a.account == "76561198000000000")
    }

    @Test func decodesTheTwoShortShapes() throws {
        let withheld = try JSONDecoder().decode(ActivityResponse.self, from: Data(#"{"version":1,"sharing":false}"#.utf8))
        let noSteam = try JSONDecoder().decode(ActivityResponse.self, from: Data(#"{"version":1,"steamInstalled":false}"#.utf8))
        #expect(withheld == .withheld)
        #expect(noSteam == .noSteam)
    }

    @Test func decodesANullLastPlayedAndNullAccount() throws {
        let json = #"{"version":1,"steamInstalled":true,"account":null,"runningAppId":null,"runningName":null,"lastPlayed":null,"recent":[],"updatedAt":5}"#
        let r = try JSONDecoder().decode(ActivityResponse.self, from: Data(json.utf8))
        guard case .activity(let a) = r else { Issue.record("expected activity"); return }
        #expect(a.lastPlayed == nil)
        #expect(a.account == nil)
    }

    @Test func roundTripsEveryShape() throws {
        let shapes: [ActivityResponse] = [
            .withheld, .noSteam,
            .activity(SteamActivity(account: "1", runningAppId: 7, runningName: "X", lastPlayed: Game(appId: 7, name: "X", at: 9), recent: [Game(appId: 7, name: "X", at: 9)], updatedAt: 10)),
        ]
        for shape in shapes {
            let data = try JSONEncoder().encode(shape)
            #expect(try JSONDecoder().decode(ActivityResponse.self, from: data) == shape)
        }
    }

    @Test func rejectsABodyThatIsNotActivity() {
        #expect(throws: (any Error).self) {
            try JSONDecoder().decode(ActivityResponse.self, from: Data(#"{"hello":"world"}"#.utf8))
        }
    }
}

@Suite struct TextTests {
    let now = Date(timeIntervalSince1970: 1_793_540_000)

    @Test func capitalisesTheRelativeTime() {
        #expect(relativeWhen(now.addingTimeInterval(-86_400), now: now) == "Yesterday")
        #expect(relativeWhen(now.addingTimeInterval(-7_200), now: now) == "2 hours ago")
    }

    @Test func formatsTheCountdown() {
        #expect(clockText(seconds: 30) == "0:30")
        #expect(clockText(seconds: 125) == "2:05")
        #expect(clockText(seconds: -4) == "0:00")
    }
}

@Suite struct HostStateTests {
    @Test func mapsStatesToBadges() {
        #expect(HostCardState.offline.badge == .offline)
        #expect(HostCardState.waking.badge == .offline)
        #expect(HostCardState.online.badge == .online)
        #expect(HostCardState.connecting.badge == .online)
        #expect(HostCardState.inUse.badge == .inUse)
        #expect(HostCardState.joining.badge == .inUse)
        #expect(HostCardState.error(.other).badge == .error)
        #expect(HostCardState.pairing.badge == .notPaired)
        #expect(HostCardState.pairingFailed(.incorrectPIN).badge == .notPaired)
        #expect(Badge.inUse.hex == 0xBF5AF2)
    }

    @Test func choosesThePressAction() {
        #expect(HostCardState.offline.pressAction == .wakeThenStart)
        #expect(HostCardState.online.pressAction == .start)
        #expect(HostCardState.error(.connectionFailed).pressAction == .start)
        #expect(HostCardState.inUse.pressAction == .askWatchOrCancel)
        #expect(HostCardState.notPaired.pressAction == .startPairing)
        #expect(HostCardState.pairingFailed(.unknown).pressAction == .startPairing)
        #expect(HostCardState.waking.pressAction == PressAction.none)
        #expect(HostCardState.pairing.pressAction == PressAction.none)
    }

    @Test func buildsTheHoldMenu() {
        #expect(holdMenu(for: .online, runningAppName: nil) == [.openBigPicture, .openDesktop, .sleep, .testNetwork, .removeComputer])
        #expect(holdMenu(for: .online, runningAppName: "Steam Big Picture") == [.openBigPicture, .openDesktop, .quit(appName: "Steam Big Picture"), .sleep, .testNetwork, .removeComputer])
        #expect(holdMenu(for: .inUse, runningAppName: "Desktop").contains(.quit(appName: "Desktop")))
        #expect(!holdMenu(for: .offline, runningAppName: "x").contains(.quit(appName: "x")))
        #expect(holdMenu(for: .notPaired, runningAppName: nil) == [.testNetwork, .removeComputer])
    }

    @Test func sleepIsOfferedButDisabledWhileTheHostCannotAnswer() {
        // An offline PC keeps the item, so the menu never reorders, but it cannot be chosen
        #expect(holdMenu(for: .offline, runningAppName: nil).contains(.sleep))
        #expect(!isEnabled(.sleep, in: .offline))
        #expect(!isEnabled(.sleep, in: .waking))
        #expect(!isEnabled(.sleep, in: .inUse))
        #expect(!isEnabled(.sleep, in: .error(.other)))
        #expect(isEnabled(.sleep, in: .online))

        // Everything else stays choosable
        for state in [HostCardState.offline, .inUse, .error(.other)] {
            #expect(isEnabled(.openBigPicture, in: state))
            #expect(isEnabled(.testNetwork, in: state))
        }
    }

    @Test func classifiesLaunchFailuresByCodeAndMessage() {
        #expect(classifyLaunchFailure(statusCode: 403, message: "Permission denied") == .notAllowed)
        #expect(classifyLaunchFailure(statusCode: 403, message: "Encryption is mandatory for this host but unsupported by the client") == .other)
        #expect(classifyLaunchFailure(statusCode: 503, message: "Failed to initialize video capture/encoding. Is a display connected and turned on?") == .noDisplay)
        #expect(classifyLaunchFailure(statusCode: 503, message: "No running app to resume") == .other)
        #expect(classifyLaunchFailure(statusCode: 400, message: "x") == .other)
    }
}

@Suite struct StatusLineTests {
    let now = Date(timeIntervalSince1970: 1_793_540_000)
    func game() -> SteamActivity {
        SteamActivity(runningAppId: 5, runningName: "Hogwarts Legacy", lastPlayed: Game(appId: 5, name: "Control Resonant", at: 1_793_540_000 - 86_400))
    }

    @Test func showsLastPlayedForAnOnlineOrOfflineHost() {
        for state in [HostCardState.online, .offline] {
            let line = statusLine(for: HostSnapshot(name: "PC", state: state, activity: .activity(game())), now: now)
            #expect(line == StatusLine(.clock, "Last played Control Resonant · Yesterday"))
        }
    }

    @Test func showsTheNoSteamLineOnlyWhenSteamIsMissing() {
        #expect(statusLine(for: HostSnapshot(name: "PC", state: .online, activity: .noSteam)) == StatusLine(.none, "No Steam library on this PC"))
        #expect(statusLine(for: HostSnapshot(name: "PC", state: .online, activity: .withheld)) == StatusLine(.none, ""))
        #expect(statusLine(for: HostSnapshot(name: "PC", state: .offline, activity: nil)) == StatusLine(.none, ""))
    }

    @Test func describesAHostInUse() {
        let full = HostSnapshot(name: "PC", state: .inUse, activity: .activity(game()), activeClient: "Louise’s MacBook", currentAppName: "Steam Big Picture")
        #expect(statusLine(for: full) == StatusLine(.controller, "Currently playing Hogwarts Legacy · Louise’s MacBook"))
        let noSteamGame = HostSnapshot(name: "PC", state: .inUse, activity: .noSteam, activeClient: "iPad", currentAppName: "Desktop")
        #expect(statusLine(for: noSteamGame) == StatusLine(.controller, "Currently playing Desktop · iPad"))
        let withheld = HostSnapshot(name: "PC", state: .inUse, activity: .withheld, activeClient: "", currentAppName: "Steam Big Picture")
        #expect(statusLine(for: withheld) == StatusLine(.controller, "Currently playing Steam Big Picture"))
        #expect(statusLine(for: HostSnapshot(name: "PC", state: .inUse)) == StatusLine(.controller, "In use by another device"))
    }

    @Test func describesProgressAndPairing() {
        #expect(statusLine(for: HostSnapshot(name: "Den", state: .waking)) == StatusLine(.spinner, "Waking Den…"))
        #expect(statusLine(for: HostSnapshot(name: "Den", state: .connecting)) == StatusLine(.spinner, "Starting Steam Big Picture…"))
        #expect(statusLine(for: HostSnapshot(name: "Den", state: .joining)) == StatusLine(.spinner, "Joining the stream…"))
        #expect(statusLine(for: HostSnapshot(name: "Den", state: .pairing, pinSecondsLeft: 65)) == StatusLine(.spinner, "Enter the PIN in Apollo on the PC · New PIN in 1:05"))
        #expect(statusLine(for: HostSnapshot(name: "Den", state: .notPaired)) == StatusLine(.lock, "Found on your network · Not paired with this Apple TV yet"))
        #expect(statusLine(for: HostSnapshot(name: "Den", state: .pairingFailed(.anotherPairing))) == StatusLine(.lockCross, "The PC is pairing with another device · Press OK to try again"))
        #expect(statusLine(for: HostSnapshot(name: "Den", state: .pairingFailed(.unknown))).text == "Pairing didn’t finish · Press OK to try again")
    }

    @Test func describesEveryError() {
        #expect(statusLine(for: HostSnapshot(name: "PC", state: .error(.notAllowed))).text == "Apollo hasn’t allowed this Apple TV to start apps · Change it in Apollo on the PC")
        #expect(statusLine(for: HostSnapshot(name: "PC", state: .error(.noDisplay))).text == "The PC has no display to stream · Turn on a virtual display in Apollo")
        #expect(statusLine(for: HostSnapshot(name: "PC", state: .error(.wakeFailed))).icon == .warning)
        #expect(errorText(.other) == "Couldn’t reach this computer · Press OK to try again")
    }

    @Test func aNetworkTestResultReplacesTheLine() {
        let h = HostSnapshot(name: "PC", state: .online, activity: .activity(game()), notice: "Network test: ports open")
        #expect(statusLine(for: h) == StatusLine(.none, "Network test: ports open"))
    }

    @Test func addFlowLines() {
        #expect(StatusLine.notFound("10.0.0.42").text == "Couldn’t find a computer at 10.0.0.42 · Check the address and try again")
        #expect(StatusLine.lookingFor("10.0.0.42").text == "Looking for 10.0.0.42…")
    }
}

@Suite struct BackdropTests {
    let played = ActivityResponse.activity(SteamActivity(lastPlayed: Game(appId: 100, name: "X", at: 1)))

    @Test func triesHeroThenCapsuleThenWallpaperThenColour() {
        let s = backdropSources(paired: true, activity: played)
        #expect(s.first == .apollo(appId: 100, kind: .hero))
        #expect(s[1] == .steamCDN(URL(string: "https://cdn.cloudflare.steamstatic.com/steam/apps/100/library_hero.jpg")!))
        #expect(s.contains(.apollo(appId: 100, kind: .capsule)))
        #expect(Array(s.suffix(2)) == [.wallpaper, .colourAndSymbol])
    }

    @Test func usesTheWallpaperWithoutAGame() {
        #expect(backdropSources(paired: true, activity: .noSteam) == [.wallpaper, .colourAndSymbol])
        #expect(backdropSources(paired: true, activity: nil) == [.wallpaper, .colourAndSymbol])
        #expect(backdropSources(paired: true, activity: .activity(SteamActivity())) == [.wallpaper, .colourAndSymbol])
    }

    @Test func withheldAndUnpairedHostsGetNoWallpaper() {
        #expect(backdropSources(paired: true, activity: .withheld) == [.colourAndSymbol])
        #expect(backdropSources(paired: false, activity: played) == [.bundledGeneric])
    }

    @Test func buildsCDNAddresses() {
        #expect(steamCDNURLs(appId: 7, kind: .logo).map(\.absoluteString) == ["https://cdn.cloudflare.steamstatic.com/steam/apps/7/logo.png"])
        #expect(steamCDNURLs(appId: 7, kind: .capsule).count == 2)
    }
}

@Suite struct NetworkTests {
    @Test func buildsHostAddresses() {
        #expect(URLSessionHostAPI.baseURL(host: "10.0.0.5", port: 47984)?.absoluteString == "https://10.0.0.5:47984")
        #expect(URLSessionHostAPI.baseURL(host: "fe80::1", port: 47984)?.absoluteString == "https://[fe80::1]:47984")
        #expect(URLSessionHostAPI.baseURL(host: "[fe80::1]", port: 47984)?.absoluteString == "https://[fe80::1]:47984")
    }
}
