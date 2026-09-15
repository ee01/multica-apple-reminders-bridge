#if os(macOS)
import Foundation
import EventKit
import BridgeCore

public enum EventKitBridgeError: Error, CustomStringConvertible {
    case permissionDenied
    case noWritableReminderSource
    case listUnavailable(String)
    case timedOut(String)

    public var description: String {
        switch self {
        case .permissionDenied: return "Apple Reminders access was not granted."
        case .noWritableReminderSource: return "No writable Apple Reminders source is available."
        case .listUnavailable(let name): return "Could not create or open Reminders list: \(name)"
        case .timedOut(let operation): return "Apple Reminders timed out while \(operation)."
        }
    }
}

@MainActor
final class EventKitReminderSink: ReminderSink {
    private let worker = EventKitStoreWorker.shared
    private let testListName: String

    init(configuration: BridgeConfiguration) {
        self.testListName = configuration.genericRequestListName
    }

    static var authorizationLabel: String {
        switch EKEventStore.authorizationStatus(for: .reminder) {
        case .fullAccess: return "Allowed"
        case .writeOnly: return "Write only"
        case .denied, .restricted: return "Denied"
        default: return "Not granted"
        }
    }

    static var hasFullAccess: Bool {
        EKEventStore.authorizationStatus(for: .reminder) == .fullAccess
    }

    static func writableListNames() -> [String] {
        guard hasFullAccess else { return [] }
        return EventKitStoreWorker.shared.writableListNames()
    }

    func requestAccess() async throws -> Bool {
        try await worker.requestAccess()
    }

    func ensureLists(_ listNames: Set<String>) async throws {
        try await worker.ensureLists(listNames)
    }

    func unavailableLists(in listNames: Set<String>) async -> [String] {
        (try? await worker.unavailableLists(in: listNames)) ?? []
    }

    func upsert(_ item: ReminderItem, existing: ReminderReceipt?) async throws -> ReminderReceipt {
        try await worker.upsert(item, existing: existing)
    }

    func resolve(_ receipt: ReminderReceipt, issueKey: String, kind: ReminderProjectionKind, generation: Int) async throws {
        try await worker.resolve(receipt, issueKey: issueKey, kind: kind, generation: generation)
    }

    func state(of receipt: ReminderReceipt, issueKey: String, kind: ReminderProjectionKind, generation: Int) async throws -> ReminderRemoteState {
        try await worker.state(of: receipt, issueKey: issueKey, kind: kind, generation: generation)
    }

    func scanRequests(in listNames: Set<String>) async throws -> [AgentRequestSnapshot] {
        try await worker.scanRequests(in: listNames)
    }

    func createTestReminder(title: String, notes: String) async throws -> ReminderReceipt {
        let item = ReminderItem(
            issueID: "bridge-test",
            issueKey: "BRIDGE-TEST",
            kind: .humanAction,
            generation: 1,
            listName: testListName,
            title: title,
            notes: notes,
            url: URL(string: "https://multica.ai"),
            priority: .normal,
            dueDate: nil,
            alarmDate: Date().addingTimeInterval(60)
        )
        return try await upsert(item, existing: nil)
    }
}

/// All EventKit store access runs on one serial queue so a stuck `saveCalendar` / fetch
/// cannot freeze the menu-bar MainActor. Timed-out sessions are abandoned and replaced.
final class EventKitStoreWorker: @unchecked Sendable {
    static let shared = EventKitStoreWorker()

    private let lock = NSLock()
    private var store = EKEventStore()
    private var queue = DispatchQueue(label: "ai.personal.multica-reminders-bridge.eventkit")

    private init() {}

    func writableListNames() -> [String] {
        let store = currentStore()
        store.refreshSourcesIfNecessary()
        var seen = Set<String>()
        var names: [String] = []
        for calendar in store.calendars(for: .reminder) where calendar.allowsContentModifications {
            let title = calendar.title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty else { continue }
            let key = title.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            guard seen.insert(key).inserted else { continue }
            names.append(title)
        }
        return names.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    func requestAccess() async throws -> Bool {
        let store = currentStore()
        let granted = try await store.requestFullAccessToReminders()
        if !granted { throw EventKitBridgeError.permissionDenied }
        return granted
    }

    func ensureLists(_ listNames: Set<String>) async throws {
        try await ensureAccess()
        for name in listNames.sorted() where !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            _ = try await reminderCalendar(named: name)
        }
    }

    func unavailableLists(in listNames: Set<String>) async throws -> [String] {
        try await ensureAccess()
        let titles = try await perform(timeout: 8, operation: "listing reminder lists") { store in
            store.refreshSourcesIfNecessary()
            return store.calendars(for: .reminder).filter(\.allowsContentModifications).map(\.title)
        }
        return listNames.sorted().filter { name in
            !titles.contains { Self.listNamesMatch($0, name) }
        }
    }

