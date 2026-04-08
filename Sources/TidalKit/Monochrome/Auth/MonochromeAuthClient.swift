import Foundation

public struct MonochromeAuthUser: Codable, Hashable, Sendable {
    public let uid: String
    public let email: String
    public let name: String?

    public init(uid: String, email: String, name: String? = nil) {
        self.uid = uid
        self.email = email
        self.name = name
    }
}

public actor MonochromeAuthClient {
    private let configuration: MonochromeConfiguration
    private let urlSession: URLSession

    private let persistedUserKey = "monochrome_auth_user_v1"
    private var currentUser: MonochromeAuthUser?

    public init(configuration: MonochromeConfiguration) {
        self.configuration = configuration

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = configuration.requestTimeout
        config.timeoutIntervalForResource = configuration.requestTimeout
        config.httpCookieStorage = .shared
        config.httpCookieAcceptPolicy = .always
        self.urlSession = URLSession(configuration: config)

        self.currentUser = Self.loadPersistedUser(
            key: persistedUserKey,
            service: configuration.keychainService
        )
    }

    public func currentSessionUser() -> MonochromeAuthUser? {
        currentUser
    }

    public func signIn(email: String, password: String) async throws -> MonochromeAuthUser {
        let _: AppwriteSession = try await appwriteRequest(
            path: "account/sessions/email",
            method: "POST",
            body: ["email": email, "password": password]
        )

        return try await fetchCurrentUser()
    }

    public func signUp(email: String, password: String) async throws -> MonochromeAuthUser {
        let _: AppwriteAccount = try await appwriteRequest(
            path: "account",
            method: "POST",
            body: [
                "userId": "unique()",
                "email": email,
                "password": password,
            ]
        )

        let _: AppwriteSession = try await appwriteRequest(
            path: "account/sessions/email",
            method: "POST",
            body: ["email": email, "password": password]
        )

        return try await fetchCurrentUser()
    }

    public func makeGoogleOAuthURL(successURL: URL, failureURL: URL) throws -> URL {
        let base = configuration.appwriteBaseURL.appending(path: "account/tokens/oauth2/google")
        guard var components = URLComponents(url: base, resolvingAgainstBaseURL: false) else {
            throw MonochromeError.invalidURL(base.absoluteString)
        }

        components.queryItems = [
            URLQueryItem(name: "project", value: configuration.appwriteProjectID),
            URLQueryItem(name: "success", value: successURL.absoluteString),
            URLQueryItem(name: "failure", value: failureURL.absoluteString),
        ]

        guard let url = components.url else {
            throw MonochromeError.invalidURL(base.absoluteString)
        }

        return url
    }

    public func extractOAuthCredentials(from callbackURL: URL) -> (userId: String, secret: String)? {
        guard let components = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false),
              let userId = components.queryItems?.first(where: { $0.name == "userId" })?.value,
              let secret = components.queryItems?.first(where: { $0.name == "secret" })?.value else {
            return nil
        }

        return (userId, secret)
    }

    public func completeGoogleOAuth(userId: String, secret: String) async throws -> MonochromeAuthUser {
        let _: AppwriteSession = try await appwriteRequest(
            path: "account/sessions/token",
            method: "POST",
            body: ["userId": userId, "secret": secret]
        )

        return try await fetchCurrentUser()
    }

    public func sendPasswordReset(email: String, returnURL: URL) async throws {
        let _: AppwriteRecovery = try await appwriteRequest(
            path: "account/recovery",
            method: "POST",
            body: ["email": email, "url": returnURL.absoluteString]
        )
    }

    public func fetchCurrentUser() async throws -> MonochromeAuthUser {
        let account: AppwriteAccount = try await appwriteRequest(path: "account", method: "GET")

        let user = MonochromeAuthUser(
            uid: account.id,
            email: account.email,
            name: account.name.isEmpty ? nil : account.name
        )

        currentUser = user
        persist(user: user)
        return user
    }

    @discardableResult
    public func restoreSession() async -> MonochromeAuthUser? {
        guard currentUser != nil else {
            currentUser = Self.loadPersistedUser(key: persistedUserKey, service: configuration.keychainService)
            return currentUser
        }

        do {
            return try await fetchCurrentUser()
        } catch {
            clearLocalSessionInternal()
            return nil
        }
    }

    public func signOut() async {
        let url = configuration.appwriteBaseURL.appending(path: "account/sessions/current")
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.setValue(configuration.appwriteProjectID, forHTTPHeaderField: "X-Appwrite-Project")
        request.setValue(configuration.userAgent, forHTTPHeaderField: "User-Agent")

        _ = try? await urlSession.data(for: request)
        clearLocalSessionInternal()
    }

    public func clearLocalSession() {
        clearLocalSessionInternal()
    }

    private func clearLocalSessionInternal() {
        currentUser = nil
        MonochromeKeychain.delete(key: persistedUserKey, service: configuration.keychainService)

        let host = configuration.appwriteBaseURL.host
        let allCookies = HTTPCookieStorage.shared.cookies ?? []
        for cookie in allCookies {
            if let host, cookie.domain.contains(host) {
                HTTPCookieStorage.shared.deleteCookie(cookie)
            }
        }
    }

    private func persist(user: MonochromeAuthUser) {
        guard let data = try? JSONEncoder().encode(user),
              let json = String(data: data, encoding: .utf8) else {
            return
        }

        MonochromeKeychain.save(json, key: persistedUserKey, service: configuration.keychainService)
    }

    private static func loadPersistedUser(key: String, service: String) -> MonochromeAuthUser? {
        guard let json = MonochromeKeychain.load(key: key, service: service),
              let data = json.data(using: .utf8),
              let user = try? JSONDecoder().decode(MonochromeAuthUser.self, from: data) else {
            return nil
        }

        return user
    }

    private func appwriteRequest<T: Decodable>(
        path: String,
        method: String,
        body: [String: Any]? = nil
    ) async throws -> T {
        let url = configuration.appwriteBaseURL.appending(path: path)
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue(configuration.appwriteProjectID, forHTTPHeaderField: "X-Appwrite-Project")
        request.setValue(configuration.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        if let body {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }

        do {
            let (data, response) = try await urlSession.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw MonochromeError.badServerResponse
            }

            if http.statusCode >= 400 {
                if let decoded = try? JSONDecoder().decode(AppwriteErrorResponse.self, from: data) {
                    throw MonochromeError.auth(mapAppwriteError(decoded.message, type: decoded.type))
                }

                throw MonochromeError.server(
                    statusCode: http.statusCode,
                    body: String(data: data, encoding: .utf8)
                )
            }

            if data.isEmpty || http.statusCode == 204 {
                if let empty = AppwriteEmpty() as? T {
                    return empty
                }
                throw MonochromeError.emptyResponse
            }

            do {
                return try JSONDecoder().decode(T.self, from: data)
            } catch {
                throw MonochromeError.decoding(error.localizedDescription)
            }
        } catch let error as MonochromeError {
            throw error
        } catch let error as URLError {
            throw MonochromeError.from(error)
        } catch {
            throw MonochromeError.network(code: -1, message: error.localizedDescription)
        }
    }

    private func mapAppwriteError(_ message: String, type: String?) -> String {
        switch type {
        case "user_invalid_credentials":
            return "Incorrect email or password."
        case "user_not_found":
            return "No account found with this email."
        case "user_already_exists":
            return "An account already exists with this email."
        case "user_blocked":
            return "This account has been disabled."
        case "password_recently_used":
            return "This password was recently used."
        case "password_personal_data":
            return "Password should not include personal data."
        case "user_password_mismatch":
            return "Incorrect password."
        case "general_rate_limit_exceeded":
            return "Too many attempts. Please try again later."
        default:
            return message
        }
    }
}

private struct AppwriteAccount: Decodable {
    let id: String
    let email: String
    let name: String

    enum CodingKeys: String, CodingKey {
        case id = "$id"
        case email
        case name
    }
}

private struct AppwriteSession: Decodable {
    let id: String

    enum CodingKeys: String, CodingKey {
        case id = "$id"
    }
}

private struct AppwriteRecovery: Decodable {
    let id: String

    enum CodingKeys: String, CodingKey {
        case id = "$id"
    }
}

private struct AppwriteErrorResponse: Decodable {
    let message: String
    let type: String?
}

private struct AppwriteEmpty: Decodable {
    init() {}
}
