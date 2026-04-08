import Foundation

public enum MonochromeAudioQuality: String, CaseIterable, Codable, Sendable {
    case low = "LOW"
    case medium = "MEDIUM"
    case high = "HIGH"
    case lossless = "LOSSLESS"
    case hiResLossless = "HI_RES_LOSSLESS"

    public var label: String {
        switch self {
        case .low: return "AAC (128 kbps)"
        case .medium: return "AAC (256 kbps)"
        case .high: return "AAC (320 kbps)"
        case .lossless: return "FLAC (Lossless)"
        case .hiResLossless: return "FLAC (Hi-Res)"
        }
    }

    public static let descending: [MonochromeAudioQuality] = [.hiResLossless, .lossless, .high, .medium, .low]

    public static func fallbackOrder(preferred: MonochromeAudioQuality) -> [MonochromeAudioQuality] {
        guard let preferredIndex = descending.firstIndex(of: preferred) else {
            return descending
        }

        let lower = descending.dropFirst(preferredIndex + 1)
        return [preferred] + lower
    }
}

public struct MonochromeMediaMetadata: Codable, Hashable, Sendable {
    public let tags: [String]?

    public init(tags: [String]? = nil) {
        self.tags = tags
    }
}

public struct MonochromeArtist: Identifiable, Codable, Hashable, Sendable {
    public let id: Int
    public let name: String
    public let picture: String?
    public let popularity: Double?

    public init(id: Int, name: String, picture: String? = nil, popularity: Double? = nil) {
        self.id = id
        self.name = name
        self.picture = picture
        self.popularity = popularity
    }
}

public struct MonochromeAlbum: Identifiable, Codable, Hashable, Sendable {
    public let id: Int
    public let title: String
    public let cover: String?
    public let numberOfTracks: Int?
    public let releaseDate: String?
    public let artist: MonochromeArtist?
    public let type: String?

    public init(
        id: Int,
        title: String,
        cover: String? = nil,
        numberOfTracks: Int? = nil,
        releaseDate: String? = nil,
        artist: MonochromeArtist? = nil,
        type: String? = nil
    ) {
        self.id = id
        self.title = title
        self.cover = cover
        self.numberOfTracks = numberOfTracks
        self.releaseDate = releaseDate
        self.artist = artist
        self.type = type
    }

    public var releaseYear: String? {
        guard let date = releaseDate, date.count >= 4 else { return nil }
        return String(date.prefix(4))
    }
}

public struct MonochromeTrack: Identifiable, Codable, Hashable, Sendable {
    public let id: Int
    public let title: String
    public let duration: Int
    public let artist: MonochromeArtist?
    public let album: MonochromeAlbum?
    public let streamStartDate: String?
    public let popularity: Double?
    public let trackNumber: Int?
    public let volumeNumber: Int?
    public let audioQuality: String?
    public let mediaMetadata: MonochromeMediaMetadata?

    public init(
        id: Int,
        title: String,
        duration: Int,
        artist: MonochromeArtist? = nil,
        album: MonochromeAlbum? = nil,
        streamStartDate: String? = nil,
        popularity: Double? = nil,
        trackNumber: Int? = nil,
        volumeNumber: Int? = nil,
        audioQuality: String? = nil,
        mediaMetadata: MonochromeMediaMetadata? = nil
    ) {
        self.id = id
        self.title = title
        self.duration = duration
        self.artist = artist
        self.album = album
        self.streamStartDate = streamStartDate
        self.popularity = popularity
        self.trackNumber = trackNumber
        self.volumeNumber = volumeNumber
        self.audioQuality = audioQuality
        self.mediaMetadata = mediaMetadata
    }

    public var releaseYear: String? {
        guard let date = streamStartDate, date.count >= 4 else { return nil }
        return String(date.prefix(4))
    }

