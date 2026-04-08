import Foundation

public enum MonochromeError: LocalizedError, Sendable {
    case invalidURL(String)
    case badServerResponse
    case server(statusCode: Int, body: String?)
    case network(code: Int, message: String)
    case decoding(String)
    case api(String)
    case authenticationRequired
    case auth(String)
    case pocketBase(String)
    case unavailableInstances
    case emptyResponse

    public var errorDescription: String? {
        switch self {
        case .invalidURL(let value):
            return "Invalid URL: \(value)"
        case .badServerResponse:
            return "Bad server response"
        case .server(let statusCode, let body):
            if let body, !body.isEmpty {
                return "Server error (\(statusCode)): \(body)"
            }
            return "Server error (\(statusCode))"
        case .network(_, let message):
            return "Network error: \(message)"
        case .decoding(let message):
            return "Decoding error: \(message)"
        case .api(let message):
            return "API error: \(message)"
        case .authenticationRequired:
            return "Authentication required"
        case .auth(let message):
            return "Auth error: \(message)"
        case .pocketBase(let message):
            return "PocketBase error: \(message)"
        case .unavailableInstances:
            return "No API instances available"
        case .emptyResponse:
            return "Empty response"
        }
    }

    static func from(_ urlError: URLError) -> MonochromeError {
        MonochromeError.network(code: urlError.errorCode, message: urlError.localizedDescription)
    }
}
