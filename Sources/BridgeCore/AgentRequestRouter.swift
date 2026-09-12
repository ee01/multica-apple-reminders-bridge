import Foundation

public enum RequestRoutingError: Error, CustomStringConvertible, Equatable {
    case noRoute(String)
    case missingAgent(String)

    public var description: String {
        switch self {
        case .noRoute(let list): return "No dispatch route is configured for Apple Reminders list: \(list)"
        case .missingAgent(let list): return "Route for \(list) has no default Multica agent."
        }
    }
}

public struct AgentRequestRouter: Sendable {
    public let configuration: BridgeConfiguration
    private let projectionPolicy: ProjectProjectionPolicy

    public init(configuration: BridgeConfiguration) {
        self.configuration = configuration
        self.projectionPolicy = ProjectProjectionPolicy(configuration: configuration)
    }

    public func route(_ request: AgentRequestSnapshot) throws -> ProjectRoute {
        guard let route = projectionPolicy.routeForRequest(listName: request.listName) else {
            throw RequestRoutingError.noRoute(request.listName)
        }
        guard route.defaultAgentID?.isEmpty == false else {
            throw RequestRoutingError.missingAgent(request.listName)
        }
        return route
    }

    public func existingIssueReference(from url: URL?) -> String? {
        guard let url else { return nil }
        let pathParts = url.pathComponents.reversed()
        for part in pathParts where part.range(of: #"^[A-Za-z][A-Za-z0-9]*-[0-9]+$"#, options: .regularExpression) != nil {
            return part
        }
        return nil
    }
}
