import SwiftUI
import UIKit

extension View {
    /// «¿Descartar cambios?» for a sheet where something is typed (owner, 2026-11-11). With
    /// changes, «Cancelar» and swiping the sheet down ask once, with «Descartar» (red) and
    /// «Seguir editando»; without changes the sheet closes right away, as always. Before this,
    /// swiping down did nothing and did not say why, and «Cancelar» threw everything away.
    ///
    /// It replaces `.interactiveDismissDisabled(hasChanges)`: put it on the sheet's outermost
    /// view (around its `NavigationStack`), keep the flag in the sheet and have «Cancelar» raise it:
    ///
    ///     struct MoneyAccountSheet: View {
    ///         @Environment(\.dismiss) private var dismiss
    ///         @State private var askingDiscard = false
    ///         private var hasChanges: Bool { name != loadedName || balance != loadedBalance }
    ///
    ///         var body: some View {
    ///             NavigationStack {
    ///                 Form { … }
    ///                     .toolbar {
    ///                         ToolbarItem(placement: .cancellationAction) {
    ///                             Button("Cancelar") {
    ///                                 if hasChanges { askingDiscard = true } else { dismiss() }
    ///                             }
    ///                         }
    ///                     }
    ///             }
    ///             .confirmsDiscard(hasChanges: hasChanges, isAsking: $askingDiscard) { dismiss() }
    ///         }
    ///     }
    ///
    /// `discard` closes the sheet; it runs once the question is gone, only after «Descartar».
    /// Saving must not go through here: «Guardar» calls `dismiss()` itself, as before.
    func confirmsDiscard(hasChanges: Bool, isAsking: Binding<Bool>, discard: @escaping () -> Void) -> some View {
        modifier(ConfirmsDiscard(hasChanges: hasChanges, isAsking: isAsking, discard: discard))
    }
}

private struct ConfirmsDiscard: ViewModifier {
    let hasChanges: Bool
    @Binding var isAsking: Bool
    let discard: () -> Void

    func body(content: Content) -> some View {
        content
            // A stray swipe down never throws away what was typed: the sheet stays, and asks.
            .interactiveDismissDisabled(hasChanges)
            .background {
                DismissAttemptWatcher { if hasChanges { isAsking = true } }
                    .accessibilityHidden(true)
            }
            .confirmsRemoval(isPresented: $isAsking, question: {
                TicketQuestion(title: "¿Descartar cambios?", note: "Lo que cambiaste no se guarda.",
                               verb: "Descartar", keep: "Seguir editando")
            }, onConfirm: discard)
    }
}

/// Tells when someone tries to swipe down a sheet that `interactiveDismissDisabled` holds.
/// SwiftUI has no way to hear of it; UIKit tells the sheet's delegate
/// (`presentationControllerDidAttemptToDismiss`). SwiftUI already owns that delegate, to know
/// when its sheets close, so it is not replaced: `DismissAttemptProxy` stands in front of it and
/// passes everything on. If it can't be set up, nothing breaks: the swipe stays held as before
/// and only «Cancelar» asks.
private struct DismissAttemptWatcher: UIViewControllerRepresentable {
    let onAttempt: () -> Void

    func makeUIViewController(context: Context) -> Controller { Controller() }

    func updateUIViewController(_ controller: Controller, context: Context) {
        controller.proxy.onAttempt = onAttempt
        controller.install()
    }

    final class Controller: UIViewController {
        let proxy = DismissAttemptProxy()

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            install()
        }

        /// Gone with its sheet: SwiftUI gets its delegate back before the sheet is released.
        override func viewDidDisappear(_ animated: Bool) {
            super.viewDidDisappear(animated)
            guard let presentation = sheet?.presentationController, presentation.delegate === proxy else { return }
            presentation.delegate = proxy.original as? any UIAdaptivePresentationControllerDelegate
        }

        /// The controller UIKit presented as the sheet this view lives in.
        private var sheet: UIViewController? {
            var top: UIViewController = self
            while let parent = top.parent { top = parent }
            return top !== self && top.presentingViewController != nil ? top : nil
        }

        /// Puts the proxy in front of whoever listens to the sheet now. Called again on every
        /// update, in case SwiftUI set its own delegate back.
        func install() {
            guard viewIfLoaded?.window != nil, let presentation = sheet?.presentationController else { return }
            let current = presentation.delegate
            guard current !== proxy else { return }
            proxy.original = current
            presentation.delegate = proxy
        }
    }
}

/// Stands in front of the sheet's own delegate: hears the swipe that was held and passes every
/// message on to the delegate that was there (SwiftUI's), which keeps working as if alone.
private final class DismissAttemptProxy: NSObject, UISheetPresentationControllerDelegate {
    /// Whoever listened before. Only read on the main thread, where UIKit calls its delegates.
    nonisolated(unsafe) weak var original: (any NSObjectProtocol)?
    var onAttempt: () -> Void = {}

    func presentationControllerDidAttemptToDismiss(_ presentationController: UIPresentationController) {
        (original as? any UIAdaptivePresentationControllerDelegate)?
            .presentationControllerDidAttemptToDismiss?(presentationController)
        onAttempt()
    }

    nonisolated override func responds(to aSelector: Selector!) -> Bool {
        if super.responds(to: aSelector) { return true }
        return original?.responds(to: aSelector) ?? false
    }

    nonisolated override func forwardingTarget(for aSelector: Selector!) -> Any? {
        if let original, original.responds(to: aSelector) { return original }
        return super.forwardingTarget(for: aSelector)
    }
}
