import Foundation

/// The clock time inside a sentence: "— 8 am", "2 of this at 11 am", "13:20".
///
/// Read here rather than asked of a model, on purpose. Nothing in this app asks
/// a model for a number except a weight, and the justification for that one
/// exception is that a weight is an observation of the food. A clock time is not
/// an observation of anything — it is a string the person typed — so parsing it
/// is arithmetic, and arithmetic belongs in code where it can be tested and
/// looked at. A model asked the same question would be right almost always,
/// which is the worst possible failure rate for something silent.
///
/// Deliberately narrow. It recognises the shapes people actually type when
/// logging late, and refuses everything else rather than guessing: an unparsed
/// message keeps the time it was sent, which is right far more often than a
/// clever wrong answer.
public enum SpokenTime {
    /// When the food was eaten, given the words and when they were sent.
    ///
    /// Returns `sentAt` unchanged when the sentence names no time. The result is
    /// never in the future: "at 11 pm" typed at 1 am means last night, because
    /// nobody logs a meal before eating it.
    public static func eatenAt(
        in text: String?,
        sentAt: EpochMillis,
        calendar: Calendar = .current
    ) -> EpochMillis {
        guard let text, let clock = parse(text) else { return sentAt }
        let sent = Date(epochMillis: sentAt)

        var parts = calendar.dateComponents([.year, .month, .day], from: sent)
        parts.hour = clock.hour
        parts.minute = clock.minute
        parts.second = 0
        guard let onSendDay = calendar.date(from: parts) else { return sentAt }

        // A stated time later than now is yesterday's. The tolerance keeps a
        // meal logged as it is eaten — "lunch at 13:00", sent 13:00:04 — from
        // being thrown back a day by four seconds of typing.
        if onSendDay.timeIntervalSince(sent) > 60 {
            return (calendar.date(byAdding: .day, value: -1, to: onSendDay) ?? onSendDay).epochMillis
        }
        return onSendDay.epochMillis
    }

    /// Hour and minute, or nil when the sentence names no time.
    ///
    /// Internal rather than private so the tests can state the cases as times
    /// rather than as whole timestamps.
    static func parse(_ text: String) -> (hour: Int, minute: Int)? {
        let text = text.lowercased()

        // 12-hour first: "8 am", "8:30pm", "at 11 a.m.". Checked before the
        // 24-hour shape because "8:30pm" matches both, and only one is right.
        if let match = firstMatch(
            #"(?<![0-9:])([0-9]{1,2})(?::([0-9]{2}))?\s*(a\.?m\.?|p\.?m\.?)"#,
            in: text
        ) {
            guard var hour = match[1].flatMap(Int.init), (1...12).contains(hour) else { return nil }
            let minute = match[2].flatMap(Int.init) ?? 0
            guard (0...59).contains(minute) else { return nil }
            let isAfternoon = match[3]?.hasPrefix("p") ?? false
            if hour == 12 { hour = 0 }
            return (isAfternoon ? hour + 12 : hour, minute)
        }

        // 24-hour, and only with a colon. A bare "8" in "8 eggs" is a count, and
        // reading it as a time would silently move a meal eight hours.
        if let match = firstMatch(#"(?<![0-9:.])([0-9]{1,2}):([0-9]{2})(?![0-9])"#, in: text) {
            guard let hour = match[1].flatMap(Int.init), (0...23).contains(hour),
                  let minute = match[2].flatMap(Int.init), (0...59).contains(minute)
            else { return nil }
            return (hour, minute)
        }

        return nil
    }

    private static func firstMatch(_ pattern: String, in text: String) -> [String?]? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, range: range) else { return nil }
        return (0..<match.numberOfRanges).map { index in
            guard let sub = Range(match.range(at: index), in: text) else { return nil }
            return String(text[sub])
        }
    }
}
