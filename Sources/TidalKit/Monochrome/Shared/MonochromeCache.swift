import Foundation

public struct MonochromeCacheStatistics: Sendable {
    public let entryCount: Int
    public let totalSizeBytes: Int

    public var formattedSize: String {
        if totalSizeBytes < 1024 {
            return "\(totalSizeBytes) B"
        }
        if totalSizeBytes < 1024 * 1024 {
            return String(format: "%.1f KB", Double(totalSizeBytes) / 1024)
        }
        return String(format: "%.1f MB", Double(totalSizeBytes) / (1024 * 1024))
    }
}

public actor MonochromeCache {
    private struct MemoryEntry {
        let data: Data
        let timestamp: Date
    }

    private struct DiskEntry: Codable {
        let data: Data
        let timestamp: Date
    }

    private var memory: [String: MemoryEntry] = [:]
    private let diskDirectory: URL

    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public var maxAge: TimeInterval
    public var maxSizeMB: Int

    public init(
        name: String = "MonochromeAPICache",
        maxAge: TimeInterval,
        maxSizeMB: Int,
        diskDirectory: URL? = nil
    ) {
        self.maxAge = maxAge
        self.maxSizeMB = maxSizeMB

        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()
        self.encoder.nonConformingFloatEncodingStrategy = .convertToString(
            positiveInfinity: "inf",
            negativeInfinity: "-inf",
            nan: "nan"
        )
        self.decoder.nonConformingFloatDecodingStrategy = .convertFromString(
            positiveInfinity: "inf",
            negativeInfinity: "-inf",
            nan: "nan"
        )

        if let diskDirectory {
            self.diskDirectory = diskDirectory
        } else {
            let cacheRoot = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
                ?? URL(fileURLWithPath: NSTemporaryDirectory())
            self.diskDirectory = cacheRoot.appendingPathComponent(name, isDirectory: true)
        }

        try? FileManager.default.createDirectory(at: self.diskDirectory, withIntermediateDirectories: true)
    }

    public func age(forKey key: String) -> TimeInterval? {
        if let entry = memory[key] {
            return Date().timeIntervalSince(entry.timestamp)
        }

        let url = diskDirectory.appendingPathComponent(diskName(for: key))
        guard let data = try? Data(contentsOf: url),
              let disk = try? decoder.decode(DiskEntry.self, from: data) else {
            return nil
        }

        return Date().timeIntervalSince(disk.timestamp)
    }

    public func get<T: Codable & Sendable>(_ type: T.Type, forKey key: String, ignoreExpiry: Bool = false) -> T? {
        if let entry = memory[key] {
            let expired = Date().timeIntervalSince(entry.timestamp) >= maxAge
            if !ignoreExpiry && expired {
                memory.removeValue(forKey: key)
            } else if let decoded = try? decoder.decode(T.self, from: entry.data) {
                return decoded
            } else {
                memory.removeValue(forKey: key)
            }
        }

        let url = diskDirectory.appendingPathComponent(diskName(for: key))
        guard let data = try? Data(contentsOf: url),
              let disk = try? decoder.decode(DiskEntry.self, from: data) else {
            return nil
        }

        let expired = Date().timeIntervalSince(disk.timestamp) >= maxAge
        if !ignoreExpiry && expired {
            try? FileManager.default.removeItem(at: url)
            return nil
        }

        guard let decoded = try? decoder.decode(T.self, from: disk.data) else {
            try? FileManager.default.removeItem(at: url)
            return nil
        }

        memory[key] = MemoryEntry(data: disk.data, timestamp: disk.timestamp)
        return decoded
    }

    public func set<T: Codable & Sendable>(_ value: T, forKey key: String) {
        guard let payload = try? encoder.encode(value) else { return }

        let now = Date()
        memory[key] = MemoryEntry(data: payload, timestamp: now)

        let disk = DiskEntry(data: payload, timestamp: now)
        if let diskData = try? encoder.encode(disk) {
            let url = diskDirectory.appendingPathComponent(diskName(for: key))
            try? diskData.write(to: url, options: .atomic)
        }

        evictIfNeeded()
    }

    public func remove(forKey key: String) {
        memory.removeValue(forKey: key)
        let url = diskDirectory.appendingPathComponent(diskName(for: key))
        try? FileManager.default.removeItem(at: url)
    }

    public func clear() {
        memory.removeAll()
        try? FileManager.default.removeItem(at: diskDirectory)
        try? FileManager.default.createDirectory(at: diskDirectory, withIntermediateDirectories: true)
    }

    public func statistics() -> MonochromeCacheStatistics {
        let urls = (try? FileManager.default.contentsOfDirectory(at: diskDirectory, includingPropertiesForKeys: [.fileSizeKey])) ?? []
        let sizes = urls.compactMap { try? $0.resourceValues(forKeys: [.fileSizeKey]).fileSize }
        let total = sizes.reduce(0, +)
        return MonochromeCacheStatistics(entryCount: urls.count, totalSizeBytes: total)
    }

    private func diskName(for key: String) -> String {
        Data(key.utf8)
            .base64EncodedString()
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "+", with: "-")
    }

    private func evictIfNeeded() {
        let maxBytes = maxSizeMB * 1024 * 1024
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: diskDirectory,
            includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey]
        )) ?? []

        var totalBytes = urls
            .compactMap { try? $0.resourceValues(forKeys: [.fileSizeKey]).fileSize }
            .reduce(0, +)

        guard totalBytes > maxBytes else { return }

        let sorted = urls.sorted { lhs, rhs in
            let lDate = (try? lhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let rDate = (try? rhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return lDate < rDate
        }

        for url in sorted where totalBytes > maxBytes {
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            try? FileManager.default.removeItem(at: url)
            totalBytes -= size
        }
    }
}
