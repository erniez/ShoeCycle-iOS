//  FeatureFlagService.swift
//  ShoeCycle
//
//  Fetches the PUBLIC feature-flag serve endpoint (no auth header), decodes the definitions,
//  and caches the last good response for offline / stale fallback
//  (architecture/feature-toggles.md §4.3). Lives alongside NetworkService / StravaService.
//

import Foundation
import OSLog

/// Loads feature-flag definitions from the public serve endpoint and persists the last good
/// response so evaluation can degrade gracefully offline.
protocol FeatureFlagLoading {
    /// Fetches fresh definitions from the network and, on success, updates the cache. On any
    /// network/parse failure, returns the last cached definitions (or an empty array if there
    /// is no cache). Never throws — flag loading must never block app launch.
    func loadFlags() async -> [FeatureFlag]

    /// The last successfully-cached definitions, without touching the network. Empty if the
    /// cache has never been populated.
    var cachedFlags: [FeatureFlag] { get }
}

final class FeatureFlagService: FeatureFlagLoading {

    /// Pinned configuration — endpoint path, cache key, TTL (no magic numbers, §5).
    enum Constant {
        /// Public serve endpoint (unauthenticated). Path pinned by sub-issue C's OpenAPI.
        static let endpoint = URL(string: "https://api.shoecycleapp.com/api/feature-flags")!
        /// UserDefaults key for the cached last-good definitions.
        static let cacheKey = "com.shoecycle.featureToggles.cachedFlags"
        /// Cache time-to-live. Definitions older than this are refreshed on next opportunity;
        /// stale-but-present cache is still used for offline fallback per §4.3.
        static let cacheTTL: TimeInterval = 60 * 60 // 1 hour
    }

    private let session: URLSession
    private let userDefaults: UserDefaults

    init(session: URLSession = .shared, userDefaults: UserDefaults = .standard) {
        self.session = session
        self.userDefaults = userDefaults
    }

    // MARK: - Loading

    func loadFlags() async -> [FeatureFlag] {
        do {
            // PUBLIC endpoint: a plain GET with NO Authorization header.
            let (data, response) = try await session.data(from: Constant.endpoint)
            guard let http = response as? HTTPURLResponse,
                  (200...299).contains(http.statusCode) else {
                return cachedFlags
            }
            let decoded = try JSONDecoder().decode(FeatureFlagsResponse.self, from: data)
            cache(decoded.flags)
            return decoded.flags
        } catch {
            // Network or parse failure never crashes and never blocks launch: fall back to the
            // last cached definitions (§4.3).
            Logger.app.error("Feature flag fetch failed, using cache: \(error.localizedDescription)")
            return cachedFlags
        }
    }

    // MARK: - Cache

    var cachedFlags: [FeatureFlag] {
        guard let entry = cachedEntry() else { return [] }
        return entry.flags
    }

    /// The cache entry including its timestamp, or nil if none / undecodable.
    private func cachedEntry() -> CacheEntry? {
        guard let data = userDefaults.data(forKey: Constant.cacheKey) else { return nil }
        return try? JSONDecoder().decode(CacheEntry.self, from: data)
    }

    /// True when a cache exists and is within `cacheTTL`.
    var isCacheFresh: Bool {
        guard let entry = cachedEntry() else { return false }
        return Date().timeIntervalSince(entry.timestamp) < Constant.cacheTTL
    }

    private func cache(_ flags: [FeatureFlag]) {
        let entry = CacheEntry(flags: flags, timestamp: Date())
        if let data = try? JSONEncoder().encode(entry) {
            userDefaults.set(data, forKey: Constant.cacheKey)
        }
    }

    private struct CacheEntry: Codable {
        let flags: [FeatureFlag]
        let timestamp: Date
    }
}
