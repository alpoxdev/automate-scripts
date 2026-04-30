import AutomateCore
import SwiftUI

private enum MenuPanel: String, CaseIterable, Identifiable {
    case jobs, add, settings
    var id: String { rawValue }
}

struct MenuBarRootView: View {
    @ObservedObject var model: MenuBarModel
    @State private var panel: MenuPanel = .jobs
    @State private var editingJob: ScriptJob?
    @State private var logJob: ScriptJob?

    var body: some View {
        let localizer = model.localizer
        VStack(spacing: 0) {
            header(localizer)
            Divider()
            summary(localizer)
                .padding(.horizontal, 18)
                .padding(.vertical, 14)
            Picker("", selection: $panel) {
                Text(localizer.text("panel.jobs")).tag(MenuPanel.jobs)
                Text(localizer.text("panel.add")).tag(MenuPanel.add)
                Text(localizer.text("panel.settings")).tag(MenuPanel.settings)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 18)
            .padding(.bottom, 12)

            Divider()
            ScrollView {
                Group {
                    if let logJob {
                        RunHistoryView(
                            job: logJob,
                            records: model.runRecords(for: logJob),
                            localizer: localizer,
                            onBack: {
                                self.logJob = nil
                                panel = .jobs
                            }
                        )
                    } else {
                        switch panel {
                        case .jobs:
                            if model.jobs.isEmpty {
                                emptyState(localizer)
                            } else {
                                JobListView(
                                    model: model,
                                    onEdit: { job in
                                        editingJob = job
                                        panel = .add
                                    },
                                    onLogs: { job in
                                        self.logJob = job
                                        panel = .jobs
                                    }
                                )
                            }
                        case .add:
                            JobEditorView(
                                localizer: localizer,
                                job: editingJob,
                                onCancel: {
                                    editingJob = nil
                                    panel = .jobs
                                },
                                onSave: { job in
                                    if editingJob == nil { model.add(job) } else { model.update(job) }
                                    editingJob = nil
                                    panel = .jobs
                                }
                            )
                        case .settings:
                            SettingsView(model: model)
                        }
                    }
                }
                .padding(18)
            }
            footer(localizer)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func header(_ localizer: Localizer) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(.blue.gradient)
                Image(systemName: "bolt.fill").foregroundStyle(.white)
            }
            .frame(width: 34, height: 34)

            VStack(alignment: .leading, spacing: 2) {
                Text(localizer.text("app.name"))
                    .font(.system(size: 16, weight: .semibold))
                Text(String(format: localizer.text("update.version"), model.appVersion.displayText))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
                Text(model.displayMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            updateControl(localizer)
            Button {
                model.reload()
            } label: {
                Label(localizer.text("common.reload"), systemImage: "arrow.clockwise")
                    .labelStyle(.iconOnly)
            }
            .buttonStyle(.borderless)
            .help(localizer.text("common.reload"))
        }
        .padding(18)
    }

    @ViewBuilder
    private func updateControl(_ localizer: Localizer) -> some View {
        switch model.updateState {
        case .available:
            Button {
                model.installAvailableUpdate()
            } label: {
                Label(localizer.text("update.button"), systemImage: "arrow.down.circle")
            }
            .controlSize(.small)
            .buttonStyle(.borderedProminent)
            .help(model.updateStatusText(localizer: localizer))
        case .checking, .installing, .restarting:
            ProgressView()
                .controlSize(.small)
                .help(model.updateStatusText(localizer: localizer))
        case .failed, .noCompatibleAsset, .developmentBuild:
            Image(systemName: "info.circle")
                .foregroundStyle(.secondary)
                .help(model.updateStatusText(localizer: localizer))
        case .idle, .upToDate:
            EmptyView()
        }
    }

    private func summary(_ localizer: Localizer) -> some View {
        HStack(spacing: 10) {
            stat(localizer.text("stat.jobs"), "\(model.jobs.count)", "tray.full")
            stat(localizer.text("stat.enabled"), "\(model.enabledCount)", "checkmark.circle")
            stat(localizer.text("stat.failures"), "\(model.failureCount)", model.failureCount == 0 ? "checkmark.seal" : "exclamationmark.triangle")
            stat(localizer.text("stat.running"), "\(model.runningCount)", "play.circle")
        }
    }

    private func stat(_ title: String, _ value: String, _ icon: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon).foregroundStyle(.blue)
            VStack(alignment: .leading, spacing: 1) {
                Text(value).font(.headline)
                Text(title).font(.caption2).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .frame(maxWidth: .infinity)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func emptyState(_ localizer: Localizer) -> some View {
        VStack(spacing: 14) {
            Image(systemName: "wand.and.stars")
                .font(.system(size: 36))
                .foregroundStyle(.secondary)
            Text(localizer.text("empty.title"))
                .font(.headline)
            Text(localizer.text("empty.subtitle"))
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button {
                panel = .add
            } label: {
                Label(localizer.text("job.addNew"), systemImage: "plus.circle.fill")
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, minHeight: 260)
        .padding()
    }

    private func footer(_ localizer: Localizer) -> some View {
        HStack {
            Text(localizer.text("footer.safeScheduling"))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer()
            Button(localizer.text("common.quit")) {
                NSApplication.shared.terminate(nil)
            }
            .buttonStyle(.borderless)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(Color(nsColor: .controlBackgroundColor))
    }
}
