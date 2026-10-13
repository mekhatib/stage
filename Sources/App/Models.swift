import SwiftUI
import WebKit

/// A demo project: a named group of people, each with their own Computer session.
struct Demo: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String
    var symbol = "sparkles"
    /// Organization new people in this demo sign into.
    var orgSlug = DemoSession.defaultOrg
    /// Person shown when switching back to this demo.
    var lastSessionID: UUID?

    static let symbols = [
        "sparkles", "person.3", "briefcase", "building.2", "headphones", "cart",
        "cross.case", "graduationcap", "banknote", "shippingbox", "wrench.and.screwdriver", "globe",
    ]
}

struct DemoSession: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String
    var role: String
    var email: String
    var note: String = ""
    var colorHex: UInt32
    /// Identifies this session's own WebKit cookie and storage container, so logins never mix.
    var storeID = UUID()
    /// DevRev organization the persona signed into, learned from the URL after sign-in.
    var orgSlug: String?
    var demoID: UUID?

    var color: Color { Color(hex: colorHex) }
    var firstName: String { String(name.split(separator: " ").first ?? Substring(name)) }
    var initials: String {
        name.split(separator: " ").compactMap(\.first).prefix(2).map(String.init).joined().uppercased()
    }

    static let palette: [UInt32] = [0xD9553F, 0x3F8F5E, 0x4F6FD1, 0x9A5FD1, 0xD1983F, 0x3FA3B5]

    static let defaultOrg = "devrev"
}

extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

extension Color {
    init(hex: UInt32) {
        self.init(.sRGB, red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255)
    }
}

/// Page paths per session (never query strings, which can hold sign-in codes).
enum StageLog {
    static let file = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Stage/stage.log")

    static func write(_ message: String) {
        let line = "\(Date.now.formatted(date: .omitted, time: .standard)) \(message)\n"
        if let handle = try? FileHandle(forWritingTo: file) {
            handle.seekToEndOfFile()
            handle.write(Data(line.utf8))
            try? handle.close()
        } else {
            try? Data(line.utf8).write(to: file)
        }
    }
}

func uptimeText(since start: Date, now: Date = .now) -> String {
    let minutes = max(0, Int(now.timeIntervalSince(start) / 60))
    return minutes >= 60 ? "\(minutes / 60)h \(minutes % 60)m" : "\(minutes)m"
}

/// All demos and their people, which sessions are running, and which one is on screen.
@MainActor
@Observable
final class Studio {
    var demos: [Demo] = []
    var sessions: [DemoSession] = []
    private(set) var runtimes: [UUID: SessionRuntime] = [:]

    var currentDemoID: UUID? {
        didSet {
            guard currentDemoID != oldValue else { return }
            UserDefaults.standard.set(currentDemoID?.uuidString, forKey: "currentDemo")
            let people = visibleSessions
            selection = currentDemo?.lastSessionID.flatMap { id in people.first { $0.id == id }?.id } ?? people.first?.id
        }
    }

    var selection: UUID? {
        didSet {
            UserDefaults.standard.set(selection?.uuidString, forKey: "selection")
            if let selection, let index = demos.firstIndex(where: { $0.id == currentDemoID }), demos[index].lastSessionID != selection {
                demos[index].lastSessionID = selection
                saveDemos()
            }
            if let selection, runtimes[selection] == nil, sessions.contains(where: { $0.id == selection }) {
                powerOn(selection)
            }
        }
    }

    var editing: DemoSession?
    var isAddingSession = false
    var editingDemo: Demo?
    var isAddingDemo = false

    private static let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Stage")
    private let sessionsFile = folder.appendingPathComponent("sessions.json")
    private let demosFile = folder.appendingPathComponent("demos.json")

    init() {
        if let data = try? Data(contentsOf: sessionsFile), let saved = try? JSONDecoder().decode([DemoSession].self, from: data) {
            sessions = saved
        }
        if let data = try? Data(contentsOf: demosFile), let saved = try? JSONDecoder().decode([Demo].self, from: data) {
            demos = saved
        }
        // People from before demos existed join a demo named after their organization.
        if demos.isEmpty, let first = sessions.first {
            demos = [Demo(name: "My demo", symbol: "person.3", orgSlug: first.orgSlug ?? DemoSession.defaultOrg)]
        }
        for index in sessions.indices where !demos.isEmpty {
            if sessions[index].demoID == nil || !demos.contains(where: { $0.id == sessions[index].demoID }) {
                sessions[index].demoID = demos[0].id
            }
            if sessions[index].orgSlug == nil {
                sessions[index].orgSlug = demos.first { $0.id == sessions[index].demoID }?.orgSlug
            }
        }
        save()
        saveDemos()

        let wasRunning = Set(UserDefaults.standard.stringArray(forKey: "running") ?? [])
        for session in sessions where wasRunning.contains(session.id.uuidString) {
            runtimes[session.id] = makeRuntime(session)
        }
        let savedDemo = UserDefaults.standard.string(forKey: "currentDemo").flatMap(UUID.init)
        currentDemoID = demos.first { $0.id == savedDemo }?.id ?? demos.first?.id
        let savedSelection = UserDefaults.standard.string(forKey: "selection").flatMap(UUID.init)
        selection = visibleSessions.first { $0.id == savedSelection }?.id ?? visibleSessions.first?.id
        if let selection { powerOn(selection) }
    }

    // MARK: Queries

