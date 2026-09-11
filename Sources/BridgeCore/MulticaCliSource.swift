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
            let data = Data(result.stdout.utf8)
            let page: [IssueSnapshot]
            do { page = try MulticaJSONParser.parseIssues(data) }
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

    public func listWorkspaces() async throws -> [(id: String, name: String, slug: String?)] {
        let result = try await run(["workspace", "list", "--full-id", "--output", "json"])
        do { return try MulticaJSONParser.parseWorkspaceList(Data(result.stdout.utf8)) }
        catch { throw MulticaSourceError.malformedOutput(String(describing: error)) }
    }

    public func login() async throws {
        // Interactive browser login can legitimately take much longer than a normal
        // read/query command. It still does not start a daemon; only the timeout differs.
        _ = try await run(["login"], timeout: 300)
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
}
