import Foundation
import UserNotifications
import UIKit
@preconcurrency import Supabase

/// Service for managing push notifications — permission, token registration, and foreground handling.
@Observable
@MainActor
final class NotificationService: NSObject {

    // MARK: - Singleton

    static let shared = NotificationService()

    // MARK: - Published State

    private(set) var isPermissionGranted: Bool = false

    // MARK: - Private

    private let supabase: SupabaseClient

    private override init() {
        self.supabase = SupabaseClientManager.shared.client
        super.init()
    }

    // MARK: - Permission

    /// Request notification permission and register for remote notifications if granted.
    func requestPermission() async {
        do {
            let granted = try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .badge, .sound])
            isPermissionGranted = granted
            if granted {
                UIApplication.shared.registerForRemoteNotifications()
            }
        } catch {
            print("NotificationService: requestPermission failed: \(error)")
        }
    }

    // MARK: - Token Registration

    /// Convert device token data to hex string and upsert to Supabase.
    func registerToken(_ deviceToken: Data) async {
        let tokenString = deviceToken.map { String(format: "%02x", $0) }.joined()

        guard let userId = try? await supabase.auth.session.user.id else {
            print("NotificationService: No authenticated user for token registration")
            return
        }

        let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"

        let record = DeviceTokenRecord(
            userId: userId.uuidString.lowercased(),
            token: tokenString,
            platform: "ios",
            appVersion: appVersion
        )

        do {
            try await supabase
                .from("device_tokens")
                .upsert(record, onConflict: "user_id,token")
                .execute()
        } catch {
            print("NotificationService: Failed to register token: \(error)")
        }
    }

    /// Remove all device tokens for the current user (called on logout).
    func removeToken() async {
        guard let userId = try? await supabase.auth.session.user.id else { return }

        do {
            try await supabase
                .from("device_tokens")
                .delete()
                .eq("user_id", value: userId.uuidString.lowercased())
                .execute()
        } catch {
            print("NotificationService: Failed to remove tokens: \(error)")
        }
    }
}

// MARK: - Codable Records

private struct DeviceTokenRecord: Codable {
    let userId: String
    let token: String
    let platform: String
    let appVersion: String

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case token
        case platform
        case appVersion = "app_version"
    }
}

// MARK: - UNUserNotificationCenterDelegate

extension NotificationService: @preconcurrency UNUserNotificationCenterDelegate {

    /// Handle foreground notification — show banner and sound.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        return [.banner, .sound]
    }

    /// Handle notification tap — extract deep link for routing.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let userInfo = response.notification.request.content.userInfo
        if let deepLink = userInfo["deep_link"] as? String {
            print("NotificationService: Deep link tapped: \(deepLink)")
            // Deep link routing will be wired in US-006
        }
    }
}
