import Foundation

/// Vibepollo's version 1 paired-client power action response. Discovery and the sleep request
/// answer with the same XML shape; only `SleepAccepted` differs.
public struct PowerActionCapabilities: Equatable, Sendable {
    public var version: Int
    public var supported: Bool
    public var allowed: Bool
    public var available: Bool
    public var activeSessionPolicy: String?
    /// 64 lowercase hex characters while the host is idle, absent otherwise.
    public var token: String?
    public var tokenLifetimeSeconds: Int
    public var accepted: Bool

    public init(version: Int, supported: Bool, allowed: Bool, available: Bool,
                activeSessionPolicy: String? = nil, token: String? = nil,
                tokenLifetimeSeconds: Int = 0, accepted: Bool = false) {
        self.version = version
        self.supported = supported
        self.allowed = allowed
        self.available = available
        self.activeSessionPolicy = activeSessionPolicy
        self.token = token
        self.tokenLifetimeSeconds = tokenLifetimeSeconds
        self.accepted = accepted
    }

    /// Reads the XML the host answers with. Nil when `PowerActionVersion` is missing, which is
    /// how a host without the power actions extension (or a non-XML answer) is told apart.
    public init?(xml: Data) {
        let fields = PowerActionFields()
        let parser = XMLParser(data: xml)
        parser.delegate = fields
        guard parser.parse(), let version = fields.int("PowerActionVersion") else { return nil }
        self.init(version: version,
                  supported: fields.flag("SleepSupported"),
                  allowed: fields.flag("SleepAllowed"),
                  available: fields.flag("SleepAvailable"),
                  activeSessionPolicy: fields.string("SleepActiveSessionPolicy"),
                  token: fields.string("SleepToken"),
                  tokenLifetimeSeconds: fields.int("SleepTokenLifetimeSeconds") ?? 0,
                  accepted: fields.flag("SleepAccepted"))
    }

    /// The three flags the host documents for offering the action at all.
    public var isOffered: Bool { version == 1 && supported && allowed }

    /// The last gate before spending the token: the host mints one only while it is idle.
    public var canSleepNow: Bool { isOffered && available && token?.isEmpty == false }
}

/// Why a sleep request failed, from the status code alone. The host's status message is not
/// reliable here: the flag-only answers leave it empty.
public enum SleepRefusal: Equatable, Sendable {
    /// 401: the host no longer recognises this client's certificate.
    case identityLost
    /// 403: the sleep grant is switched off for this client.
    case notAllowed
    /// 409: busy, or the token expired or was already used.
    case busy
    /// 501: the host has no native sleep.
    case unsupported
    /// 503: the host is busy admitting the request.
    case hostBusy
    /// Anything else, including no answer at all.
    case other
}

public func classifySleepRefusal(statusCode: Int) -> SleepRefusal {
    switch statusCode {
    case 401: .identityLost
    case 403: .notAllowed
    case 409: .busy
    case 501: .unsupported
    case 503: .hostBusy
    default: .other
    }
}

/// Collects the root's child elements. Their names are unique in this response.
private final class PowerActionFields: NSObject, XMLParserDelegate {
    private var values: [String: String] = [:]
    private var current: String?
    private var text = ""

    func int(_ name: String) -> Int? {
        guard let value = values[name]?.trimmingCharacters(in: .whitespacesAndNewlines) else { return nil }
        return Int(value)
    }

    func flag(_ name: String) -> Bool { int(name) == 1 }

    func string(_ name: String) -> String? {
        guard let value = values[name]?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return nil }
        return value
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        current = elementName
        text = ""
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if current != nil { text += string }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?) {
        guard current == elementName else { return }
        values[elementName] = text
        current = nil
        text = ""
    }
}
