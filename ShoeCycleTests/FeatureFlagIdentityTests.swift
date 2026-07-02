//  FeatureFlagIdentityTests.swift
//  ShoeCycleTests
//
//  Tests for FeatureFlagIdentityProvider: the UUID-lowercase trap, stability across "launches"
//  (new instances over the same store), and Cognito-sub precedence.
//

import XCTest
@testable import ShoeCycle

final class FeatureFlagIdentityTests: XCTestCase {

    private func makeTestDefaults() -> UserDefaults {
        UserDefaults(suiteName: "com.shoecycle.tests.identity.\(UUID().uuidString)")!
    }

    // Given: No authenticated user and no previously-persisted anon id
    // When: bucketingId() is called
    // Then: A non-empty, lowercase canonical 8-4-4-4-12 UUID is returned and persisted
    func testGeneratesLowercasePersistedAnonId() {
        let defaults = makeTestDefaults()
        let provider = FeatureFlagIdentityProvider(userDefaults: defaults)

        let id = provider.bucketingId()

        XCTAssertFalse(id.isEmpty)
        XCTAssertEqual(id, id.lowercased(), "Anon UUID MUST be lowercase (cross-platform trap)")
        // 8-4-4-4-12 lowercase-hex canonical form.
        let pattern = "^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$"
        XCTAssertNotNil(id.range(of: pattern, options: .regularExpression),
                        "Anon id \(id) is not lowercase canonical UUID form")
        // Persisted at the pinned key.
        XCTAssertEqual(defaults.string(forKey: FeatureFlagIdentityProvider.anonIdStorageKey), id)
    }

    // Given: An anon id already persisted
    // When: A fresh provider (simulating a new app launch) reads the id
    // Then: The same id is returned — the user does not flip cohorts across restarts
    func testAnonIdStableAcrossLaunches() {
        let defaults = makeTestDefaults()

        let first = FeatureFlagIdentityProvider(userDefaults: defaults).bucketingId()
        // New instance over the same store == a subsequent launch.
        let second = FeatureFlagIdentityProvider(userDefaults: defaults).bucketingId()

        XCTAssertEqual(first, second)
    }

    // Given: An authenticated user id (Cognito sub) is available
    // When: bucketingId() is called
    // Then: The sub is used verbatim and takes precedence over the anon UUID
    func testAuthenticatedIdTakesPrecedenceAndIsVerbatim() {
        let defaults = makeTestDefaults()
        let sub = "cognito-sub-9f8e7d6c5b4a"
        let provider = FeatureFlagIdentityProvider(
            userDefaults: defaults,
            authenticatedUserId: { sub }
        )

        XCTAssertEqual(provider.bucketingId(), sub, "Cognito sub must be used verbatim")
    }
}
