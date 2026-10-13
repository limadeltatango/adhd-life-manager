import Foundation
import Combine

private enum SnapshotStorage {
    static var directory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("LifeManager", isDirectory: true)
    }

    static var file: URL { directory.appendingPathComponent("life-manager-v1.json") }

    static func load() throws -> LifeManagerSnapshot {
        guard FileManager.default.fileExists(atPath: file.path) else {
            return LifeManagerSnapshot()
        }
        let data = try Data(contentsOf: file)
        let snapshot = try JSONDecoder().decode(LifeManagerSnapshot.self, from: data)
        guard snapshot.formatVersion == 1 else {
            throw NSError(domain: "LifeManagerStorage", code: 10,
                          userInfo: [NSLocalizedDescriptionKey: "Unrecognized local data version"])
        }
        return snapshot
    }

    static func save(_ snapshot: LifeManagerSnapshot) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(snapshot)
        try data.write(to: file, options: [.atomic])
    }
}

@MainActor
final class TaskStore: ObservableObject {
    static let shared = TaskStore()

    @Published private(set) var snapshot: LifeManagerSnapshot
    @Published private(set) var notificationPermission = "Checking…"
    @Published var userMessage: String?

    private(set) var isReadOnly = false
    private var hasBooted = false

    private init() {
        do {
            snapshot = try SnapshotStorage.load()
        } catch {
            // Preserve a damaged/unknown file; never overwrite it with empty data.
            snapshot = LifeManagerSnapshot()
            isReadOnly = true
            userMessage = "Local storage couldn't be read. Existing data has been preserved. No new changes will be saved. \(error.localizedDescription)"
        }
    }

    var loops: [LifeLoop] { snapshot.loops }
    var unresolved: [LifeLoop] { snapshot.loops.filter(\.isUnresolved) }
    var preferences: AppPreferences { snapshot.preferences }
    var completedCount: Int { snapshot.loops.filter { !$0.isUnresolved }.count }

    func now(at date: Date = Date()) -> [LifeLoop] {
        AttentionQueue.now(from: snapshot.loops, at: date, limit: 3)
    }

    func bootIfNeeded() {
        guard !hasBooted else { return }
        hasBooted = true
        LocalNotificationService.shared.registerActions()
        Task { await refreshPermission() }
        // Re-register future one-shot reminders after app relaunch. No network call.
        for loop in loops where loop.remindAt.map({ $0 > Date() }) == true {
            Task { await syncNotification(for: loop.id) }
        }
    }

    func refreshPermission() async {
        notificationPermission = await LocalNotificationService.shared.permissionDescription()
    }

    func askForNotificationPermission() {
        Task {
            do {
                _ = try await LocalNotificationService.shared.requestPermission()
                await refreshPermission()
            } catch {
                await refreshPermission()
                userMessage = error.localizedDescription
            }
        }
    }

