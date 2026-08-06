/// What the app says while it is reading a photograph.
///
/// Recognition takes a few seconds on every single meal, which makes this the
/// most-seen text in the app. One fixed line is honest and, by the fiftieth
/// meal, invisible. A line that changes is proof the app is still working —
/// motion is the signal, and the words are what make the wait pleasant rather
/// than merely short.
///
/// Two rules the phrases have to keep. They never mention calories, grams or
/// macronutrients: this is the most-read text in the app, and a joke about
/// counting calories teaches the one idea the whole product exists to avoid.
/// And they are about the plate, never about the model — "Consulting the
/// neural network" is the app talking about itself to someone who is holding a
/// bowl of ramen.
public enum PlateChatter {
    /// Deliberately mundane at the start of the list and stranger further in:
    /// most reads finish in the first two or three, so the everyday ones carry
    /// the common case and the odd ones reward a slow connection.
    public static let phrases: [String] = [
        "Reading your plate…",
        "Naming what's on it…",
        "Separating the dishes…",
        "Looking under the sauce…",
        "Checking for hidden butter…",
        "Deciding if that's parsley or coriander…",
        "Asking whether that's a fish…",
        "Counting the plates…",
        "Squinting at the olive oil…",
        "Interrogating the garnish…",
        "Counting H₂O molecules…",
        "Looking for the vegetables…",
        "Consulting the Mediterranean…",
        "Peering under the cheese…",
        "Weighing nothing, on principle…",
        "Wondering about that sauce…",
        "Counting sesame seeds…",
        "Giving the broth a stir…",
        "Asking the rice how much it is…"
    ]

    /// An order to show them in, starting on one of the everyday lines.
    ///
    /// Shuffling the whole list would open on "Counting H₂O molecules" as often
    /// as on "Reading your plate", and the first line is the one that has to
    /// say what is actually happening. So the opener is drawn from the plain
    /// few and the rest follow in a shuffled order.
    ///
    /// `using` is passed in rather than taken from a global generator so a test
    /// can pin the order; `Int.random` is not available to a framework-free
    /// module's callers without one.
    public static func order<G: RandomNumberGenerator>(using generator: inout G) -> [String] {
        let plainCount = 3
        let opener = Int.random(in: 0..<plainCount, using: &generator)
        var rest = phrases
        rest.remove(at: opener)
        return [phrases[opener]] + rest.shuffled(using: &generator)
    }

    /// How long one line stays up. Long enough to read a short phrase without
    /// re-reading it, short enough that a five-second wait shows two or three.
    public static let interval: Double = 2.2
}
