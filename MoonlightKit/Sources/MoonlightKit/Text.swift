import Foundation

/// "Yesterday", "2 hours ago": the relative time with its first letter capitalised.
public func relativeWhen(_ date: Date, now: Date = Date(), locale: Locale = Locale(identifier: "en_US")) -> String {
    let formatter = RelativeDateTimeFormatter()
    formatter.dateTimeStyle = .named
    formatter.unitsStyle = .full
    formatter.locale = locale
    let text = formatter.localizedString(for: date, relativeTo: now)
    return text.prefix(1).uppercased() + text.dropFirst()
}

/// "m:ss" for the pairing PIN countdown.
public func clockText(seconds: Int) -> String {
    let s = max(0, seconds)
    return "\(s / 60):" + String(format: "%02d", s % 60)
}
