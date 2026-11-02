import CentavoCore
import LocalAuthentication

/// «Is this the owner?»: Face ID or Touch ID, or the phone's passcode when they fail. Used by
/// «Mi dinero» and by the backup's restore and «Cambiar contraseña» (2026-11-02 audit).
///
/// A phone with no passcode at all has nothing to check against: it passes, as the phone
/// itself does (2026-10-31). The words say so before (`UnlockMethod.none`).
enum OwnerCheck {
    @MainActor
    static func confirm(reason: String, context: LAContext = LAContext()) async -> Bool {
        var problem: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &problem) else {
            return problem?.code == LAError.passcodeNotSet.rawValue
        }
        return (try? await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)) ?? false
    }

    /// What this phone uses, read now (Face ID can be turned off or the passcode removed).
    static var method: UnlockMethod {
        var passcode: NSError?
        if !LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: &passcode),
           passcode?.code == LAError.passcodeNotSet.rawValue { return .none }
        // `biometryType` is only filled after a `canEvaluatePolicy`.
        let context = LAContext()
        _ = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        switch context.biometryType {
        case .faceID: return .faceID
        case .touchID: return .touchID
        default: return .passcode
        }
    }
}
