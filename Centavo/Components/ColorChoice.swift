import SwiftUI
import UIKit

/// The row of the palette's colors in a card's or category's sheet: one tap picks one.
struct ColorRow: View {
    @Binding var selection: Int
    @ScaledMetric(relativeTo: .body) private var swatch = Theme.Size.colorSwatch

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: Theme.Size.tapTarget), spacing: Theme.Space.xxs)],
                  spacing: Theme.Space.xxs) {
            ForEach(Theme.categories.indices, id: \.self) { index in
                let selected = index == selection
                Button {
                    selection = index
                } label: {
                    Circle()
                        .fill(Theme.categories[index])
                        .frame(width: swatch, height: swatch)
                        .padding(Theme.Space.xxs)
                        .overlay {
                            if selected { Circle().strokeBorder(Theme.ink, lineWidth: Theme.Stroke.strong) }
                        }
                        .frame(minWidth: Theme.Size.tapTarget, minHeight: Theme.Size.tapTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Theme.categoryColorNames[index])
                .accessibilityIdentifier("color-\(index)")
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .sensoryFeedback(.selection, trigger: selection)
    }
}

/// «Color» inside a tile's menu: the palette by name, the current one checked.
struct ColorMenu: View {
    @Binding var selection: Int

    var body: some View {
        Menu("Color", systemImage: "paintpalette") {
            Picker("Color", selection: $selection) {
                ForEach(Theme.categories.indices, id: \.self) { index in
                    Label { Text(Theme.categoryColorNames[index]) } icon: { Self.dot(index) }
                        .tag(index)
                }
            }
        }
    }

    /// A menu draws its icons in one tint; an image marked original keeps its color.
    private static func dot(_ index: Int) -> Image {
        let symbol = UIImage(systemName: "circle.fill")?
            .withTintColor(UIColor(Theme.categories[index]), renderingMode: .alwaysOriginal)
        return symbol.map(Image.init(uiImage:)) ?? Image(systemName: "circle.fill")
    }
}

#Preview("Colores") {
    @Previewable @State var selection = 2
    ColorRow(selection: $selection)
        .padding(Theme.Space.screen)
        .background(Theme.background)
}