    func upsert(_ item: ReminderItem, existing: ReminderReceipt?) async throws -> ReminderReceipt {
        try await ensureAccess()
        let recoveredID = try await recoverReminderID(receipt: existing, issueKey: item.issueKey, kind: item.kind == .main ? .mainIssue : .humanAction, generation: item.generation)
        let calendarName = item.listName
        return try await perform(timeout: 15, operation: "saving reminder") { store in
            let reminder: EKReminder
            if let recoveredID, let found = store.calendarItem(withIdentifier: recoveredID) as? EKReminder {
                reminder = found
            } else {
                reminder = EKReminder(eventStore: store)
            }
            reminder.calendar = try self.reminderCalendar(named: calendarName, store: store)
            reminder.title = item.title
            reminder.notes = self.appendMarker(to: item.notes, issueKey: item.issueKey, kind: item.kind == .main ? .mainIssue : .humanAction, generation: item.generation)
            reminder.url = item.url
            reminder.priority = self.eventKitPriority(item.priority)
            reminder.dueDateComponents = item.dueDate.map {
                Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: $0)
            }
            reminder.alarms?.forEach { reminder.removeAlarm($0) }
            if let alarmDate = item.alarmDate { reminder.addAlarm(EKAlarm(absoluteDate: alarmDate)) }
            reminder.isCompleted = false
            try store.save(reminder, commit: true)
            return ReminderReceipt(calendarItemIdentifier: reminder.calendarItemIdentifier, externalIdentifier: reminder.calendarItemExternalIdentifier)
        }
    }

    func resolve(_ receipt: ReminderReceipt, issueKey: String, kind: ReminderProjectionKind, generation: Int) async throws {
        try await ensureAccess()
        guard let recoveredID = try await recoverReminderID(receipt: receipt, issueKey: issueKey, kind: kind, generation: generation) else { return }
        try await perform(timeout: 15, operation: "completing reminder") { store in
            guard let reminder = store.calendarItem(withIdentifier: recoveredID) as? EKReminder, !reminder.isCompleted else { return }
            reminder.isCompleted = true
            try store.save(reminder, commit: true)
        }
    }

    func state(of receipt: ReminderReceipt, issueKey: String, kind: ReminderProjectionKind, generation: Int) async throws -> ReminderRemoteState {
        try await ensureAccess()
        guard let recoveredID = try await recoverReminderID(receipt: receipt, issueKey: issueKey, kind: kind, generation: generation) else { return .missing }
        return try await perform(timeout: 8, operation: "reading reminder state") { store in
            guard let reminder = store.calendarItem(withIdentifier: recoveredID) as? EKReminder else { return .missing }
            return reminder.isCompleted ? .completed : .pending
        }
    }

    func scanRequests(in listNames: Set<String>) async throws -> [AgentRequestSnapshot] {
        try await ensureAccess()
        var output: [AgentRequestSnapshot] = []
        for name in listNames.sorted() {
            let calendarID: String? = try await perform(timeout: 8, operation: "opening list \(name)") { store in
                self.existingCalendar(named: name, store: store)?.calendarIdentifier
            }
            guard let calendarID else { continue }
            let values = try await fetchReminderSnapshots(calendarIdentifier: calendarID, timeout: 20)
            for reminder in values where !reminder.isCompleted {
                let notes = reminder.notes
                guard !notes.contains("Bridge ref:") else { continue }
                let stableID = reminder.externalIdentifier ?? reminder.calendarItemIdentifier
                guard !stableID.isEmpty else { continue }
                output.append(AgentRequestSnapshot(
                    id: stableID,
                    receipt: ReminderReceipt(calendarItemIdentifier: reminder.calendarItemIdentifier, externalIdentifier: reminder.externalIdentifier),
                    listName: name,
                    title: reminder.title,
                    notes: notes,
                    url: reminder.url,
                    dueDate: reminder.dueDate,
                    priority: reminder.priority
                ))
            }
        }
        return output
    }

    private struct ReminderSnapshot: Sendable {
        var calendarItemIdentifier: String
        var externalIdentifier: String?
        var title: String
        var notes: String
        var url: URL?
        var dueDate: Date?
        var priority: Int
        var isCompleted: Bool
        var markerNotes: String { notes }
    }

    private func recoverReminderID(receipt: ReminderReceipt?, issueKey: String, kind: ReminderProjectionKind, generation: Int) async throws -> String? {
        if let id = receipt?.calendarItemIdentifier {
            let exists: Bool = try await perform(timeout: 8, operation: "looking up reminder") { store in
                store.calendarItem(withIdentifier: id) is EKReminder
            }
            if exists { return id }
        }
        if let external = receipt?.externalIdentifier {
            let id: String? = try await perform(timeout: 8, operation: "looking up reminder by external id") { store in
                store.calendarItems(withExternalIdentifier: external).compactMap { $0 as? EKReminder }.first?.calendarItemIdentifier
            }
            if let id { return id }
        }
        let marker = marker(issueKey: issueKey, kind: kind, generation: generation)
        let snapshots = try await fetchReminderSnapshots(calendarIdentifier: nil, timeout: 20)
        return snapshots.first(where: { $0.markerNotes.contains(marker) })?.calendarItemIdentifier
    }

    private func fetchReminderSnapshots(calendarIdentifier: String?, timeout: TimeInterval) async throws -> [ReminderSnapshot] {
        let (store, queue) = currentSession()
        do {
            return try await withCheckedThrowingContinuation { continuation in
                let box = OnceResume(continuation)
                queue.async {
                    let calendars: [EKCalendar]
                    if let calendarIdentifier {
                        guard let calendar = store.calendar(withIdentifier: calendarIdentifier) else {
                            box.resume(returning: [])
                            return
                        }
                        calendars = [calendar]
                    } else {
                        calendars = store.calendars(for: .reminder).filter(\.allowsContentModifications)
                    }
                    guard !calendars.isEmpty else {
                        box.resume(returning: [])
                        return
                    }
                    let predicate = store.predicateForReminders(in: calendars)
                    store.fetchReminders(matching: predicate) { reminders in
                        let snapshots = (reminders ?? []).map { reminder in
                            ReminderSnapshot(
                                calendarItemIdentifier: reminder.calendarItemIdentifier,
                                externalIdentifier: reminder.calendarItemExternalIdentifier,
                                title: reminder.title ?? "Untitled Agent Request",
                                notes: reminder.notes ?? "",
                                url: reminder.url,
                                dueDate: self.date(from: reminder.dueDateComponents),
                                priority: reminder.priority,
                                isCompleted: reminder.isCompleted
                            )
                        }
                        box.resume(returning: snapshots)
                    }
                }
                Task {
                    try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                    box.resume(throwing: EventKitBridgeError.timedOut("fetching reminders"))
                }
            }
        } catch {
            if case EventKitBridgeError.timedOut = error { resetSession() }
            throw error
        }
    }

    private func reminderCalendar(named name: String) async throws -> String {
        try await perform(timeout: 12, operation: "creating list \(name)") { store in
            try self.reminderCalendar(named: name, store: store).calendarIdentifier
        }
    }

    private func reminderCalendar(named name: String, store: EKEventStore) throws -> EKCalendar {
        if let existing = existingCalendar(named: name, store: store) { return existing }
        guard let source = store.defaultCalendarForNewReminders()?.source else { throw EventKitBridgeError.noWritableReminderSource }
        let calendar = EKCalendar(for: .reminder, eventStore: store)
        calendar.title = name.trimmingCharacters(in: .whitespacesAndNewlines)
        calendar.source = source
        try store.saveCalendar(calendar, commit: true)
        guard calendar.allowsContentModifications else { throw EventKitBridgeError.listUnavailable(name) }
        return calendar
    }

    private func existingCalendar(named name: String, store: EKEventStore) -> EKCalendar? {
        store.calendars(for: .reminder).first { calendar in
            calendar.allowsContentModifications && Self.listNamesMatch(calendar.title, name)
        }
    }

    static func listNamesMatch(_ lhs: String, _ rhs: String) -> Bool {
        lhs.trimmingCharacters(in: .whitespacesAndNewlines)
            .caseInsensitiveCompare(rhs.trimmingCharacters(in: .whitespacesAndNewlines)) == .orderedSame
    }

    private func ensureAccess() async throws {
        switch EKEventStore.authorizationStatus(for: .reminder) {
        case .fullAccess: return
        case .notDetermined:
            _ = try await requestAccess()
        default:
            throw EventKitBridgeError.permissionDenied
        }
    }

    private func perform<T: Sendable>(timeout: TimeInterval, operation: String, work: @escaping (EKEventStore) throws -> T) async throws -> T {
        let (store, queue) = currentSession()
        do {
            return try await withCheckedThrowingContinuation { continuation in
                let box = OnceResume(continuation)
                queue.async {
                    do { box.resume(returning: try work(store)) }
                    catch { box.resume(throwing: error) }
                }
                Task {
                    try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                    box.resume(throwing: EventKitBridgeError.timedOut(operation))
                }
            }
        } catch {
            if case EventKitBridgeError.timedOut = error { resetSession() }
            throw error
        }
    }

    private func currentStore() -> EKEventStore {
        lock.lock()
        defer { lock.unlock() }
        return store
    }

    private func currentSession() -> (EKEventStore, DispatchQueue) {
        lock.lock()
        defer { lock.unlock() }
        return (store, queue)
    }

    private func resetSession() {
        lock.lock()
        store = EKEventStore()
        queue = DispatchQueue(label: "ai.personal.multica-reminders-bridge.eventkit.\(UUID().uuidString)")
        lock.unlock()
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

private final class OnceResume<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<T, Error>?

    init(_ continuation: CheckedContinuation<T, Error>) {
        self.continuation = continuation
    }

    func resume(returning value: T) {
        lock.lock()
        let pending = continuation
        continuation = nil
        lock.unlock()
        pending?.resume(returning: value)
    }

    func resume(throwing error: Error) {
        lock.lock()
        let pending = continuation
        continuation = nil
        lock.unlock()
        pending?.resume(throwing: error)
    }
}
#endif
