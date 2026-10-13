import SwiftUI
import UIKit
import Combine

private enum LifeTab: Hashable {
    case now
    case capture
    case loops
    case settings
}

struct LifeManagerRootView: View {
    @EnvironmentObject private var store: TaskStore
    @State private var tab: LifeTab = .now

    var body: some View {
        TabView(selection: $tab) {
            NowView(openCapture: { tab = .capture })
                .tabItem { Label("Now", systemImage: "sun.max") }
                .tag(LifeTab.now)

            CaptureView(afterSave: { tab = .now })
                .tabItem { Label("Capture", systemImage: "plus.circle.fill") }
                .tag(LifeTab.capture)

            OpenLoopsView()
                .tabItem { Label("Open Loops", systemImage: "tray.full") }
                .tag(LifeTab.loops)

            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
                .tag(LifeTab.settings)
        }
        .tint(.teal)
        .alert(
            "Life Manager",
            isPresented: Binding(
                get: { store.userMessage != nil },
                set: { if !$0 { store.userMessage = nil } }
            )
        ) {
            Button("OK") { store.userMessage = nil }
        } message: {
            Text(store.userMessage ?? "")
        }
    }
}

private struct NowView: View {
    @EnvironmentObject private var store: TaskStore
    let openCapture: () -> Void
    @State private var currentTime = Date()

    private var current: [LifeLoop] { store.now(at: currentTime) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("One thing at a time")
                            .font(.largeTitle.bold())
                        Text("Showing up to three open items that need attention.")
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 8)

                    if current.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 36))
                                .foregroundStyle(.teal)
                            Text("Nothing needs attention right now")
                                .font(.title3.bold())
                            Text("Capture something when it comes to mind. Future reminders remain in Open Loops until they're due.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Button("Capture something", action: openCapture)
                                .buttonStyle(.borderedProminent)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(20)
                        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18))
                    } else {
                        ForEach(current) { loop in
                            LoopCard(loop: loop)
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Label("Test a prompt", systemImage: "bell.badge")
                            .font(.headline)
                        Text("Schedule a local reminder for 25 seconds from now. You can leave the app before it arrives.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Button("Try a sample reminder") {
                            store.scheduleSamplePrompt()
                        }
                        .buttonStyle(.bordered)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(18)
                    .background(Color.teal.opacity(0.08), in: RoundedRectangle(cornerRadius: 16))

                    Text("Acknowledged ≠ completed. 'I did it' moves a task to verification instead of silently closing it.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 30)
            }
            .navigationTitle("Now")
            .onAppear { currentTime = Date() }
            .onReceive(
                Timer.publish(every: 30, on: .main, in: .common).autoconnect()
            ) { currentTime = $0 }
        }
    }
}

private struct CaptureView: View {
    @EnvironmentObject private var store: TaskStore
    let afterSave: () -> Void

    @State private var title = ""
    @State private var details = ""
    @State private var kind: CaptureKind = .task
    @State private var wantsReminder = false
    @State private var reminder = Date().addingTimeInterval(3600)
    @FocusState private var titleHasFocus: Bool

    private var validTitle: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Capture type", selection: $kind) {
                        ForEach(CaptureKind.allCases) { item in
                            Text(item.title).tag(item)
                        }
                    }
                    .pickerStyle(.segmented)

                    TextField("What do you need to remember?", text: $title, axis: .vertical)
                        .lineLimit(1...4)
                        .submitLabel(.done)
                        .focused($titleHasFocus)

                    TextField("Extra details (optional)", text: $details, axis: .vertical)
                        .lineLimit(2...6)
                } header: {
                    Text("Get it out of your head")
                } footer: {
                    Text(kind == .thought
                         ? "Thoughts are saved without nagging you. You can turn one into a task later."
                         : "Tasks without a future reminder appear in Now immediately.")
                }

                if kind == .task {
                    Section("Reminder") {
                        Toggle("Remind me later", isOn: $wantsReminder)
                        if wantsReminder {
                            DatePicker("When", selection: $reminder, in: Date()..., displayedComponents: [.date, .hourAndMinute])
                        }
                    }
                }

                Section {
                    Button(action: capture) {
                        HStack {
                            Spacer()
                            Label("Capture", systemImage: "plus.circle.fill")
                                .font(.headline)
                            Spacer()
                        }
                    }
                    .disabled(!validTitle)
                }
            }
            .navigationTitle("Capture")
        }
    }

    private func capture() {
        let id = store.add(
            title: title,
            details: details,
            kind: kind,
            remindAt: (kind == .task && wantsReminder ? reminder : nil)
        )
        guard id != nil else { return }
        title = ""
        details = ""
        kind = .task
        wantsReminder = false
        reminder = Date().addingTimeInterval(3600)
        titleHasFocus = false
        afterSave()
    }
}

