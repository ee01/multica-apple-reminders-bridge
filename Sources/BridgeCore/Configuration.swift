import Foundation

public enum ReviewCompletionBehavior: String, Codable, CaseIterable, Hashable, Sendable {
    /// Completing the Review sibling is treated as approval of the delivered Issue.
    /// The Bridge closes the Multica Issue only after strict state guards pass.
    case closeIssue = "close_issue"
    /// Completing the Review sibling only acknowledges the Apple reminder.
    case acknowledgeOnly = "acknowledge_only"
}

public struct BridgeConfiguration: Codable, Equatable, Sendable {
    public var multicaCLIPath: String
    public var multicaProfile: String
    public var workspaceID: String?
    public var workspaceSlug: String?
    public var appBaseURL: String

    public var genericRequestListName: String
    public var projectRoutes: [ProjectRoute]
    public var defaultMirrorMode: MirrorMode
    public var defaultProjectID: String?
    public var defaultProjectName: String?
    public var defaultAgentID: String?
    public var defaultAgentName: String?
    public var requestDispatchEnabled: Bool

    public var reminderAlarmEnabled: Bool
    public var reminderAlarmDelaySeconds: TimeInterval
    public var pollIntervalSeconds: TimeInterval
    public var issuePageSize: Int
    public var maxRunHydrationPerSync: Int
    public var blockedGraceSeconds: TimeInterval
    public var failureRemindersEnabled: Bool
    public var reviewCompletionBehavior: ReviewCompletionBehavior
    public var suppressionLabels: Set<String>
    public var urgentLabels: Set<String>
    public var alwaysLabels: Set<String>

    public init(
        multicaCLIPath: String = "/opt/homebrew/bin/multica",
        multicaProfile: String = "reminders-bridge",
        workspaceID: String? = nil,
        workspaceSlug: String? = nil,
        appBaseURL: String = "https://multica.ai",
        genericRequestListName: String = "Agent Requests",
        projectRoutes: [ProjectRoute] = [],
        defaultMirrorMode: MirrorMode = .appleOriginOnly,
        defaultProjectID: String? = nil,
        defaultProjectName: String? = nil,
        defaultAgentID: String? = nil,
        defaultAgentName: String? = nil,
        requestDispatchEnabled: Bool = true,
        reminderAlarmEnabled: Bool = true,
        reminderAlarmDelaySeconds: TimeInterval = 60,
        pollIntervalSeconds: TimeInterval = 180,
        issuePageSize: Int = 100,
        maxRunHydrationPerSync: Int = 30,
        blockedGraceSeconds: TimeInterval = 600,
        failureRemindersEnabled: Bool = true,
        reviewCompletionBehavior: ReviewCompletionBehavior = .closeIssue,
        suppressionLabels: Set<String> = ["no-reminder"],
        urgentLabels: Set<String> = ["reminder-urgent"],
        alwaysLabels: Set<String> = ["reminder-always"]
    ) {
        self.multicaCLIPath = multicaCLIPath
        self.multicaProfile = multicaProfile
        self.workspaceID = workspaceID
        self.workspaceSlug = workspaceSlug
        self.appBaseURL = appBaseURL
        self.genericRequestListName = genericRequestListName
        self.projectRoutes = projectRoutes
        self.defaultMirrorMode = defaultMirrorMode
        self.defaultProjectID = defaultProjectID
        self.defaultProjectName = defaultProjectName
        self.defaultAgentID = defaultAgentID
        self.defaultAgentName = defaultAgentName
        self.requestDispatchEnabled = requestDispatchEnabled
        self.reminderAlarmEnabled = reminderAlarmEnabled
        self.reminderAlarmDelaySeconds = reminderAlarmDelaySeconds
        self.pollIntervalSeconds = pollIntervalSeconds
        self.issuePageSize = issuePageSize
        self.maxRunHydrationPerSync = maxRunHydrationPerSync
        self.blockedGraceSeconds = blockedGraceSeconds
        self.failureRemindersEnabled = failureRemindersEnabled
        self.reviewCompletionBehavior = reviewCompletionBehavior
        self.suppressionLabels = suppressionLabels
        self.urgentLabels = urgentLabels
        self.alwaysLabels = alwaysLabels
    }

    /// Kept only for decoding old v0.1 configuration files. New code uses project/fallback lists.
    public var reminderListName: String { genericRequestListName }

    public var requestListNames: Set<String> {
        Set([genericRequestListName] + projectRoutes.map(\.appleListName))
    }

    public func route(forAppleList name: String) -> ProjectRoute? {
        if let exact = projectRoutes.first(where: { $0.appleListName == name }) { return exact }
        guard name == genericRequestListName else { return nil }
        return ProjectRoute(
            id: "default",
            appleListName: genericRequestListName,
            multicaProjectID: defaultProjectID,
            multicaProjectName: defaultProjectName,
            defaultAgentID: defaultAgentID,
            defaultAgentName: defaultAgentName,
            mirrorMode: defaultMirrorMode
        )
    }

    public func route(for issue: IssueSnapshot) -> ProjectRoute? {
        if let projectID = issue.projectID,
           let route = projectRoutes.first(where: { $0.multicaProjectID == projectID }) { return route }
        if let projectName = issue.projectName,
           let route = projectRoutes.first(where: { $0.multicaProjectName == projectName }) { return route }
        return nil
    }

