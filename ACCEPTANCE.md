# ADHD Life Manager V0.1 — Acceptance checklist

- [ ] `LifeManager.swiftpm` opens and builds in Swift Playground on iPad.
- [ ] A new Task captured without a reminder appears in Now and Open Loops.
- [ ] A new Thought appears in Open Loops, but not Now.
- [ ] Tasks and Thoughts survive closing and reopening the app.
- [ ] Editing a task title/details/reminder is retained after restart.
- [ ] Tapping Try a sample reminder asks for permission when appropriate.
- [ ] Reminder arrives after about 25 seconds with the app in the background.
- [ ] Snooze from notification keeps the loop open and schedules a new reminder.
- [ ] Skip from notification keeps the loop open and postpones it.
- [ ] I did it from notification marks needs verification; does not auto-close.
- [ ] Verify & close marks the loop resolved.
- [ ] Denied notifications produce a clear message while preserving task state.
- [ ] On iPhone installation, test mirrored Apple Watch notification separately.

**Outcome:** V0.1.0 first iPad build failed on Settings `Section` initializer inference. Fixed in V0.1.1, pending recompilation on iPad. Core smoke tests and Swift parser passed on Linux.
