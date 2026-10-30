import SwiftUI

/// A suggestion one tap away («Oxxo», «+ Renta», «café»): the same small rounded tag on every
/// screen, outlined so it reads on the paper and on a form row alike. `selected` fills it in
/// brass (the onboarding's chosen fixed expense). Never the system's grey `.bordered`.
struct TicketChip: View {
    let title: String
    var systemImage: String?
    var selected = false
    var identifier: String?
    let action: () -> Void

    init(_ title: String, systemImage: String? = nil, selected: Bool = false, identifier: String? = nil,
         action: @escaping () -> Void) {
        self.title = title
        self.systemImage = systemImage
        self.selected = selected
        self.identifier = identifier
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Group {
                if let systemImage {
                    Label(title, systemImage: systemImage)
                } else {
                    Text(title)
                }
            }
            .font(.ticket(.footnote))
            .lineLimit(1)
            .foregroundStyle(selected ? Theme.onBrass : Theme.ink)
            .padding(.horizontal, Theme.Space.m)
            .frame(minHeight: Theme.Size.tapTarget)
            .background(selected ? Theme.brass : Color.clear,
                        in: RoundedRectangle(cornerRadius: Theme.Radius.control))
            .overlay {
                if !selected {
                    RoundedRectangle(cornerRadius: Theme.Radius.control).strokeBorder(Theme.dimmed)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.control))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier(identifier ?? "")
    }
}

#Preview("Pastillas") {
    HStack(spacing: Theme.Space.s) {
        TicketChip("Oxxo") {}
        TicketChip("Renta", systemImage: "plus") {}
        TicketChip("Luz", selected: true) {}
    }
    .padding(Theme.Space.screen)
    .ticketPreview()
}