private struct LoopCard: View {
    @EnvironmentObject private var store: TaskStore
    let loop: LifeLoop
    var onEdit: (() -> Void)? = nil
    var onDelete: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: icon)
                    .foregroundStyle(loop.state == .awaitingVerification ? .orange : .teal)
                    .font(.title3)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 5) {
                    Text(loop.title)
                        .font(.headline)
                        .fixedSize(horizontal: false, vertical: true)
                    if !loop.details.isEmpty {
                        Text(loop.details)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(3)
                    }
                    statusLine
                }
                Spacer(minLength: 0)
                if onEdit != nil || onDelete != nil {
                    Menu {
                        if let onEdit {
                            Button("Edit", systemImage: "pencil", action: onEdit)
                        }
                        if let onDelete {
                            Button("Delete", systemImage: "trash", role: .destructive, action: onDelete)
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityLabel("Options for \(loop.title)")
                }
            }

            if loop.kind == .task {
                if loop.state == .awaitingVerification {
                    HStack {
                        Button("Verify & close") {
                            store.apply(.verified, to: loop.id)
                        }
                        .buttonStyle(.borderedProminent)
                        Button("Not finished") {
                            store.apply(.reopened, to: loop.id)
                        }
                        .buttonStyle(.bordered)
                    }
                } else if loop.state == .open {
                    HStack(spacing: 8) {
                        Button("I did it") {
                            store.apply(.reportedDone, to: loop.id)
                        }
                        .buttonStyle(.borderedProminent)
                        Button("Snooze") {
                            store.apply(.snoozed, to: loop.id)
                        }
                        .buttonStyle(.bordered)
                        Button("Skip") {
                            store.apply(.skipped, to: loop.id)
                        }
                        .buttonStyle(.bordered)
                    }
                    .controlSize(.small)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .accessibilityElement(children: .contain)
    }

    private var icon: String {
        if loop.state == .awaitingVerification { return "checkmark.seal" }
        return loop.kind == .thought ? "lightbulb" : "circle.dotted"
    }

    @ViewBuilder
    private var statusLine: some View {
        if loop.state == .awaitingVerification {
            Text("Self-reported done · still needs verification")
                .foregroundStyle(.orange)
                .font(.caption)
        } else if let date = loop.remindAt, loop.state == .open {
            Text("Next prompt: \(date.formatted(date: .abbreviated, time: .shortened))")
                .foregroundStyle(.secondary)
                .font(.caption)
        } else if loop.kind == .thought {
            Text("Saved thought")
                .foregroundStyle(.secondary)
                .font(.caption)
        } else if loop.state == .verified {
            Text("Verified complete")
                .foregroundStyle(.green)
                .font(.caption)
        } else {
            Text("Open · no reminder scheduled")
                .foregroundStyle(.secondary)
                .font(.caption)
        }
    }
}

private struct OpenLoopsView: View {
    @EnvironmentObject private var store: TaskStore
    @State private var editing: LifeLoop?
    @State private var pendingDeleteID: UUID?

    private var awaiting: [LifeLoop] {
        store.unresolved.filter { $0.state == .awaitingVerification }
    }
    private var tasks: [LifeLoop] {
        store.unresolved.filter { $0.state == .open && $0.kind == .task }
    }
    private var thoughts: [LifeLoop] {
        store.unresolved.filter { $0.kind == .thought }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    countHeader

                    if store.unresolved.isEmpty {
                        ContentUnavailableView(
                            "No open loops",
                            systemImage: "checkmark.circle",
                            description: Text("Everything has been resolved, or nothing has been captured yet.")
                        )
                    }
                    if !awaiting.isEmpty {
                        section("Needs verification", items: awaiting)
                    }
                    if !tasks.isEmpty {
                        section("Open tasks", items: tasks)
                    }
                    if !thoughts.isEmpty {
                        section("Captured thoughts", items: thoughts)
                    }

                    if store.completedCount > 0 {
                        Text("\(store.completedCount) verified and resolved")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .padding(.top, 10)
                    }
                }
                .padding(18)
            }
            .navigationTitle("Open Loops")
            .sheet(item: $editing) { loop in
                EditLoopView(loop: loop)
            }
            .confirmationDialog(
                "Delete this captured item?",
                isPresented: Binding(
                    get: { pendingDeleteID != nil },
                    set: { if !$0 { pendingDeleteID = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) {
                    if let id = pendingDeleteID { store.remove(id) }
                    pendingDeleteID = nil
                }
                Button("Cancel", role: .cancel) { pendingDeleteID = nil }
            } message: {
                Text("This will remove the item and its future reminder from this device.")
            }
        }
    }

    private var countHeader: some View {
        HStack {
            Text("\(store.unresolved.count) unresolved")
                .font(.subheadline.weight(.semibold))
            Spacer()
            Text("Saved on this device")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.bottom, 8)
    }

    private func section(_ heading: String, items: [LifeLoop]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(heading)
                .font(.title3.bold())
                .padding(.top, 8)
            ForEach(items) { loop in
                LoopCard(
                    loop: loop,
                    onEdit: { editing = loop },
                    onDelete: { pendingDeleteID = loop.id }
                )
            }
        }
    }
}

