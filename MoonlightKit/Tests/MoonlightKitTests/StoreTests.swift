import Foundation
import Testing
@testable import MoonlightKit

private actor Calls {
    var art: [String] = []
    var cdn: [String] = []
    var wallpaper = 0
    func addArt(_ s: String) { art.append(s) }
    func addCDN(_ s: String) { cdn.append(s) }
    func addWallpaper() { wallpaper += 1 }
}

private final class FakeAPI: HostAPI, @unchecked Sendable {
    var response: Result<ActivityResponse, Error> = .failure(URLError(.notConnectedToInternet))
    var arts: [String: Data] = [:]      // "100/hero" -> data
    var wallpaperData: Data? = Data("wall".utf8)
    let calls = Calls()

    func activity() async throws -> ActivityResponse { try response.get() }
    func art(appId: Int, kind: ArtKind) async throws -> Data? {
        await calls.addArt("\(appId)/\(kind.rawValue)")
        return arts["\(appId)/\(kind.rawValue)"]
    }
    func wallpaper() async throws -> Data? {
        await calls.addWallpaper()
        return wallpaperData
    }
}

private final class FakeCDN: ArtCDN, @unchecked Sendable {
    var files: [String: Data] = [:]
    let calls: Calls
    init(calls: Calls) { self.calls = calls }
    func data(from url: URL) async throws -> Data? {
        await calls.addCDN(url.lastPathComponent)
        return files[url.lastPathComponent]
    }
}

private func activity(_ appId: Int, name: String = "Game") -> ActivityResponse {
    .activity(SteamActivity(lastPlayed: Game(appId: appId, name: name, at: 5)))
}

private func makeStore(_ api: FakeAPI, _ cdn: FakeCDN, dir: URL, host: String = "host-1") -> SteamActivityStore {
    SteamActivityStore(hostID: host, directory: dir, api: api, cdn: cdn, now: { Date(timeIntervalSince1970: 1_000) })
}

private func tempDir() -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("mk-\(UUID().uuidString)")
}

@Suite struct SteamActivityStoreTests {
    @Test func cachesTheActivityAndTheHeroFromApollo() async {
        let dir = tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let api = FakeAPI(); api.response = .success(activity(100)); api.arts["100/hero"] = Data("hero".utf8)
        let store = makeStore(api, FakeCDN(calls: api.calls), dir: dir)
        let snap = await store.refresh(includeWallpaper: true)
        #expect(snap.activity == activity(100))
        #expect(snap.hero == Data("hero".utf8))
        #expect(snap.fetchedAt == Date(timeIntervalSince1970: 1_000))
        #expect(snap.wallpaper == nil)
        #expect(await api.calls.wallpaper == 0)   // a hero exists, so no wallpaper is fetched
    }

    @Test func fallsBackToTheCDNThenTheCapsule() async {
        let dir = tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let api = FakeAPI(); api.response = .success(activity(100))
        let cdn = FakeCDN(calls: api.calls); cdn.files["library_hero.jpg"] = Data("cdn-hero".utf8)
        let a = await makeStore(api, cdn, dir: dir, host: "a").refresh(includeWallpaper: false)
        #expect(a.hero == Data("cdn-hero".utf8))

        cdn.files = ["header.jpg": Data("header".utf8)]
        let b = await makeStore(api, cdn, dir: dir, host: "b").refresh(includeWallpaper: false)
        #expect(b.hero == Data("header".utf8))
        #expect(await api.calls.art.contains("100/capsule"))
    }

    @Test func keepsTheCacheWhenAFetchFails() async {
        let dir = tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let api = FakeAPI(); api.response = .success(activity(100)); api.arts["100/hero"] = Data("hero".utf8)
        let store = makeStore(api, FakeCDN(calls: api.calls), dir: dir)
        let first = await store.refresh(includeWallpaper: false)
        api.response = .failure(URLError(.timedOut))
        let second = await store.refresh(includeWallpaper: true)
        #expect(second == first)
    }

    @Test func fetchesArtAgainOnlyWhenTheGameChanges() async {
        let dir = tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let api = FakeAPI(); api.response = .success(activity(100)); api.arts["100/hero"] = Data("one".utf8); api.arts["200/hero"] = Data("two".utf8)
        let store = makeStore(api, FakeCDN(calls: api.calls), dir: dir)
        _ = await store.refresh(includeWallpaper: false)
        _ = await store.refresh(includeWallpaper: false)
        #expect(await api.calls.art == ["100/hero"])
        api.response = .success(activity(200))
        let snap = await store.refresh(includeWallpaper: false)
        #expect(snap.hero == Data("two".utf8))
        #expect(await api.calls.art == ["100/hero", "200/hero"])
    }

    @Test func fetchesTheWallpaperWhenThereIsNoHero() async {
        let dir = tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let api = FakeAPI(); api.response = .success(activity(100))   // no art anywhere
        let store = makeStore(api, FakeCDN(calls: api.calls), dir: dir)
        let snap = await store.refresh(includeWallpaper: true)
        #expect(snap.hero == nil)
        #expect(snap.wallpaper == Data("wall".utf8))
    }

    @Test func fetchesTheWallpaperWithoutSteamButOnlyWhenAsked() async {
        let dir = tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let api = FakeAPI(); api.response = .success(.noSteam)
        let store = makeStore(api, FakeCDN(calls: api.calls), dir: dir)
        #expect(await store.refresh(includeWallpaper: false).wallpaper == nil)
        #expect(await store.refresh(includeWallpaper: true).wallpaper == Data("wall".utf8))
        #expect(await api.calls.wallpaper == 1)
    }

    @Test func clearsEverythingWhenActivityIsWithheld() async {
        let dir = tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let api = FakeAPI(); api.response = .success(activity(100)); api.arts["100/hero"] = Data("hero".utf8)
        let store = makeStore(api, FakeCDN(calls: api.calls), dir: dir)
        _ = await store.refresh(includeWallpaper: true)
        api.response = .success(.withheld)
        let snap = await store.refresh(includeWallpaper: true)
        #expect(snap.activity == .withheld)
        #expect(snap.hero == nil)
        #expect(snap.wallpaper == nil)
    }

    @Test func survivesARestartAndRemoval() async {
        let dir = tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let api = FakeAPI(); api.response = .success(activity(100)); api.arts["100/hero"] = Data("hero".utf8)
        let first = await makeStore(api, FakeCDN(calls: api.calls), dir: dir).refresh(includeWallpaper: false)
        let reopened = makeStore(FakeAPI(), FakeCDN(calls: api.calls), dir: dir)
        #expect(await reopened.snapshot() == first)
        await reopened.remove()
        let gone = await reopened.snapshot()
        #expect(gone.activity == nil)
        #expect(gone.hero == nil)
    }

    @Test func keepsHostsApart() async {
        let dir = tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let api = FakeAPI(); api.response = .success(activity(100)); api.arts["100/hero"] = Data("hero".utf8)
        _ = await makeStore(api, FakeCDN(calls: api.calls), dir: dir, host: "a").refresh(includeWallpaper: false)
        let other = makeStore(FakeAPI(), FakeCDN(calls: api.calls), dir: dir, host: "b")
        #expect(await other.snapshot().activity == nil)
    }
}
