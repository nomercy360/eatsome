/// Small numbers are words in the app's sentences so short summaries read as
/// prose instead of telemetry.
public enum Count {
    public static func spell(_ value: Int, capitalized: Bool = true) -> String {
        let words = [
            "Zero", "One", "Two", "Three", "Four", "Five", "Six", "Seven",
            "Eight", "Nine", "Ten", "Eleven", "Twelve", "Thirteen", "Fourteen",
            "Fifteen", "Sixteen", "Seventeen", "Eighteen", "Nineteen", "Twenty"
        ]
        guard value >= 0, value < words.count else { return "\(value)" }
        return capitalized ? words[value] : words[value].lowercased()
    }

    public static func meals(_ value: Int) -> String {
        value == 1 ? "One meal" : "\(spell(value)) meals"
    }
}
