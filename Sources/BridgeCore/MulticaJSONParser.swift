import Foundation

public enum MulticaParseError: Error, CustomStringConvertible {
    case invalidJSON
    case unsupportedShape(String)
    case missingRequiredField(String)

    public var description: String {
        switch self {
        case .invalidJSON: return "Multica CLI returned invalid JSON"
        case .unsupportedShape(let shape): return "Unsupported Multica JSON shape: \(shape)"
        case .missingRequiredField(let field): return "Multica JSON is missing required field: \(field)"
        }
    }
}

public enum MulticaJSONParser {
    public static func parseIssues(_ data: Data) throws -> [IssueSnapshot] {
        let root = try json(data)
        return try extractArray(root, preferredKeys: ["issues", "items", "data", "results"]).map { raw in
            guard let dict = raw as? [String: Any] else { throw MulticaParseError.unsupportedShape("issue row") }
            return try parseIssue(dict)
        }
    }

    public static func parseIssue(_ data: Data) throws -> IssueSnapshot {
        let root = try json(data)
        if let dict = root as? [String: Any] {
            if let nested = firstDictionary(in: dict, keys: ["issue", "data", "item"]) {
                return try parseIssue(nested)
            }
            return try parseIssue(dict)
        }
        throw MulticaParseError.unsupportedShape(String(describing: type(of: root)))
    }

    public static func parseRuns(_ data: Data) throws -> [RunSnapshot] {
        let root = try json(data)
        return try extractArray(root, preferredKeys: ["runs", "tasks", "items", "data", "results"]).compactMap { raw in
            guard let dict = raw as? [String: Any] else { return nil }
            return parseRun(dict)
        }.sorted { lhs, rhs in
            let l = lhs.createdAt ?? lhs.startedAt ?? .distantPast
            let r = rhs.createdAt ?? rhs.startedAt ?? .distantPast
            return l > r
        }
    }

    public static func parseWorkspaceList(_ data: Data) throws -> [(id: String, name: String, slug: String?)] {
        let root = try json(data)
        return try extractArray(root, preferredKeys: ["workspaces", "items", "data", "results"]).compactMap { raw in
            guard let dict = raw as? [String: Any] else { return nil }
            guard let id = string(dict, keys: ["id", "workspace_id", "workspaceId"]) else { return nil }
            let name = string(dict, keys: ["name", "title"]) ?? id
            let slug = string(dict, keys: ["slug", "workspace_slug", "workspaceSlug"])
            return (id, name, slug)
        }
    }

    private static func parseIssue(_ dict: [String: Any]) throws -> IssueSnapshot {
        guard let id = string(dict, keys: ["id", "issue_id", "issueId", "uuid"]) else {
            throw MulticaParseError.missingRequiredField("issue.id")
        }
        let key = string(dict, keys: ["key", "issue_key", "issueKey", "identifier"]) ?? id
        let title = string(dict, keys: ["title", "name", "summary"]) ?? key

        let statusObject = firstDictionary(in: dict, keys: ["status", "issue_status", "issueStatus"])
        let statusName: String = statusObject.flatMap { string($0, keys: ["name", "slug", "key", "status"]) }
            ?? string(dict, keys: ["status_name", "statusName", "status"])
            ?? "unknown"
        let explicitCategory = statusObject.flatMap { string($0, keys: ["category", "type", "group"]) }
            ?? string(dict, keys: ["status_category", "statusCategory"])
        let statusCategory = IssueStatusCategory.infer(name: statusName, explicitCategory: explicitCategory)

        let priorityObject = firstDictionary(in: dict, keys: ["priority"])
        let priorityRaw = priorityObject.flatMap { string($0, keys: ["name", "slug", "key"]) }
            ?? string(dict, keys: ["priority"])
        let priority = IssuePriority(normalizing: priorityRaw)

        let labels = parseLabels(dict["labels"] ?? dict["label_names"] ?? dict["labelNames"])

        let assigneeName = nestedActorName(dict["assignee"])
            ?? nestedActorName(dict["assigned_to"])
            ?? string(dict, keys: ["assignee_name", "assigneeName"])
        let projectName = nestedName(dict["project"]) ?? string(dict, keys: ["project_name", "projectName"])
        let workspaceSlug = nestedString(dict["workspace"], keys: ["slug"]) ?? string(dict, keys: ["workspace_slug", "workspaceSlug"])

        let updatedAt = date(dict, keys: ["updated_at", "updatedAt", "modified_at", "modifiedAt"])
        let dueDate = date(dict, keys: ["due_date", "dueDate"])
        let summary = string(dict, keys: ["result_summary", "resultSummary", "summary", "latest_summary", "latestSummary", "description_preview"])

        var latestRun: RunSnapshot?
        if let runDict = firstDictionary(in: dict, keys: ["latest_run", "latestRun", "run"]) {
            latestRun = parseRun(runDict)
        }

        return IssueSnapshot(
            id: id,
            key: key,
            title: title,
            statusName: statusName,
            statusCategory: statusCategory,
            priority: priority,
            labels: labels,
            assigneeName: assigneeName,
            projectName: projectName,
            workspaceSlug: workspaceSlug,
            updatedAt: updatedAt,
            dueDate: dueDate,
            summary: summary,
            latestRun: latestRun
        )
    }

