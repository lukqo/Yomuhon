//
//  HTTPClient.swift
//  Yomuhon
//

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif


enum SourceDebugTrace {
    static func log(_ category: String, _ message: @autoclosure () -> String) {
#if DEBUG
        print("[Yomuhon][\(category)] \(message())")
#endif
    }
}

final class RequestCancellationToken {
    private let lock = NSLock()
    private var cancelled = false

    var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelled
    }

    func cancel() {
        lock.lock()
        cancelled = true
        lock.unlock()
    }
}

enum HTTPRequestCancellationContext {
    private static let threadKey = "yomuhon.http.cancellationToken"

    static var currentToken: RequestCancellationToken? {
        Thread.current.threadDictionary[threadKey] as? RequestCancellationToken
    }

    static func withToken<T>(
        _ token: RequestCancellationToken?,
        operation: () throws -> T
    ) throws -> T {
        let previous = Thread.current.threadDictionary[threadKey]

        if let token {
            Thread.current.threadDictionary[threadKey] = token
        } else {
            Thread.current.threadDictionary.removeObject(forKey: threadKey)
        }

        defer {
            if let previous {
                Thread.current.threadDictionary[threadKey] = previous
            } else {
                Thread.current.threadDictionary.removeObject(forKey: threadKey)
            }
        }

        if token?.isCancelled == true {
            throw HTTPClientError.cancelled
        }

        return try operation()
    }
}


/// Coordinates user-facing source work with background health diagnostics.
/// Interactive search/detail/reader requests always take priority; diagnostics
/// wait until the reader path is idle before starting another network request.
final class SourceRuntimeActivityCenter {
    static let shared = SourceRuntimeActivityCenter()

    private let condition = NSCondition()
    private var activeInteractiveOperations = 0

    var hasInteractiveActivity: Bool {
        condition.lock()
        defer { condition.unlock() }
        return activeInteractiveOperations > 0
    }

    func withInteractiveActivity<T>(_ operation: () throws -> T) rethrows -> T {
        beginInteractiveActivity()
        defer { endInteractiveActivity() }
        return try operation()
    }

    func waitUntilInteractiveIdle(
        timeout: TimeInterval,
        cancellationToken: RequestCancellationToken? = nil
    ) throws {
        let deadline = Date().addingTimeInterval(max(0.1, timeout))
        condition.lock()
        defer { condition.unlock() }

        while activeInteractiveOperations > 0 {
            if cancellationToken?.isCancelled == true {
                throw HTTPClientError.cancelled
            }
            if Date() >= deadline {
                throw HTTPClientError.timedOut
            }
            _ = condition.wait(until: min(deadline, Date().addingTimeInterval(0.10)))
        }
    }

    private func beginInteractiveActivity() {
        condition.lock()
        activeInteractiveOperations += 1
        condition.broadcast()
        condition.unlock()
    }

    private func endInteractiveActivity() {
        condition.lock()
        activeInteractiveOperations = max(0, activeInteractiveOperations - 1)
        condition.broadcast()
        condition.unlock()
    }
}

enum SourceRequestPriority: Equatable {
    case interactive
    case background
}

enum SourceRequestPriorityContext {
    private static let threadKey = "yomuhon.http.requestPriority"

    static var current: SourceRequestPriority {
        (Thread.current.threadDictionary[threadKey] as? String) == "background"
            ? .background
            : .interactive
    }

    static func withPriority<T>(
        _ priority: SourceRequestPriority,
        operation: () throws -> T
    ) rethrows -> T {
        let previous = Thread.current.threadDictionary[threadKey]
        Thread.current.threadDictionary[threadKey] = priority == .background
            ? "background"
            : "interactive"

        defer {
            if let previous {
                Thread.current.threadDictionary[threadKey] = previous
            } else {
                Thread.current.threadDictionary.removeObject(forKey: threadKey)
            }
        }

        return try operation()
    }
}


private final class HTTPRequestResultBox {
    private let lock = NSLock()
    private var storage: Result<Data, Error>?

    func set(_ result: Result<Data, Error>) {
        lock.lock()
        storage = result
        lock.unlock()
    }

    func get() -> Result<Data, Error>? {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }
}

struct HTTPClient {
    private let timeout: TimeInterval
    private let maximumRetryCount: Int

