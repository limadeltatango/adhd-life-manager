import Foundation

@main
struct CoreSmokeTests {
    static func main() throws {
        let now = Date(timeIntervalSince1970: 1_790_000_000)
        let preferences = AppPreferences()
        var loop = LifeLoop(title: "Test the reminder", createdAt: now)
        assert(loop.needsAttention(at: now))
        loop.apply(.snoozed, at: now, preferences: preferences)
        assert(!loop.needsAttention(at: now))
        assert(loop.remindAt == now.addingTimeInterval(600))
        loop.apply(.skipped, at: now, preferences: preferences)
        assert(loop.skipCount == 1)
        assert(loop.remindAt == now.addingTimeInterval(86_400))
        loop.apply(.reportedDone, at: now, preferences: preferences)
        assert(loop.state == .awaitingVerification)
        assert(loop.isUnresolved)
        assert(loop.reportedDoneAt != nil && loop.verifiedAt == nil)
        assert(loop.needsAttention(at: now))
        loop.apply(.verified, at: now, preferences: preferences)
        assert(loop.state == .verified)
        assert(!loop.isUnresolved)
        assert(!loop.needsAttention(at: now))

        var thought = LifeLoop(title: "Capture a stray thought", kind: .thought, createdAt: now)
        assert(!thought.needsAttention(at: now))
        thought.apply(.snoozed, at: now, preferences: preferences)
        assert(thought.remindAt == nil)

        var pending = LifeLoop(title: "Pending", createdAt: now)
        pending.apply(.reportedDone, at: now, preferences: preferences)
        pending.apply(.reopened, at: now, preferences: preferences)
        assert(pending.state == .open)

        let snapshot = LifeManagerSnapshot(loops: [loop, thought, pending], preferences: preferences)
        let data = try JSONEncoder().encode(snapshot)
        let restored = try JSONDecoder().decode(LifeManagerSnapshot.self, from: data)
        assert(restored.loops.count == 3)
        assert(restored.loops[0] == loop)
        assert(AttentionQueue.now(from: restored.loops, at: now).map(\.id) == [pending.id])
        print("Life Manager core: all assertions passed")
    }
}