    private enum CodingKeys: String, CodingKey {
        case multicaCLIPath, multicaProfile, workspaceID, workspaceSlug, appBaseURL
        case genericRequestListName, projectRoutes, defaultMirrorMode, defaultProjectID, defaultProjectName, defaultAgentID, defaultAgentName, requestDispatchEnabled
        case reminderListName, reminderAlarmEnabled, reminderAlarmDelaySeconds
        case pollIntervalSeconds, issuePageSize, maxRunHydrationPerSync, blockedGraceSeconds
        case failureRemindersEnabled, reviewCompletionBehavior, suppressionLabels, urgentLabels, alwaysLabels
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.multicaCLIPath = try c.decodeIfPresent(String.self, forKey: .multicaCLIPath) ?? "/opt/homebrew/bin/multica"
        self.multicaProfile = try c.decodeIfPresent(String.self, forKey: .multicaProfile) ?? "reminders-bridge"
        self.workspaceID = try c.decodeIfPresent(String.self, forKey: .workspaceID)
        self.workspaceSlug = try c.decodeIfPresent(String.self, forKey: .workspaceSlug)
        self.appBaseURL = try c.decodeIfPresent(String.self, forKey: .appBaseURL) ?? "https://multica.ai"
        self.genericRequestListName = try c.decodeIfPresent(String.self, forKey: .genericRequestListName)
            ?? c.decodeIfPresent(String.self, forKey: .reminderListName)
            ?? "Agent Requests"
        self.projectRoutes = try c.decodeIfPresent([ProjectRoute].self, forKey: .projectRoutes) ?? []
        self.defaultMirrorMode = try c.decodeIfPresent(MirrorMode.self, forKey: .defaultMirrorMode) ?? .appleOriginOnly
        self.defaultProjectID = try c.decodeIfPresent(String.self, forKey: .defaultProjectID)
        self.defaultProjectName = try c.decodeIfPresent(String.self, forKey: .defaultProjectName)
        self.defaultAgentID = try c.decodeIfPresent(String.self, forKey: .defaultAgentID)
        self.defaultAgentName = try c.decodeIfPresent(String.self, forKey: .defaultAgentName)
        self.requestDispatchEnabled = try c.decodeIfPresent(Bool.self, forKey: .requestDispatchEnabled) ?? true
        self.reminderAlarmEnabled = try c.decodeIfPresent(Bool.self, forKey: .reminderAlarmEnabled) ?? true
        self.reminderAlarmDelaySeconds = try c.decodeIfPresent(TimeInterval.self, forKey: .reminderAlarmDelaySeconds) ?? 60
        self.pollIntervalSeconds = try c.decodeIfPresent(TimeInterval.self, forKey: .pollIntervalSeconds) ?? 180
        self.issuePageSize = try c.decodeIfPresent(Int.self, forKey: .issuePageSize) ?? 100
        self.maxRunHydrationPerSync = try c.decodeIfPresent(Int.self, forKey: .maxRunHydrationPerSync) ?? 30
        self.blockedGraceSeconds = try c.decodeIfPresent(TimeInterval.self, forKey: .blockedGraceSeconds) ?? 600
        self.failureRemindersEnabled = try c.decodeIfPresent(Bool.self, forKey: .failureRemindersEnabled) ?? true
        self.reviewCompletionBehavior = try c.decodeIfPresent(ReviewCompletionBehavior.self, forKey: .reviewCompletionBehavior) ?? .closeIssue
        self.suppressionLabels = try c.decodeIfPresent(Set<String>.self, forKey: .suppressionLabels) ?? ["no-reminder"]
        self.urgentLabels = try c.decodeIfPresent(Set<String>.self, forKey: .urgentLabels) ?? ["reminder-urgent"]
        self.alwaysLabels = try c.decodeIfPresent(Set<String>.self, forKey: .alwaysLabels) ?? ["reminder-always"]
    }


    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(multicaCLIPath, forKey: .multicaCLIPath)
        try c.encode(multicaProfile, forKey: .multicaProfile)
        try c.encodeIfPresent(workspaceID, forKey: .workspaceID)
        try c.encodeIfPresent(workspaceSlug, forKey: .workspaceSlug)
        try c.encode(appBaseURL, forKey: .appBaseURL)
        try c.encode(genericRequestListName, forKey: .genericRequestListName)
        try c.encode(projectRoutes, forKey: .projectRoutes)
        try c.encode(defaultMirrorMode, forKey: .defaultMirrorMode)
        try c.encodeIfPresent(defaultProjectID, forKey: .defaultProjectID)
        try c.encodeIfPresent(defaultProjectName, forKey: .defaultProjectName)
        try c.encodeIfPresent(defaultAgentID, forKey: .defaultAgentID)
        try c.encodeIfPresent(defaultAgentName, forKey: .defaultAgentName)
        try c.encode(requestDispatchEnabled, forKey: .requestDispatchEnabled)
        try c.encode(reminderAlarmEnabled, forKey: .reminderAlarmEnabled)
        try c.encode(reminderAlarmDelaySeconds, forKey: .reminderAlarmDelaySeconds)
        try c.encode(pollIntervalSeconds, forKey: .pollIntervalSeconds)
        try c.encode(issuePageSize, forKey: .issuePageSize)
        try c.encode(maxRunHydrationPerSync, forKey: .maxRunHydrationPerSync)
        try c.encode(blockedGraceSeconds, forKey: .blockedGraceSeconds)
        try c.encode(failureRemindersEnabled, forKey: .failureRemindersEnabled)
        try c.encode(reviewCompletionBehavior, forKey: .reviewCompletionBehavior)
        try c.encode(suppressionLabels, forKey: .suppressionLabels)
        try c.encode(urgentLabels, forKey: .urgentLabels)
        try c.encode(alwaysLabels, forKey: .alwaysLabels)
    }

    public static func load(from url: URL) throws -> BridgeConfiguration {
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(BridgeConfiguration.self, from: data)
    }

    public func save(to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(self)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }
}
