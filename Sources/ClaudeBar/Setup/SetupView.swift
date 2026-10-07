import AppKit
import ClaudeBarCore
import SwiftUI

/// Where the setup window's buttons are (window points from the top-left), so a click test hits exactly them.
@MainActor
enum SetupTargets {
    static var frames: [String: CGRect] = [:]
}

/// The setup window's four steps: Welcome, Find Cat Office, Connect, Done.
struct SetupView: View {
    @ObservedObject var model: SetupModel
    @EnvironmentObject var state: AppState
    static let size = CGSize(width: 460, height: 420)
    static let restartWarning = "This stops Cat Office's dev server and ends any Claude sessions running inside Cat Office."
    static let runningPatchWarning = "Cat Office is running: patching restarts it, which ends any Claude sessions running inside Cat Office."

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if model.step != .welcome {
                progress.padding(.bottom, 14)
            }
            Group {
                switch model.step {
                case .welcome: welcome
                case .find: find
                case .connect: connect
                case .done: done
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            if model.step == .find || model.step == .connect {
                footer.padding(.top, 10)
            }
        }
        .padding(20)
        .frame(width: Self.size.width, height: Self.size.height)
    }

    // MARK: - Progress and footer

    private var progress: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                ForEach(SetupModel.Step.allCases, id: \.self) { s in
                    Capsule().fill(s.rawValue <= model.step.rawValue ? Color.accentColor : Color.primary.opacity(0.12))
                        .frame(height: 4)
                }
            }
            Text("Step \(model.step.rawValue + 1) of \(SetupModel.Step.allCases.count) · \(title(model.step))")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func title(_ step: SetupModel.Step) -> String {
        switch step {
        case .welcome: "Welcome"
        case .find: "Find Cat Office"
        case .connect: "Connect"
        case .done: "Done"
        }
    }

    private var footer: some View {
        HStack {
            Button("Skip for now") { model.skip() }
                .buttonStyle(.link)
                .disabled(model.working)
                .setupTarget("setup-skip")
            Spacer()
            Button("Back") { back() }
                .disabled(model.working)
                .setupTarget("setup-back")
            Button {
                next()
            } label: {
                HStack(spacing: 6) {
                    if model.working { ProgressView().controlSize(.small) }
                    Text("Continue")
                }
            }
            .keyboardShortcut(.defaultAction)
            .disabled(!canContinue)
            .setupTarget("setup-continue")
        }
    }

    private var canContinue: Bool {
        switch model.step {
        case .find: !model.searching && model.chosen != nil
        case .connect: !model.working
        default: false
        }
    }

    private func back() {
        switch model.step {
        case .find: model.step = .welcome
        case .connect: model.step = .find
        default: break
        }
    }

    private func next() {
        switch model.step {
        case .find: model.step = .connect
        case .connect: Task { await model.connect() }
        default: break
        }
    }

    // MARK: - Welcome

    private var welcome: some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: "cat.fill")
                .font(.system(size: 64, weight: .regular))
                .foregroundStyle(Color.accentColor)
            Text("Welcome to ClaudeBar").font(.title2.weight(.semibold))
            Text("ClaudeBar shows your Claude usage, your projects and your Cat Office in the menu bar.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 340)
            Text("Setup takes about a minute. Nothing on your Mac changes until you click Continue.")
                .font(.caption).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 340)
            Spacer()
            Button {
                Task { await model.find() }
            } label: {
                Text("Set up").frame(minWidth: 120)
            }
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
            .setupTarget("setup-setup")
            Button("Skip for now") { model.skip() }
                .buttonStyle(.link)
                .setupTarget("setup-skip-welcome")
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Find

    private var find: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Find Cat Office").font(.title3.weight(.semibold))
            if model.searching {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Looking for Cat Office…")
                }
                Text("macOS may ask to let ClaudeBar look in your Documents, Desktop or Downloads folders — that's for finding Cat Office.")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else if model.candidates.isEmpty {
                Text("ClaudeBar couldn't find Cat Office.")
                Text("If you have it, choose its folder (the one with package.json and server/agent-bridge).")
                    .font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 10) {
                    Button("Choose folder…") { chooseFolder() }
                    Button("I don't use Cat Office") { model.useNoCatOffice() }
                }
            } else if model.candidates.count == 1, let only = model.candidates.first {
                found(only)
                Button("Not this one? Choose folder…") { chooseFolder() }
                    .buttonStyle(.link).font(.callout)
            } else {
                Text("ClaudeBar found \(model.candidates.count) copies of Cat Office. Pick the one you use:")
                    .fixedSize(horizontal: false, vertical: true)
                ScrollView {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(model.candidates, id: \.path) { candidate in radioRow(candidate) }
                    }
                }
                .frame(maxHeight: 180)
                Button("Choose another folder…") { chooseFolder() }
                    .buttonStyle(.link).font(.callout)
            }
            if let error = model.choiceError {
                Label(error + " Choose again.", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(Theme.waiting).font(.callout)
            }
        }
    }

    private func found(_ candidate: CatOfficeCandidate) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("Found your Cat Office", systemImage: "checkmark.circle.fill")
                .font(.headline).foregroundStyle(Theme.working)
            HStack(spacing: 6) {
                Text(name(candidate.path)).font(.callout.weight(.medium))
                if candidate.running { runningBadge }
            }
            Text(abbreviated(candidate.path)).font(.caption).foregroundStyle(.secondary)
                .lineLimit(1).truncationMode(.middle)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8).fill(Theme.working.opacity(0.12)))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.working.opacity(0.5)))
    }

    private func radioRow(_ candidate: CatOfficeCandidate) -> some View {
        Button {
            model.chosen = candidate.path
        } label: {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: model.chosen == candidate.path ? "largecircle.fill.circle" : "circle")
                    .foregroundStyle(model.chosen == candidate.path ? Color.accentColor : .secondary)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(name(candidate.path)).font(.callout.weight(.medium))
                        if candidate.running { runningBadge }
                    }
                    Text(abbreviated(candidate.path)).font(.caption).foregroundStyle(.secondary)
                        .lineLimit(1).truncationMode(.middle)
                }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var runningBadge: some View {
        Text("running").font(.caption2.weight(.semibold)).foregroundStyle(Theme.working)
            .padding(.horizontal, 5).padding(.vertical, 1)
            .background(Capsule().fill(Theme.working.opacity(0.15)))
    }

    private func name(_ path: String) -> String { URL(fileURLWithPath: path).lastPathComponent }

    private func abbreviated(_ path: String) -> String {
        let home = model.env.home.path
        return path.hasPrefix(home + "/") ? "~" + path.dropFirst(home.count) : path
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        panel.message = "Choose your Cat Office folder"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        _ = model.choose(url.path)
    }

    // MARK: - Connect

    private var connect: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Connect").font(.title3.weight(.semibold))
            if model.chosen != nil {
                VStack(alignment: .leading, spacing: 4) {
                    choice($model.patch, "Patch Cat Office", "Matching cats, helpers, and usage without a terminal.", result: "patch")
                    if model.patch, model.running {
                        Text(Self.runningPatchWarning).font(.caption).foregroundStyle(Theme.waiting)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.leading, 20)
                    }
                }
            }
            VStack(alignment: .leading, spacing: 6) {
                choice($model.usage, "Usage in the menu bar", "Claude Code's status line tells ClaudeBar your usage and projects.", result: "usage")
                if model.usage { statusLineNote.padding(.leading, 20) }
            }
            if model.chosen != nil, !model.running {
                choice($model.start, "Start Cat Office now", "Runs Cat Office's dev server (it needs Node.js).", result: "start")
            }
            if model.chosen == nil {
                Text("Without Cat Office, ClaudeBar still shows your usage and projects.")
                    .font(.callout).foregroundStyle(.secondary)
            }
        }
        .disabled(model.working)
    }

    private func choice(_ isOn: Binding<Bool>, _ title: String, _ line: String, result key: String) -> some View {
        HStack(alignment: .top) {
            Toggle(isOn: isOn) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.body.weight(.medium))
                    Text(line).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
            .toggleStyle(.checkbox)
            Spacer(minLength: 0)
            if let r = model.results[key] { mark(r.ok) }
        }
    }

    @ViewBuilder private var statusLineNote: some View {
        switch model.statusLine {
        case .own(let command):
            VStack(alignment: .leading, spacing: 4) {
                Text("You have your own status line (\(command)).").font(.caption).foregroundStyle(.secondary)
                    .lineLimit(1).truncationMode(.tail)
                Picker("", selection: $model.keepOwnStatusLine) {
                    Text("Keep your status line (ClaudeBar reads its data quietly)").tag(true)
                    Text("Use ClaudeBar's status line (yours is backed up)").tag(false)
                }
                .pickerStyle(.radioGroup)
                .labelsHidden()
                .font(.callout)
            }
        case .claudeBar:
            Text("ClaudeBar's status line is already set up.").font(.caption).foregroundStyle(.secondary)
        case .wrapped:
            Text("Your status line is already kept, with ClaudeBar reading its data.").font(.caption).foregroundStyle(.secondary)
        case .unreadable:
            Text("~/.claude/settings.json isn't valid JSON, so it will be left alone.").font(.caption).foregroundStyle(Theme.waiting)
        case .none:
            Text("Installs ClaudeBar's status line; settings.json is backed up first.").font(.caption).foregroundStyle(.secondary)
        }
    }

    private func mark(_ ok: Bool) -> some View {
        Image(systemName: ok ? "checkmark.circle.fill" : "xmark.circle.fill")
            .foregroundStyle(ok ? Theme.working : Theme.waiting)
    }

    // MARK: - Done

    private var done: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(model.summary.allSatisfy(\.ok) ? "You're set up" : "Setup finished").font(.title3.weight(.semibold))
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(model.summary.enumerated()), id: \.offset) { _, line in
                    HStack(alignment: .top, spacing: 8) {
                        mark(line.ok)
                        Text(line.text).font(.callout).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            if let start = model.results["start"], !start.ok, start.text.contains("Node.js") {
                Link("Get Node.js at nodejs.org ↗", destination: URL(string: "https://nodejs.org")!).font(.callout)
            }
            if model.results["usage"]?.ok == true {
                Text("Usage appears after your next message in Claude Code.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            if model.needsRestart {
                VStack(alignment: .leading, spacing: 4) {
                    Button {
                        Task { await model.restart() }
                    } label: {
                        HStack(spacing: 6) {
                            if model.working { ProgressView().controlSize(.small) }
                            Text("Restart Cat Office")
                        }
                    }
                    .disabled(model.working)
                    .help(Self.restartWarning)
                    .setupTarget("setup-restart")
                    Text(Self.restartWarning).font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer()
            HStack {
                Button("Full guide ↗") { state.openHelpGuide() }
                    .buttonStyle(.link)
                    .setupTarget("setup-guide")
                Spacer()
                Button("Open the office") { model.openOffice() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(model.working)
                    .setupTarget("setup-open-office")
            }
        }
    }
}

private extension View {
    /// A stable accessibility id, and the control's frame in the window for the click test.
    func setupTarget(_ id: String) -> some View {
        accessibilityIdentifier(id)
            .onGeometryChange(for: CGRect.self, of: { $0.frame(in: .global) }) { SetupTargets.frames[id] = $0 }
            // Gone with its step: the click test only ever sees targets that are on screen.
            .onDisappear { SetupTargets.frames[id] = nil }
    }
}
