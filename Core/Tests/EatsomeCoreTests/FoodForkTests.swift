import Foundation
import Testing

@testable import EatsomeCore

@Suite("Forks: which of them are questions")
struct FoodForkTests {
    static let latte = Nutrients(protein: 3.2, fat: 3.5, carbohydrate: 4.9, kcal: 64)
    static let cola = Nutrients(protein: 0, fat: 0, carbohydrate: 10.6, kcal: 42)
    static let zero = Nutrients(protein: 0, fat: 0, carbohydrate: 0, kcal: 0.3)

    /// The floor and the share, from `Backend/eval/forks-poc.md`: a gyudon's
    /// size (Δ350–540 kcal) and the drink in an opaque cup (Δ135–220) are
    /// questions; the milk in a cappuccino (Δ18–63) is not, although it is
    /// half the drink.
    @Test("An assumed fork with a material spread is open; a small one is not")
    func gate() {
        let sizes = FoodFork(axis: "size", chosenFrom: .assumed, options: [
            FoodForkOption(label: "Tall", grams: 354, per100g: Self.latte, chosen: true),
            FoodForkOption(label: "Grande", grams: 473, per100g: Self.latte),
            FoodForkOption(label: "Venti", grams: 591, per100g: Self.latte),
        ])
        // (591 − 354) × 0.64 ≈ 152 kcal: over the floor and over a fifth of 227.
        #expect(sizes.kcalSpread > 150)
        #expect(sizes.isOpen(rowKcal: 227))

        let milk = FoodFork(axis: "milk", chosenFrom: .assumed, options: [
            FoodForkOption(label: "whole milk", grams: 354, per100g: Self.latte, chosen: true),
            FoodForkOption(label: "oat milk", grams: 354, per100g: Nutrients(protein: 1, fat: 2.5, carbohydrate: 8, kcal: 58)),
        ])
        // Δ ≈ 21 kcal on a 227 kcal drink.
        #expect(!milk.isOpen(rowKcal: 227))

        // The floor is absolute: a big share of a small row is still a small
        // number, and not worth a tap in a day.
        let cappuccino = FoodFork(axis: "milk", chosenFrom: .assumed, options: [
            FoodForkOption(label: "semi-skimmed", grams: 200, per100g: Nutrients(protein: 3, fat: 2, carbohydrate: 5, kcal: 50), chosen: true),
            FoodForkOption(label: "whole", grams: 200, per100g: Nutrients(protein: 3, fat: 4, carbohydrate: 5, kcal: 68)),
        ])
        #expect(cappuccino.kcalSpread > FoodFork.askShare * 100)
        #expect(!cappuccino.isOpen(rowKcal: 100))
    }

    @Test("A stated or seen default is never a question, however wide the fork")
    func evidenceGates() {
        let options = [
            FoodForkOption(label: "6-inch", grams: 229, per100g: Self.latte),
            FoodForkOption(label: "Footlong", grams: 458, per100g: Self.latte, chosen: true),
        ]
        #expect(!FoodFork(axis: "size", chosenFrom: .stated, options: options).isOpen(rowKcal: 293))
        #expect(!FoodFork(axis: "size", chosenFrom: .seen, options: options).isOpen(rowKcal: 293))
        #expect(FoodFork(axis: "size", chosenFrom: .assumed, options: options).isOpen(rowKcal: 293))
    }

    @Test("A row lists its open forks widest first, and answering one closes it")
    func openForksOrdered() {
        let drink = FoodFork(axis: "drink", chosenFrom: .assumed, options: [
            FoodForkOption(label: "Coca-Cola", grams: 500, per100g: Self.cola, chosen: true),
            FoodForkOption(label: "Coke Zero", grams: 500, per100g: Self.zero),
        ])
        let size = FoodFork(axis: "size", chosenFrom: .assumed, options: [
            FoodForkOption(label: "Small", grams: 350, per100g: Self.cola),
            FoodForkOption(label: "Medium", grams: 500, per100g: Self.cola, chosen: true),
            FoodForkOption(label: "Large", grams: 700, per100g: Self.cola),
        ])
        var item = MealItem(label: "Coca-Cola", grams: 500, per100g: Self.cola, brand: "McDonald's", forks: [size, drink])
        // Δ210 for the drink beats Δ147 for the size.
        #expect(item.openForks.map(\.axis) == ["drink", "size"])

        let zero = try! #require(drink.options.last)
        let answered = drink.choosing(zero)
        #expect(answered.chosenFrom == .stated)
        #expect(answered.chosen?.label == "Coke Zero")
        #expect(answered.options.filter(\.chosen).count == 1)
        item.forks = [answered]
        #expect(item.openForks.isEmpty)
    }

    @Test("A fork round-trips through JSON with the wire spellings")
    func codable() throws {
        let fork = FoodFork(axis: "size", chosenFrom: .seen, options: [
            FoodForkOption(label: "Grande", grams: 473, per100g: Self.latte, chosen: true),
            FoodForkOption(label: "Venti", grams: 591, per100g: Self.latte),
        ])
        let data = try JSONEncoder().encode(fork)
        let text = String(decoding: data, as: UTF8.self)
        #expect(text.contains(#""chosen_from":"seen""#))
        #expect(text.contains(#""per_100g""#))
        #expect(try JSONDecoder().decode(FoodFork.self, from: data) == fork)
        // An evidence word this build does not know is corrupt, not "newer".
        let unknown = text.replacingOccurrences(of: #""seen""#, with: #""guessed""#)
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(FoodFork.self, from: Data(unknown.utf8))
        }
    }
}
