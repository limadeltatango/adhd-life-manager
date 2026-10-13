import Foundation

// This file deliberately depends only on Foundation so that state transitions and
// persistence formats can be tested outside the Apple SDK environment.

enum CaptureKind: String, Codable, CaseIterable, Identifiable {
    case task
    case thought

    var id: String { rawValue }
    var title: String { self == .task ? "Task" : "Thought" }
}

enum LoopState: String, Codable {
    case open
    case awaitingVerification
    case verified
}

enum LoopAction: String, Codable {
    case reportedDone
    case snoozed
    case skipped
    case verified
    case reopened
}

struct AppPreferences: Codable, Equatable {
    // V0.1 is local-only regardless of the future server address.
    var localDemoMode: Bool = true
    var snoozeMinutes: Int = 10
    var skipHours: Int = 24
    var playSound: Bool = true
    var futureBackendURL: String = ""
}

struct LifeLoop: Codable, Identifiable, Equatable {
    let id: UUID
    var title: String
    var details: String
    var kind: CaptureKind
    let createdAt: Date
    var modifiedAt: Date
    var state: LoopState
    var remindAt: Date?
    var acknowledgedAt: Date?
    var reportedDoneAt: Date?
    var verifiedAt: Date?
    var skippedAt: Date?
    var skipCount: Int
    var lastAction: LoopAction?

    init(
        id: UUID = UUID(),
        title: String,
        details: String = "",
        kind: CaptureKind = .task,
        createdAt: Date = Date(),
        remindAt: Date? = nil
    ) {
        self.id = id
        self.title = title
        self.details = details
        self.kind = kind
        self.createdAt = createdAt
        self.modifiedAt = createdAt
        self.state = .open
        self.remindAt = (kind == .task ? remindAt : nil)
        self.acknowledgedAt = nil
        self.reportedDoneAt = nil
        self.verifiedAt = nil
        self.skippedAt = nil
        self.skipCount = 0
        self.lastAction = nil
    }

    var isUnresolved: Bool { state != .verified }
    var isAwaitingVerification: Bool { state == .awaitingVerification }

    func needsAttention(at date: Date) -> Bool {
        guard kind == .task, isUnresolved else { return false }
        if state == .awaitingVerification { return true }
        return remindAt.map { $0 <= date } ?? true
    }

    mutating func apply(
        _ action: LoopAction,
        at date: Date,
        preferences: AppPreferences
    ) {
        switch action {
        case .reportedDone:
            guard state == .open else { return }
            state = .awaitingVerification
            acknowledgedAt = date
            reportedDoneAt = date
            remindAt = nil

        case .snoozed:
            guard state == .open, kind == .task else { return }
            acknowledgedAt = date
            remindAt = date.addingTimeInterval(TimeInterval(preferences.snoozeMinutes * 60))

        case .skipped:
            guard state == .open, kind == .task else { return }
            acknowledgedAt = date
            skippedAt = date
            skipCount += 1
            remindAt = date.addingTimeInterval(TimeInterval(preferences.skipHours * 3600))

        case .verified:
            guard state == .awaitingVerification else { return }
            state = .verified
            verifiedAt = date
            remindAt = nil

        case .reopened:
            guard state == .awaitingVerification else { return }
            state = .open
            reportedDoneAt = nil
            verifiedAt = nil
            remindAt = nil
        }
        modifiedAt = date
        lastAction = action
    }
}

struct LoopEvent: Codable, Identifiable, Equatable {
    let id: UUID
    let loopID: UUID
    let occurredAt: Date
    let event: String

    init(loopID: UUID, event: String, occurredAt: Date = Date()) {
        self.id = UUID()
        self.loopID = loopID
        self.occurredAt = occurredAt
        self.event = event
    }
}

struct LifeManagerSnapshot: Codable {
    var formatVersion: Int = 1
    var loops: [LifeLoop] = []
    var preferences: AppPreferences = AppPreferences()
    var events: [LoopEvent] = []
}

enum AttentionQueue {
    static func now(from loops: [LifeLoop], at date: Date, limit: Int = 3) -> [LifeLoop] {
        loops.filter { $0.needsAttention(at: date) }
            .sorted { a, b in
                let aRank = priority(a, at: date)
                let bRank = priority(b, at: date)
                if aRank != bRank { return aRank < bRank }
                // Older overdue reminders are more urgent; otherwise prefer recent captures.
                if aRank == 1 {
                    return (a.remindAt ?? date) < (b.remindAt ?? date)
                }
                return a.createdAt > b.createdAt
            }
            .prefix(max(0, limit))
            .map { $0 }
    }

    private static func priority(_ loop: LifeLoop, at date: Date) -> Int {
        if loop.state == .awaitingVerification { return 0 }
        if let reminder = loop.remindAt, reminder <= date { return 1 }
        return 2
    }
}
