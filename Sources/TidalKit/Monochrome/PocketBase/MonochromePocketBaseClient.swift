import Foundation

public struct MonochromePBUserRecord: Decodable, Sendable {
    public let id: String
    public let firebaseID: String?
    public let library: String?
    public let history: String?
    public let userPlaylists: String?
    public let userFolders: String?
    public let username: String?
    public let displayName: String?
    public let avatarURL: String?
    public let banner: String?
    public let status: String?
    public let about: String?
    public let website: String?
    public let privacy: String?
    public let lastfmUsername: String?
    public let favoriteAlbums: String?

    enum CodingKeys: String, CodingKey {
        case id
        case firebaseID = "firebase_id"
        case library
        case history
        case userPlaylists = "user_playlists"
        case userFolders = "user_folders"
        case username
        case displayName = "display_name"
        case avatarURL = "avatar_url"
        case banner
        case status
        case about
        case website
        case privacy
        case lastfmUsername = "lastfm_username"
        case favoriteAlbums = "favorite_albums"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        id = try container.decode(String.self, forKey: .id)
        firebaseID = try container.decodeIfPresent(String.self, forKey: .firebaseID)

        username = try container.decodeIfPresent(String.self, forKey: .username)
        displayName = try container.decodeIfPresent(String.self, forKey: .displayName)
        avatarURL = try container.decodeIfPresent(String.self, forKey: .avatarURL)
        banner = try container.decodeIfPresent(String.self, forKey: .banner)
        about = try container.decodeIfPresent(String.self, forKey: .about)
        website = try container.decodeIfPresent(String.self, forKey: .website)
        lastfmUsername = try container.decodeIfPresent(String.self, forKey: .lastfmUsername)

        library = Self.decodeJSONField(container: container, key: .library)
        history = Self.decodeJSONField(container: container, key: .history)
        userPlaylists = Self.decodeJSONField(container: container, key: .userPlaylists)
        userFolders = Self.decodeJSONField(container: container, key: .userFolders)
        status = Self.decodeJSONField(container: container, key: .status)
        privacy = Self.decodeJSONField(container: container, key: .privacy)
        favoriteAlbums = Self.decodeJSONField(container: container, key: .favoriteAlbums)
    }

    private static func decodeJSONField(
        container: KeyedDecodingContainer<CodingKeys>,
        key: CodingKeys
    ) -> String? {
        if let value = try? container.decodeIfPresent(String.self, forKey: key) {
            return value
        }

        if let jsonValue = try? container.decodeIfPresent(JSONValue.self, forKey: key),
           let data = try? JSONSerialization.data(withJSONObject: jsonValue.value),
           let value = String(data: data, encoding: .utf8) {
            return value
        }

        return nil
    }
}

