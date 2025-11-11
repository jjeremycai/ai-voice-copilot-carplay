//
//  EntitlementsCache.swift
//  Shaw
//

import Foundation

class EntitlementsCache {
    static let shared = EntitlementsCache()

    private let defaults = UserDefaults.standard
    private let stateKey = "com.shaw.entitlements.state"
    private let lastRefreshKey = "com.shaw.entitlements.lastRefresh"

    private init() {}

    func save(state: SubscriptionState) {
        if let encoded = try? JSONEncoder().encode(state) {
            defaults.set(encoded, forKey: stateKey)
            defaults.set(Date(), forKey: lastRefreshKey)
        }
    }

    func load() -> SubscriptionState? {
        guard let data = defaults.data(forKey: stateKey),
              let state = try? JSONDecoder().decode(SubscriptionState.self, from: data) else {
            return nil
        }
        return state
    }

    func clear() {
        defaults.removeObject(forKey: stateKey)
        defaults.removeObject(forKey: lastRefreshKey)
    }

    var lastRefresh: Date? {
        defaults.object(forKey: lastRefreshKey) as? Date
    }

    func needsRefresh(interval: TimeInterval = 900) -> Bool {
        guard let lastRefresh = lastRefresh else { return true }
        return Date().timeIntervalSince(lastRefresh) > interval
    }
}
