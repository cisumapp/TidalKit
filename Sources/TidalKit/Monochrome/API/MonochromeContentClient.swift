import Foundation

public actor MonochromeContentClient {
    private let configuration: MonochromeConfiguration
    private let instanceManager: MonochromeInstanceManager
    private let cache: MonochromeCache
    private let network: MonochromeNetworkClient
    private let decoder = JSONDecoder()

    public init(
        configuration: MonochromeConfiguration,
        instanceManager: MonochromeInstanceManager,
        cache: MonochromeCache,
        networkClient: MonochromeNetworkClient
    ) {
        self.configuration = configuration
        self.instanceManager = instanceManager
        self.cache = cache
        self.network = networkClient
    }

    // MARK: - Search

    public func searchTracks(query: String) async throws -> [MonochromeTrack] {
        guard let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            throw MonochromeError.invalidURL(query)
        }

        let data = try await fetchData(path: "/search/?s=\(encoded)")
        return try decodeSearchTracks(from: data)
    }

    public func searchAlbums(query: String) async throws -> [MonochromeAlbum] {
        guard let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            throw MonochromeError.invalidURL(query)
        }

        let data = try await fetchData(path: "/search/?al=\(encoded)")
        return Self.decodeAlbumSearch(from: data)
    }

    public func searchAll(query: String) async throws -> MonochromeSearchAllResult {
        guard let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            throw MonochromeError.invalidURL(query)
        }

        async let tracksTask = fetchData(path: "/search/?s=\(encoded)")
        async let artistsTask = fetchData(path: "/search/?a=\(encoded)")
        async let albumsTask = fetchData(path: "/search/?al=\(encoded)")
        async let playlistsTask = fetchData(path: "/search/?p=\(encoded)")

        var tracks: [MonochromeTrack] = []
        if let data = try? await tracksTask {
            tracks = (try? decodeSearchTracks(from: data)) ?? []
        }

        var artists: [MonochromeArtist] = []
        if let data = try? await artistsTask {
            artists = Self.decodeArtistSearch(from: data)
        }

        var albums: [MonochromeAlbum] = []
        if let data = try? await albumsTask {
            albums = Self.decodeAlbumSearch(from: data)
        }

        var playlists: [MonochromePlaylist] = []
        if let data = try? await playlistsTask {
            playlists = Self.parsePlaylistSearchResults(data: data)
        }

        return MonochromeSearchAllResult(
            artists: artists,
            albums: albums,
            tracks: tracks,
            playlists: playlists
        )
    }

    // MARK: - Artist

    public func fetchArtist(id: Int) async throws -> MonochromeArtistDetail {
        let cacheKey = "artist_\(id)"
        if let cached = await cache.get(MonochromeArtistDetail.self, forKey: cacheKey) {
            return cached
        }

        async let metaTask = fetchData(path: "/artist/?id=\(id)")
        async let contentTask: Data? = try? fetchData(path: "/artist/?f=\(id)")

        let metadata = try await metaTask
        let metadataJSON = (try? JSONSerialization.jsonObject(with: metadata) as? [String: Any]) ?? [:]
        let artistObject = (metadataJSON["artist"] as? [String: Any]) ?? [:]

        let name = artistObject["name"] as? String ?? "Unknown"
        let picture = artistObject["picture"] as? String
        let popularity = (artistObject["popularity"] as? NSNumber)?.doubleValue

        var topTracks: [MonochromeTrack] = []
        var albums: [MonochromeAlbum] = []
        var eps: [MonochromeAlbum] = []

        if let contentData = await contentTask {
            let contentJSON = (try? JSONSerialization.jsonObject(with: contentData) as? [String: Any]) ?? [:]

            if let tracksArray = contentJSON["tracks"] as? [[String: Any]] {
                var artistDict: [String: Any] = ["id": id, "name": name]
                if let picture {
                    artistDict["picture"] = picture
                }

                let enriched = tracksArray.map { raw -> [String: Any] in
                    var copy = raw
                    if copy["artist"] == nil {
                        copy["artist"] = artistDict
                    }
                    return copy
                }

                if let data = try? JSONSerialization.data(withJSONObject: enriched),
                   let decoded = try? decoder.decode([MonochromeTrack].self, from: data) {
                    topTracks = decoded
                        .sorted { ($0.popularity ?? 0) > ($1.popularity ?? 0) }
                        .prefix(15)
                        .map { $0 }
                }
            }

            if let albumObj = contentJSON["albums"] as? [String: Any],
               let items = albumObj["items"] as? [[String: Any]],
               let data = try? JSONSerialization.data(withJSONObject: items),
               let decoded = try? decoder.decode([MonochromeAlbum].self, from: data) {
                let sorted = decoded.sorted { ($0.releaseDate ?? "") > ($1.releaseDate ?? "") }
                for album in sorted {
                    let type = album.type?.uppercased() ?? ""
                    if type == "EP" || type == "SINGLE" {
                        eps.append(album)
                    } else {
                        albums.append(album)
                    }
                }
            }
        }

        if topTracks.isEmpty && albums.isEmpty && eps.isEmpty {
            try await fallbackArtistData(id: id, name: name, picture: picture, topTracks: &topTracks, albums: &albums, eps: &eps)
        }

        let detail = MonochromeArtistDetail(
            id: id,
            name: name,
            picture: picture,
            popularity: popularity,
            topTracks: topTracks,
            albums: albums,
            eps: eps
        )

        await cache.set(detail, forKey: cacheKey)
        return detail
    }

    public func fetchArtistBio(id: Int) async -> String? {
        let cacheKey = "bio_\(id)"
        if let cached = await cache.get(String.self, forKey: cacheKey) {
            return cached
        }

        do {
            let json = try await fetchTidalJSON(path: "/artists/\(id)/bio?locale=en_US&countryCode=GB")
            let bio = json["text"] as? String
            if let bio {
                await cache.set(bio, forKey: cacheKey)
            }
            return bio
        } catch {
            return nil
        }
    }

    public func fetchSimilarArtists(id: Int) async -> [MonochromeArtist] {
        let cacheKey = "similar_\(id)"
        if let cached = await cache.get([MonochromeArtist].self, forKey: cacheKey) {
            return cached
        }

        guard let data = try? await fetchData(path: "/artist/similar/?id=\(id)"),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return []
        }

        let artistsRaw = (json["artists"] as? [[String: Any]])
            ?? (json["items"] as? [[String: Any]])
            ?? []

        guard !artistsRaw.isEmpty,
              let payload = try? JSONSerialization.data(withJSONObject: artistsRaw),
              let artists = try? decoder.decode([MonochromeArtist].self, from: payload) else {
            return []
        }

        await cache.set(artists, forKey: cacheKey)
        return artists
    }

    // MARK: - Album/Playlist

    public func fetchAlbum(id: Int) async throws -> MonochromeAlbumDetail {
        let cacheKey = "album_\(id)"
        if let cached = await cache.get(MonochromeAlbumDetail.self, forKey: cacheKey) {
            return cached
        }

        let data = try await fetchData(path: "/album/?id=\(id)")
        let json = (try JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
        let root = (json["data"] as? [String: Any]) ?? json

        var album: MonochromeAlbum?
        if let albumData = try? JSONSerialization.data(withJSONObject: root) {
            album = try? decoder.decode(MonochromeAlbum.self, from: albumData)
        }

        var tracks = decodeTrackItems(root["items"] as? [[String: Any]] ?? [])
        let totalTracks = (root["numberOfTracks"] as? Int) ?? tracks.count

        if tracks.count < totalTracks {
            var offset = tracks.count
            while offset < totalTracks {
                guard let pageData = try? await fetchData(path: "/album/?id=\(id)&offset=\(offset)"),
                      let pageJSON = try? JSONSerialization.jsonObject(with: pageData) as? [String: Any],
                      let pageRoot = pageJSON["data"] as? [String: Any],
                      let pageItems = pageRoot["items"] as? [[String: Any]],
                      !pageItems.isEmpty else {
                    break
                }

                tracks.append(contentsOf: decodeTrackItems(pageItems))
                offset = tracks.count
            }
        }

        if album == nil {
            album = tracks.first?.album
        }

        guard let finalAlbum = album else {
            throw MonochromeError.decoding("Unable to decode album")
        }

        let detail = MonochromeAlbumDetail(album: finalAlbum, tracks: tracks)
        await cache.set(detail, forKey: cacheKey)
        return detail
    }

    public func fetchPlaylist(uuid: String) async throws -> MonochromePlaylistDetail {
        let cacheKey = "playlist_\(uuid)"
        if let cached = await cache.get(MonochromePlaylistDetail.self, forKey: cacheKey) {
            return cached
        }

        let data = try await fetchData(path: "/playlist/?id=\(uuid)")
        let json = (try JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
        let root = (json["data"] as? [String: Any]) ?? json

        let title = root["title"] as? String ?? "Playlist"
        let image = (root["squareImage"] as? String) ?? (root["image"] as? String)
        let description = root["description"] as? String

        let tracks = decodeTrackItems(root["items"] as? [[String: Any]] ?? [])
        let numberOfTracks = (root["numberOfTracks"] as? Int) ?? tracks.count

        let detail = MonochromePlaylistDetail(
            uuid: uuid,
            title: title,
            image: image,
            description: description,
            numberOfTracks: numberOfTracks,
            tracks: tracks
        )

        await cache.set(detail, forKey: cacheKey)
        return detail
    }

    // MARK: - Streams

    public func fetchTrack(id: Int) async throws -> MonochromeTrack {
        let cacheKey = "track_\(id)"
        if let cached = await cache.get(MonochromeTrack.self, forKey: cacheKey) {
            return cached
        }

        let json = try await fetchTidalJSON(path: "/tracks/\(id)?countryCode=GB")
        let payload = try JSONSerialization.data(withJSONObject: json)
        let track = try decoder.decode(MonochromeTrack.self, from: payload)

        await cache.set(track, forKey: cacheKey)
        return track
    }

    public func fetchStreamURL(trackID: Int, quality: MonochromeAudioQuality = .high) async throws -> String? {
        let data = try await fetchData(
            path: "/track/?id=\(trackID)&quality=\(quality.rawValue)",
            instanceKind: .streaming
        )

        let response = try decoder.decode(StreamTrackResponse.self, from: data)
        guard let manifestBase64 = response.data?.manifest,
              let manifestData = Data(base64Encoded: manifestBase64),
              let manifest = try? decoder.decode(StreamManifest.self, from: manifestData) else {
            return nil
        }

        return manifest.urls.first
    }

    public func fetchStreamURLWithFallback(
        trackID: Int,
        preferredQuality: MonochromeAudioQuality
    ) async -> String? {
        for quality in MonochromeAudioQuality.fallbackOrder(preferred: preferredQuality) {
            do {
                if let url = try await fetchStreamURL(trackID: trackID, quality: quality) {
                    return url
                }
            } catch {
                continue
            }
        }

        return nil
    }

    // MARK: - Images

    public func imageURL(id: String?, size: Int = 320) -> URL? {
        guard let id, !id.isEmpty else { return nil }
        if id.hasPrefix("http") { return URL(string: id) }

        let formatted = id.replacingOccurrences(of: "-", with: "/")
        return URL(string: "https://resources.tidal.com/images/\(formatted)/\(size)x\(size).jpg")
    }

    // MARK: - Private networking

    private func fetchData(path: String, instanceKind: MonochromeInstanceKind = .api) async throws -> Data {
        let available = await instanceManager.instances(for: instanceKind)
        let candidates = available.isEmpty
            ? [MonochromeAPIInstance(url: configuration.defaultAPIBaseURL.absoluteString, version: "default")]
            : available

        guard !candidates.isEmpty else {
            throw MonochromeError.unavailableInstances
        }

        var lastError: Error = MonochromeError.unavailableInstances
        let start = Int.random(in: 0..<candidates.count)

        for index in 0..<candidates.count {
            let base = candidates[(start + index) % candidates.count].url
            guard let url = Self.makeURL(base: base, path: path) else { continue }

            var request = URLRequest(url: url)
            request.setValue(configuration.userAgent, forHTTPHeaderField: "User-Agent")

            do {
                return try await network.send(request)
            } catch {
                lastError = error
            }
        }

        if let mono = lastError as? MonochromeError {
            throw mono
        }

        throw MonochromeError.network(code: -1, message: lastError.localizedDescription)
    }

    private func fetchTidalJSON(path: String) async throws -> [String: Any] {
        guard let token = configuration.tidalFallbackToken, !token.isEmpty else {
            throw MonochromeError.auth("Tidal fallback token is not configured")
        }

        let base = configuration.tidalFallbackBaseURL.absoluteString
        guard let url = Self.makeURL(base: base, path: path) else {
            throw MonochromeError.invalidURL(path)
        }

        var request = URLRequest(url: url)
        request.setValue(configuration.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue(token, forHTTPHeaderField: "X-Tidal-Token")

        let data = try await network.send(request)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw MonochromeError.decoding("Expected JSON object")
        }

        return json
    }

    private static func makeURL(base: String, path: String) -> URL? {
        let cleanedBase = base.hasSuffix("/") ? String(base.dropLast()) : base
        let cleanedPath = path.hasPrefix("/") ? path : "/\(path)"
        return URL(string: "\(cleanedBase)\(cleanedPath)")
    }

    // MARK: - Private parsing

    private func decodeSearchTracks(from data: Data) throws -> [MonochromeTrack] {
        do {
            let response = try decoder.decode(SearchResponse.self, from: data)
            return response.data?.items ?? []
        } catch {
            throw MonochromeError.decoding(error.localizedDescription)
        }
    }

    private func decodeTrackItems(_ items: [[String: Any]]) -> [MonochromeTrack] {
        items.compactMap { item in
            let trackObject = (item["item"] as? [String: Any]) ?? item
            guard let trackData = try? JSONSerialization.data(withJSONObject: trackObject),
                  let track = try? decoder.decode(MonochromeTrack.self, from: trackData) else {
                return nil
            }
            return track
        }
    }

    private func fallbackArtistData(
        id: Int,
        name: String,
        picture: String?,
        topTracks: inout [MonochromeTrack],
        albums: inout [MonochromeAlbum],
        eps: inout [MonochromeAlbum]
    ) async throws {
        guard configuration.tidalFallbackToken != nil else { return }

        if let topTracksJSON = try? await fetchTidalJSON(path: "/artists/\(id)/toptracks?countryCode=FR"),
           let items = topTracksJSON["items"] as? [[String: Any]] {
            var artistDict: [String: Any] = ["id": id, "name": name]
            if let picture {
                artistDict["picture"] = picture
            }

            let enriched = items.map { raw -> [String: Any] in
                var copy = raw
                if copy["artist"] == nil {
                    copy["artist"] = artistDict
                }
                return copy
            }

            if let data = try? JSONSerialization.data(withJSONObject: enriched),
               let decoded = try? decoder.decode([MonochromeTrack].self, from: data) {
                topTracks = decoded
                    .sorted { ($0.popularity ?? 0) > ($1.popularity ?? 0) }
                    .prefix(15)
                    .map { $0 }
            }
        }

        if let albumsJSON = try? await fetchTidalJSON(path: "/artists/\(id)/albums?countryCode=FR"),
           let items = albumsJSON["items"] as? [[String: Any]],
           let data = try? JSONSerialization.data(withJSONObject: items),
           let decoded = try? decoder.decode([MonochromeAlbum].self, from: data) {
            let sorted = decoded.sorted { ($0.releaseDate ?? "") > ($1.releaseDate ?? "") }
            for album in sorted {
                let type = album.type?.uppercased() ?? ""
                if type == "EP" || type == "SINGLE" {
                    eps.append(album)
                } else {
                    albums.append(album)
                }
            }
        }

        if topTracks.isEmpty && albums.isEmpty && eps.isEmpty {
            let query = name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
            if let searchData = try? await fetchData(path: "/search/?s=\(query)"),
               let json = try? JSONSerialization.jsonObject(with: searchData) as? [String: Any],
               let items = (json["data"] as? [String: Any])?["items"] as? [[String: Any]] {
                let filtered = items.filter { item in
                    guard let artistName = (item["artist"] as? [String: Any])?["name"] as? String else {
                        return false
                    }
                    return artistName.localizedCaseInsensitiveContains(name)
                }

                if let data = try? JSONSerialization.data(withJSONObject: filtered),
                   let decoded = try? decoder.decode([MonochromeTrack].self, from: data) {
                    topTracks = Array(decoded.prefix(15))
                }
            }
        }
    }

    private static func decodeArtistSearch(from data: Data) -> [MonochromeArtist] {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let dataObj = json["data"] as? [String: Any],
              let artistsObj = dataObj["artists"] as? [String: Any],
              let items = artistsObj["items"] as? [[String: Any]],
              let payload = try? JSONSerialization.data(withJSONObject: items),
              let decoded = try? JSONDecoder().decode([MonochromeArtist].self, from: payload) else {
            return []
        }

        let filtered = decoded.filter { $0.picture != nil }
        var bestByName: [String: MonochromeArtist] = [:]

        for artist in filtered {
            let key = artist.name.lowercased()
            if let existing = bestByName[key] {
                if (artist.popularity ?? 0) > (existing.popularity ?? 0) {
                    bestByName[key] = artist
                }
            } else {
                bestByName[key] = artist
            }
        }

        return filtered.filter { bestByName[$0.name.lowercased()]?.id == $0.id }
    }

    private static func decodeAlbumSearch(from data: Data) -> [MonochromeAlbum] {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let dataObj = json["data"] as? [String: Any],
              let albumsObj = dataObj["albums"] as? [String: Any],
              let items = albumsObj["items"] as? [[String: Any]],
              let payload = try? JSONSerialization.data(withJSONObject: items),
              let decoded = try? JSONDecoder().decode([MonochromeAlbum].self, from: payload) else {
            return []
        }

        return decoded.filter { $0.cover != nil }
    }

    private static func parsePlaylistSearchResults(data: Data) -> [MonochromePlaylist] {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return []
        }

        let items: [[String: Any]]
        if let directItems = json["items"] as? [[String: Any]] {
            items = directItems
        } else if let dataObject = json["data"] as? [String: Any],
                  let playlistsObject = dataObject["playlists"] as? [String: Any],
                  let nestedItems = playlistsObject["items"] as? [[String: Any]] {
            items = nestedItems
        } else {
            return []
        }

        return items.compactMap { item in
            guard let uuid = item["uuid"] as? String else { return nil }
            let title = item["title"] as? String
            let image = (item["squareImage"] as? String) ?? (item["image"] as? String)
            let numberOfTracks = item["numberOfTracks"] as? Int
            let userName = (item["creator"] as? [String: Any])?["name"] as? String

            return MonochromePlaylist(
                uuid: uuid,
                title: title,
                image: image,
                numberOfTracks: numberOfTracks,
                user: userName.map { MonochromePlaylistUser(name: $0) }
            )
        }
    }
}

private struct SearchResponse: Decodable {
    let data: SearchData?
}

private struct SearchData: Decodable {
    let items: [MonochromeTrack]
}

private struct StreamTrackResponse: Decodable {
    let version: String?
    let data: StreamTrackData?
}

private struct StreamTrackData: Decodable {
    let trackId: Int
    let manifest: String?
}

private struct StreamManifest: Decodable {
    let urls: [String]
}
