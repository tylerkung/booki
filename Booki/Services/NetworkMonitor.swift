import Foundation
import Network
import SwiftUI
/// Monitors network connectivity using NWPathMonitor
/// Publishes isConnected state for the app to observe
@MainActor
@Observable
final class NetworkMonitor {

    // MARK: - Published Properties

    /// Whether the device has network connectivity
    private(set) var isConnected: Bool = true

    /// Human-readable description of the connection status
    private(set) var connectionStatus: String = "Connected"

    /// The type of network connection (wifi, cellular, etc.)
    private(set) var connectionType: ConnectionType = .unknown

    // MARK: - Private Properties

    /// The network path monitor
    private let monitor: NWPathMonitor

    /// Queue for receiving network updates
    private let queue = DispatchQueue(label: "NetworkMonitor")

    /// Debounce task for connection changes to avoid flicker
    private var debounceTask: Task<Void, Never>?

    /// Debounce delay in milliseconds
    private let debounceDelay: UInt64 = 500_000_000 // 0.5 seconds

    /// Whether the monitor has started
    private var isMonitoring: Bool = false

    // MARK: - Connection Type

    /// Describes the type of network connection
    enum ConnectionType {
        case wifi
        case cellular
        case wiredEthernet
        case other
        case unknown

        var displayName: String {
            switch self {
            case .wifi:
                return "Wi-Fi"
            case .cellular:
                return "Cellular"
            case .wiredEthernet:
                return "Ethernet"
            case .other:
                return "Connected"
            case .unknown:
                return "Unknown"
            }
        }

        var iconName: String {
            switch self {
            case .wifi:
                return "wifi"
            case .cellular:
                return "antenna.radiowaves.left.and.right"
            case .wiredEthernet:
                return "cable.connector"
            case .other, .unknown:
                return "network"
            }
        }
    }

    // MARK: - Initialization

    init() {
        self.monitor = NWPathMonitor()
        startMonitoring()
    }

    deinit {
        // Cancel the monitor directly since deinit is non-isolated
        monitor.cancel()
    }

    // MARK: - Public Methods

    /// Start monitoring network changes
    func startMonitoring() {
        guard !isMonitoring else { return }
        isMonitoring = true

        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor [weak self] in
                self?.handlePathUpdate(path)
            }
        }

        monitor.start(queue: queue)
    }

    /// Stop monitoring network changes
    func stopMonitoring() {
        guard isMonitoring else { return }
        isMonitoring = false
        monitor.cancel()
    }

    // MARK: - Private Methods

    /// Handle network path updates with debouncing to avoid flicker
    private func handlePathUpdate(_ path: NWPath) {
        // Cancel any pending debounce task
        debounceTask?.cancel()

        let newIsConnected = path.status == .satisfied
        let newConnectionType = determineConnectionType(path)

        // If going offline, update immediately (no debounce)
        if !newIsConnected && isConnected {
            updateState(isConnected: false, connectionType: newConnectionType)
            return
        }

        // If going online, debounce to avoid flicker during brief connectivity changes
        if newIsConnected && !isConnected {
            debounceTask = Task {
                try? await Task.sleep(nanoseconds: debounceDelay)

                guard !Task.isCancelled else { return }

                // Re-check the current state after debounce
                updateState(isConnected: newIsConnected, connectionType: newConnectionType)
            }
            return
        }

        // Otherwise just update the connection type
        updateState(isConnected: newIsConnected, connectionType: newConnectionType)
    }

    /// Update the published state
    private func updateState(isConnected: Bool, connectionType: ConnectionType) {
        self.isConnected = isConnected
        self.connectionType = connectionType

        if isConnected {
            connectionStatus = connectionType.displayName
        } else {
            connectionStatus = "Offline"
        }

        // Post notification for other parts of the app to react
        NotificationCenter.default.post(
            name: .networkStatusChanged,
            object: nil,
            userInfo: ["isConnected": isConnected]
        )
    }

    /// Determine the connection type from the network path
    private func determineConnectionType(_ path: NWPath) -> ConnectionType {
        if path.usesInterfaceType(.wifi) {
            return .wifi
        } else if path.usesInterfaceType(.cellular) {
            return .cellular
        } else if path.usesInterfaceType(.wiredEthernet) {
            return .wiredEthernet
        } else if path.status == .satisfied {
            return .other
        } else {
            return .unknown
        }
    }
}

// MARK: - Notification Names

extension Notification.Name {
    /// Posted when network connectivity status changes
    /// userInfo contains: isConnected (Bool)
    static let networkStatusChanged = Notification.Name("networkStatusChanged")
}

// MARK: - Offline Banner View

/// A banner view displayed when the device is offline
struct OfflineBannerView: View {
    @Environment(NetworkMonitor.self) private var networkMonitor

    /// Whether to show an expanded message
    var showExpandedMessage: Bool = false

    var body: some View {
        if !networkMonitor.isConnected {
            HStack(spacing: 8) {
                Image(systemName: "wifi.slash")
                    .font(Theme.font(size: 14, weight: .semibold))

                Text("You are offline")
                    .font(Theme.subheadline)
                    .fontWeight(.semibold)

                if showExpandedMessage {
                    Spacer()
                    Text("Some features may be limited")
                        .font(Theme.caption)
                        .foregroundStyle(Theme.warning.opacity(0.8))
                }
            }
            .foregroundStyle(Theme.background)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: showExpandedMessage ? .leading : .center)
            .background(Theme.warning)
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }
}

// MARK: - Offline Disabled View Modifier

/// A view modifier that disables interactions and shows a message when offline
struct OfflineDisabledModifier: ViewModifier {
    @Environment(NetworkMonitor.self) private var networkMonitor

    /// Custom message to show when offline (nil uses default)
    var message: String?

    /// Whether this modifier should be active
    var isActive: Bool = true

    func body(content: Content) -> some View {
        content
            .disabled(!networkMonitor.isConnected && isActive)
            .opacity(!networkMonitor.isConnected && isActive ? 0.5 : 1.0)
    }
}

extension View {
    /// Disables the view when offline with optional custom message
    func disabledWhenOffline(message: String? = nil, isActive: Bool = true) -> some View {
        self.modifier(OfflineDisabledModifier(message: message, isActive: isActive))
    }
}

// MARK: - Offline Alert Modifier

/// A view modifier that shows an alert when attempting an action while offline
struct OfflineAlertModifier: ViewModifier {
    @Environment(NetworkMonitor.self) private var networkMonitor
    @Binding var showAlert: Bool

    var message: String

    func body(content: Content) -> some View {
        content
            .alert("Requires Internet Connection", isPresented: $showAlert) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(message)
            }
    }
}

extension View {
    /// Shows an alert when the binding is true and device is offline
    func offlineAlert(isPresented: Binding<Bool>, message: String = "This action requires an internet connection. Please connect to the internet and try again.") -> some View {
        self.modifier(OfflineAlertModifier(showAlert: isPresented, message: message))
    }
}

// MARK: - Preview

#Preview("Offline Banner") {
    VStack {
        OfflineBannerView()
        OfflineBannerView(showExpandedMessage: true)
        Spacer()
    }
    .frame(maxWidth: .infinity)
    .background(Theme.background)
    .environment(NetworkMonitor())
}
