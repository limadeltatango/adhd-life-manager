# ADHD Life Manager — V0.1.0

SwiftUI iPhone/iPad app prototype designed to be opened in Swift Playground on iPad.

## Open on your iPad

1. Download **LifeManager-v0.1.0.zip** to the **Files** app on your iPad.
2. Tap the ZIP to expand it. Inside is an app project named **LifeManager.swiftpm**.
3. Open the **Swift Playground** app, choose **Browse**, and find **LifeManager.swiftpm** in Files. Open it and tap **Run**. If Files offers **Open in Swift Playground**, that also works.
4. If the app displays a build error, send the exact first error (or a screenshot). You do **not** need to edit the source files yourself.

## What is implemented

- **Now:** up to three relevant unresolved tasks at a time, with verified items kept off the queue.
- **Capture:** quick typed Task or Thought. Tasks can have optional reminders; thoughts don't generate prompts.
- **Open Loops:** every unresolved task and captured thought, including items awaiting verification, plus editing and deletion.
- **Actions:** **I did it** marks a task as *self-reported complete, awaiting verification*. **Verify & close** is a separate confirmation. **Snooze** postpones; **Skip** postpones without closing the task. Reopen is supported.
- **Notifications:** an actionable, one-shot **local** notification; a 25-second demonstration button is on Now and Settings.
- **Settings:** permission status/requests, snooze interval, skip interval, sound preference, inactive future server address, and local demo status.
- **Persistence:** tasks, statuses, preferences, and an internal event log are saved atomically to the app's Application Support directory as JSON.

## First acceptance test

1. **Capture** a task such as “Take out the recycling” without a reminder.
2. Check that it appears in **Now** and **Open Loops**. Close and reopen the app; verify it is still there.
3. In **Now**, tap **Try a sample reminder**. Allow notification permission when prompted, then leave the app or lock the iPad. Expect the test prompt about 25 seconds later.
4. Try one action: **Snooze**, **Skip for now**, or **I did it**. Reopen **Open Loops**. Snooze and Skip keep the item open; I did it places it in **Needs verification**.
5. Tap **Verify & close** to resolve a self-reported item. Repeat the demo separately to try the other notification actions.

### Apple Watch testing

Apple Watch notification mirroring is paired to the **iPhone**, not to the iPad. The iPad app can validate local notification behavior now; Apple Watch mirroring requires first installing the iPhone app on your paired iPhone (for example using Apple's App Store Connect/TestFlight workflow), and then testing the notification on that iPhone while the watch is worn. Mirroring and action availability cannot be guaranteed in advance.

## Limits and safety

- **V0.1 is a local demo**, not a production reminder service. No DigitalOcean, Omi, AI, Watch extension, network, remote push, or background polling is included.
- “Verify & close” means a second **manual user confirmation** at this stage, not sensor-based independent proof of task completion.
- One-shot reminders do not automatically repeat after being ignored. An overdue task remains visible in Now; Snooze or Skip explicitly schedules the next reminder.
- If notifications are denied, the tasks remain saved but no system notification can be delivered. Change permissions in iPad Settings if needed.
- Data stays in the app sandbox, has no cloud backup in V0.1, and may be removed if the app is deleted. Do not rely on this prototype as the only record of time-critical obligations.
- The future backend URL field stores only a text address. It does not connect or transmit data. Do not enter secrets in that field.
- Device-side iPad/iPhone compilation, notification delivery, and Watch mirroring **have not yet been tested** by the assistant. Apple SDKs and Swift Playground are not present in the Linux validation environment.

## Technical notes

- `LifeManager.swiftpm` uses Swift tools version 5.9, SwiftUI, iOS 17+, and AppleProductTypes `.iOSApplication`.
- No third-party Swift packages or paid services.
- The core transition and Codable model (`LifeManagerCore.swift`) can be compiled and tested with Linux Swift using `Tests/CoreSmokeTests.swift`.
- Notification interactions are processed by `UNUserNotificationCenterDelegate`; a background action is persisted before the next prompt is scheduled.
- Bundle identifier: `com.limadeltatango.lifemanager` (can be changed in the app's Playgrounds settings when configuring a developer team/distribution).

## Development isolation

This package is intentionally independent of Axik AI Weave, BuildAxis, Arbiter/Forge, Atlas, OpenStorage, and all existing production DigitalOcean services.