    @discardableResult
    func add(title: String, details: String, kind: CaptureKind, remindAt: Date?) -> UUID? {
        let cleaned = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return nil }
        let loop = LifeLoop(
            title: cleaned,
            details: details.trimmingCharacters(in: .whitespacesAndNewlines),
            kind: kind,
            remindAt: remindAt
        )
        var next = snapshot
        next.loops.insert(loop, at: 0)
        next.events.append(LoopEvent(loopID: loop.id, event: "captured_\(kind.rawValue)"))
        guard commit(next) else { return nil }
        if loop.remindAt != nil { Task { await syncNotification(for: loop.id) } }
        return loop.id
    }

    func update(
        id: UUID,
        title: String,
        details: String,
        kind: CaptureKind,
        remindAt: Date?
    ) -> Bool {
        let cleaned = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return false }
        var next = snapshot
        guard let index = next.loops.firstIndex(where: { $0.id == id }),
              next.loops[index].state != .verified else { return false }
        next.loops[index].title = cleaned
        next.loops[index].details = details.trimmingCharacters(in: .whitespacesAndNewlines)
        next.loops[index].kind = kind
        if kind == .thought && next.loops[index].state == .awaitingVerification {
            next.loops[index].state = .open
            next.loops[index].reportedDoneAt = nil
        }
        next.loops[index].remindAt = (
            kind == .task && next.loops[index].state == .open ? remindAt : nil
        )
        next.loops[index].modifiedAt = Date()
        next.events.append(LoopEvent(loopID: id, event: "edited"))
        guard commit(next) else { return false }
        Task { await syncNotification(for: id) }
        return true
    }

    func remove(_ id: UUID) {
        var next = snapshot
        guard next.loops.contains(where: { $0.id == id }) else { return }
        next.loops.removeAll { $0.id == id }
        next.events.append(LoopEvent(loopID: id, event: "deleted"))
        guard commit(next) else { return }
        LocalNotificationService.shared.cancel(id)
    }

    func apply(_ action: LoopAction, to id: UUID) {
        guard applyAndPersist(action, to: id) else { return }
        Task { await syncNotification(for: id) }
    }

    // Called from the notification delegate while iOS grants background execution.
    // Do not signal completion until the next snoozed/skipped prompt is registered.
    func applyNotificationAction(_ action: LoopAction, to id: UUID) async {
        guard applyAndPersist(action, to: id) else { return }
        await syncNotification(for: id)
    }

    private func applyAndPersist(_ action: LoopAction, to id: UUID) -> Bool {
        var next = snapshot
        guard let index = next.loops.firstIndex(where: { $0.id == id }) else { return false }
        let before = next.loops[index]
        next.loops[index].apply(action, at: Date(), preferences: next.preferences)
        guard next.loops[index] != before else { return false }
        next.events.append(LoopEvent(loopID: id, event: action.rawValue))
        return commit(next)
    }

    func scheduleDemoPrompt(for id: UUID) {
        var next = snapshot
        guard let index = next.loops.firstIndex(where: { $0.id == id }),
              next.loops[index].kind == .task,
              next.loops[index].state == .open else { return }
        next.loops[index].remindAt = Date().addingTimeInterval(25)
        next.loops[index].modifiedAt = Date()
        next.events.append(LoopEvent(loopID: id, event: "demo_prompt_scheduled"))
        guard commit(next) else { return }
        Task { await syncNotification(for: id, isDemo: true) }
    }

    func scheduleSamplePrompt() {
        // Reuse the still-open demo task instead of flooding the open-loop list.
        let existing = loops.first {
            $0.kind == .task && $0.state == .open &&
            $0.title == "Try a Life Manager reminder"
        }
        if let existing {
            scheduleDemoPrompt(for: existing.id)
            return
        }
        let id = add(
            title: "Try a Life Manager reminder",
            details: "Use I did it, Snooze, or Skip when this appears. Then return to verify completion.",
            kind: .task,
            remindAt: nil
        )
        if let id { scheduleDemoPrompt(for: id) }
    }

    func setPreferences(_ updated: AppPreferences) {
        var next = snapshot
        next.preferences = updated
        guard commit(next) else { return }
        for loop in loops where loop.remindAt.map({ $0 > Date() }) == true {
            Task { await syncNotification(for: loop.id) }
        }
    }

    func reloadFromDisk() {
        guard !isReadOnly else { return }
        do {
            snapshot = try SnapshotStorage.load()
        } catch {
            isReadOnly = true
            userMessage = "Couldn't reload saved tasks. Existing data has not been overwritten. \(error.localizedDescription)"
        }
        Task { await refreshPermission() }
    }

    private func commit(_ next: LifeManagerSnapshot) -> Bool {
        guard !isReadOnly else {
            userMessage = "Storage is in recovery mode. No changes can be saved until the data issue is resolved."
            return false
        }
        do {
            // Commit to disk first. UI changes only after durable write succeeds.
            try SnapshotStorage.save(next)
            snapshot = next
            return true
        } catch {
            userMessage = "Couldn't save this change: \(error.localizedDescription)"
            return false
        }
    }

    private func syncNotification(for id: UUID, isDemo: Bool = false) async {
        guard let loop = loops.first(where: { $0.id == id }) else {
            LocalNotificationService.shared.cancel(id)
            return
        }
        do {
            try await LocalNotificationService.shared.schedule(loop, playSound: preferences.playSound)
            await refreshPermission()
            if isDemo {
                userMessage = "Test reminder scheduled for about 25 seconds from now. Close Life Manager to test delivery."
            }
        } catch {
            await refreshPermission()
            userMessage = error.localizedDescription
        }
    }
}
