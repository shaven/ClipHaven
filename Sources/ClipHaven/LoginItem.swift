import ServiceManagement

/// Start at login through `SMAppService.mainApp`, which registers the running app bundle.
enum LoginItem {
    static var status: SMAppService.Status { SMAppService.mainApp.status }

    static var isEnabled: Bool { status == .enabled }

    static func set(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }

    /// For the settings window: what the owner needs to know beyond the checkbox.
    static var note: String {
        switch status {
        case .enabled: "ClipHaven starts when you log in."
        case .requiresApproval: "Approve ClipHaven in System Settings > General > Login Items."
        case .notFound: "Run the app from build/ClipHaven.app or /Applications to enable this."
        case .notRegistered: ""
        @unknown default: ""
        }
    }
}
