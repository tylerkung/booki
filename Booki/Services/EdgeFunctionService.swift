import Foundation
import Supabase

/// Error types for Edge Function calls
enum EdgeFunctionError: Error, LocalizedError {
    case notAuthenticated
    case invalidURL
    case networkError(Error)
    case serverError(statusCode: Int, message: String?)
    case decodingError(Error)
    case encodingError(Error)

    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "User is not authenticated"
        case .invalidURL:
            return "Invalid Edge Function URL"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .serverError(let statusCode, let message):
            if let message = message {
                return "Server error (\(statusCode)): \(message)"
            }
            return "Server error: \(statusCode)"
        case .decodingError(let error):
            return "Failed to decode response: \(error.localizedDescription)"
        case .encodingError(let error):
            return "Failed to encode request: \(error.localizedDescription)"
        }
    }
}

/// Service for calling Supabase Edge Functions from the iOS app
/// Handles authentication, JSON encoding/decoding, and error handling
final class EdgeFunctionService {

    // MARK: - Singleton

    /// Shared singleton instance
    static let shared = EdgeFunctionService()

    // MARK: - Private Properties

    private let supabase: SupabaseClient

    // MARK: - Initialization

    private init() {
        self.supabase = SupabaseClientManager.shared.client
    }

    // MARK: - Public Methods

    /// Call a Supabase Edge Function with a JSON body
    /// - Parameters:
    ///   - name: The name of the Edge Function to call
    ///   - body: The request body to encode as JSON
    /// - Returns: The decoded response of type T
    /// - Throws: EdgeFunctionError on failure
    func callFunction<T: Decodable>(name: String, body: Encodable) async throws -> T {
        // Get the current session to obtain the access token
        let session: Session
        do {
            session = try await supabase.auth.session
            print("DEBUG EdgeFunction: Got session, token expires at: \(session.expiresAt)")
            print("DEBUG EdgeFunction: Access token prefix: \(String(session.accessToken.prefix(20)))...")
        } catch {
            print("DEBUG EdgeFunction: No session found, error: \(error)")
            throw EdgeFunctionError.notAuthenticated
        }

        // Construct the Edge Function URL
        let baseURL = SupabaseConfig.url
        guard let url = URL(string: "\(baseURL.absoluteString)/functions/v1/\(name)") else {
            throw EdgeFunctionError.invalidURL
        }

        // Create the request
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue(SupabaseConfig.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // Encode the body
        do {
            let encoder = JSONEncoder()
            request.httpBody = try encoder.encode(AnyEncodable(body))
        } catch {
            throw EdgeFunctionError.encodingError(error)
        }

        // Make the request with retry logic for network errors
        let data: Data
        let response: URLResponse
        (data, response) = try await retryWithBackoff(attempt: 1, maxAttempts: 3) {
            try await URLSession.shared.data(for: request)
        }

        // Check HTTP status code
        if let httpResponse = response as? HTTPURLResponse {
            guard (200...299).contains(httpResponse.statusCode) else {
                // Try to extract error message from response body
                let errorMessage = String(data: data, encoding: .utf8)
                throw EdgeFunctionError.serverError(statusCode: httpResponse.statusCode, message: errorMessage)
            }
        }

        // Decode the response
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode(T.self, from: data)
        } catch {
            throw EdgeFunctionError.decodingError(error)
        }
    }

    // MARK: - Private Methods

    /// Retry an operation with exponential backoff on network failures
    /// - Parameters:
    ///   - attempt: Current attempt number (1-indexed)
    ///   - maxAttempts: Maximum number of attempts before giving up
    ///   - operation: The async operation to retry
    /// - Returns: The result of the successful operation
    /// - Throws: EdgeFunctionError.networkError if all retries fail, or rethrows non-URLError errors
    private func retryWithBackoff<T>(
        attempt: Int,
        maxAttempts: Int,
        operation: () async throws -> T
    ) async throws -> T {
        do {
            return try await operation()
        } catch let error as URLError {
            // Only retry on URLError (network issues)
            guard attempt < maxAttempts else {
                throw EdgeFunctionError.networkError(error)
            }

            // Calculate delay with exponential backoff: 1s, 2s, 4s
            let delaySeconds = pow(2.0, Double(attempt - 1))
            try await Task.sleep(nanoseconds: UInt64(delaySeconds * 1_000_000_000))

            // Retry the operation
            return try await retryWithBackoff(
                attempt: attempt + 1,
                maxAttempts: maxAttempts,
                operation: operation
            )
        } catch {
            // Non-URLError errors are not retried (e.g., encoding errors)
            throw error
        }
    }
}

// MARK: - Type Erasure Helper

/// Type-erased Encodable wrapper to allow generic encoding
private struct AnyEncodable: Encodable {
    private let _encode: (Encoder) throws -> Void

    init<T: Encodable>(_ wrapped: T) {
        _encode = wrapped.encode
    }

    func encode(to encoder: Encoder) throws {
        try _encode(encoder)
    }
}