    init(
        timeout: TimeInterval = 20,
        maximumRetryCount: Int = 0
    ) {
        self.timeout = max(0.1, timeout)
        self.maximumRetryCount = max(0, maximumRetryCount)
    }

    func data(from url: URL) throws -> Data {
        var request = URLRequest(url: url)
        request.timeoutInterval = timeout
        return try data(for: request)
    }

    func data(for request: URLRequest) throws -> Data {
        let cancellationToken = HTTPRequestCancellationContext.currentToken
        var retryIndex = 0

        while true {
            if cancellationToken?.isCancelled == true {
                throw HTTPClientError.cancelled
            }

            do {
                return try performRequest(
                    request,
                    cancellationToken: cancellationToken
                )
            } catch {
                if cancellationToken?.isCancelled == true {
                    throw HTTPClientError.cancelled
                }

                guard retryIndex < maximumRetryCount,
                      shouldRetry(error)
                else {
                    throw error
                }

                retryIndex += 1
                try waitBeforeRetry(
                    retryIndex: retryIndex,
                    cancellationToken: cancellationToken
                )
            }
        }
    }

    private func performRequest(
        _ originalRequest: URLRequest,
        cancellationToken: RequestCancellationToken?
    ) throws -> Data {
        let requestPriority = SourceRequestPriorityContext.current
        let traceID = UUID().uuidString.prefix(8)
        let traceStartedAt = Date()
        SourceDebugTrace.log(
            "HTTP",
            "\(traceID) START priority=\(requestPriority) timeout=\(timeout)s url=\(originalRequest.url?.absoluteString ?? "nil")"
        )

        if requestPriority == .background {
            try SourceRuntimeActivityCenter.shared.waitUntilInteractiveIdle(
                timeout: max(30, timeout * 4),
                cancellationToken: cancellationToken
            )
        }

        try HTTPRequestLimiter.shared.waitTurn(
            for: originalRequest.url,
            cancellationToken: cancellationToken
        )

        if cancellationToken?.isCancelled == true {
            throw HTTPClientError.cancelled
        }

        let semaphore = DispatchSemaphore(value: 0)
        let resultBox = HTTPRequestResultBox()

        var request = originalRequest
        if request.timeoutInterval <= 0 {
            request.timeoutInterval = timeout
        } else {
            request.timeoutInterval = min(request.timeoutInterval, timeout)
        }
        let requestURL = request.url

        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            defer { semaphore.signal() }

            let resolvedResult: Result<Data, Error>

            if let error {
                resolvedResult = .failure(error)
            } else if let httpResponse = response as? HTTPURLResponse {
                if (200...299).contains(httpResponse.statusCode) {
                    resolvedResult = .success(data ?? Data())
                } else {
                    if httpResponse.statusCode == 429 {
                        HTTPRequestLimiter.shared.registerRateLimit(for: requestURL)
                    }

                    resolvedResult = .failure(
                        HTTPClientError.httpStatus(httpResponse.statusCode)
                    )
                }
            } else {
                resolvedResult = .failure(HTTPClientError.invalidResponse)
            }

            switch resolvedResult {
            case .success(let data):
                SourceDebugTrace.log(
                    "HTTP",
                    "\(traceID) RESPONSE success bytes=\(data.count) elapsed=\(String(format: "%.3f", Date().timeIntervalSince(traceStartedAt)))s url=\(requestURL?.absoluteString ?? "nil")"
                )
            case .failure(let error):
                SourceDebugTrace.log(
                    "HTTP",
                    "\(traceID) RESPONSE failure error=\(String(describing: error)) elapsed=\(String(format: "%.3f", Date().timeIntervalSince(traceStartedAt)))s url=\(requestURL?.absoluteString ?? "nil")"
                )
            }
            resultBox.set(resolvedResult)
        }

        task.resume()

        let deadline = Date().addingTimeInterval(timeout + 1)

