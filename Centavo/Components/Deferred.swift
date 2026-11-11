import SwiftUI

/// A view made only when it is shown. A `NavigationLink` builds its destination every time the
/// screen that holds it draws; a destination whose first state costs something (the keychain,
/// a file) goes in here so it is paid once, on opening it.
///
///     NavigationLink { Deferred { BackupSettingsView() } } label: { … }
struct Deferred<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View { content() }
}
