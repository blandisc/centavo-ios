import Foundation

/// Which build this is, to tell whether the iPhone has the latest (owner, 2026-10-30). The build
/// stamps it (Tools/stamp-build.sh): the number of commits and the commit's short hash.
enum AppVersion {
    /// «Al día 0.1.0 · compilación 312 · 59f8d9e».
    static var line: String {
        let info = Bundle.main.infoDictionary ?? [:]
        let version = info["CFBundleShortVersionString"] as? String ?? "—"
        let build = info["CFBundleVersion"] as? String ?? "—"
        let commit = info["CentavoCommit"] as? String
        return (["Al día \(version)", "compilación \(build)"] + (commit.map { [$0] } ?? [])).joined(separator: " · ")
    }
}