    public func withQuality(_ quality: String, mediaMetadata: MonochromeMediaMetadata? = nil) -> MonochromeTrack {
        MonochromeTrack(
            id: id,
            title: title,
            duration: duration,
            artist: artist,
            album: album,
            streamStartDate: streamStartDate,
            popularity: popularity,
            trackNumber: trackNumber,
            volumeNumber: volumeNumber,
            audioQuality: quality,
            mediaMetadata: mediaMetadata ?? self.mediaMetadata
        )
    }
}

public struct MonochromePlaylistUser: Codable, Hashable, Sendable {
    public let name: String?

    public init(name: String? = nil) {
        self.name = name
    }
}

public struct MonochromePlaylist: Identifiable, Codable, Hashable, Sendable {
    public let uuid: String
    public let title: String?
    public let image: String?
    public let numberOfTracks: Int?
    public let user: MonochromePlaylistUser?

    public var id: String { uuid }

    public init(
        uuid: String,
        title: String? = nil,
        image: String? = nil,
        numberOfTracks: Int? = nil,
        user: MonochromePlaylistUser? = nil
    ) {
        self.uuid = uuid
        self.title = title
        self.image = image
        self.numberOfTracks = numberOfTracks
        self.user = user
    }
}

public struct MonochromeMix: Identifiable, Codable, Hashable, Sendable {
    public let id: String
    public let title: String?
    public let subTitle: String?
    public let mixType: String?
    public let cover: String?

    public init(id: String, title: String? = nil, subTitle: String? = nil, mixType: String? = nil, cover: String? = nil) {
        self.id = id
        self.title = title
        self.subTitle = subTitle
        self.mixType = mixType
        self.cover = cover
    }
}

public struct MonochromeUserPlaylist: Identifiable, Codable, Hashable, Sendable {
    public let id: String
    public var name: String
    public var tracks: [MonochromeTrack]
    public var cover: String
    public var description: String
    public var createdAt: Double
    public var updatedAt: Double
    public var numberOfTracks: Int
    public var images: [String]
    public var isPublic: Bool

    public init(
        id: String = UUID().uuidString,
        name: String,
        tracks: [MonochromeTrack] = [],
        cover: String = "",
        description: String = "",
        createdAt: Double = Date().timeIntervalSince1970 * 1000,
        updatedAt: Double = Date().timeIntervalSince1970 * 1000,
        numberOfTracks: Int = 0,
        images: [String] = [],
        isPublic: Bool = false
    ) {
        self.id = id
        self.name = name
        self.tracks = tracks
        self.cover = cover
        self.description = description
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.numberOfTracks = numberOfTracks
        self.images = images
        self.isPublic = isPublic
    }
}

public struct MonochromeUserFolder: Identifiable, Codable, Hashable, Sendable {
    public let id: String
    public var name: String
    public var cover: String
    public var playlists: [String]
    public var createdAt: Double
    public var updatedAt: Double

