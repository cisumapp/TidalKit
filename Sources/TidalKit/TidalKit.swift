import Foundation

/// Entry namespace for Monochrome API support in TidalKit.
///
/// Example:
///
///     let sdk = Monochrome.shared
///     let results = try await sdk.content.searchTracks(query: "Daft Punk")
///
public enum TidalKit {
	/// Creates a new Monochrome SDK instance with custom configuration.
	@MainActor
	public static func monochrome(configuration: MonochromeConfiguration = .production) -> Monochrome {
		Monochrome(configuration: configuration)
	}
}

/// Convenience alias for users that want an explicit SDK naming style.
public typealias MonochromeSDK = Monochrome