        while true {
            if cancellationToken?.isCancelled == true {
                SourceDebugTrace.log("HTTP", "\(traceID) CANCEL token url=\(requestURL?.absoluteString ?? "nil")")
                task.cancel()
                throw HTTPClientError.cancelled
            }

            if requestPriority == .background,
               SourceRuntimeActivityCenter.shared.hasInteractiveActivity {
                task.cancel()
                throw HTTPClientError.preemptedByInteractiveActivity
            }

            if Date() >= deadline {
                SourceDebugTrace.log(
                    "HTTP",
                    "\(traceID) MANUAL_TIMEOUT elapsed=\(String(format: "%.3f", Date().timeIntervalSince(traceStartedAt)))s url=\(requestURL?.absoluteString ?? "nil")"
                )
                task.cancel()
                throw HTTPClientError.timedOut
            }

            if semaphore.wait(timeout: .now() + 0.10) == .success {
                break
            }
        }

        let finalResult = resultBox.get()

        switch finalResult {
        case .success(let data):
            return data
        case .failure(let error):
            if cancellationToken?.isCancelled == true {
                throw HTTPClientError.cancelled
            }
            throw error
        case .none:
            throw HTTPClientError.invalidResponse
        }
    }

    private func shouldRetry(_ error: Error) -> Bool {
        if let clientError = error as? HTTPClientError {
            switch clientError {
            case .httpStatus(let status):
                return [408, 425, 429, 500, 502, 503, 504].contains(status)
            case .timedOut:
                return true
            case .invalidResponse, .cancelled, .preemptedByInteractiveActivity:
                return false
            }
        }

        if let urlError = error as? URLError {
            return [
                .timedOut,
                .networkConnectionLost,
                .cannotConnectToHost,
                .cannotFindHost,
                .dnsLookupFailed,
                .notConnectedToInternet,
                .resourceUnavailable
            ].contains(urlError.code)
        }

        return false
    }

    private func waitBeforeRetry(
        retryIndex: Int,
        cancellationToken: RequestCancellationToken?
    ) throws {
        let backoff = min(1.5, 0.35 * pow(2.0, Double(max(0, retryIndex - 1))))
        let deadline = Date().addingTimeInterval(backoff)

        while Date() < deadline {
            if cancellationToken?.isCancelled == true {
                throw HTTPClientError.cancelled
            }

            Thread.sleep(
                forTimeInterval: min(
                    0.05,
                    max(0, deadline.timeIntervalSinceNow)
                )
            )
        }
    }
}

enum HTTPClientError: Error {
    case invalidResponse
    case httpStatus(Int)
    case timedOut
    case cancelled
    case preemptedByInteractiveActivity

    var isRateLimited: Bool {
        if case .httpStatus(429) = self {
            return true
        }

        return false
    }

    var isCancellation: Bool {
        switch self {
        case .cancelled, .preemptedByInteractiveActivity:
            return true
        default:
            return false
        }
    }
}

final class HTTPRequestLimiter {
    static let shared = HTTPRequestLimiter()

    private let lock = NSLock()
    private var nextAllowedRequestDateByHost: [String: Date] = [:]
    private let minimumInterval: TimeInterval = 0.16
    private let rateLimitCooldown: TimeInterval = 6.0

    func waitTurn(
        for url: URL?,
        cancellationToken: RequestCancellationToken? = nil
    ) throws {
        let key = limiterKey(for: url)

        lock.lock()
        let now = Date()
        let nextAllowedRequestDate = nextAllowedRequestDateByHost[key] ?? .distantPast
        let waitInterval = max(0, nextAllowedRequestDate.timeIntervalSince(now))
        let scheduledDate = max(now, nextAllowedRequestDate).addingTimeInterval(minimumInterval)
        nextAllowedRequestDateByHost[key] = scheduledDate
        lock.unlock()

        guard waitInterval > 0 else {
            if cancellationToken?.isCancelled == true {
                throw HTTPClientError.cancelled
            }
            return
        }

        let deadline = Date().addingTimeInterval(waitInterval)

        while Date() < deadline {
            if cancellationToken?.isCancelled == true {
                throw HTTPClientError.cancelled
            }

            Thread.sleep(forTimeInterval: min(0.05, max(0, deadline.timeIntervalSinceNow)))
        }
    }

    func registerRateLimit(for url: URL?) {
        let key = limiterKey(for: url)

        lock.lock()
        let current = nextAllowedRequestDateByHost[key] ?? .distantPast
        nextAllowedRequestDateByHost[key] = max(
            current,
            Date().addingTimeInterval(rateLimitCooldown)
        )
        lock.unlock()
    }

    private func limiterKey(for url: URL?) -> String {
        url?.host?.lowercased() ?? "__global__"
    }
}
