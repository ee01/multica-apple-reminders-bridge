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
    private let listName: String
    private let alarmEnabled: Bool
    private let alarmDelaySeconds: TimeInterval

    init(configuration: BridgeConfiguration) {
        self.listName = configuration.reminderListName
        self.alarmEnabled = configuration.reminderAlarmEnabled
        self.alarmDelaySeconds = max(0, configuration.reminderAlarmDelaySeconds)
    }

    func requestAccess() async throws -> Bool {
        let granted = try await store.requestFullAccessToReminders()
        if !granted { throw EventKitBridgeError.permissionDenied }
        _ = try reminderCalendar()
        return granted
    }

    func upsert(_ item: HumanAttentionItem, existing: ReminderReceipt?) async throws -> ReminderReceipt {
        _ = try await ensureAccess()
        let recovered = try await recoverReminder(receipt: existing, issueKey: item.issueKey, reviewGeneration: item.reviewGeneration)
        let isNew = recovered == nil
        let reminder = recovered ?? EKReminder(eventStore: store)
        reminder.calendar = try reminderCalendar()
        reminder.title = item.title
        reminder.notes = appendMarker(to: item.notes, issueKey: item.issueKey, reviewGeneration: item.reviewGeneration)
        reminder.url = item.url
        reminder.priority = eventKitPriority(item.priority)
        reminder.dueDateComponents = item.dueDate.map {
            Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: $0)
        }
        if isNew && alarmEnabled {
            reminder.addAlarm(EKAlarm(absoluteDate: Date().addingTimeInterval(alarmDelaySeconds)))
        }
        reminder.isCompleted = false
        try store.save(reminder, commit: true)
        return ReminderReceipt(
            calendarItemIdentifier: reminder.calendarItemIdentifier,
            externalIdentifier: reminder.calendarItemExternalIdentifier
        )
    }

    func resolve(_ receipt: ReminderReceipt, issueKey: String, reviewGeneration: Int) async throws {
        _ = try await ensureAccess()
        guard let reminder = try await recoverReminder(receipt: receipt, issueKey: issueKey, reviewGeneration: reviewGeneration) else { return }
        if !reminder.isCompleted {
            reminder.isCompleted = true
            try store.save(reminder, commit: true)
        }
    }

    func state(of receipt: ReminderReceipt, issueKey: String, reviewGeneration: Int) async throws -> ReminderRemoteState {
        _ = try await ensureAccess()
        guard let reminder = try await recoverReminder(receipt: receipt, issueKey: issueKey, reviewGeneration: reviewGeneration) else { return .missing }
        return reminder.isCompleted ? .completed : .pending
    }

    func createTestReminder(title: String, notes: String) async throws -> ReminderReceipt {
        try await upsert(
            HumanAttentionItem(
                issueID: "bridge-test",
                issueKey: "BRIDGE-TEST",
                reviewGeneration: 1,
                title: title,
                notes: notes,
                url: URL(string: "https://multica.ai"),
                priority: .normal,
                dueDate: nil
            ),
            existing: nil
        )
    }

    private func ensureAccess() async throws -> Bool {
        switch EKEventStore.authorizationStatus(for: .reminder) {
        case .fullAccess: return true
        case .notDetermined: return try await requestAccess()
        default: throw EventKitBridgeError.permissionDenied
        }
    }

    private func reminderCalendar() throws -> EKCalendar {
        if let existing = store.calendars(for: .reminder).first(where: { $0.title == listName && $0.allowsContentModifications }) {
            return existing
        }
        guard let source = store.defaultCalendarForNewReminders()?.source else {
            throw EventKitBridgeError.noWritableReminderSource
        }
        let calendar = EKCalendar(for: .reminder, eventStore: store)
        calendar.title = listName
        calendar.source = source
        try store.saveCalendar(calendar, commit: true)
        guard calendar.allowsContentModifications else { throw EventKitBridgeError.listUnavailable(listName) }
        return calendar
    }

    private func recoverReminder(receipt: ReminderReceipt?, issueKey: String, reviewGeneration: Int) async throws -> EKReminder? {
        if let id = receipt?.calendarItemIdentifier,
           let reminder = store.calendarItem(withIdentifier: id) as? EKReminder {
            return reminder
        }
        if let external = receipt?.externalIdentifier {
            if let reminder = store.calendarItems(withExternalIdentifier: external).compactMap({ $0 as? EKReminder }).first {
                return reminder
            }
        }

        let marker = marker(issueKey: issueKey, reviewGeneration: reviewGeneration)
        let calendar = try reminderCalendar()
        let predicate = store.predicateForReminders(in: [calendar])
        let reminders: [EKReminder] = await withCheckedContinuation { continuation in
            store.fetchReminders(matching: predicate) { values in
                continuation.resume(returning: values ?? [])
            }
        }
        return reminders.first(where: { $0.notes?.contains(marker) == true })
    }

    private func marker(issueKey: String, reviewGeneration: Int) -> String {
        "Bridge ref: \(issueKey)#review-\(reviewGeneration)"
    }

    private func appendMarker(to notes: String, issueKey: String, reviewGeneration: Int) -> String {
        let value = marker(issueKey: issueKey, reviewGeneration: reviewGeneration)
        if notes.contains(value) { return notes }
        return notes + "\n\n" + value
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
