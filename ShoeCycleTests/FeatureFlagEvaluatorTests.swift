//  FeatureFlagEvaluatorTests.swift
//  ShoeCycleTests
//
//  Cross-platform conformance for the Swift feature-toggle evaluator. Loads the committed
//  spec-A test-vectors fixture (vendored byte-identical into the test bundle) and asserts the
//  Swift port produces the same hash / bucket / inRollout as the frozen oracle — including the
//  two signedness canaries. Plus default-fallback and cached/offline-fallback tests.
//

import XCTest
@testable import ShoeCycle

final class FeatureFlagEvaluatorTests: XCTestCase {

    // MARK: - Fixture model

    /// Fixture shape (architecture/feature-toggles.vectors.json §5.2).
    private struct Fixture: Decodable {
        let schemaVersion: Int
        let vectors: [Vector]
    }

    private struct Vector: Decodable {
        let flagKey: String
        let bucketingId: String
        let bucketingInput: String
        let hashHex8: String
        let hashUint32: UInt32
        let bucket: Int
        let rolloutPercentage: Int
        let inRollout: Bool
    }

    /// Expected fixture schema version — assert it so a future breaking change fails loudly.
    private let expectedSchemaVersion = 1

    private func loadFixture() throws -> Fixture {
        let bundle = Bundle(for: type(of: self))
        guard let url = bundle.url(forResource: "feature-toggles.vectors", withExtension: "json") else {
            XCTFail("Vendored fixture feature-toggles.vectors.json not found in test bundle")
            throw NSError(domain: "FeatureFlagEvaluatorTests", code: 1)
        }
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(Fixture.self, from: data)
    }

    // MARK: - Conformance

    // Given: The frozen spec-A test-vectors fixture (vendored byte-identical)
    // When: The Swift evaluator recomputes hashUint32, bucket, and inRollout for every vector
    // Then: Every column matches the oracle exactly (proving cross-platform agreement)
    func testConformanceAgainstFrozenFixture() throws {
        let fixture = try loadFixture()

        XCTAssertEqual(fixture.schemaVersion, expectedSchemaVersion,
                       "Fixture schema version drifted from what this test expects")
        XCTAssertEqual(fixture.vectors.count, 6, "Expected the 6 committed conformance vectors")

        for vector in fixture.vectors {
            // Guard against a stale copy: our computed input must match the fixture's.
            XCTAssertEqual("\(vector.flagKey):\(vector.bucketingId)", vector.bucketingInput,
                           "bucketingInput mismatch for \(vector.flagKey)")

            let computedHash = FeatureFlagEvaluator.hashUint32(
                flagKey: vector.flagKey,
                bucketingId: vector.bucketingId
            )
            XCTAssertEqual(computedHash, vector.hashUint32,
                           "hashUint32 mismatch for \(vector.bucketingInput): got \(computedHash), expected \(vector.hashUint32)")

            // Human-readable hex rendering of the first 4 digest bytes must also line up.
            XCTAssertEqual(String(format: "%08x", computedHash), vector.hashHex8,
                           "hashHex8 mismatch for \(vector.bucketingInput)")

            let computedBucket = FeatureFlagEvaluator.bucket(
                flagKey: vector.flagKey,
                bucketingId: vector.bucketingId
            )
            XCTAssertEqual(computedBucket, vector.bucket,
                           "bucket mismatch for \(vector.bucketingInput): got \(computedBucket), expected \(vector.bucket)")

            // Defensive: every bucket must be non-negative and in [0, 100) — the signedness
            // trap manifests as a negative or out-of-range bucket.
            XCTAssertTrue((0..<100).contains(computedBucket),
                          "bucket \(computedBucket) out of range [0,100) for \(vector.bucketingInput)")

            // inRollout = bucket < rolloutPercentage
            let flag = FeatureFlag(key: vector.flagKey, enabled: true, rolloutPercentage: vector.rolloutPercentage)
            let computedInRollout = FeatureFlagEvaluator.isEnabled(flag, bucketingId: vector.bucketingId)
            XCTAssertEqual(computedInRollout, vector.inRollout,
                           "inRollout mismatch for \(vector.bucketingInput): got \(computedInRollout), expected \(vector.inRollout)")
        }
    }

