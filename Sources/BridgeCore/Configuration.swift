import Foundation

public struct BridgeConfiguration: Codable, Equatable, Sendable {
    public var multicaCLIPath: String
    public var multicaProfile: String
    public var workspaceID: String?
    public var workspaceSlug: String?
    public var appBaseURL: String
    public var reminderListName: String
    public var reminderAlarmEnabled: Bool
    public var reminderAlarmDelaySeconds: TimeInterval
    public var pollIntervalSeconds: TimeInterval
    public var issuePageSize: Int
    public var maxRunHydrationPerSync: Int
    public var blockedGraceSeconds: TimeInterval
    public var failureRemindersEnabled: Bool
    public var suppressionLabels: Set<String>
    public var urgentLabels: Set<String>
    public var alwaysLabels: Set<String>

    public init(
        multicaCLIPath: String = "/opt/homebrew/bin/multica",
        multicaProfile: String = "reminders-bridge",
        workspaceID: String? = nil,
        workspaceSlug: String? = nil,
        appBaseURL: String = "https://multica.ai",
        reminderListName: String = "Multica Reviews",
        reminderAlarmEnabled: Bool = true,
        reminderAlarmDelaySeconds: TimeInterval = 60,
        pollIntervalSeconds: TimeInterval = 180,
        issuePageSize: Int = 100,
        maxRunHydrationPerSync: Int = 30,
        blockedGraceSeconds: TimeInterval = 600,
        failureRemindersEnabled: Bool = true,
        suppressionLabels: Set<String> = ["no-reminder"],
        urgentLabels: Set<String> = ["reminder-urgent"],
        alwaysLabels: Set<String> = ["reminder-always"]
    ) {
        self.multicaCLIPath = multicaCLIPath
        self.multicaProfile = multicaProfile
        self.workspaceID = workspaceID
        self.workspaceSlug = workspaceSlug
        self.appBaseURL = appBaseURL
        self.reminderListName = reminderListName
        self.reminderAlarmEnabled = reminderAlarmEnabled
        self.reminderAlarmDelaySeconds = reminderAlarmDelaySeconds
        self.pollIntervalSeconds = pollIntervalSeconds
        self.issuePageSize = issuePageSize
        self.maxRunHydrationPerSync = maxRunHydrationPerSync
        self.blockedGraceSeconds = blockedGraceSeconds
        self.failureRemindersEnabled = failureRemindersEnabled
        self.suppressionLabels = suppressionLabels
        self.urgentLabels = urgentLabels
        self.alwaysLabels = alwaysLabels
    }


    private enum CodingKeys: String, CodingKey {
        case multicaCLIPath, multicaProfile, workspaceID, workspaceSlug, appBaseURL
        case reminderListName, reminderAlarmEnabled, reminderAlarmDelaySeconds
        case pollIntervalSeconds, issuePageSize, maxRunHydrationPerSync, blockedGraceSeconds
        case failureRemindersEnabled, suppressionLabels, urgentLabels, alwaysLabels
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.multicaCLIPath = try c.decodeIfPresent(String.self, forKey: .multicaCLIPath) ?? "/opt/homebrew/bin/multica"
        self.multicaProfile = try c.decodeIfPresent(String.self, forKey: .multicaProfile) ?? "reminders-bridge"
        self.workspaceID = try c.decodeIfPresent(String.self, forKey: .workspaceID)
        self.workspaceSlug = try c.decodeIfPresent(String.self, forKey: .workspaceSlug)
        self.appBaseURL = try c.decodeIfPresent(String.self, forKey: .appBaseURL) ?? "https://multica.ai"
        self.reminderListName = try c.decodeIfPresent(String.self, forKey: .reminderListName) ?? "Multica Reviews"
        self.reminderAlarmEnabled = try c.decodeIfPresent(Bool.self, forKey: .reminderAlarmEnabled) ?? true
        self.reminderAlarmDelaySeconds = try c.decodeIfPresent(TimeInterval.self, forKey: .reminderAlarmDelaySeconds) ?? 60
        self.pollIntervalSeconds = try c.decodeIfPresent(TimeInterval.self, forKey: .pollIntervalSeconds) ?? 180
        self.issuePageSize = try c.decodeIfPresent(Int.self, forKey: .issuePageSize) ?? 100
        self.maxRunHydrationPerSync = try c.decodeIfPresent(Int.self, forKey: .maxRunHydrationPerSync) ?? 30
        self.blockedGraceSeconds = try c.decodeIfPresent(TimeInterval.self, forKey: .blockedGraceSeconds) ?? 600
        self.failureRemindersEnabled = try c.decodeIfPresent(Bool.self, forKey: .failureRemindersEnabled) ?? true
        self.suppressionLabels = try c.decodeIfPresent(Set<String>.self, forKey: .suppressionLabels) ?? ["no-reminder"]
        self.urgentLabels = try c.decodeIfPresent(Set<String>.self, forKey: .urgentLabels) ?? ["reminder-urgent"]
        self.alwaysLabels = try c.decodeIfPresent(Set<String>.self, forKey: .alwaysLabels) ?? ["reminder-always"]
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
