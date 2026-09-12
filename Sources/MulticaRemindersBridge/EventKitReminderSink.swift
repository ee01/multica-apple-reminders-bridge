#if os(macOS)
import Foundation
import EventKit
import BridgeCore

public enum EventKitBridgeError: Error, CustomStringConvertible {
    case permissionDenied
    case noWritableReminderSource
    case listUnavailable(String)

    public var description: String {
        switch self {
        case .permissionDenied: return "Apple Reminders access was not granted."
        case .noWritableReminderSource: return "No writable Apple Reminders source is available."
        case .listUnavailable(let name): return "Could not create or open Reminders list: \(name)"
        }
    }
}

@MainActor
final class EventKitReminderSink: ReminderSink {
    private let store = EKEventStore()

    init(configuration: BridgeConfiguration) {}

    func requestAccess() async throws -> Bool {
        let granted = try await store.requestFullAccessToReminders()
        if !granted { throw EventKitBridgeError.permissionDenied }
        return granted
    }

    func upsert(_ item: ReminderItem, existing: ReminderReceipt?) async throws -> ReminderReceipt {
        _ = try await ensureAccess()
        let recovered = try await recoverReminder(receipt: existing, issueKey: item.issueKey, kind: item.kind == .main ? .mainIssue : .humanAction, generation: item.generation)
        let reminder = recovered ?? EKReminder(eventStore: store)
        reminder.calendar = try reminderCalendar(named: item.listName)
        reminder.title = item.title
        reminder.notes = appendMarker(to: item.notes, issueKey: item.issueKey, kind: item.kind == .main ? .mainIssue : .humanAction, generation: item.generation)
        reminder.url = item.url
        reminder.priority = eventKitPriority(item.priority)
        reminder.dueDateComponents = item.dueDate.map {
            Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: $0)
        }
        // Bridge-managed projections own their notification alarms. Main Agent work deliberately has none.
        reminder.alarms?.forEach { reminder.removeAlarm($0) }
        if let alarmDate = item.alarmDate { reminder.addAlarm(EKAlarm(absoluteDate: alarmDate)) }
        reminder.isCompleted = false
        try store.save(reminder, commit: true)
        return ReminderReceipt(calendarItemIdentifier: reminder.calendarItemIdentifier, externalIdentifier: reminder.calendarItemExternalIdentifier)
    }

    func resolve(_ receipt: ReminderReceipt, issueKey: String, kind: ReminderProjectionKind, generation: Int) async throws {
        _ = try await ensureAccess()
        guard let reminder = try await recoverReminder(receipt: receipt, issueKey: issueKey, kind: kind, generation: generation) else { return }
        if !reminder.isCompleted {
            reminder.isCompleted = true
            try store.save(reminder, commit: true)
        }
    }

    func state(of receipt: ReminderReceipt, issueKey: String, kind: ReminderProjectionKind, generation: Int) async throws -> ReminderRemoteState {
        _ = try await ensureAccess()
        guard let reminder = try await recoverReminder(receipt: receipt, issueKey: issueKey, kind: kind, generation: generation) else { return .missing }
        return reminder.isCompleted ? .completed : .pending
    }

    func scanRequests(in listNames: Set<String>) async throws -> [AgentRequestSnapshot] {
        _ = try await ensureAccess()
        var output: [AgentRequestSnapshot] = []
        for name in listNames.sorted() {
            guard let calendar = store.calendars(for: .reminder).first(where: { $0.title == name && $0.allowsContentModifications }) else { continue }
            let values = await fetchReminders(in: [calendar])
            for reminder in values where !reminder.isCompleted {
                let notes = reminder.notes ?? ""
                guard !notes.contains("Bridge ref:") else { continue }
                let calendarID = reminder.calendarItemIdentifier
                let externalID = reminder.calendarItemExternalIdentifier
                let stableID = externalID ?? calendarID
                guard let stableID, !stableID.isEmpty else { continue }
                output.append(AgentRequestSnapshot(
                    id: stableID,
                    receipt: ReminderReceipt(calendarItemIdentifier: calendarID, externalIdentifier: externalID),
                    listName: name,
                    title: reminder.title ?? "Untitled Agent Request",
                    notes: notes,
                    url: reminder.url,
                    dueDate: date(from: reminder.dueDateComponents),
                    priority: reminder.priority
                ))
            }
        }
        return output
    }

    func createTestReminder(title: String, notes: String) async throws -> ReminderReceipt {
        let item = ReminderItem(issueID: "bridge-test", issueKey: "BRIDGE-TEST", kind: .humanAction, generation: 1, listName: "Agent Requests", title: title, notes: notes, url: URL(string: "https://multica.ai"), priority: .normal, dueDate: nil, alarmDate: Date().addingTimeInterval(60))
        return try await upsert(item, existing: nil)
    }

    private func ensureAccess() async throws -> Bool {
        switch EKEventStore.authorizationStatus(for: .reminder) {
        case .fullAccess: return true
        case .notDetermined: return try await requestAccess()
        default: throw EventKitBridgeError.permissionDenied
        }
    }

    private func reminderCalendar(named name: String) throws -> EKCalendar {
        if let existing = store.calendars(for: .reminder).first(where: { $0.title == name && $0.allowsContentModifications }) { return existing }
        guard let source = store.defaultCalendarForNewReminders()?.source else { throw EventKitBridgeError.noWritableReminderSource }
        let calendar = EKCalendar(for: .reminder, eventStore: store)
        calendar.title = name
        calendar.source = source
        try store.saveCalendar(calendar, commit: true)
        guard calendar.allowsContentModifications else { throw EventKitBridgeError.listUnavailable(name) }
        return calendar
    }

    private func recoverReminder(receipt: ReminderReceipt?, issueKey: String, kind: ReminderProjectionKind, generation: Int) async throws -> EKReminder? {
        if let id = receipt?.calendarItemIdentifier, let reminder = store.calendarItem(withIdentifier: id) as? EKReminder { return reminder }
        if let external = receipt?.externalIdentifier,
           let reminder = store.calendarItems(withExternalIdentifier: external).compactMap({ $0 as? EKReminder }).first { return reminder }
        let marker = marker(issueKey: issueKey, kind: kind, generation: generation)
        let calendars = store.calendars(for: .reminder).filter(\.allowsContentModifications)
        let reminders = await fetchReminders(in: calendars)
        return reminders.first(where: { $0.notes?.contains(marker) == true })
    }

    private func fetchReminders(in calendars: [EKCalendar]) async -> [EKReminder] {
        guard !calendars.isEmpty else { return [] }
        let predicate = store.predicateForReminders(in: calendars)
        return await withCheckedContinuation { continuation in
            store.fetchReminders(matching: predicate) { continuation.resume(returning: $0 ?? []) }
        }
    }

    private func marker(issueKey: String, kind: ReminderProjectionKind, generation: Int) -> String {
        switch kind {
        case .mainIssue: return "Bridge ref: \(issueKey)#main"
        case .humanAction: return "Bridge ref: \(issueKey)#human-\(generation)"
        }
    }

    private func appendMarker(to notes: String, issueKey: String, kind: ReminderProjectionKind, generation: Int) -> String {
        let value = marker(issueKey: issueKey, kind: kind, generation: generation)
        let stripped = notes.components(separatedBy: "\n").filter { !$0.hasPrefix("Bridge ref:") }.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        return stripped.isEmpty ? value : stripped + "\n\n" + value
    }

    private func date(from components: DateComponents?) -> Date? {
        guard let components else { return nil }
        return Calendar.current.date(from: components)
    }

    private func eventKitPriority(_ severity: AttentionSeverity) -> Int {
        switch severity {
        case .urgent: return Int(EKReminderPriority.high.rawValue)
        case .high: return Int(EKReminderPriority.medium.rawValue)
        case .normal: return Int(EKReminderPriority.none.rawValue)
        }
    }
}
#endif