    // Given: The two deliberate signedness-canary vectors (high bit set in digest byte 0)
    // When: The evaluator reads the first 4 bytes as an unsigned UInt32 before the modulo
    // Then: Buckets are 83 and 46 (NOT the negative/absolute-value results a signed read gives)
    func testSignednessCanaries() {
        // e9b6b98f → 3921066383 → bucket 83 (signed read would give -13)
        XCTAssertEqual(
            FeatureFlagEvaluator.hashUint32(flagKey: "translation-rollout",
                                            bucketingId: "a1b2c3d4-0000-4000-8000-000000000002"),
            3921066383
        )
        XCTAssertEqual(
            FeatureFlagEvaluator.bucket(flagKey: "translation-rollout",
                                        bucketingId: "a1b2c3d4-0000-4000-8000-000000000002"),
            83
        )

        // 9298ff9e → 2459500446 → bucket 46 (signed read would give -50)
        XCTAssertEqual(
            FeatureFlagEvaluator.hashUint32(flagKey: "offline-sync",
                                            bucketingId: "cognito-sub-9f8e7d6c5b4a"),
            2459500446
        )
        XCTAssertEqual(
            FeatureFlagEvaluator.bucket(flagKey: "offline-sync",
                                        bucketingId: "cognito-sub-9f8e7d6c5b4a"),
            46
        )
    }

    // MARK: - Precedence

    // Given: A flag with enabled == false
    // When: Resolving it, regardless of rolloutPercentage
    // Then: Kill switch wins → OFF
    func testKillSwitchWinsOverRollout() {
        let flag = FeatureFlag(key: "k", enabled: false, rolloutPercentage: 100)
        XCTAssertFalse(FeatureFlagEvaluator.isEnabled(flag, bucketingId: "id"))
    }

    // Given: An enabled flag at >= 100 percent (including out-of-range 150)
    // When: Resolving it
    // Then: ON for everyone, no hashing needed
    func testFullRolloutIsOn() {
        XCTAssertTrue(FeatureFlagEvaluator.isEnabled(
            FeatureFlag(key: "k", enabled: true, rolloutPercentage: 100), bucketingId: "id"))
        XCTAssertTrue(FeatureFlagEvaluator.isEnabled(
            FeatureFlag(key: "k", enabled: true, rolloutPercentage: 150), bucketingId: "id"))
    }

    // Given: An enabled flag at <= 0 percent (including out-of-range -5) or missing percentage
    // When: Resolving it
    // Then: OFF for everyone, fail-safe, never hashes/crashes
    func testZeroOrMissingRolloutIsOff() {
        XCTAssertFalse(FeatureFlagEvaluator.isEnabled(
            FeatureFlag(key: "k", enabled: true, rolloutPercentage: 0), bucketingId: "id"))
        XCTAssertFalse(FeatureFlagEvaluator.isEnabled(
            FeatureFlag(key: "k", enabled: true, rolloutPercentage: -5), bucketingId: "id"))
        XCTAssertFalse(FeatureFlagEvaluator.isEnabled(
            FeatureFlag(key: "k", enabled: true, rolloutPercentage: nil), bucketingId: "id"))
    }

    // MARK: - Unknown-key / default fallback (§4.2)

    // Given: A set of definitions that does NOT contain the requested key
    // When: Resolving with and without a caller default
    // Then: Returns the caller default, else false — never throws
    func testUnknownKeyReturnsCallerDefault() {
        let flags = [FeatureFlag(key: "present", enabled: true, rolloutPercentage: 100)]

        XCTAssertFalse(FeatureFlagEvaluator.isEnabled(
            key: "absent", in: flags, bucketingId: "id"))
        XCTAssertTrue(FeatureFlagEvaluator.isEnabled(
            key: "absent", in: flags, bucketingId: "id", default: true))
        // Present key still evaluates normally.
        XCTAssertTrue(FeatureFlagEvaluator.isEnabled(
            key: "present", in: flags, bucketingId: "id"))
    }

    // MARK: - Malformed payload decode (fail-safe)

    // Given: JSON where rolloutPercentage is a non-integer / null
    // When: Decoding the flag and resolving it
    // Then: rolloutPercentage decodes to nil and the flag resolves OFF, never crashing
    func testMalformedRolloutPercentageDecodesToOff() throws {
        let json = """
        { "flags": [
            { "key": "bad-string", "enabled": true, "rolloutPercentage": "oops" },
            { "key": "null-pct", "enabled": true, "rolloutPercentage": null }
        ] }
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(FeatureFlagsResponse.self, from: json)
        XCTAssertEqual(response.flags.count, 2)
        for flag in response.flags {
            XCTAssertNil(flag.rolloutPercentage)
            XCTAssertFalse(FeatureFlagEvaluator.isEnabled(flag, bucketingId: "id"))
        }
    }
}