    private static func parseRun(_ dict: [String: Any]) -> RunSnapshot? {
        guard let id = string(dict, keys: ["id", "task_id", "taskId", "run_id", "runId", "uuid"]) else { return nil }
        let statusObject = firstDictionary(in: dict, keys: ["status"])
        let rawStatus = statusObject.flatMap { string($0, keys: ["name", "slug", "key"]) }
            ?? string(dict, keys: ["status", "state"])
        let errorObject = firstDictionary(in: dict, keys: ["error", "failure"])
        let errorMessage = errorObject.flatMap { string($0, keys: ["message", "detail", "reason"]) }
            ?? string(dict, keys: ["error_message", "errorMessage", "failure_reason", "failureReason", "last_error"])
        let agentName = nestedActorName(dict["agent"]) ?? string(dict, keys: ["agent_name", "agentName"])
        return RunSnapshot(
            id: id,
            status: RunStatus(normalizing: rawStatus),
            createdAt: date(dict, keys: ["created_at", "createdAt"]),
            startedAt: date(dict, keys: ["started_at", "startedAt"]),
            completedAt: date(dict, keys: ["completed_at", "completedAt", "finished_at", "finishedAt"]),
            errorMessage: errorMessage,
            waitReason: string(dict, keys: ["wait_reason", "waitReason"]),
            agentName: agentName
        )
    }

    private static func json(_ data: Data) throws -> Any {
        do { return try JSONSerialization.jsonObject(with: data) }
        catch { throw MulticaParseError.invalidJSON }
    }

    private static func extractArray(_ root: Any, preferredKeys: [String]) throws -> [Any] {
        if let array = root as? [Any] { return array }
        if let dict = root as? [String: Any] {
            for key in preferredKeys {
                if let array = dict[key] as? [Any] { return array }
                if let nested = dict[key] as? [String: Any] {
                    if let array = nested["items"] as? [Any] { return array }
                    if let array = nested["data"] as? [Any] { return array }
                }
            }
        }
        throw MulticaParseError.unsupportedShape(String(describing: type(of: root)))
    }

    private static func firstDictionary(in dict: [String: Any], keys: [String]) -> [String: Any]? {
        for key in keys where dict[key] is [String: Any] { return dict[key] as? [String: Any] }
        return nil
    }

    private static func string(_ dict: [String: Any], keys: [String]) -> String? {
        for key in keys {
            if let value = dict[key] as? String, !value.isEmpty { return value }
            if let number = dict[key] as? NSNumber { return number.stringValue }
        }
        return nil
    }

    private static func date(_ dict: [String: Any], keys: [String]) -> Date? {
        for key in keys {
            if let raw = dict[key] as? String, let parsed = FlexibleDateParser.parse(raw) { return parsed }
        }
        return nil
    }

    private static func nestedActorName(_ raw: Any?) -> String? {
        guard let dict = raw as? [String: Any] else { return raw as? String }
        return string(dict, keys: ["display_name", "displayName", "name", "title", "email"])
    }

    private static func nestedName(_ raw: Any?) -> String? {
        guard let dict = raw as? [String: Any] else { return raw as? String }
        return string(dict, keys: ["name", "title", "slug"])
    }

    private static func nestedString(_ raw: Any?, keys: [String]) -> String? {
        guard let dict = raw as? [String: Any] else { return nil }
        return string(dict, keys: keys)
    }

    private static func parseLabels(_ raw: Any?) -> Set<String> {
        guard let raw else { return [] }
        if let labels = raw as? [String] { return Set(labels.map { $0.lowercased() }) }
        if let array = raw as? [Any] {
            let names = array.compactMap { item -> String? in
                if let s = item as? String { return s }
                if let d = item as? [String: Any] { return string(d, keys: ["name", "slug", "label"]) }
                return nil
            }
            return Set(names.map { $0.lowercased() })
        }
        return []
    }
}
