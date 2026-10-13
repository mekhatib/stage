import SwiftUI
import WebKit

@main
struct StageApp: App {
    @State private var studio = Studio()

    var body: some Scene {
        Window("Stage", id: "stage") {
            ContentView()
                .environment(studio)
                .frame(minWidth: 960, minHeight: 640)
        }
        .defaultSize(width: 1440, height: 920)
        .windowToolbarStyle(.unified(showsTitle: false))
        .commands { StageCommands(studio: studio) }
    }
}

// MARK: - Layout

struct ContentView: View {
    @Environment(Studio.self) private var studio

    var body: some View {
        @Bindable var studio = studio
        NavigationSplitView {
            Sidebar()
                .navigationSplitViewColumnWidth(min: 220, ideal: 250, max: 320)
        } detail: {
            Detail()
        }
        .toolbar { StageToolbar() }
        .toolbar(removing: .title)
        .sheet(isPresented: $studio.isAddingSession) {
            SessionEditor(session: studio.newSession())
        }
        .sheet(item: $studio.editing) { session in
            SessionEditor(session: session)
        }
        .sheet(isPresented: $studio.isAddingDemo) {
            DemoEditor(demo: Demo(name: "", orgSlug: ""))
        }
        .sheet(item: $studio.editingDemo) { demo in
            DemoEditor(demo: demo)
        }
    }
}

// MARK: - Sidebar

struct Sidebar: View {
    @Environment(Studio.self) private var studio

    var body: some View {
        @Bindable var studio = studio
        List(selection: $studio.selection) {
            Section {
                ForEach(studio.visibleSessions) { SessionRow(session: $0).tag($0.id) }
            } header: {
                Text("People")
            }
        }
        .listStyle(.sidebar)
        .overlay {
            if studio.visibleSessions.isEmpty {
                ContentUnavailableView {
                    Label("No people yet", systemImage: "person.badge.plus")
                } description: {
                    Text("Add the personas for this demo.")
                }
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Stage")
                    .font(.custom("Georgia-Italic", size: 22))
                    .padding(.horizontal, 6)
                DemoPicker()
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 4)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            Button {
                studio.isAddingSession = true
            } label: {
                Label("Add person", systemImage: "plus")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glass)
            .controlSize(.large)
            .disabled(studio.currentDemo == nil)
            .padding(14)
        }
    }
}

/// Glass card at the top of the sidebar that switches between demo projects.
struct DemoPicker: View {
    @Environment(Studio.self) private var studio
    @State private var confirmingDelete: Demo?

    var body: some View {
        @Bindable var studio = studio
        Menu {
            Picker("Demo", selection: $studio.currentDemoID) {
                ForEach(studio.demos) { demo in
                    Label(demo.name, systemImage: demo.symbol).tag(Optional(demo.id))
                }
            }
            .pickerStyle(.inline)
            Divider()
            Button("New Demo…", systemImage: "plus") { studio.isAddingDemo = true }
            if let demo = studio.currentDemo {
                Button("Edit “\(demo.name)”…", systemImage: "pencil") { studio.editingDemo = demo }
                if studio.demos.count > 1 {
                    Button("Power Off Other Demos", systemImage: "power") { studio.powerOffOtherDemos() }
                    Button("Delete “\(demo.name)”…", systemImage: "trash", role: .destructive) { confirmingDelete = demo }
                }
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: studio.currentDemo?.symbol ?? "sparkles")
                    .font(.system(size: 14, weight: .semibold))
                    .frame(width: 30, height: 30)
                    .background(.quaternary, in: .rect(cornerRadius: 8))
                VStack(alignment: .leading, spacing: 1) {
                    Text(studio.currentDemo?.name ?? "No demo")
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                    Text(summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(8)
            .contentShape(.rect)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 12))
        .confirmationDialog("Delete “\(confirmingDelete?.name ?? "")”?", isPresented: Binding(
            get: { confirmingDelete != nil }, set: { if !$0 { confirmingDelete = nil } }
        ), presenting: confirmingDelete) { demo in
            Button("Delete Demo and Its People", role: .destructive) { studio.remove(demo: demo) }
        } message: { demo in
            Text("\(studio.people(in: demo).count) people and their sign-ins will be removed.")
        }
    }

    private var summary: String {
        guard let demo = studio.currentDemo else { return "Create a demo to start" }
        let people = studio.people(in: demo).count
        let running = studio.runningCount(in: demo)
        return "\(people) \(people == 1 ? "person" : "people")" + (running > 0 ? " · \(running) running" : "")
    }
}

struct SessionRow: View {
    @Environment(Studio.self) private var studio
    let session: DemoSession

