# TidalKit

Swift package for integrating with the Monochrome API ecosystem from iOS and macOS apps.

This package currently ships a Monochrome-focused SDK surface with typed models, actor-based clients, built-in instance failover, caching, Appwrite auth helpers, and PocketBase sync support.

## At A Glance

- Platform support: iOS 17+, macOS 14+
- Concurrency model: Swift Concurrency (async/await + actors)
- Main entry point: `Monochrome.shared` or `TidalKit.monochrome(...)`
- Modules: content, auth, instances, cache, PocketBase
- Auth mode: headless (no built-in login UI views)

## Installation

Add TidalKit through Swift Package Manager:

```swift
// Package.swift
let package = Package(
    name: "YourApp",
    dependencies: [
        .package(url: "https://github.com/<your-org>/TidalKit.git", from: "1.0.0")
    ],
    targets: [
        .target(
            name: "YourApp",
            dependencies: ["TidalKit"]
        )
    ]
)
```

Then import in your app target:

```swift
import TidalKit
```

## Quickstart

### 1. Create an SDK instance

```swift
import TidalKit

@MainActor
func makeSDK() -> Monochrome {
    // Uses production defaults.
    return Monochrome.shared

    // Or with custom config:
    // let config = MonochromeConfiguration(tidalFallbackToken: "...")
    // return TidalKit.monochrome(configuration: config)
}
```

### 2. Search and inspect content

```swift
import TidalKit

@MainActor
func searchExample() async {
    let sdk = Monochrome.shared

    do {
        let results = try await sdk.content.searchAll(query: "Daft Punk")
        print("Artists: \(results.artists.count)")
        print("Albums: \(results.albums.count)")
        print("Tracks: \(results.tracks.count)")
        print("Playlists: \(results.playlists.count)")
    } catch {
        print("Search failed: \(error)")
    }
}
```

### 3. Resolve a stream URL with quality fallback

```swift
import TidalKit

@MainActor
func streamExample(trackID: Int) async {
    let sdk = Monochrome.shared

    let streamURL = await sdk.content.fetchStreamURLWithFallback(
        trackID: trackID,
        preferredQuality: .hiResLossless
    )

    print("Resolved stream: \(streamURL ?? "none")")
}
```

## API Cookbook

In the snippets below, assume you already have an SDK instance:

```swift
let sdk = await MainActor.run { Monochrome.shared }
```

### Configure The SDK

```swift
import TidalKit

@MainActor
func configuredSDK() -> Monochrome {
    let config = MonochromeConfiguration(
        tidalFallbackToken: "YOUR_TIDAL_TOKEN",
        cacheMaxAge: 12 * 3600,
        cacheMaxSizeMB: 300,
        requestTimeout: 25,
        maxRequestAttempts: 4
    )

    return TidalKit.monochrome(configuration: config)
}
```

### Content Client

#### Search

```swift
let tracks = try await sdk.content.searchTracks(query: "Nujabes")
let albums = try await sdk.content.searchAlbums(query: "Discovery")
let all = try await sdk.content.searchAll(query: "Justice")
```

#### Artist data

```swift
let artist = try await sdk.content.fetchArtist(id: 1566)
let bio = await sdk.content.fetchArtistBio(id: 1566)
let similar = await sdk.content.fetchSimilarArtists(id: 1566)
```

#### Album and playlist details

```swift
let album = try await sdk.content.fetchAlbum(id: 123456)
let playlist = try await sdk.content.fetchPlaylist(uuid: "your-playlist-uuid")
```

#### Track + stream resolution

```swift
let track = try await sdk.content.fetchTrack(id: 987654)

let direct = try await sdk.content.fetchStreamURL(
    trackID: track.id,
    quality: .lossless
)

let fallback = await sdk.content.fetchStreamURLWithFallback(
    trackID: track.id,
    preferredQuality: .hiResLossless
)
```

#### Image URL helper

```swift
let coverURL = sdk.content.imageURL(id: track.album?.cover, size: 640)
```

### Auth Client (Headless)

#### Email/password

```swift
let user = try await sdk.auth.signIn(email: "you@example.com", password: "secret")
print(user.uid)
```

#### Sign up

```swift
let newUser = try await sdk.auth.signUp(email: "new@example.com", password: "secret")
```

#### Google OAuth handoff flow

```swift
let success = URL(string: "myapp://auth/callback")!
let failure = URL(string: "myapp://auth/failure")!

let oauthURL = try await sdk.auth.makeGoogleOAuthURL(successURL: success, failureURL: failure)
// Open oauthURL in your browser/auth session.

// Later, from your callback URL:
if let creds = await sdk.auth.extractOAuthCredentials(from: callbackURL) {
    let oauthUser = try await sdk.auth.completeGoogleOAuth(userId: creds.userId, secret: creds.secret)
    print(oauthUser.email)
}
```

#### Session utilities

```swift
let restored = await sdk.auth.restoreSession()
let current = await sdk.auth.currentSessionUser()
try await sdk.auth.sendPasswordReset(email: "you@example.com", returnURL: URL(string: "https://example.com/reset")!)
await sdk.auth.signOut()
```

### Instance Manager

```swift
let apiInstances = await sdk.instances.instances(for: .api)
let streamingInstances = await sdk.instances.instances(for: .streaming)

await sdk.instances.addUserInstance("https://my.instance.example", kind: .api)
await sdk.instances.refreshInstances()
await sdk.instances.removeUserInstance("https://my.instance.example", kind: .api)
```

### PocketBase Sync Client

```swift
let uid = "user-id"

let snapshot = try await sdk.pocketBase.fullSync(uid: uid)
let history = try await sdk.pocketBase.fetchHistory(uid: uid)

if let firstTrack = snapshot.tracks.first {
    try await sdk.pocketBase.syncLibraryItem(
        uid: uid,
        type: .track,
        track: firstTrack,
        added: true
    )
}
```

#### User playlists and folders

```swift
let playlists = try await sdk.pocketBase.loadUserPlaylists(uid: uid)
let folders = try await sdk.pocketBase.loadUserFolders(uid: uid)

if var playlist = playlists.first {
    playlist.name = "Road Trip"
    try await sdk.pocketBase.syncUserPlaylist(uid: uid, playlist: playlist)
}

try await sdk.pocketBase.syncUserFolders(uid: uid, folders: folders)
```

#### User profile

```swift
var profile = try await sdk.pocketBase.loadUserProfile(uid: uid)
profile.displayName = "Monochrome Listener"
profile.status = "Exploring new releases"
try await sdk.pocketBase.saveUserProfile(uid: uid, profile: profile)
```

### Cache API

```swift
await sdk.cache.set(["hello", "world"], forKey: "example_key")
let value: [String]? = await sdk.cache.get([String].self, forKey: "example_key")
let age = await sdk.cache.age(forKey: "example_key")
let stats = await sdk.cache.statistics()

print(value ?? [])
print(age ?? 0)
print(stats.formattedSize)

await sdk.cache.remove(forKey: "example_key")
// await sdk.cache.clear()
```

### Error Handling Pattern

```swift
do {
    _ = try await sdk.content.searchTracks(query: "Boards of Canada")
} catch let error as MonochromeError {
    print(error.localizedDescription)
} catch {
    print("Unexpected error: \(error)")
}
```

## Credits

- Monochrome, its API/service behavior, and the underlying product work are by the Monochrome project.
  - Site: https://monochrome.tf
- Special thanks to c22dev for the idea and for surfacing Monochrome.
  - https://github.com/c22dev

## Disclaimer

This package is an unofficial client SDK for third-party services. Service owners can change endpoints and behavior at any time.
