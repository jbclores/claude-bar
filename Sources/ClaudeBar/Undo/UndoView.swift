import ClaudeBarCore
import SwiftUI

/// The undo window: pick, Undo selected, then what happened.
struct UndoView: View {
    static let size = CGSize(width: 460, height: 380)
    @ObservedObject var model: UndoModel
    @EnvironmentObject var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(model.phase == .done ? "Done" : UndoText.title).font(.title3.weight(.semibold))
            switch model.phase {
            case .loading:
                HStack(spacing: 8) { ProgressView().controlSize(.small); Text("Checking what ClaudeBar changed…").foregroundStyle(Theme.secondaryText) }
                Spacer()
            case .choose: choose
            case .done: done
            }
        }
        .padding(20)
        .frame(width: Self.size.width, height: Self.size.height, alignment: .topLeading)
        .task { if model.phase == .loading { await model.load() } }
    }

    private var choose: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(UndoText.intro).font(.callout).foregroundStyle(Theme.secondaryText).fixedSize(horizontal: false, vertical: true)
            ForEach(model.rows) { row in rowView(row) }
            if let warning = model.warning {
                Text(warning).font(.caption).foregroundStyle(Theme.waiting).fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            HStack {
                Button("Cancel") { model.close() }
                    .disabled(model.working)
                    .setupTarget("undo-cancel")
                Spacer()
                Button {
                    Task { await model.undo() }
                } label: {
                    HStack(spacing: 6) {
                        if model.working { ProgressView().controlSize(.small) }
                        Text("Undo selected")
                    }
                }
                .buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
                .disabled(model.working || model.ticked.isEmpty)
                .setupTarget("undo-run")
            }
        }
        .disabled(model.working)
    }

    @ViewBuilder private func rowView(_ row: UndoRow) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Toggle(isOn: Binding(get: { model.binding(row.kind) }, set: { model.set(row.kind, $0) })) {
                Text(row.title).font(.body.weight(.medium))
            }
            .toggleStyle(.checkbox)
            .disabled(!row.available)
            Text(row.detail).font(.caption).foregroundStyle(Theme.secondaryText).fixedSize(horizontal: false, vertical: true)
                .padding(.leading, 20)
            if !row.available {
                Button("How to do it by hand ↗") { state.openChangesPage() }
                    .buttonStyle(.link).font(.caption).padding(.leading, 20)
            }
        }
        .opacity(row.available ? 1 : 0.6)
    }

    private var done: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(UndoRow.Kind.allCases, id: \.self) { kind in
                if let r = model.results[kind] {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: r.ok ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundStyle(r.ok ? Theme.working : Theme.waiting)
                        Text(r.text).font(.callout).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            ForEach(model.doneLines, id: \.self) { line in
                Text(line).font(.callout).foregroundStyle(Theme.secondaryText).fixedSize(horizontal: false, vertical: true)
            }
            if model.needsRestart {
                Button {
                    Task { await model.restart() }
                } label: {
                    HStack(spacing: 6) {
                        if model.working { ProgressView().controlSize(.small) }
                        Text("Restart Cat Office")
                    }
                }
                .disabled(model.working)
                .setupTarget("undo-restart")
                if let error = model.restartError {
                    Text(error).font(.caption).foregroundStyle(Theme.waiting).fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer()
            HStack {
                Button("What ClaudeBar changes ↗") { state.openChangesPage() }.buttonStyle(.link)
                Spacer()
                if model.removed {
                    Button("Quit ClaudeBar") { model.quit() }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction).setupTarget("undo-quit")
                } else {
                    Button("Done") { model.close() }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction).disabled(model.working).setupTarget("undo-done")
                }
            }
        }
    }
}