    public init(
        id: String = UUID().uuidString,
        name: String,
        cover: String = "",
        playlists: [String] = [],
        createdAt: Double = Date().timeIntervalSince1970 * 1000,
        updatedAt: Double = Date().timeIntervalSince1970 * 1000
    ) {
        self.id = id
        self.name = name
        self.cover = cover
        self.playlists = playlists
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public struct MonochromeFavoriteAlbum: Codable, Identifiable, Hashable, Sendable {
    public let id: String
    public var title: String
    public var artist: String
    public var cover: String
    public var description: String

    public init(id: String = "", title: String = "", artist: String = "", cover: String = "", description: String = "") {
        self.id = id
        self.title = title
        self.artist = artist
        self.cover = cover
        self.description = description
    }
}

public struct MonochromeProfilePrivacy: Codable, Hashable, Sendable {
    public var playlists: String
    public var lastfm: String

    public init(playlists: String = "public", lastfm: String = "public") {
        self.playlists = playlists
        self.lastfm = lastfm
    }
}

public struct MonochromeUserProfile: Codable, Hashable, Sendable {
    public var username: String
    public var displayName: String
    public var avatarUrl: String
    public var banner: String
    public var status: String
    public var about: String
    public var website: String
    public var lastfmUsername: String
    public var privacy: MonochromeProfilePrivacy
    public var historyCount: Int
    public var favoriteAlbums: [MonochromeFavoriteAlbum]

    public init(
        username: String = "",
        displayName: String = "",
        avatarUrl: String = "",
        banner: String = "",
        status: String = "",
        about: String = "",
        website: String = "",
        lastfmUsername: String = "",
        privacy: MonochromeProfilePrivacy = MonochromeProfilePrivacy(),
        historyCount: Int = 0,
        favoriteAlbums: [MonochromeFavoriteAlbum] = []
    ) {
        self.username = username
        self.displayName = displayName
        self.avatarUrl = avatarUrl
        self.banner = banner
        self.status = status
        self.about = about
        self.website = website
        self.lastfmUsername = lastfmUsername
        self.privacy = privacy
        self.historyCount = historyCount
        self.favoriteAlbums = favoriteAlbums
    }
}

public enum MonochromeLibraryItemType: String, Sendable {
    case track
    case album
    case artist
    case playlist
    case mix
}

public struct MonochromeSearchAllResult: Sendable {
    public let artists: [MonochromeArtist]
    public let albums: [MonochromeAlbum]
    public let tracks: [MonochromeTrack]
    public let playlists: [MonochromePlaylist]

    public init(artists: [MonochromeArtist], albums: [MonochromeAlbum], tracks: [MonochromeTrack], playlists: [MonochromePlaylist]) {
        self.artists = artists
        self.albums = albums
        self.tracks = tracks
        self.playlists = playlists
    }
}

public struct MonochromeAlbumDetail: Codable, Sendable {
    public let album: MonochromeAlbum
    public let tracks: [MonochromeTrack]

    public init(album: MonochromeAlbum, tracks: [MonochromeTrack]) {
        self.album = album
        self.tracks = tracks
    }
}

public struct MonochromeArtistDetail: Codable, Sendable {
    public let id: Int
    public let name: String
    public let picture: String?
    public let popularity: Double?
    public let topTracks: [MonochromeTrack]
    public let albums: [MonochromeAlbum]
    public let eps: [MonochromeAlbum]

    public init(
        id: Int,
        name: String,
        picture: String? = nil,
        popularity: Double? = nil,
        topTracks: [MonochromeTrack],
        albums: [MonochromeAlbum],
        eps: [MonochromeAlbum]
    ) {
        self.id = id
        self.name = name
        self.picture = picture
        self.popularity = popularity
        self.topTracks = topTracks
        self.albums = albums
        self.eps = eps
    }
}

public struct MonochromePlaylistDetail: Codable, Sendable {
    public let uuid: String
    public let title: String
    public let image: String?
    public let description: String?
    public let numberOfTracks: Int
    public let tracks: [MonochromeTrack]

    public init(
        uuid: String,
        title: String,
        image: String? = nil,
        description: String? = nil,
        numberOfTracks: Int,
        tracks: [MonochromeTrack]
    ) {
        self.uuid = uuid
        self.title = title
        self.image = image
        self.description = description
        self.numberOfTracks = numberOfTracks
        self.tracks = tracks
    }
}

public struct MonochromeCloudSnapshot: Sendable {
    public let tracks: [MonochromeTrack]
    public let albums: [MonochromeAlbum]
    public let artists: [MonochromeArtist]
    public let playlists: [MonochromePlaylist]
    public let mixes: [MonochromeMix]
    public let history: [MonochromeTrack]

    public init(
        tracks: [MonochromeTrack],
        albums: [MonochromeAlbum],
        artists: [MonochromeArtist],
        playlists: [MonochromePlaylist],
        mixes: [MonochromeMix],
        history: [MonochromeTrack]
    ) {
        self.tracks = tracks
        self.albums = albums
        self.artists = artists
        self.playlists = playlists
        self.mixes = mixes
        self.history = history
    }
}
