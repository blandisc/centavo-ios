import Foundation

/// What is switched off for now (owner, 2026-11-18: «Mi dinero» isn't polished enough to launch).
/// Off means hidden, never removed: its code, its store (`dinero.store`) and its place in the
/// backup stay as they are, so whoever had data keeps it and turning it back on is one line.
enum Features {
    /// «Mi dinero»: its tab and every mention of it on screen. Off in Release; in Debug,
    /// `-centavo-mi-dinero` or any of its demos (`-centavo-dinero-demo`, `-centavo-dinero-vacio`)
    /// turns it on, so its UI tests keep running.
    static var money: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("-centavo-mi-dinero") || DemoData.isMoneyDemoRequested
        #else
        false
        #endif
    }
}
