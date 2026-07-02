//  FeatureFlag.swift
//  ShoeCycle
//
//  Feature-toggle deterministic bucketing — Swift port of the cross-platform contract
//  (architecture/feature-toggles.md, epic ShoeCycle-Web-6qm). The evaluator below MUST
//  produce byte-identical hash/bucket/inRollout decisions to the server (D), Web (F), and
//  Android (H). Any divergence is a bug in this port, not in the contract.
//

import Foundation
import CryptoKit

// MARK: - Flag definition (served JSON contract, §1)

/// A single feature-flag DEFINITION (global config, not per-user data). The per-caller
/// rollout decision is computed locally by `FeatureFlagEvaluator`.
///
/// Matches the OpenAPI `FeatureFlag` schema. `targeting` is reserved (v2+) and intentionally
/// ignored by this v1 evaluator; unknown keys are ignored per the contract.
struct FeatureFlag: Codable, Equatable {
    let key: String
    let enabled: Bool
    /// May be absent / non-integer in malformed payloads. Optional so a bad value decodes to
    /// `nil` (→ OFF, §4.1) rather than failing the whole payload decode.
    let rolloutPercentage: Int?

    enum CodingKeys: String, CodingKey {
        case key
        case enabled
        case rolloutPercentage
    }

    init(key: String, enabled: Bool, rolloutPercentage: Int?) {
        self.key = key
        self.enabled = enabled
        self.rolloutPercentage = rolloutPercentage
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        key = try container.decode(String.self, forKey: .key)
        enabled = try container.decode(Bool.self, forKey: .enabled)
        // Decode leniently: a missing, null, or non-integer rolloutPercentage becomes nil,
        // which the evaluator treats as OFF. A malformed definition must fail safe, not crash.
        rolloutPercentage = try? container.decodeIfPresent(Int.self, forKey: .rolloutPercentage)
    }
}

/// Envelope returned by the public `/api/feature-flags` serve endpoint.
struct FeatureFlagsResponse: Codable, Equatable {
    let flags: [FeatureFlag]
}

// MARK: - Evaluator (deterministic bucketing algorithm, §3 + precedence §4)

/// Pure, stateless port of the pinned bucketing algorithm. No I/O, no dependencies — this is
/// the cross-platform correctness surface exercised by the conformance fixture.
enum FeatureFlagEvaluator {

    /// Pinned constants (§3.3, §4.1). No magic numbers.
    private enum Constant {
        /// Number of leading digest bytes taken to form `hashUint32`.
        static let hashBytesTaken = 4
        /// Modulus producing a bucket in [0, 100).
        static let bucketModulus: UInt32 = 100
        /// A percentage at or above this resolves ON for everyone (subject to `enabled`).
        static let fullRolloutPercentage = 100
        /// A percentage at or below this resolves OFF for everyone.
        static let noRolloutPercentage = 0
    }

    // MARK: hashUint32 (§3.2)

    /// SHA-256 over the UTF-8 bytes of `"\(flagKey):\(bucketingId)"`, then the first 4 digest
    /// bytes interpreted big-endian as an UNSIGNED 32-bit integer.
    ///
    /// The `UInt32` return type is load-bearing: the high bit may be set (byte 0 ≥ 0x80), so a
    /// signed read would go negative and mis-bucket. See the signedness-canary vectors.
    static func hashUint32(flagKey: String, bucketingId: String) -> UInt32 {
        // Pinned input format: `${flagKey}:${bucketingId}` — colon, no whitespace, no newline.
        let input = "\(flagKey):\(bucketingId)"
        let digest = SHA256.hash(data: Data(input.utf8))
        // Take digest bytes 0..3 directly from the binary digest (never via a hex string).
        // Assemble big-endian: byte 0 is most significant.
        var result: UInt32 = 0
        for byte in digest.prefix(Constant.hashBytesTaken) {
            result = (result << 8) | UInt32(byte)
        }
        return result
    }

    /// bucket = hashUint32 % 100. Always non-negative and in [0, 100) because the operand is
    /// unsigned (`UInt32`).
    static func bucket(flagKey: String, bucketingId: String) -> Int {
        Int(hashUint32(flagKey: flagKey, bucketingId: bucketingId) % Constant.bucketModulus)
    }

    // MARK: Resolution (precedence, §4.1)

    /// Resolve a known flag definition against a bucketing id, in the exact pinned order:
    /// kill switch → >=100 ON → <=0/missing OFF → bucket check.
    static func isEnabled(_ flag: FeatureFlag, bucketingId: String) -> Bool {
        // 1. Kill switch wins over everything.
        guard flag.enabled else { return false }

        // Missing / non-integer rolloutPercentage → OFF (treat as 0). Never hash, never crash.
        guard let percentage = flag.rolloutPercentage else { return false }

        // 2. >= 100 → ON for everyone (absorbs out-of-range high values; no clamp needed).
        if percentage >= Constant.fullRolloutPercentage { return true }
        // 3. <= 0 → OFF for everyone (absorbs out-of-range low values).
        if percentage <= Constant.noRolloutPercentage { return false }

        // 4. Bucket check: ON iff bucket < rolloutPercentage (strict <).
        return bucket(flagKey: flag.key, bucketingId: bucketingId) < percentage
    }

    /// Resolve a flag by key against a set of definitions.
    ///
    /// - Unknown key → the caller-supplied `default` (§4.2), which itself defaults to `false`.
    ///   Never throws.
    static func isEnabled(
        key: String,
        in flags: [FeatureFlag],
        bucketingId: String,
        default defaultValue: Bool = false
    ) -> Bool {
        guard let flag = flags.first(where: { $0.key == key }) else {
            return defaultValue
        }
        return isEnabled(flag, bucketingId: bucketingId)
    }
}
