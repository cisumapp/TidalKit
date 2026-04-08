import Testing
@testable import TidalKit
import Foundation

@Test func audioQualityFallbackOrderStartsWithPreferred() {
    let order = MonochromeAudioQuality.fallbackOrder(preferred: .high)
    #expect(order == [.high, .medium, .low])
}

@Test func productionConfigurationHasExpectedDefaults() {
    let config = MonochromeConfiguration.production
    #expect(config.defaultAPIBaseURL.absoluteString == "https://api.monochrome.tf")
    #expect(config.appwriteProjectID == "auth-for-monochrome")
    #expect(config.maxRequestAttempts >= 1)
}

@Test func cacheRoundTripPersistsData() async throws {
    let directory = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("tidalkit-tests-\(UUID().uuidString)", isDirectory: true)

    let cache = MonochromeCache(maxAge: 300, maxSizeMB: 16, diskDirectory: directory)
    let track = MonochromeTrack(id: 42, title: "Test Track", duration: 210)

    await cache.set(track, forKey: "track_42")
    let decoded = await cache.get(MonochromeTrack.self, forKey: "track_42")

    #expect(decoded?.id == 42)
    #expect(decoded?.title == "Test Track")
    #expect((await cache.statistics()).entryCount >= 1)

    await cache.clear()
}

@Test func oauthURLContainsRequiredQueryItems() async throws {
    let authClient = MonochromeAuthClient(configuration: .production)
    let successURL = URL(string: "myapp://auth/callback")!
    let failureURL = URL(string: "myapp://auth/failure")!

    let oauthURL = try await authClient.makeGoogleOAuthURL(successURL: successURL, failureURL: failureURL)
    let components = URLComponents(url: oauthURL, resolvingAgainstBaseURL: false)
    let items = components?.queryItems ?? []

    #expect(items.contains(where: { $0.name == "project" && $0.value == "auth-for-monochrome" }))
    #expect(items.contains(where: { $0.name == "success" && $0.value == successURL.absoluteString }))
    #expect(items.contains(where: { $0.name == "failure" && $0.value == failureURL.absoluteString }))
}