    var currentDemo: Demo? { demos.first { $0.id == currentDemoID } }
    var visibleSessions: [DemoSession] { sessions.filter { $0.demoID == currentDemoID } }
    var selected: DemoSession? { visibleSessions.first { $0.id == selection } }
    var selectedRuntime: SessionRuntime? { selected.flatMap { runtimes[$0.id] } }
    var running: [DemoSession] { visibleSessions.filter { runtimes[$0.id] != nil } }

    func runtime(for session: DemoSession) -> SessionRuntime? { runtimes[session.id] }
    func people(in demo: Demo) -> [DemoSession] { sessions.filter { $0.demoID == demo.id } }
    func runningCount(in demo: Demo) -> Int { people(in: demo).filter { runtimes[$0.id] != nil }.count }

    func newSession() -> DemoSession {
        let demo = currentDemo
        return DemoSession(name: "", role: "", email: "",
                           colorHex: DemoSession.palette[visibleSessions.count % DemoSession.palette.count],
                           orgSlug: demo?.orgSlug ?? DemoSession.defaultOrg, demoID: demo?.id)
    }

    // MARK: Sessions

    func powerOn(_ id: UUID) {
        guard runtimes[id] == nil, let session = sessions.first(where: { $0.id == id }) else { return }
        runtimes[id] = makeRuntime(session)
        rememberRunning()
    }

    private func makeRuntime(_ session: DemoSession) -> SessionRuntime {
        let runtime = SessionRuntime(session: session)
        runtime.onOrgDetected = { [weak self] slug in
            guard let self, let index = self.sessions.firstIndex(where: { $0.id == session.id }),
                  self.sessions[index].orgSlug != slug else { return }
            self.sessions[index].orgSlug = slug
            self.save()
        }
        return runtime
    }

    func powerOff(_ id: UUID) {
        runtimes[id]?.shutDown()
        runtimes[id] = nil
        rememberRunning()
    }

    func powerOffAll() {
        for id in Array(runtimes.keys) { powerOff(id) }
    }

    /// Frees memory used by demos that aren't on screen; their logins are kept.
    func powerOffOtherDemos() {
        for session in sessions where session.demoID != currentDemoID { powerOff(session.id) }
    }

    func select(index: Int) {
        let people = visibleSessions
        guard people.indices.contains(index) else { return }
        selection = people[index].id
    }

    func save(_ session: DemoSession) {
        if let index = sessions.firstIndex(where: { $0.id == session.id }) {
            let orgChanged = sessions[index].orgSlug != session.orgSlug
            sessions[index] = session
            if orgChanged, runtimes[session.id] != nil {
                powerOff(session.id)
                powerOn(session.id)
            }
        } else {
            sessions.append(session)
            selection = session.id
        }
        save()
    }

    func move(_ id: UUID, to demoID: UUID) {
        guard let index = sessions.firstIndex(where: { $0.id == id }) else { return }
        sessions[index].demoID = demoID
        save()
        if selection == id { selection = visibleSessions.first?.id }
    }

    func remove(_ id: UUID) {
        guard let session = sessions.first(where: { $0.id == id }) else { return }
        powerOff(id)
        sessions.removeAll { $0.id == id }
        save()
        WKWebsiteDataStore.remove(forIdentifier: session.storeID) { _ in }
        if selection == id { selection = visibleSessions.first?.id }
    }

    /// Clears DevRev's cached copy of chats and other data (local database, offline worker, caches).
    /// Cookies and local storage stay, but DevRev may still ask for a new sign-in code.
    func refreshData(_ id: UUID) {
        guard let session = sessions.first(where: { $0.id == id }) else { return }
        StageLog.write("\(session.firstName): refreshing cached data")
        WKWebsiteDataStore(forIdentifier: session.storeID).removeData(ofTypes: SessionRuntime.refreshDataTypes, modifiedSince: .distantPast) { [weak self] in
            Task { @MainActor in self?.runtimes[id]?.goHome() }
        }
    }

    /// Signs the session out by deleting its WebKit storage, then opens it fresh.
    func resetSignIn(_ id: UUID) {
        guard let session = sessions.first(where: { $0.id == id }) else { return }
        powerOff(id)
        WKWebsiteDataStore.remove(forIdentifier: session.storeID) { [weak self] _ in
            Task { @MainActor in self?.powerOn(id) }
        }
    }

    // MARK: Demos

    func save(_ demo: Demo) {
        if let index = demos.firstIndex(where: { $0.id == demo.id }) {
            let oldOrg = demos[index].orgSlug
            demos[index] = demo
            if oldOrg != demo.orgSlug {
                for person in people(in: demo) where person.orgSlug == oldOrg {
                    var updated = person
                    updated.orgSlug = demo.orgSlug
                    save(updated)
                }
            }
        } else {
            demos.append(demo)
            currentDemoID = demo.id
        }
        saveDemos()
    }

    /// Deletes a demo together with its people and their sign-ins. The last demo can't be deleted.
    func remove(demo: Demo) {
        guard demos.count > 1 else { return }
        for person in people(in: demo) { remove(person.id) }
        demos.removeAll { $0.id == demo.id }
        saveDemos()
        if currentDemoID == demo.id { currentDemoID = demos.first?.id }
    }

    // MARK: Persistence

    private func save() {
        try? FileManager.default.createDirectory(at: Self.folder, withIntermediateDirectories: true)
        try? JSONEncoder().encode(sessions).write(to: sessionsFile, options: .atomic)
    }

    private func saveDemos() {
        try? FileManager.default.createDirectory(at: Self.folder, withIntermediateDirectories: true)
        try? JSONEncoder().encode(demos).write(to: demosFile, options: .atomic)
    }

    private func rememberRunning() {
        UserDefaults.standard.set(runtimes.keys.map(\.uuidString), forKey: "running")
    }
}