private struct EditLoopView: View {
    @EnvironmentObject private var store: TaskStore
    @Environment(\.dismiss) private var dismiss
    let loop: LifeLoop

    @State private var title: String
    @State private var details: String
    @State private var kind: CaptureKind
    @State private var wantsReminder: Bool
    @State private var reminder: Date

    init(loop: LifeLoop) {
        self.loop = loop
        _title = State(initialValue: loop.title)
        _details = State(initialValue: loop.details)
        _kind = State(initialValue: loop.kind)
        _wantsReminder = State(initialValue: loop.remindAt != nil)
        _reminder = State(initialValue: max(loop.remindAt ?? Date().addingTimeInterval(3600), Date().addingTimeInterval(60)))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Edit item") {
                    Picker("Type", selection: $kind) {
                        ForEach(CaptureKind.allCases) { item in
                            Text(item.title).tag(item)
                        }
                    }
                    .pickerStyle(.segmented)
                    TextField("Title", text: $title)
                    TextField("Details", text: $details, axis: .vertical)
                        .lineLimit(2...6)
                }
                if kind == .task && loop.state == .open {
                    Section("Reminder") {
                        Toggle("Remind me later", isOn: $wantsReminder)
                        if wantsReminder {
                            DatePicker("When", selection: $reminder, in: Date()..., displayedComponents: [.date, .hourAndMinute])
                        }
                    }
                }
                if loop.state == .awaitingVerification {
                    Section {
                        Text("This item was reported done. Verify it from Open Loops or choose Not finished to reopen it.")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Edit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let saved = store.update(
                            id: loop.id,
                            title: title,
                            details: details,
                            kind: kind,
                            remindAt: (kind == .task && wantsReminder ? reminder : nil)
                        )
                        if saved { dismiss() }
                    }
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}

private struct SettingsView: View {
    @EnvironmentObject private var store: TaskStore

    private var snoozeBinding: Binding<Int> {
        Binding(
            get: { store.preferences.snoozeMinutes },
            set: { value in
                var updated = store.preferences
                updated.snoozeMinutes = value
                store.setPreferences(updated)
            }
        )
    }

    private var skipBinding: Binding<Int> {
        Binding(
            get: { store.preferences.skipHours },
            set: { value in
                var updated = store.preferences
                updated.skipHours = value
                store.setPreferences(updated)
            }
        )
    }

    private var soundBinding: Binding<Bool> {
        Binding(
            get: { store.preferences.playSound },
            set: { value in
                var updated = store.preferences
                updated.playSound = value
                store.setPreferences(updated)
            }
        )
    }

    private var backendBinding: Binding<String> {
        Binding(
            get: { store.preferences.futureBackendURL },
            set: { value in
                var updated = store.preferences
                updated.futureBackendURL = value
                store.setPreferences(updated)
            }
        )
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("Mode", value: "Local demonstration")
                    Label("No cloud connection, microphone, or AI required", systemImage: "iphone")
                        .font(.subheadline)
                } header: {
                    Text("Operating mode")
                } footer: {
                    Text("Only local mode is implemented in version 0.1. No information is transmitted to a server.")
                }

                Section {
                    LabeledContent("Notifications", value: store.notificationPermission)
                    Button("Request notification permission") {
                        store.askForNotificationPermission()
                    }
                    Button("Open device notification settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    }
                    Button("Try a reminder in 25 seconds") {
                        store.scheduleSamplePrompt()
                    }
                } header: {
                    Text("Prompts")
                } footer: {
                    Text("The sample reminder contains I did it, Snooze, and Skip actions. Delivery when the app is closed must be tested on your device.")
                }

                Section("Prompt preferences") {
                    Picker("Snooze interval", selection: snoozeBinding) {
                        Text("5 minutes").tag(5)
                        Text("10 minutes").tag(10)
                        Text("15 minutes").tag(15)
                        Text("30 minutes").tag(30)
                    }
                    Picker("Skip for", selection: skipBinding) {
                        Text("6 hours").tag(6)
                        Text("12 hours").tag(12)
                        Text("24 hours").tag(24)
                    }
                    Toggle("Play notification sound", isOn: soundBinding)
                }

                Section {
                    TextField("https://your-server.example", text: backendBinding)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                        .textContentType(.URL)
                    LabeledContent("Connection", value: "Not connected")
                } header: {
                    Text("Future backend (inactive)")
                } footer: {
                    Text("This address is stored on-device only. V0.1 never contacts it; don't enter passwords or API tokens.")
                }

                Section {
                    LabeledContent("App version", value: "0.1.1")
                    LabeledContent("Open loops", value: "\(store.unresolved.count)")
                    LabeledContent("Verified complete", value: "\(store.completedCount)")
                }
            }
            .navigationTitle("Settings")
            .task { await store.refreshPermission() }
        }
    }
}
