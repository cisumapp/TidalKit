import Foundation

public struct MonochromeConfiguration: Sendable {
    public var defaultAPIBaseURL: URL
    public var appwriteBaseURL: URL
    public var appwriteProjectID: String
    public var pocketBaseBaseURL: URL
    public var tidalFallbackBaseURL: URL
    public var tidalFallbackToken: String?
    public var userAgent: String

    public var instanceUptimeURLs: [URL]
    public var fallbackAPIInstances: [String]
    public var fallbackStreamingInstances: [String]
    public var instanceCacheDuration: TimeInterval

    public var cacheMaxAge: TimeInterval
    public var cacheMaxSizeMB: Int

    public var requestTimeout: TimeInterval
    public var maxRequestAttempts: Int

    public var keychainService: String

    public init(
        defaultAPIBaseURL: URL = URL(string: "https://hifi.geeked.wtf")!,
        appwriteBaseURL: URL = URL(string: "https://auth.monochrome.tf/v1")!,
        appwriteProjectID: String = "auth-for-monochrome",
        pocketBaseBaseURL: URL = URL(string: "https://data.samidy.xyz")!,
        tidalFallbackBaseURL: URL = URL(string: "https://api.tidal.com/v1")!,
        tidalFallbackToken: String? = nil,
        userAgent: String = "TidalKit/MonochromeSDK",
        instanceUptimeURLs: [URL] = [
            URL(string: "https://tidal-uptime.jiffy-puffs-1j.workers.dev/")!,
            URL(string: "https://tidal-uptime.props-76styles.workers.dev/")!,
        ],
        fallbackAPIInstances: [String] = [
            "https://hifi.geeked.wtf",
            "https://eu-central.monochrome.tf",
            "https://us-west.monochrome.tf",
            // "https://api.monochrome.tf",
            "https://monochrome-api.samidy.com",
            "https://maus.qqdl.site",
            "https://vogel.qqdl.site",
            "https://katze.qqdl.site",
            "https://hund.qqdl.site",
            // "https://tidal.kinoplus.online",
            "https://wolf.qqdl.site",
        ],
        fallbackStreamingInstances: [String] = [
            "https://hifi.geeked.wtf",
            "https://maus.qqdl.site",
            "https://vogel.qqdl.site",
            "https://katze.qqdl.site",
            "https://hund.qqdl.site",
            "https://wolf.qqdl.site",
        ],
        instanceCacheDuration: TimeInterval = 15 * 60,
        cacheMaxAge: TimeInterval = 24 * 3600,
        cacheMaxSizeMB: Int = 200,
        requestTimeout: TimeInterval = 10,
        maxRequestAttempts: Int = 1,
        keychainService: String = "com.tidalkit.monochrome.security"
    ) {
        self.defaultAPIBaseURL = defaultAPIBaseURL
        self.appwriteBaseURL = appwriteBaseURL
        self.appwriteProjectID = appwriteProjectID
        self.pocketBaseBaseURL = pocketBaseBaseURL
        self.tidalFallbackBaseURL = tidalFallbackBaseURL
        self.tidalFallbackToken = tidalFallbackToken
        self.userAgent = userAgent
        self.instanceUptimeURLs = instanceUptimeURLs
        self.fallbackAPIInstances = fallbackAPIInstances
        self.fallbackStreamingInstances = fallbackStreamingInstances
        self.instanceCacheDuration = instanceCacheDuration
        self.cacheMaxAge = cacheMaxAge
        self.cacheMaxSizeMB = cacheMaxSizeMB
        self.requestTimeout = requestTimeout
        self.maxRequestAttempts = maxRequestAttempts
        self.keychainService = keychainService
    }

    public static let production = MonochromeConfiguration()
}
