import Testing
@testable import ShamanCore

@Suite("Reading-screen chatter")
struct PlateChatterTests {
    /// The one rule the whole product rests on, applied to the text a person
    /// reads more often than any other in the app.
    @Test("Nothing here counts calories, grams or macros")
    func neverCountsWhatTheAppDoesNot() {
        // Protein is not here: it is the one macro the app does count, so a
        // phrase may say it. Everything else is the road to a calorie counter.
        let banned = ["calorie", "kcal", "gram", "macro", "carb"]
        for phrase in PlateChatter.phrases {
            let lowered = phrase.lowercased()
            for word in banned {
                #expect(!lowered.contains(word), "\"\(phrase)\" mentions \(word)")
            }
        }
        // This caught "Not counting calories…", which was written as a joke
        // about the rule and would have shown the word to every person on
        // every meal. Denying the frame still puts the frame on screen.
    }

    @Test("Every line is short enough for one row, and ends in an ellipsis")
    func fitsOnOneLine() {
        for phrase in PlateChatter.phrases {
            #expect(phrase.count <= 42, "\"\(phrase)\" is \(phrase.count) characters")
            #expect(phrase.hasSuffix("…"), "\"\(phrase)\" should trail off")
        }
        #expect(Set(PlateChatter.phrases).count == PlateChatter.phrases.count)
    }

    @Test("The order opens on a plain line and shows every phrase once")
    func orderIsAShuffleWithAKnownOpener() {
        var generator = SystemRandomNumberGenerator()
        for _ in 0..<50 {
            let order = PlateChatter.order(using: &generator)
            #expect(Set(order) == Set(PlateChatter.phrases))
            #expect(order.count == PlateChatter.phrases.count)
            #expect(PlateChatter.phrases.prefix(3).contains(order[0]), "opened on \(order[0])")
        }
    }
}
