import Foundation

@MainActor
public final class Monochrome {
    public static let shared = Monochrome()

    public let configuration: MonochromeConfiguration
    public let cache: MonochromeCache
    public let instances: MonochromeInstanceManager
    public let content: MonochromeContentClient
    public let auth: MonochromeAuthClient
    public let pocketBase: MonochromePocketBaseClient

    public init(configuration: MonochromeConfiguration = .production) {
        self.configuration = configuration

        let cache = MonochromeCache(
            maxAge: configuration.cacheMaxAge,
            maxSizeMB: configuration.cacheMaxSizeMB
        )
        self.cache = cache

        let instances = MonochromeInstanceManager(configuration: configuration)
        self.instances = instances

        let network = MonochromeNetworkClient(configuration: configuration)
        self.content = MonochromeContentClient(
            configuration: configuration,
            instanceManager: instances,
            cache: cache,
            networkClient: network
        )

        self.auth = MonochromeAuthClient(configuration: configuration)
        self.pocketBase = MonochromePocketBaseClient(
            configuration: configuration,
            cache: cache,
            networkClient: network
        )
    }
}
