import SwiftUI

extension View {
    /// What every `#Preview` wraps itself in: the app's paper and its forced dark mode, so a
    /// preview looks like the app and not like a white canvas.
    func ticketPreview() -> some View {
        self
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.background.ignoresSafeArea())
            .preferredColorScheme(.dark)
            .onAppear { TicketFont.register() }
    }
}
