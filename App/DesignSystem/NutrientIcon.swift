import SwiftUI

/// The five nutrient marks supplied with the product's nutrition language.
///
/// They remain original-colour image assets rather than template images:
/// colour and silhouette work together, so the distinction survives when the
/// marks are small and does not rely on colour alone.
enum NutrientKind: String {
    case protein
    case carbs
    case fat
    case caffeine
    case alcohol

    fileprivate var assetName: String { "nutrient-\(rawValue)" }
}

struct NutrientIcon: View {
    let kind: NutrientKind
    var size: CGFloat = 18

    var body: some View {
        Image(kind.assetName)
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}
