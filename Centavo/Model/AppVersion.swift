import Foundation

/// Which build this is, to tell whether the iPhone has the latest (owner, 2026-10-30):
/// the number of commits and the commit's short hash, passed as build settings by
/// `Tools/instalar.sh` (any other build says «compilación 1 · local»).
enum AppVersion {
    /// «Al día 0.1.0 · compilación 312 · 59f8d9e».
    static var line: String {
        let info = Bundle.main.infoDictionary ?? [:]
        let version = info["CFBundleShortVersionString"] as? String ?? "—"
        let build = info["CFBundleVersion"] as? String ?? "—"
        let commit = info["CentavoCommit"] as? String
        return (["Al día \(version)", "compilación \(build)"] + (commit.map { [$0] } ?? [])).joined(separator: " · ")
    }

    /// The same line in the phone's language, for «Ajustes». `line` stays as it is: it goes
    /// into every backup (`writtenBy`).
    static var shownLine: String {
        let info = Bundle.main.infoDictionary ?? [:]
        let version = info["CFBundleShortVersionString"] as? String ?? "—"
        let build = info["CFBundleVersion"] as? String ?? "—"
        guard let commit = info["CentavoCommit"] as? String else {
            return String(localized: "Al día \(version) · compilación \(build)")
        }
        return String(localized: "Al día \(version) · compilación \(build) · \(commit)")
    }
}