public actor MonochromePocketBaseClient {
    private let configuration: MonochromeConfiguration
    private let cache: MonochromeCache
    private let network: MonochromeNetworkClient

    private let collection = "DB_users"
    private var cachedRecord: MonochromePBUserRecord?

    public init(
        configuration: MonochromeConfiguration,
        cache: MonochromeCache,
        networkClient: MonochromeNetworkClient
    ) {
        self.configuration = configuration
        self.cache = cache
        self.network = networkClient
    }

    public func clearRecordCache() {
        cachedRecord = nil
    }

    public func getUserRecord(uid: String, forceRefresh: Bool = false) async throws -> MonochromePBUserRecord {
        if !forceRefresh,
           let cachedRecord,
           cachedRecord.firebaseID == uid {
            return cachedRecord
        }

        let filter = "firebase_id=\"\(uid)\""
        guard let encoded = filter.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "\(baseURL)/api/collections/\(collection)/records?filter=\(encoded)&f_id=\(uid)&sort=-username") else {
            throw MonochromeError.invalidURL(filter)
        }

        let data = try await send(url: url)

        let response: MonochromePBListResponse
        do {
            response = try JSONDecoder().decode(MonochromePBListResponse.self, from: data)
        } catch {
            throw MonochromeError.decoding(error.localizedDescription)
        }

        if let existing = response.items.first {
            cachedRecord = existing
            return existing
        }

        return try await createUserRecord(uid: uid)
    }

    public func fullSync(uid: String) async throws -> MonochromeCloudSnapshot {
        let record = try await getUserRecord(uid: uid, forceRefresh: true)

        let library = Self.parseJSON(record.library) ?? [:]
        let tracksDict = (library["tracks"] as? [String: Any]) ?? [:]
        let albumsDict = (library["albums"] as? [String: Any]) ?? [:]
        let artistsDict = (library["artists"] as? [String: Any]) ?? [:]
        let playlistsDict = (library["playlists"] as? [String: Any]) ?? [:]
        let mixesDict = (library["mixes"] as? [String: Any]) ?? [:]

        let tracks = Self.decodeTracks(Array(tracksDict.values.compactMap { $0 as? [String: Any] }))
        let albums = Self.decodeAlbums(Array(albumsDict.values.compactMap { $0 as? [String: Any] }))
        let artists = Self.decodeArtists(Array(artistsDict.values.compactMap { $0 as? [String: Any] }))
        let playlists = Self.decodePlaylists(Array(playlistsDict.values.compactMap { $0 as? [String: Any] }))
        let mixes = Self.decodeMixes(Array(mixesDict.values.compactMap { $0 as? [String: Any] }))

        let history = Self.decodeTracks(
            (Self.parseJSONArray(record.history) ?? []).compactMap { $0 as? [String: Any] }
        )

        return MonochromeCloudSnapshot(
            tracks: tracks,
            albums: albums,
            artists: artists,
            playlists: playlists,
            mixes: mixes,
            history: history
        )
    }

    public func fetchHistory(uid: String) async throws -> [MonochromeTrack] {
        let record = try await getUserRecord(uid: uid, forceRefresh: true)
        let historyArray = Self.parseJSONArray(record.history) ?? []
        return Self.decodeTracks(historyArray.compactMap { $0 as? [String: Any] })
    }

    public func syncLibraryItem(
        uid: String,
        type: MonochromeLibraryItemType,
        track: MonochromeTrack? = nil,
        album: MonochromeAlbum? = nil,
        artist: MonochromeArtist? = nil,
        playlist: MonochromePlaylist? = nil,
        mix: MonochromeMix? = nil,
        added: Bool
    ) async throws {
        let record = try await getUserRecord(uid: uid, forceRefresh: true)
        var library = Self.parseJSON(record.library) ?? [:]

        let pluralType = type == .mix ? "mixes" : "\(type.rawValue)s"
        var items = (library[pluralType] as? [String: Any]) ?? [:]

        let key: String? = {
            if let track { return String(track.id) }
            if let album { return String(album.id) }
            if let artist { return String(artist.id) }
            if let playlist { return playlist.uuid }
            if let mix { return mix.id }
            return nil
        }()

        if added {
            if let track {
                items[String(track.id)] = Self.minifyTrack(track)
            } else if let album {
                items[String(album.id)] = Self.minifyAlbum(album)
            } else if let artist {
                items[String(artist.id)] = Self.minifyArtist(artist)
            } else if let playlist {
                items[playlist.uuid] = Self.minifyPlaylist(playlist)
            } else if let mix {
                items[mix.id] = Self.minifyMix(mix)
            }
        } else if let key {
            items.removeValue(forKey: key)
        }

        library[pluralType] = items
        try await updateUserField(recordID: record.id, uid: uid, field: "library", value: library)
        cachedRecord = try await getUserRecord(uid: uid, forceRefresh: true)
    }

    public func syncHistoryItem(uid: String, track: MonochromeTrack) async throws {
        let record = try await getUserRecord(uid: uid, forceRefresh: true)
        var history = Self.parseJSONArray(record.history) ?? []

        let entry = Self.minifyHistoryEntry(track)
        history.insert(entry, at: 0)
        if history.count > 100 {
            history = Array(history.prefix(100))
        }

        try await updateUserField(recordID: record.id, uid: uid, field: "history", value: history)
    }

    public func syncUserPlaylist(uid: String, playlist: MonochromeUserPlaylist) async throws {
        let record = try await getUserRecord(uid: uid, forceRefresh: true)
        var dict = Self.parseJSON(record.userPlaylists) ?? [:]
        dict[playlist.id] = Self.userPlaylistToDict(playlist)
        try await updateUserField(recordID: record.id, uid: uid, field: "user_playlists", value: dict)
    }

    public func deleteUserPlaylist(uid: String, playlistID: String) async throws {
        let record = try await getUserRecord(uid: uid, forceRefresh: true)

        var playlistDict = Self.parseJSON(record.userPlaylists) ?? [:]
        playlistDict.removeValue(forKey: playlistID)

        var folderDict = Self.parseJSON(record.userFolders) ?? [:]
        for (key, rawValue) in folderDict {
            guard var folder = rawValue as? [String: Any],
                  var playlistIDs = folder["playlists"] as? [String] else {
                continue
            }

            playlistIDs.removeAll { $0 == playlistID }
            folder["playlists"] = playlistIDs
            folderDict[key] = folder
        }

        try await updateUserFields(
            recordID: record.id,
            uid: uid,
            fields: [
                "user_playlists": playlistDict,
                "user_folders": folderDict,
            ]
        )
    }

    public func syncUserFolders(uid: String, folders: [MonochromeUserFolder]) async throws {
        let record = try await getUserRecord(uid: uid, forceRefresh: true)

        var dict: [String: Any] = [:]
        for folder in folders {
            dict[folder.id] = Self.userFolderToDict(folder)
        }

        try await updateUserField(recordID: record.id, uid: uid, field: "user_folders", value: dict)
    }

    public func loadUserPlaylists(uid: String) async throws -> [MonochromeUserPlaylist] {
        let record = try await getUserRecord(uid: uid, forceRefresh: true)
        return Self.decodeUserPlaylists(from: record.userPlaylists)
    }

    public func loadUserFolders(uid: String) async throws -> [MonochromeUserFolder] {
        let record = try await getUserRecord(uid: uid, forceRefresh: true)
        return Self.decodeUserFolders(from: record.userFolders)
    }

    public func loadUserProfile(uid: String) async throws -> MonochromeUserProfile {
        let record = try await getUserRecord(uid: uid, forceRefresh: true)
        var profile = MonochromeUserProfile()

        profile.username = record.username ?? ""
        profile.displayName = record.displayName ?? ""
        profile.avatarUrl = record.avatarURL ?? ""
        profile.banner = record.banner ?? ""
        profile.status = record.status ?? ""
        profile.about = record.about ?? ""
        profile.website = record.website ?? ""
        profile.lastfmUsername = record.lastfmUsername ?? ""

        if let privacy = record.privacy,
           let data = privacy.data(using: .utf8),
           let decoded = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            profile.privacy.playlists = decoded["playlists"] as? String ?? "public"
            profile.privacy.lastfm = decoded["lastfm"] as? String ?? "public"
        }

        if let favoriteAlbums = record.favoriteAlbums,
           let data = favoriteAlbums.data(using: .utf8),
           let decoded = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
            profile.favoriteAlbums = decoded.compactMap { raw in
                guard let id = raw["id"] as? String else { return nil }
                return MonochromeFavoriteAlbum(
                    id: id,
                    title: raw["title"] as? String ?? "",
                    artist: raw["artist"] as? String ?? "",
                    cover: raw["cover"] as? String ?? "",
                    description: raw["description"] as? String ?? ""
                )
            }
        }

        if let history = record.history,
           let data = history.data(using: .utf8),
           let decoded = try? JSONSerialization.jsonObject(with: data) as? [Any] {
            profile.historyCount = decoded.count
        }

        return profile
    }

    public func saveUserProfile(uid: String, profile: MonochromeUserProfile) async throws {
        let record = try await getUserRecord(uid: uid, forceRefresh: true)

        var fields: [String: Any] = [
            "username": profile.username,
            "display_name": profile.displayName,
            "avatar_url": profile.avatarUrl,
            "banner": profile.banner,
            "status": profile.status,
            "about": profile.about,
            "website": profile.website,
            "lastfm_username": profile.lastfmUsername,
        ]

        let privacy: [String: String] = [
            "playlists": profile.privacy.playlists,
            "lastfm": profile.privacy.lastfm,
        ]
        fields["privacy"] = privacy

        fields["favorite_albums"] = profile.favoriteAlbums.map { album in
            [
                "id": album.id,
                "title": album.title,
                "artist": album.artist,
                "cover": album.cover,
                "description": album.description,
            ]
        }

        try await updateUserFields(recordID: record.id, uid: uid, fields: fields)
    }

    public func updateUserField(recordID: String, uid: String, field: String, value: Any) async throws {
        try await updateField(recordID: recordID, uid: uid, field: field, value: value)
    }

    public func updateUserFields(recordID: String, uid: String, fields: [String: Any]) async throws {
        guard let url = URL(string: "\(baseURL)/api/collections/\(collection)/records/\(recordID)?f_id=\(uid)") else {
            throw MonochromeError.invalidURL(recordID)
        }

        var body: [String: Any] = [:]
        for (field, value) in fields {
            body[field] = try Self.stringifyJSON(value)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        request.setValue(configuration.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        _ = try await network.send(request)
    }

    // MARK: - Private

    private var baseURL: String {
        configuration.pocketBaseBaseURL.absoluteString
    }

    private func createUserRecord(uid: String) async throws -> MonochromePBUserRecord {
        guard let url = URL(string: "\(baseURL)/api/collections/\(collection)/records?f_id=\(uid)") else {
            throw MonochromeError.invalidURL(uid)
        }

        let body: [String: Any] = [
            "firebase_id": uid,
            "library": "{}",
            "history": "[]",
            "user_playlists": "{}",
            "user_folders": "{}",
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(configuration.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let data = try await network.send(request)

        do {
            let created = try JSONDecoder().decode(MonochromePBUserRecord.self, from: data)
            cachedRecord = created
            return created
        } catch {
            throw MonochromeError.decoding(error.localizedDescription)
        }
    }

    private func updateField(recordID: String, uid: String, field: String, value: Any) async throws {
        guard let url = URL(string: "\(baseURL)/api/collections/\(collection)/records/\(recordID)?f_id=\(uid)") else {
            throw MonochromeError.invalidURL(recordID)
        }

        let encoded = try Self.stringifyJSON(value)
        let body: [String: Any] = [field: encoded]

        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        request.setValue(configuration.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        _ = try await network.send(request)
    }

    private func send(url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.setValue(configuration.userAgent, forHTTPHeaderField: "User-Agent")
        return try await network.send(request)
    }

    private static func stringifyJSON(_ value: Any) throws -> String {
        if let dict = value as? [String: Any] {
            let data = try JSONSerialization.data(withJSONObject: dict)
            return String(data: data, encoding: .utf8) ?? "{}"
        }

        if let array = value as? [Any] {
            let data = try JSONSerialization.data(withJSONObject: array)
            return String(data: data, encoding: .utf8) ?? "[]"
        }

        return "\(value)"
    }

    private static func parseJSON(_ value: String?) -> [String: Any]? {
        guard let value,
              let data = value.data(using: .utf8) else {
            return nil
        }

        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    private static func parseJSONArray(_ value: String?) -> [Any]? {
        guard let value,
              let data = value.data(using: .utf8) else {
            return nil
        }

        return try? JSONSerialization.jsonObject(with: data) as? [Any]
    }

    private static func decodeTracks(_ raws: [[String: Any]]) -> [MonochromeTrack] {
        raws.compactMap { raw in
            var dict = raw
            if dict["title"] == nil || dict["title"] is NSNull {
                dict["title"] = "Unknown"
            }
            if dict["duration"] == nil || dict["duration"] is NSNull {
                dict["duration"] = 0
            }
            if dict["id"] == nil || dict["id"] is NSNull {
                return nil
            }

            guard let data = try? JSONSerialization.data(withJSONObject: dict),
                  let decoded = try? JSONDecoder().decode(MonochromeTrack.self, from: data) else {
                return nil
            }

            return decoded
        }
    }

    private static func decodeAlbums(_ raws: [[String: Any]]) -> [MonochromeAlbum] {
        raws.compactMap { raw in
            var dict = raw
            if dict["title"] == nil || dict["title"] is NSNull {
                dict["title"] = "Unknown"
            }
            if dict["id"] == nil || dict["id"] is NSNull {
                return nil
            }

            guard let data = try? JSONSerialization.data(withJSONObject: dict),
                  let decoded = try? JSONDecoder().decode(MonochromeAlbum.self, from: data) else {
                return nil
            }

            return decoded
        }
    }

    private static func decodeArtists(_ raws: [[String: Any]]) -> [MonochromeArtist] {
        raws.compactMap { raw in
            var dict = raw
            if dict["name"] == nil || dict["name"] is NSNull {
                dict["name"] = "Unknown"
            }
            if dict["id"] == nil || dict["id"] is NSNull {
                return nil
            }

            guard let data = try? JSONSerialization.data(withJSONObject: dict),
                  let decoded = try? JSONDecoder().decode(MonochromeArtist.self, from: data) else {
                return nil
            }

            return decoded
        }
    }

    private static func decodePlaylists(_ raws: [[String: Any]]) -> [MonochromePlaylist] {
        raws.compactMap { raw in
            guard raw["uuid"] != nil,
                  let data = try? JSONSerialization.data(withJSONObject: raw),
                  let decoded = try? JSONDecoder().decode(MonochromePlaylist.self, from: data) else {
                return nil
            }

            return decoded
        }
    }

    private static func decodeMixes(_ raws: [[String: Any]]) -> [MonochromeMix] {
        raws.compactMap { raw in
            guard raw["id"] != nil,
                  let data = try? JSONSerialization.data(withJSONObject: raw),
                  let decoded = try? JSONDecoder().decode(MonochromeMix.self, from: data) else {
                return nil
            }

            return decoded
        }
    }

    private static func decodeUserPlaylists(from jsonString: String?) -> [MonochromeUserPlaylist] {
        guard let dict = parseJSON(jsonString) else { return [] }

        return dict.values.compactMap { value in
            guard let object = value as? [String: Any],
                  let id = object["id"] as? String,
                  let name = object["name"] as? String else {
                return nil
            }

            let trackRaw = (object["tracks"] as? [[String: Any]]) ?? []
            let tracks = decodeTracks(trackRaw)

            return MonochromeUserPlaylist(
                id: id,
                name: name,
                tracks: tracks,
                cover: object["cover"] as? String ?? "",
                description: object["description"] as? String ?? "",
                createdAt: object["createdAt"] as? Double ?? 0,
                updatedAt: object["updatedAt"] as? Double ?? 0,
                numberOfTracks: object["numberOfTracks"] as? Int ?? tracks.count,
                images: object["images"] as? [String] ?? [],
                isPublic: object["isPublic"] as? Bool ?? false
            )
        }
    }

    private static func decodeUserFolders(from jsonString: String?) -> [MonochromeUserFolder] {
        guard let dict = parseJSON(jsonString) else { return [] }

        return dict.values.compactMap { value in
            guard let object = value as? [String: Any],
                  let id = object["id"] as? String,
                  let name = object["name"] as? String else {
                return nil
            }

            return MonochromeUserFolder(
                id: id,
                name: name,
                cover: object["cover"] as? String ?? "",
                playlists: object["playlists"] as? [String] ?? [],
                createdAt: object["createdAt"] as? Double ?? 0,
                updatedAt: object["updatedAt"] as? Double ?? 0
            )
        }
    }

    private static func minifyTrack(_ track: MonochromeTrack) -> [String: Any] {
        var data: [String: Any] = [
            "id": track.id,
            "title": track.title,
            "duration": track.duration,
            "addedAt": Int(Date().timeIntervalSince1970 * 1000),
        ]

        if let audioQuality = track.audioQuality {
            data["audioQuality"] = audioQuality
        }

        if let tags = track.mediaMetadata?.tags, !tags.isEmpty {
            data["mediaMetadata"] = ["tags": tags]
        }

        if let artist = track.artist {
            let artistDict: [String: Any] = ["id": artist.id, "name": artist.name]
            data["artist"] = artistDict
            data["artists"] = [artistDict]
        }

        if let album = track.album {
            var albumData: [String: Any] = ["id": album.id, "title": album.title]
            if let cover = album.cover {
                albumData["cover"] = cover
            }
            if let releaseDate = album.releaseDate {
                albumData["releaseDate"] = releaseDate
            }
            data["album"] = albumData
        }

        return data
    }

    private static func minifyAlbum(_ album: MonochromeAlbum) -> [String: Any] {
        var data: [String: Any] = [
            "id": album.id,
            "title": album.title,
            "addedAt": Int(Date().timeIntervalSince1970 * 1000),
        ]

        if let cover = album.cover {
            data["cover"] = cover
        }
        if let releaseDate = album.releaseDate {
            data["releaseDate"] = releaseDate
        }
        if let artist = album.artist {
            data["artist"] = ["id": artist.id, "name": artist.name]
        }
        if let type = album.type {
            data["type"] = type
        }
        if let numberOfTracks = album.numberOfTracks {
            data["numberOfTracks"] = numberOfTracks
        }

        return data
    }

    private static func minifyArtist(_ artist: MonochromeArtist) -> [String: Any] {
        var data: [String: Any] = [
            "id": artist.id,
            "name": artist.name,
            "addedAt": Int(Date().timeIntervalSince1970 * 1000),
        ]

        if let picture = artist.picture {
            data["picture"] = picture
        }

        return data
    }

    private static func minifyPlaylist(_ playlist: MonochromePlaylist) -> [String: Any] {
        var data: [String: Any] = [
            "uuid": playlist.uuid,
            "addedAt": Int(Date().timeIntervalSince1970 * 1000),
        ]

        if let title = playlist.title {
            data["title"] = title
        }
        if let image = playlist.image {
            data["image"] = image
        }
        if let numberOfTracks = playlist.numberOfTracks {
            data["numberOfTracks"] = numberOfTracks
        }
        if let userName = playlist.user?.name {
            data["user"] = ["name": userName]
        }

        return data
    }

    private static func minifyMix(_ mix: MonochromeMix) -> [String: Any] {
        var data: [String: Any] = [
            "id": mix.id,
            "addedAt": Int(Date().timeIntervalSince1970 * 1000),
        ]

        if let title = mix.title {
            data["title"] = title
        }
        if let subTitle = mix.subTitle {
            data["subTitle"] = subTitle
        }
        if let mixType = mix.mixType {
            data["mixType"] = mixType
        }
        if let cover = mix.cover {
            data["cover"] = cover
        }

        return data
    }

    private static func minifyHistoryEntry(_ track: MonochromeTrack) -> [String: Any] {
        var data = minifyTrack(track)
        data["timestamp"] = Int(Date().timeIntervalSince1970 * 1000)
        return data
    }

    private static func userPlaylistToDict(_ playlist: MonochromeUserPlaylist) -> [String: Any] {
        var dict: [String: Any] = [
            "id": playlist.id,
            "name": playlist.name,
            "cover": playlist.cover,
            "description": playlist.description,
            "createdAt": playlist.createdAt,
            "updatedAt": playlist.updatedAt,
            "numberOfTracks": playlist.numberOfTracks,
            "images": playlist.images,
            "isPublic": playlist.isPublic,
        ]

        dict["tracks"] = playlist.tracks.map(Self.minifyTrack)
        return dict
    }

    private static func userFolderToDict(_ folder: MonochromeUserFolder) -> [String: Any] {
        [
            "id": folder.id,
            "name": folder.name,
            "cover": folder.cover,
            "playlists": folder.playlists,
            "createdAt": folder.createdAt,
            "updatedAt": folder.updatedAt,
        ]
    }
}

private struct MonochromePBListResponse: Decodable {
    let items: [MonochromePBUserRecord]
}

private struct JSONValue: Decodable {
    let value: Any

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if let dict = try? container.decode([String: JSONValue].self) {
            value = dict.mapValues { $0.value }
        } else if let array = try? container.decode([JSONValue].self) {
            value = array.map { $0.value }
        } else if let string = try? container.decode(String.self) {
            value = string
        } else if let int = try? container.decode(Int.self) {
            value = int
        } else if let double = try? container.decode(Double.self) {
            value = double
        } else if let bool = try? container.decode(Bool.self) {
            value = bool
        } else {
            value = NSNull()
        }
    }
}
