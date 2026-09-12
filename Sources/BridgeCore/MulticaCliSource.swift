import Foundation

public enum MulticaSourceError: Error, CustomStringConvertible {
    case notAuthenticated(String)
    case workspaceUnavailable(String)
    case command(String)
    case malformedOutput(String)

    public var description: String {
        switch self {
        case .notAuthenticated(let message): return "Multica authentication required: \(message)"
        case .workspaceUnavailable(let message): return "Multica workspace unavailable: \(message)"
        case .command(let message): return "Multica CLI error: \(message)"
        case .malformedOutput(let message): return "Multica returned malformed data: \(message)"
        }
    }
}

public struct MulticaCliSource<Runner: CommandRunning>: MulticaSource, Sendable {
    public let configuration: BridgeConfiguration
    public let runner: Runner
    public let commandTimeout: TimeInterval

    public init(configuration: BridgeConfiguration, runner: Runner, commandTimeout: TimeInterval = 25) {
        self.configuration = configuration
        self.runner = runner
        self.commandTimeout = commandTimeout
    }

    public func authStatus() async throws -> String {
        let result = try await run(["auth", "status"])
        return result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public func version() async throws -> String {
        let result = try await run(["version"])
        return result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public func fetchIssues() async throws -> [IssueSnapshot] {
        var all: [IssueSnapshot] = []
        var offset = 0
        let limit = max(1, configuration.issuePageSize)
        while true {
            var args = ["issue", "list", "--limit", String(limit), "--offset", String(offset), "--full-id", "--output", "json"]
            args.append(contentsOf: workspaceArguments())
            let result = try await run(args)
            let page: [IssueSnapshot]
            do { page = try MulticaJSONParser.parseIssues(Data(result.stdout.utf8)) }
            catch { throw MulticaSourceError.malformedOutput(String(describing: error)) }
            all.append(contentsOf: page)
            if page.count < limit { break }
            offset += page.count
            if offset > 10_000 { break }
        }
        return deduplicate(all)
    }

    public func fetchIssue(idOrKey: String) async throws -> IssueSnapshot {
        var args = ["issue", "get", idOrKey, "--resolve-properties", "--output", "json"]
        args.append(contentsOf: workspaceArguments())
        let result = try await run(args)
        do { return try MulticaJSONParser.parseIssue(Data(result.stdout.utf8)) }
        catch { throw MulticaSourceError.malformedOutput(String(describing: error)) }
    }

    public func fetchRuns(issueIDOrKey: String) async throws -> [RunSnapshot] {
        var args = ["issue", "runs", issueIDOrKey, "--full-id", "--output", "json"]
        args.append(contentsOf: workspaceArguments())
        let result = try await run(args)
        do { return try MulticaJSONParser.parseRuns(Data(result.stdout.utf8)) }
        catch { throw MulticaSourceError.malformedOutput(String(describing: error)) }
    }

    public func createIssue(_ request: IssueCreateRequest) async throws -> IssueSnapshot {
        // Recovery first: a crash after Cloud creation but before SQLite commit must not duplicate work.
        // If creation succeeded but assignment did not, recovery also finishes the missing assignment.
        if let existing = try await findIssue(bridgeRequestID: request.requestID) {
            if existing.assigneeName == nil, let agentID = request.agentID, !agentID.isEmpty {
                try await assignIssue(issueIDOrKey: existing.key, agentID: agentID)
                return (try? await fetchIssue(idOrKey: existing.key)) ?? existing
            }
            return existing
        }

        let marker = "Apple Bridge request: \(request.requestID)"
        let description = [request.description.trimmingCharacters(in: .whitespacesAndNewlines), "", marker]
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
        let descriptionURL = try makeTemporaryTextFile(contents: description)
        defer { try? FileManager.default.removeItem(at: descriptionURL) }

        var args = ["issue", "create", "--title", request.title, "--description-file", descriptionURL.path, "--status", "todo", "--output", "json"]
        if let projectID = request.projectID, !projectID.isEmpty { args += ["--project", projectID] }
        if let dueDate = request.dueDate { args += ["--due-date", Self.formatDay(dueDate)] }
        args.append(contentsOf: workspaceArguments())
        let result = try await run(args)
        let issue: IssueSnapshot
        do { issue = try MulticaJSONParser.parseIssue(Data(result.stdout.utf8)) }
        catch { throw MulticaSourceError.malformedOutput(String(describing: error)) }

        if let agentID = request.agentID, !agentID.isEmpty {
            try await assignIssue(issueIDOrKey: issue.key, agentID: agentID)
        }
        return (try? await fetchIssue(idOrKey: issue.key)) ?? issue
    }

    public func findIssue(bridgeRequestID: String) async throws -> IssueSnapshot? {
        let marker = "Apple Bridge request: \(bridgeRequestID)"
        var args = ["issue", "search", marker, "--limit", "5", "--include-closed", "--output", "json"]
        args.append(contentsOf: workspaceArguments())
        do {
            let result = try await run(args)
            let values = try MulticaJSONParser.parseSearchIssues(Data(result.stdout.utf8))
            return values.first
        } catch let error as MulticaSourceError { throw error }
        catch { throw MulticaSourceError.malformedOutput(String(describing: error)) }
    }

    public func assignIssue(issueIDOrKey: String, agentID: String) async throws {
        var args = ["issue", "assign", issueIDOrKey, "--to-id", agentID]
        args.append(contentsOf: workspaceArguments())
        _ = try await run(args)
    }

    public func addComment(issueIDOrKey: String, content: String) async throws {
        let file = try makeTemporaryTextFile(contents: content)
        defer { try? FileManager.default.removeItem(at: file) }
        var args = ["issue", "comment", "add", issueIDOrKey, "--content-file", file.path]
        args.append(contentsOf: workspaceArguments())
        _ = try await run(args)
    }

    public func listProjects() async throws -> [MulticaProject] {
        var args = ["project", "list", "--full-id", "--output", "json"]
        args.append(contentsOf: workspaceArguments())
        let result = try await run(args)
        do { return try MulticaJSONParser.parseProjects(Data(result.stdout.utf8)) }
        catch { throw MulticaSourceError.malformedOutput(String(describing: error)) }
    }

    public func listAgents() async throws -> [MulticaAgent] {
        var args = ["agent", "list", "--full-id", "--output", "json"]
        args.append(contentsOf: workspaceArguments())
        let result = try await run(args)
        do { return try MulticaJSONParser.parseAgents(Data(result.stdout.utf8)) }
        catch { throw MulticaSourceError.malformedOutput(String(describing: error)) }
    }

    public func listWorkspaces() async throws -> [(id: String, name: String, slug: String?)] {
        let result = try await run(["workspace", "list", "--full-id", "--output", "json"])
        do { return try MulticaJSONParser.parseWorkspaceList(Data(result.stdout.utf8)) }
        catch { throw MulticaSourceError.malformedOutput(String(describing: error)) }
    }

    public func login() async throws {
        // Login only creates/refreshes this CLI profile. It never starts a daemon.
        _ = try await run(["login"], timeout: 300)
    }

    private func makeTemporaryTextFile(contents: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("multica-bridge-\(UUID().uuidString).md")
        try Data(contents.utf8).write(to: url, options: .atomic)
        return url
    }

    private func run(_ commandArguments: [String], timeout: TimeInterval? = nil) async throws -> CommandResult {
        let args = commandArguments + ["--profile", configuration.multicaProfile]
        do {
            return try await runner.run(executable: configuration.multicaCLIPath, arguments: args, timeout: timeout ?? commandTimeout)
        } catch let error as CommandRunnerError {
            let text = error.description.lowercased()
            if text.contains("login") || text.contains("auth") || text.contains("token") || text.contains("unauthorized") {
                throw MulticaSourceError.notAuthenticated(error.description)
            }
            if text.contains("workspace") && (text.contains("not found") || text.contains("access")) {
                throw MulticaSourceError.workspaceUnavailable(error.description)
            }
            throw MulticaSourceError.command(error.description)
        } catch {
            throw MulticaSourceError.command(String(describing: error))
        }
    }

    private func workspaceArguments() -> [String] {
        if let id = configuration.workspaceID, !id.isEmpty { return ["--workspace-id", id] }
        return []
    }

    private func deduplicate(_ values: [IssueSnapshot]) -> [IssueSnapshot] {
        var seen = Set<String>()
        return values.filter { seen.insert($0.id).inserted }
    }

    private static func formatDay(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = Calendar(identifier: .gregorian)
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }
}
