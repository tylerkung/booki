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
        } catch {
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
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // Encode the body
        do {
            let encoder = JSONEncoder()
            request.httpBody = try encoder.encode(AnyEncodable(body))
        } catch {
            throw EdgeFunctionError.encodingError(error)
        }

        // Make the request
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw EdgeFunctionError.networkError(error)
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
