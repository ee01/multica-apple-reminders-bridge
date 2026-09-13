import Foundation

@MainActor
public final class InMemoryReminderSink: ReminderSink {
    public struct Stored: Sendable {
        public var item: ReminderItem
        public var state: ReminderRemoteState
        public var receipt: ReminderReceipt
    }

    public private(set) var records: [String: Stored] = [:]
    public var requests: [AgentRequestSnapshot] = []
    public var accessGranted = true
    public private(set) var ensuredLists: Set<String> = []

    public init() {}

    public func requestAccess() async throws -> Bool { accessGranted }

    public func ensureLists(_ listNames: Set<String>) async throws {
        ensuredLists.formUnion(listNames)
    }

    public func upsert(_ item: ReminderItem, existing: ReminderReceipt?) async throws -> ReminderReceipt {
        let id = existing?.calendarItemIdentifier ?? UUID().uuidString
        let receipt = ReminderReceipt(calendarItemIdentifier: id, externalIdentifier: existing?.externalIdentifier)
        records[id] = Stored(item: item, state: .pending, receipt: receipt)
        return receipt
    }

    public func resolve(_ receipt: ReminderReceipt, issueKey: String, kind: ReminderProjectionKind, generation: Int) async throws {
        guard let id = receipt.calendarItemIdentifier, var stored = records[id] else { return }
        stored.state = .completed
        records[id] = stored
    }

    public func state(of receipt: ReminderReceipt, issueKey: String, kind: ReminderProjectionKind, generation: Int) async throws -> ReminderRemoteState {
        guard let id = receipt.calendarItemIdentifier, let stored = records[id] else { return .missing }
        return stored.state
    }

    public func scanRequests(in listNames: Set<String>) async throws -> [AgentRequestSnapshot] {
        let visible = requests.filter { listNames.contains($0.listName) }
        // Model the real EventKit contract: a scanned request already exists remotely and
        // can be resolved in-place even when the chosen mirror mode does not keep a Main.
        for request in visible {
            guard let id = request.receipt.calendarItemIdentifier, records[id] == nil else { continue }
            let item = ReminderItem(
                issueID: "request:\(request.id)", issueKey: "REQUEST", kind: .main, generation: 0,
                listName: request.listName, title: request.title, notes: request.notes, url: request.url,
                priority: .normal, dueDate: request.dueDate, alarmDate: nil
            )
            records[id] = Stored(item: item, state: .pending, receipt: request.receipt)
        }
        return visible
    }

    public func createTestReminder(title: String, notes: String) async throws -> ReminderReceipt {
        try await upsert(ReminderItem(issueID: "test", issueKey: "TEST", kind: .humanAction, generation: 1, listName: "Agent Requests", title: title, notes: notes, url: nil, priority: .normal), existing: nil)
    }

    public func markCompleted(id: String) {
        guard var value = records[id] else { return }
        value.state = .completed
        records[id] = value
    }

    public func delete(id: String) { records.removeValue(forKey: id) }
}
