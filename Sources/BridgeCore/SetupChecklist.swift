import Foundation

public enum SetupStep: Int, CaseIterable, Equatable, Sendable {
    case connect
    case workspace
    case reminders
    case done
}

public struct SetupChecklist: Equatable, Sendable {
    public var isAuthenticated: Bool
    public var hasWorkspace: Bool
    public var hasRemindersAccess: Bool

    public init(isAuthenticated: Bool, hasWorkspace: Bool, hasRemindersAccess: Bool) {
        self.isAuthenticated = isAuthenticated
        self.hasWorkspace = hasWorkspace
        self.hasRemindersAccess = hasRemindersAccess
    }

    /// Enough to sync and to dispatch new Reminders. The default Agent is chosen automatically.
    public var isReadyToSync: Bool { isAuthenticated && hasWorkspace && hasRemindersAccess }
    public var isComplete: Bool { isReadyToSync }

    public var nextStep: SetupStep {
        if !isAuthenticated { return .connect }
        if !hasWorkspace { return .workspace }
        if !hasRemindersAccess { return .reminders }
        return .done
    }
}
