import Foundation

public actor MonochromeNetworkClient {
    private let session: URLSession
    private let maxAttempts: Int

    public init(configuration: MonochromeConfiguration, session: URLSession? = nil) {
        if let session {
            self.session = session
        } else {
            let config = URLSessionConfiguration.default
            config.timeoutIntervalForRequest = configuration.requestTimeout
            config.timeoutIntervalForResource = configuration.requestTimeout
            config.httpCookieStorage = .shared
            config.httpCookieAcceptPolicy = .always
            self.session = URLSession(configuration: config)
        }

        self.maxAttempts = max(1, configuration.maxRequestAttempts)
    }

    public func send(_ request: URLRequest, expectedStatusCodes: Range<Int> = 200..<300) async throws -> Data {
        var attempt = 0
        var lastError: MonochromeError = .badServerResponse

        while attempt < maxAttempts {
            attempt += 1
            do {
                let (data, response) = try await session.data(for: request)
                guard let http = response as? HTTPURLResponse else {
                    lastError = .badServerResponse
                    throw lastError
                }

                guard expectedStatusCodes.contains(http.statusCode) else {
                    let body = String(data: data, encoding: .utf8)
                    let serverError = MonochromeError.server(statusCode: http.statusCode, body: body)

                    if attempt < maxAttempts, isRetryableStatus(http.statusCode) {
                        try await backoff(attempt: attempt)
                        lastError = serverError
                        continue
                    }

                    throw serverError
                }

                return data
            } catch let error as URLError {
                let mapped = MonochromeError.from(error)
                if attempt < maxAttempts, isRetryableNetworkError(error) {
                    try await backoff(attempt: attempt)
                    lastError = mapped
                    continue
                }
                throw mapped
            } catch let error as MonochromeError {
                throw error
            } catch {
                throw MonochromeError.network(code: -1, message: error.localizedDescription)
            }
        }

        throw lastError
    }

    private func isRetryableStatus(_ statusCode: Int) -> Bool {
        statusCode == 408 || statusCode == 425 || statusCode == 429 || (500...599).contains(statusCode)
    }

    private func isRetryableNetworkError(_ error: URLError) -> Bool {
        switch error.code {
        case .timedOut,
             .cannotConnectToHost,
             .networkConnectionLost,
             .dnsLookupFailed,
             .notConnectedToInternet,
             .cannotFindHost:
            return true
        default:
            return false
        }
    }

    private func backoff(attempt: Int) async throws {
        let delayMs = min(4000, 250 * (1 << max(0, attempt - 1)))
        try await Task.sleep(for: .milliseconds(delayMs))
    }
}
