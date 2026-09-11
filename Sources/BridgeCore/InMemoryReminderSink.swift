import Foundation

@MainActor
public final class InMemoryReminderSink: ReminderSink {
    public struct Stored: Sendable {
        public var item: HumanAttentionItem
        public var state: ReminderRemoteState
        public var receipt: ReminderReceipt
    }

    public private(set) var records: [String: Stored] = [:]
    public var accessGranted = true

    public init() {}

    public func requestAccess() async throws -> Bool { accessGranted }

    public func upsert(_ item: HumanAttentionItem, existing: ReminderReceipt?) async throws -> ReminderReceipt {
        let id = existing?.calendarItemIdentifier ?? UUID().uuidString
        let receipt = ReminderReceipt(calendarItemIdentifier: id, externalIdentifier: existing?.externalIdentifier)
        records[id] = Stored(item: item, state: .pending, receipt: receipt)
        return receipt
    }

    public func resolve(_ receipt: ReminderReceipt, issueKey: String, reviewGeneration: Int) async throws {
        guard let id = receipt.calendarItemIdentifier, var stored = records[id] else { return }
        stored.state = .completed
        records[id] = stored
    }

    public func state(of receipt: ReminderReceipt, issueKey: String, reviewGeneration: Int) async throws -> ReminderRemoteState {
        guard let id = receipt.calendarItemIdentifier, let stored = records[id] else { return .missing }
        return stored.state
    }

    public func createTestReminder(title: String, notes: String) async throws -> ReminderReceipt {
        try await upsert(HumanAttentionItem(issueID: "test", issueKey: "TEST", reviewGeneration: 1, title: title, notes: notes, url: nil, priority: .normal, dueDate: nil), existing: nil)
    }

    public func markCompleted(id: String) {
        guard var value = records[id] else { return }
        value.state = .completed
        records[id] = value
    }

    public func delete(id: String) {
        records.removeValue(forKey: id)
    }
}
