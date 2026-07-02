//  FeatureFlagsInteractions.swift
//  ShoeCycle
//
//  VSI layer for feature toggles: an interactor owns the fetch + evaluation, a FeatureFlags
//  state struct carries the raw definitions, and views observe resolved boolean values only
//  (via isEnabled(_:default:)) — never the raw service or evaluation logic
//  (architecture/vsi-pattern.md).
//

import SwiftUI

// MARK: - State (data only)

/// Feature-flag feature state. Holds the loaded raw definitions and the resolved bucketing
/// identity. Views never mutate this directly and never re-implement evaluation — they call
/// `isEnabled(_:default:)` to read resolved booleans.
struct FeatureFlagsState {
    fileprivate(set) var flags: [FeatureFlag] = []
    fileprivate(set) var isLoading: Bool = false

    /// The bucketing identity resolved once at load time and reused for every evaluation so a
    /// caller stays in / out of a cohort consistently within a session.
    fileprivate(set) var bucketingId: String = ""

    /// Resolve a flag by key to a boolean, applying the full precedence + bucketing algorithm.
    /// Unknown key → the supplied `default` (else `false`). Never crashes.
    func isEnabled(_ key: String, default defaultValue: Bool = false) -> Bool {
        FeatureFlagEvaluator.isEnabled(
            key: key,
            in: flags,
            bucketingId: bucketingId,
            default: defaultValue
        )
    }
}

// MARK: - Interactor (all logic + side effects)

/// Owns feature-flag fetch, caching fallback, and identity resolution. The only place that
/// touches `FeatureFlagService` and `FeatureFlagIdentityProvider`.
struct FeatureFlagsInteractor {

    enum Action {
        /// Load flags: seed from cache immediately for a non-flickering launch, then refresh
        /// from the network in the background.
        case viewAppeared
        /// Refresh definitions from the network (cache fallback on failure).
        case refresh
    }

    private let service: FeatureFlagLoading
    private let identityProvider: FeatureFlagIdentityProviding

    init(
        service: FeatureFlagLoading = FeatureFlagService(),
        identityProvider: FeatureFlagIdentityProviding = FeatureFlagIdentityProvider()
    ) {
        self.service = service
        self.identityProvider = identityProvider
    }

    /// Async because the network fetch is async; the interactor owns the Task/await, not the
    /// view. Callers dispatch and re-render when state changes.
    func handle(state: Binding<FeatureFlagsState>, action: Action) async {
        switch action {
        case .viewAppeared:
            // Resolve identity up front (generates + persists the anon UUID synchronously if
            // needed — never an empty bucketing id).
            state.wrappedValue.bucketingId = identityProvider.bucketingId()
            // Seed from last-good cache immediately so evaluation works offline / pre-fetch.
            state.wrappedValue.flags = service.cachedFlags
            await handle(state: state, action: .refresh)

        case .refresh:
            if state.wrappedValue.bucketingId.isEmpty {
                state.wrappedValue.bucketingId = identityProvider.bucketingId()
            }
            state.wrappedValue.isLoading = true
            let flags = await service.loadFlags()
            state.wrappedValue.flags = flags
            state.wrappedValue.isLoading = false
        }
    }
}

// MARK: - Known flag keys

/// Central registry of flag keys so views reference constants, not string literals.
enum FeatureFlagKey {
    /// Trivial reversible demo flag proving end-to-end wiring (gates a badge in Settings).
    static let settingsDemoBadge = "ios-settings-demo-badge"
}
