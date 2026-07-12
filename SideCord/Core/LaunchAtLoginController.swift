import Combine
import ServiceManagement

@MainActor
final class LaunchAtLoginController: ObservableObject {
    @Published private(set) var status: SMAppService.Status

    private let service: SMAppService

    var isEnabled: Bool {
        status == .enabled
    }

    var requiresApproval: Bool {
        status == .requiresApproval
    }

    init(service: SMAppService = .mainApp) {
        self.service = service
        status = service.status
    }

    func refresh() {
        status = service.status
    }

    func setEnabled(_ enabled: Bool) throws {
        defer { refresh() }

        let currentStatus = service.status
        if enabled {
            if currentStatus == .notRegistered || currentStatus == .notFound {
                try service.register()
            }
        } else if currentStatus == .enabled || currentStatus == .requiresApproval {
            try service.unregister()
        }
    }
}
