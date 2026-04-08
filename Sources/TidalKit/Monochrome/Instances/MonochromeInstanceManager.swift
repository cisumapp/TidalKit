import Foundation

public enum MonochromeInstanceKind: String, Sendable {
    case api
    case streaming
}

public struct MonochromeAPIInstance: Identifiable, Hashable, Codable, Sendable {
    public var id: String { url }
    public let url: String
    public let version: String
    public let name: String?
    public let isUser: Bool

    public var label: String {
        URL(string: url)?.host ?? url
    }

    public init(url: String, version: String = "unknown", name: String? = nil, isUser: Bool = false) {
        let cleaned = url.hasSuffix("/") ? String(url.dropLast()) : url
        self.url = cleaned
        self.version = version
        self.name = name
        self.isUser = isUser
    }
}

public actor MonochromeInstanceManager {
    private struct CachedData: Codable {
        let timestamp: TimeInterval
        let api: [MonochromeAPIInstance]
        let streaming: [MonochromeAPIInstance]
    }

    private let defaults: UserDefaults
    private let cacheKey = "tidalkit-monochrome-api-instances-v1"
    private let userKey = "tidalkit-monochrome-user-instances-v1"

    private let uptimeURLs: [URL]
    private let cacheDuration: TimeInterval

    public private(set) var apiInstances: [MonochromeAPIInstance]
    public private(set) var streamingInstances: [MonochromeAPIInstance]
    public private(set) var isRefreshing: Bool = false

    private var userAPIInstances: [MonochromeAPIInstance] = []
    private var userStreamingInstances: [MonochromeAPIInstance] = []

    public init(
        configuration: MonochromeConfiguration,
        defaults: UserDefaults = .standard,
        loadFromNetworkOnInit: Bool = true
    ) {
        self.defaults = defaults
        self.uptimeURLs = configuration.instanceUptimeURLs
        self.cacheDuration = configuration.instanceCacheDuration

        self.apiInstances = configuration.fallbackAPIInstances.map { MonochromeAPIInstance(url: $0, version: "fallback") }
        self.streamingInstances = configuration.fallbackStreamingInstances.map { MonochromeAPIInstance(url: $0, version: "fallback") }

        if let data = defaults.data(forKey: userKey),
           let decoded = try? JSONDecoder().decode([String: [MonochromeAPIInstance]].self, from: data) {
            self.userAPIInstances = decoded[MonochromeInstanceKind.api.rawValue] ?? []
            self.userStreamingInstances = decoded[MonochromeInstanceKind.streaming.rawValue] ?? []
        }

        if let data = defaults.data(forKey: cacheKey),
           let cached = try? JSONDecoder().decode(CachedData.self, from: data),
           Date().timeIntervalSince1970 - cached.timestamp < cacheDuration {
            self.apiInstances = Self.prioritySort(cached.api)
            self.streamingInstances = Self.prioritySort(cached.streaming)
        }

        if loadFromNetworkOnInit {
            Task { await self.loadFromNetwork() }
        }
    }

    public func instances(for kind: MonochromeInstanceKind) -> [MonochromeAPIInstance] {
        switch kind {
        case .api:
            return userAPIInstances + apiInstances
        case .streaming:
            return userStreamingInstances + streamingInstances
        }
    }

    public func refreshInstances() async {
        isRefreshing = true
        defaults.removeObject(forKey: cacheKey)
        await loadFromNetwork()
        isRefreshing = false
    }

    public func addUserInstance(_ url: String, kind: MonochromeInstanceKind) {
        let instance = MonochromeAPIInstance(url: url, version: "custom", isUser: true)
        switch kind {
        case .api:
            guard !userAPIInstances.contains(where: { $0.url == instance.url }) else { return }
            userAPIInstances.append(instance)
        case .streaming:
            guard !userStreamingInstances.contains(where: { $0.url == instance.url }) else { return }
            userStreamingInstances.append(instance)
        }
        saveUserInstances()
    }

    public func removeUserInstance(_ url: String, kind: MonochromeInstanceKind) {
        switch kind {
        case .api:
            userAPIInstances.removeAll { $0.url == url }
        case .streaming:
            userStreamingInstances.removeAll { $0.url == url }
        }
        saveUserInstances()
    }

    private func loadFromNetwork() async {
        var selectedData: Data?

        for url in uptimeURLs {
            do {
                let (data, response) = try await URLSession.shared.data(from: url)
                guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { continue }
                selectedData = data
                break
            } catch {
                continue
            }
        }

        guard let selectedData,
              let json = try? JSONSerialization.jsonObject(with: selectedData) as? [String: Any] else {
            return
        }

        let api = Self.decodeInstances(json["api"])
        let streaming = Self.decodeInstances(json["streaming"])

        guard !api.isEmpty else { return }
        apiInstances = Self.prioritySort(api)
        streamingInstances = Self.prioritySort(streaming.isEmpty ? api : streaming)
        saveToCache()
    }

    private static func decodeInstances(_ value: Any?) -> [MonochromeAPIInstance] {
        guard let array = value as? [[String: Any]] else { return [] }

        return array.compactMap { item in
            guard let url = item["url"] as? String else { return nil }
            if isBlocked(url) { return nil }

            return MonochromeAPIInstance(
                url: url,
                version: item["version"] as? String ?? "unknown",
                name: item["name"] as? String,
                isUser: false
            )
        }
    }

    private static func isBlocked(_ url: String) -> Bool {
        url.contains(".squid.wtf")
    }

    private static func prioritySort(_ instances: [MonochromeAPIInstance]) -> [MonochromeAPIInstance] {
        var top: [MonochromeAPIInstance] = []
        var middle: [MonochromeAPIInstance] = []
        var bottom: [MonochromeAPIInstance] = []

        for instance in instances {
            if instance.url.contains("hifi.geeked.wtf") {
                top.append(instance)
            } else if instance.url.contains(".qqdl.site") {
                bottom.append(instance)
            } else {
                middle.append(instance)
            }
        }

        return top + middle.shuffled() + bottom.shuffled()
    }
    private func saveToCache() {
        let cached = CachedData(
            timestamp: Date().timeIntervalSince1970,
            api: apiInstances,
            streaming: streamingInstances
        )

        if let data = try? JSONEncoder().encode(cached) {
            defaults.set(data, forKey: cacheKey)
        }
    }

    private func saveUserInstances() {
        let payload = [
            MonochromeInstanceKind.api.rawValue: userAPIInstances,
            MonochromeInstanceKind.streaming.rawValue: userStreamingInstances,
        ]

        if let data = try? JSONEncoder().encode(payload) {
            defaults.set(data, forKey: userKey)
        }
    }
}