    var body: some View {
        let runtime = studio.runtime(for: session)
        HStack(spacing: 11) {
            Avatar(session: session, size: 30, dimmed: runtime == nil)
                .overlay(alignment: .bottomTrailing) {
                    if let runtime {
                        Circle()
                            .fill(runtime.isSignedIn ? Color.green : Color.orange)
                            .frame(width: 9, height: 9)
                            .overlay(Circle().strokeBorder(.background, lineWidth: 1.5))
                            .offset(x: 1, y: 1)
                    }
                }
            VStack(alignment: .leading, spacing: 1) {
                Text(session.name)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(runtime == nil ? .secondary : .primary)
                    .lineLimit(1)
                Text(runtime.map { $0.isSignedIn ? session.role : "Signing in…" } ?? session.role)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            if let runtime {
                TimelineView(.periodic(from: .now, by: 30)) { context in
                    Text(uptimeText(since: runtime.startedAt, now: context.date))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.vertical, 3)
        .help("\(session.name) · \(session.role)\(session.email.isEmpty ? "" : " · \(session.email)")")
        .contextMenu {
            if runtime == nil {
                Button("Power On", systemImage: "power") { studio.powerOn(session.id) }
            } else {
                Button("Reload", systemImage: "arrow.clockwise") { runtime?.reload() }
                Button("Refresh Data (May Ask to Sign In)", systemImage: "arrow.triangle.2.circlepath") { studio.refreshData(session.id) }
                Button("Power Off", systemImage: "power") { studio.powerOff(session.id) }
            }
            Divider()
            Button("Edit…", systemImage: "pencil") { studio.editing = session }
            if studio.demos.count > 1 {
                Menu("Move to Demo") {
                    ForEach(studio.demos.filter { $0.id != session.demoID }) { demo in
                        Button(demo.name, systemImage: demo.symbol) { studio.move(session.id, to: demo.id) }
                    }
                }
            }
            Button("Sign Out and Reset", systemImage: "arrow.counterclockwise") { studio.resetSignIn(session.id) }
            Divider()
            Button("Remove Session", systemImage: "trash", role: .destructive) { studio.remove(session.id) }
        }
    }
}

struct Avatar: View {
    let session: DemoSession
    var size: CGFloat = 30
    var dimmed = false

    var body: some View {
        Text(session.initials.isEmpty ? "?" : session.initials)
            .font(.system(size: size * 0.38, weight: .semibold, design: .rounded))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background {
                Circle().fill(
                    LinearGradient(colors: [session.color.opacity(0.85), session.color], startPoint: .top, endPoint: .bottom)
                )
            }
            .saturation(dimmed ? 0 : 1)
            .opacity(dimmed ? 0.55 : 1)
    }
}

// MARK: - Detail

struct Detail: View {
    @Environment(Studio.self) private var studio

    var body: some View {
        if let session = studio.selected {
            if let runtime = studio.runtime(for: session) {
                WebContainer(webView: runtime.webView)
                    .overlay(alignment: .top) {
                        if runtime.isLoading {
                            ProgressView(value: runtime.progress)
                                .progressViewStyle(.linear)
                                .tint(session.color)
                                .frame(height: 2)
                                .transition(.opacity)
                        }
                    }
                    .animation(.easeOut(duration: 0.25), value: runtime.isLoading)
                    .overlay(alignment: .top) {
                        if let actual = runtime.unexpectedOrg, let expected = session.orgSlug {
                            OrgMismatchBanner(session: session, runtime: runtime, expected: expected, actual: actual)
                                .padding(.top, 14)
                                .transition(.move(edge: .top).combined(with: .opacity))
                        }
                    }
                    .animation(.snappy, value: runtime.unexpectedOrg)
            } else {
                PoweredOff(session: session)
            }
        } else if studio.demos.isEmpty {
            Welcome()
        } else {
            ContentUnavailableView {
                Label(studio.currentDemo?.name ?? "No demo", systemImage: studio.currentDemo?.symbol ?? "sparkles")
            } description: {
                Text("Add the people in this demo. Each one gets their own Computer and sign-in.")
            } actions: {
                Button("Add person") { studio.isAddingSession = true }
                    .buttonStyle(.glassProminent)
                    .disabled(studio.currentDemo == nil)
            }
        }
    }
}

/// First launch: explains Stage and starts the first demo.
struct Welcome: View {
    @Environment(Studio.self) private var studio

    var body: some View {
        VStack(spacing: 22) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 96, height: 96)
            VStack(spacing: 8) {
                Text("Welcome to Stage").font(.system(size: 30, weight: .semibold))
                Text("Run DevRev Computer as several demo personas at once, each with its own sign-in.\nStart by creating a demo, then add the people in it.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            Button {
                studio.isAddingDemo = true
            } label: {
                Label("Create your first demo", systemImage: "plus")
                    .padding(.horizontal, 10)
            }
            .buttonStyle(.glassProminent)
            .controlSize(.extraLarge)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Shown when DevRev signs someone into a different organization than the one they're set up for,
/// which is what happens when they aren't a member of the configured organization.
struct OrgMismatchBanner: View {
    @Environment(Studio.self) private var studio
    let session: DemoSession
    let runtime: SessionRuntime
    let expected: String
    let actual: String

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.title3)
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(session.firstName) isn't in “\(expected)”")
                    .font(.system(size: 13, weight: .semibold))
                Text("DevRev signed them into “\(actual)” instead. Invite \(session.email.isEmpty ? "them" : session.email) to \(expected), or use \(actual).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Button("Use \(actual)") {
                var updated = session
                updated.orgSlug = actual
                studio.save(updated)
            }
            .buttonStyle(.glassProminent)
            Button("Retry \(expected)") { runtime.goHome() }
                .buttonStyle(.glass)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: 720)
        .glassEffect(.regular, in: .rect(cornerRadius: 18))
    }
}

/// Hosts the selected session's web view; switching sessions swaps the view without reloading it.
struct WebContainer: NSViewRepresentable {
    let webView: WKWebView

    func makeNSView(context: Context) -> NSView {
        let container = NSView()
        attach(to: container)
        return container
    }

    func updateNSView(_ container: NSView, context: Context) {
        if webView.superview !== container { attach(to: container) }
    }

    private func attach(to container: NSView) {
        container.subviews.forEach { $0.removeFromSuperview() }
        webView.removeFromSuperview()
        webView.frame = container.bounds
        webView.autoresizingMask = [.width, .height]
        container.addSubview(webView)
    }
}

struct PoweredOff: View {
    @Environment(Studio.self) private var studio
    let session: DemoSession

    var body: some View {
        VStack(spacing: 22) {
            Avatar(session: session, size: 88)
                .shadow(color: session.color.opacity(0.4), radius: 30, y: 10)
            VStack(spacing: 6) {
                Text(session.name).font(.system(size: 30, weight: .semibold))
                Text([session.role, session.note].filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.title3)
                    .foregroundStyle(.secondary)
                if !session.email.isEmpty {
                    Text(session.email)
                        .font(.callout.monospaced())
                        .foregroundStyle(.tertiary)
                        .textSelection(.enabled)
                }
            }
            Button {
                studio.powerOn(session.id)
            } label: {
                Label("Open Computer", systemImage: "power")
                    .padding(.horizontal, 10)
            }
            .buttonStyle(.glassProminent)
            .tint(session.color)
            .controlSize(.extraLarge)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            RadialGradient(colors: [session.color.opacity(0.16), .clear], center: .center, startRadius: 0, endRadius: 560)
                .ignoresSafeArea()
        }
    }
}

// MARK: - Toolbar

struct StageToolbar: ToolbarContent {
    @Environment(Studio.self) private var studio

    var body: some ToolbarContent {
        let runtime = studio.selectedRuntime

        ToolbarItemGroup(placement: .navigation) {
            Button { runtime?.goBack() } label: { Label("Back", systemImage: "chevron.left") }
                .disabled(runtime?.canGoBack != true)
            Button { runtime?.goForward() } label: { Label("Forward", systemImage: "chevron.right") }
                .disabled(runtime?.canGoForward != true)
        }

        ToolbarItem(placement: .principal) {
            PersonaSwitcher()
        }

        ToolbarItemGroup(placement: .primaryAction) {
            Button { runtime?.goHome() } label: { Label("Computer", systemImage: "bubble.left.and.text.bubble.right") }
                .help("Back to the Computer chat")
                .disabled(runtime == nil)
            Button { runtime?.reload() } label: { Label("Reload", systemImage: "arrow.clockwise") }
                .disabled(runtime == nil)
            if let session = studio.selected {
                if runtime == nil {
                    Button { studio.powerOn(session.id) } label: { Label("Power On", systemImage: "power") }
                } else {
                    Button { studio.powerOff(session.id) } label: { Label("Power Off", systemImage: "power") }
                        .help("Power off \(session.firstName)")
                }
            }
        }
    }
}

/// A glass capsule of avatars for the running sessions; the selected one expands to show its name.
struct PersonaSwitcher: View {
    @Environment(Studio.self) private var studio
    @Namespace private var glass

    var body: some View {
        GlassEffectContainer(spacing: 8) {
            HStack(spacing: 6) {
                ForEach(studio.running) { session in
                    let isSelected = session.id == studio.selection
                    Button {
                        withAnimation(.snappy(duration: 0.28)) { studio.selection = session.id }
                    } label: {
                        HStack(spacing: 7) {
                            Avatar(session: session, size: 22)
                            if isSelected {
                                Text(session.firstName)
                                    .font(.system(size: 13, weight: .semibold))
                                    .transition(.opacity.combined(with: .move(edge: .leading)))
                            }
                        }
                        .padding(.leading, 4)
                        .padding(.trailing, isSelected ? 12 : 4)
                        .padding(.vertical, 4)
                        .contentShape(.capsule)
                    }
                    .buttonStyle(.plain)
                    .glassEffect(isSelected ? .regular.tint(session.color.opacity(0.3)).interactive() : .regular.interactive(), in: .capsule)
                    .glassEffectID(session.id, in: glass)
                    .help("\(session.name) · \(session.role)")
                }
            }
        }
    }
}

// MARK: - Session editor

struct SessionEditor: View {
    @Environment(Studio.self) private var studio
    @Environment(\.dismiss) private var dismiss
    @State var session: DemoSession

    private var isNew: Bool { !studio.sessions.contains { $0.id == session.id } }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 14) {
                Avatar(session: session, size: 46)
                VStack(alignment: .leading, spacing: 2) {
                    Text(isNew ? "Add person" : "Edit person").font(.title2.weight(.semibold))
                    Text(studio.demos.first { $0.id == session.demoID }.map { "In \($0.name) · own sign-in, own Computer" } ?? "Own sign-in, own Computer")
                        .font(.callout).foregroundStyle(.secondary)
                }
            }
            Form {
                TextField("Name", text: $session.name, prompt: Text("Maya Chen"))
                TextField("Role", text: $session.role, prompt: Text("Support lead"))
                TextField("Sign-in email", text: $session.email, prompt: Text("you+persona@devrev.ai"))
                TextField("Organization", text: Binding(
                    get: { session.orgSlug ?? "" },
                    set: { session.orgSlug = $0.trimmingCharacters(in: .whitespaces).lowercased().nilIfEmpty }
                ), prompt: Text(studio.demos.first { $0.id == session.demoID }?.orgSlug ?? DemoSession.defaultOrg))
                .help("The DevRev org this person signs into. They must be a member of it.")
                TextField("Note", text: $session.note, prompt: Text("Has MFA"))
                LabeledContent("Color") {
                    HStack(spacing: 10) {
                        ForEach(DemoSession.palette, id: \.self) { hex in
                            Button { session.colorHex = hex } label: {
                                Circle()
                                    .fill(Color(hex: hex))
                                    .frame(width: 20, height: 20)
                                    .padding(3)
                                    .overlay(Circle().strokeBorder(Color.primary.opacity(session.colorHex == hex ? 0.5 : 0), lineWidth: 2))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .scrollDisabled(true)

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .buttonStyle(.glass)
                    .keyboardShortcut(.cancelAction)
                Button(isNew ? "Add person" : "Save") {
                    studio.save(session)
                    dismiss()
                }
                .buttonStyle(.glassProminent)
                .tint(session.color)
                .keyboardShortcut(.defaultAction)
                .disabled(session.name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 460)
    }
}

// MARK: - Demo editor

struct DemoEditor: View {
    @Environment(Studio.self) private var studio
    @Environment(\.dismiss) private var dismiss
    @State var demo: Demo

    private var isNew: Bool { !studio.demos.contains { $0.id == demo.id } }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 14) {
                Image(systemName: demo.symbol)
                    .font(.system(size: 20, weight: .semibold))
                    .frame(width: 46, height: 46)
                    .glassEffect(.regular, in: .rect(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 2) {
                    Text(isNew ? "New demo" : "Edit demo").font(.title2.weight(.semibold))
                    Text("A project with its own set of people.").font(.callout).foregroundStyle(.secondary)
                }
            }
            Form {
                TextField("Name", text: $demo.name, prompt: Text("Acme support escalation"))
                Section {
                    TextField("Organization", text: $demo.orgSlug, prompt: Text("acme"))
                } footer: {
                    Text("The part after app.devrev.ai/ in the org's URL. People in this demo must be members of it.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                LabeledContent("Icon") {
                    LazyVGrid(columns: Array(repeating: GridItem(.fixed(30), spacing: 6), count: 6), spacing: 6) {
                        ForEach(Demo.symbols, id: \.self) { symbol in
                            Button { demo.symbol = symbol } label: {
                                Image(systemName: symbol)
                                    .frame(width: 30, height: 30)
                                    .background(demo.symbol == symbol ? AnyShapeStyle(.tint.opacity(0.25)) : AnyShapeStyle(.clear),
                                                in: .rect(cornerRadius: 7))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .scrollDisabled(true)

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .buttonStyle(.glass)
                    .keyboardShortcut(.cancelAction)
                Button(isNew ? "Create demo" : "Save") {
                    demo.name = demo.name.trimmingCharacters(in: .whitespaces)
                    demo.orgSlug = demo.orgSlug.trimmingCharacters(in: .whitespaces).lowercased().nilIfEmpty ?? DemoSession.defaultOrg
                    studio.save(demo)
                    dismiss()
                }
                .buttonStyle(.glassProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(demo.name.trimmingCharacters(in: .whitespaces).isEmpty || demo.orgSlug.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 460)
    }
}

// MARK: - Commands

struct StageCommands: Commands {
    let studio: Studio

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("Add Person…") { studio.isAddingSession = true }
                .keyboardShortcut("n")
            Button("New Demo…") { studio.isAddingDemo = true }
                .keyboardShortcut("n", modifiers: [.command, .shift])
        }
        CommandMenu("Demo") {
            ForEach(Array(studio.demos.prefix(9).enumerated()), id: \.element.id) { index, demo in
                Button(demo.name) { studio.currentDemoID = demo.id }
                    .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: [.command, .option])
            }
            Divider()
            Button("New Demo…") { studio.isAddingDemo = true }
            Button("Power Off Other Demos") { studio.powerOffOtherDemos() }
                .disabled(studio.demos.count < 2)
        }
        CommandMenu("Session") {
            Button("Computer Chat") { studio.selectedRuntime?.goHome() }
                .keyboardShortcut("h", modifiers: [.command, .shift])
            Button("Reload") { studio.selectedRuntime?.reload() }
                .keyboardShortcut("r")
            Button("Refresh Data (May Ask to Sign In)") { if let id = studio.selection { studio.refreshData(id) } }
                .keyboardShortcut("r", modifiers: [.command, .shift])
            Button("Back") { studio.selectedRuntime?.goBack() }
                .keyboardShortcut("[")
            Button("Forward") { studio.selectedRuntime?.goForward() }
                .keyboardShortcut("]")
            Divider()
            Button("Power Off") { if let id = studio.selection { studio.powerOff(id) } }
                .keyboardShortcut("w", modifiers: [.command, .shift])
            Button("Power Off All Sessions") { studio.powerOffAll() }
            Divider()
            ForEach(Array(studio.visibleSessions.prefix(9).enumerated()), id: \.element.id) { index, person in
                Button(person.name) { studio.select(index: index) }
                    .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")))
            }
        }
    }
}
