//  FeatureFlagIdentity.swift
//  ShoeCycle
//
//  Bucketing-identity resolution for feature toggles (architecture/feature-toggles.md §3.1).
//  Precedence: authenticated Cognito `sub` when available, else a persisted anonymous UUID
//  that survives app restarts.
//

import Foundation

/// Supplies the stable per-caller identity hashed for percentage bucketing.
protocol FeatureFlagIdentityProviding {
    /// The bucketing id per the pinned precedence: authenticated user id if signed in, else a
    /// persisted anonymous UUID. Never empty — an anon UUID is generated + persisted
    /// synchronously on first read if none exists yet.
    func bucketingId() -> String
}

/// Default identity provider.
///
/// The app currently has no authenticated-user identity, so `authenticatedUserId` defaults to
/// `nil` and the anonymous-UUID path is used. When Cognito auth is added, inject the `sub`
/// here (verbatim — no normalization) and it takes precedence.
final class FeatureFlagIdentityProvider: FeatureFlagIdentityProviding {

    /// UserDefaults key for the persisted anonymous UUID. Namespaced per the pinned iOS
    /// location (§3.1) so it is stable across launches.
    static let anonIdStorageKey = "com.shoecycle.featureToggles.anonId"

    private let userDefaults: UserDefaults
    private let authenticatedUserIdProvider: () -> String?

    /// - Parameters:
    ///   - userDefaults: persistence for the anonymous UUID (pinned iOS location).
    ///   - authenticatedUserId: closure returning the Cognito `sub` when signed in, else nil.
    ///     Defaults to always-nil until auth exists in the app.
    init(
        userDefaults: UserDefaults = .standard,
        authenticatedUserId: @escaping () -> String? = { nil }
    ) {
        self.userDefaults = userDefaults
        self.authenticatedUserIdProvider = authenticatedUserId
    }

    func bucketingId() -> String {
        // 1. Authenticated identity wins and is used verbatim (no case normalization).
        if let authenticatedId = authenticatedUserIdProvider(), !authenticatedId.isEmpty {
            return authenticatedId
        }
        // 2. Else the persisted anonymous UUID, generating + persisting one synchronously if
        // none exists. Never returns empty (that would collapse all anon users into one bucket).
        return persistedAnonymousId()
    }

    private func persistedAnonymousId() -> String {
        if let existing = userDefaults.string(forKey: Self.anonIdStorageKey), !existing.isEmpty {
            return existing
        }
        // CRITICAL cross-platform trap (§3.1): Swift's UUID().uuidString is UPPERCASE, but the
        // contract pins the lowercase canonical 8-4-4-4-12 form. Normalize to lowercase ONCE,
        // at generation time, before persisting — otherwise iOS buckets the same anon user
        // differently from Web/Android.
        let newId = UUID().uuidString.lowercased()
        userDefaults.set(newId, forKey: Self.anonIdStorageKey)
        return newId
    }
}
