import Foundation
import Security

/// Where the app leaves the `WidgetSnapshot` and the widgets read it.
///
/// First choice is the App Group, when this build is really signed with it (its container
/// exists). A free developer account gets profiles without the App Group from
/// `xcodebuild`, so then the snapshot goes in a Keychain item of an access group both
/// targets share: free profiles allow any `TEAMID.*` group without registering it.
public struct WidgetSnapshotStore: Sendable {
    public static let appGroup = "group.com.blandisc.centavo"
    /// Info.plist key with the Keychain group, `$(AppIdentifierPrefix)com.blandisc.centavo.shared`,
    /// so the team prefix is resolved when signing.
    public static let keychainGroupKey = "CentavoKeychainGroup"
    static let service = "centavo.widget"
    static let account = "snapshot"

    public let appGroup: String
    public let keychainGroup: String?

    public init(appGroup: String = WidgetSnapshotStore.appGroup,
                keychainGroup: String? = Bundle.main.object(forInfoDictionaryKey: WidgetSnapshotStore.keychainGroupKey) as? String) {
        self.appGroup = appGroup
        self.keychainGroup = keychainGroup.flatMap { $0.isEmpty || $0.hasPrefix("$(") ? nil : $0 }
    }

    /// The App Group's defaults, only when the group is really there: without the entitlement
    /// `UserDefaults(suiteName:)` still answers, but writes to the process's own defaults.
    public var groupDefaults: UserDefaults? {
        guard FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup) != nil else { return nil }
        return UserDefaults(suiteName: appGroup)
    }

    public func read() -> Data? {
        if let defaults = groupDefaults { return defaults.data(forKey: WidgetSnapshot.key) }
        var query = itemQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess else { return nil }
        return result as? Data
    }

    @discardableResult public func write(_ data: Data) -> Bool {
        if let defaults = groupDefaults {
            defaults.set(data, forKey: WidgetSnapshot.key)
            return true
        }
        let changes: [String: Any] = [kSecValueData as String: data,
                                      kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock]
        let status = SecItemUpdate(itemQuery as CFDictionary, changes as CFDictionary)
        guard status == errSecItemNotFound else { return status == errSecSuccess }
        return SecItemAdd(itemQuery.merging(changes) { $1 } as CFDictionary, nil) == errSecSuccess
    }

    /// The Keychain item: one generic password, readable after the first unlock (the widget
    /// draws with the phone locked).
    var itemQuery: [String: Any] {
        var query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrService as String: Self.service,
                                    kSecAttrAccount as String: Self.account]
        if let keychainGroup { query[kSecAttrAccessGroup as String] = keychainGroup }
        return query
    }
}
