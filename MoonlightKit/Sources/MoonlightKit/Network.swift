import Foundation
import Security

public enum HostAPIError: Error, Equatable {
    case badStatus(Int)
    case notHTTP
}

/// Talks to a paired Apollo host over the HTTPS port the client already uses for pairing.
///
/// The server certificate is compared byte for byte with the one stored at pairing, as `HttpManager` does.
/// The client answers the certificate request with the identity made at pairing. The app builds this from
/// `CryptoManager` and the stored host record. Not yet exercised against a live host.
public final class URLSessionHostAPI: NSObject, HostAPI, URLSessionDelegate, @unchecked Sendable {
    private let base: URL
    private let pinned: Data
    private let identity: SecIdentity
    private let chain: [SecCertificate]
    private var session: URLSession!

    public init?(host: String, httpsPort: Int, pinnedServerCertificate: Data, identity: SecIdentity, certificates: [SecCertificate]) {
        guard let base = Self.baseURL(host: host, port: httpsPort) else { return nil }
        self.base = base
        self.pinned = pinnedServerCertificate
        self.identity = identity
        self.chain = certificates
        super.init()
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 10
        self.session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }

    /// `https://host:port`, with brackets around an IPv6 literal.
    static func baseURL(host: String, port: Int) -> URL? {
        let safe = host.contains(":") && !host.hasPrefix("[") ? "[\(host)]" : host
        return URL(string: "https://\(safe):\(port)")
    }

    private func get(_ path: String) async throws -> (Data, Int) {
        let (data, response) = try await session.data(from: base.appendingPathComponent(path))
        guard let http = response as? HTTPURLResponse else { throw HostAPIError.notHTTP }
        return (data, http.statusCode)
    }

    public func activity() async throws -> ActivityResponse {
        let (data, status) = try await get("moonlight/steam")
        guard status == 200 else { throw HostAPIError.badStatus(status) }
        return try JSONDecoder().decode(ActivityResponse.self, from: data)
    }

    public func art(appId: Int, kind: ArtKind) async throws -> Data? {
        try await optionalImage("moonlight/steam/art/\(appId)/\(kind.rawValue)")
    }

    public func wallpaper() async throws -> Data? {
        try await optionalImage("moonlight/wallpaper")
    }

    private func optionalImage(_ path: String) async throws -> Data? {
        let (data, status) = try await get(path)
        if status == 404 { return nil }
        guard status == 200 else { throw HostAPIError.badStatus(status) }
        return data
    }

    public func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge,
                           completionHandler: @escaping @Sendable (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        switch challenge.protectionSpace.authenticationMethod {
        case NSURLAuthenticationMethodServerTrust:
            guard let trust = challenge.protectionSpace.serverTrust,
                  let certs = SecTrustCopyCertificateChain(trust) as? [SecCertificate], certs.count == 1,
                  SecCertificateCopyData(certs[0]) as Data == pinned
            else { return completionHandler(.cancelAuthenticationChallenge, nil) }
            completionHandler(.useCredential, URLCredential(trust: trust))
        case NSURLAuthenticationMethodClientCertificate:
            completionHandler(.useCredential, URLCredential(identity: identity, certificates: chain, persistence: .forSession))
        default:
            completionHandler(.performDefaultHandling, nil)
        }
    }
}

/// Steam's content delivery network. A 404 returns `nil`.
public struct URLSessionCDN: ArtCDN {
    public init() {}

    public func data(from url: URL) async throws -> Data? {
        let (data, response) = try await URLSession.shared.data(from: url)
        guard let http = response as? HTTPURLResponse else { throw HostAPIError.notHTTP }
        if http.statusCode == 404 { return nil }
        guard http.statusCode == 200 else { throw HostAPIError.badStatus(http.statusCode) }
        return data
    }
}
