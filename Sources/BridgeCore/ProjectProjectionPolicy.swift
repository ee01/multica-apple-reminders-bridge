import Foundation

public struct ProjectionPlan: Equatable, Sendable {
    public let listName: String
    public let mirrorMode: MirrorMode
    public let shouldMaintainMain: Bool
    public let routeID: String?

    public init(listName: String, mirrorMode: MirrorMode, shouldMaintainMain: Bool, routeID: String?) {
        self.listName = listName
        self.mirrorMode = mirrorMode
        self.shouldMaintainMain = shouldMaintainMain
        self.routeID = routeID
    }
}

public struct ProjectProjectionPolicy: Sendable {
    public let configuration: BridgeConfiguration

    public init(configuration: BridgeConfiguration) { self.configuration = configuration }

    public func plan(issue: IssueSnapshot, binding: IssueBinding?) -> ProjectionPlan {
        let route = routeForIssue(issue, binding: binding)
        let mode = route?.mirrorMode ?? configuration.defaultMirrorMode
        let listName = binding?.appleListName.nonEmpty
            ?? route?.appleListName.nonEmpty
            ?? configuration.genericRequestListName
        let origin = binding?.origin ?? .multica

        let maintainMain: Bool
        switch mode {
        case .allActive: maintainMain = !issue.statusCategory.isTerminal
        case .appleOriginOnly: maintainMain = origin == .apple && !issue.statusCategory.isTerminal
        case .attentionOnly: maintainMain = false
        }

        return ProjectionPlan(listName: listName, mirrorMode: mode, shouldMaintainMain: maintainMain, routeID: route?.id ?? binding?.routeID)
    }

    public func routeForRequest(listName: String) -> ProjectRoute? {
        configuration.route(forAppleList: listName)
    }

    public func routeForIssue(_ issue: IssueSnapshot, binding: IssueBinding?) -> ProjectRoute? {
        if let routeID = binding?.routeID,
           let route = configuration.projectRoutes.first(where: { $0.id == routeID }) { return route }
        return configuration.route(for: issue)
    }
}

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}
