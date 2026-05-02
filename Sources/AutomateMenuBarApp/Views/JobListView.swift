import AutomateCore
import SwiftUI

struct JobListView: View {
    @ObservedObject var model: MenuBarModel
    let onEdit: (ScriptJob) -> Void
    let onLogs: (ScriptJob) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(model.jobs, id: \ScriptJob.id) { (job: ScriptJob) in
                jobCard(job)
            }
        }
    }

    private func jobCard(_ job: ScriptJob) -> some View {
        let localizer = model.localizer
        let latest = model.latestRecord(for: job)
        let running = model.isRunning(job)
        let failed = latest.map { $0.exitCode != 0 || $0.timedOut } ?? false

        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                if running {
                    ProgressView()
                        .controlSize(.small)
                        .frame(width: 20, height: 20)
                } else {
                    Image(systemName: failed ? "exclamationmark.triangle.fill" : (job.enabled ? "checkmark.circle.fill" : "pause.circle.fill"))
                        .foregroundStyle(failed ? .red : (job.enabled ? .green : .secondary))
                        .font(.title3)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(job.name)
                        .font(.headline)
                        .lineLimit(1)
                    Text(localizer.scheduleDescription(job.schedule))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(running ? localizer.text("job.running") : localizer.text("common.run")) { model.run(job) }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(running)
            }

            Text(commandLine(job))
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .textSelection(.enabled)

            TimelineView(.periodic(from: .now, by: 1)) { context in
                HStack {
                    statusText(latest, running: running, localizer: localizer, now: context.date)
                    Spacer()
                    Button(localizer.text("common.logs")) {
                        onLogs(job)
                    }
                    .controlSize(.small)
                    Button(localizer.text("common.edit")) { onEdit(job) }
                        .controlSize(.small)
                    Button(localizer.text(job.enabled ? "common.disable" : "common.enable")) { model.toggle(job) }
                        .controlSize(.small)
                    Button(role: .destructive) {
                        model.delete(job)
                    } label: {
                        Text(localizer.text("job.delete"))
                    }
                    .controlSize(.small)
                }
            }
        }
        .padding(14)
        .background(.background, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(failed ? Color.red.opacity(0.45) : Color.primary.opacity(0.08), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.05), radius: 8, y: 3)
    }

    private func statusText(_ record: RunRecord?, running: Bool, localizer: Localizer, now: Date) -> some View {
        Group {
            if running {
                Label(localizer.text("job.running"), systemImage: "hourglass")
                    .foregroundStyle(.blue)
            } else if let record {
                let status = localizer.runStatusPresentation(for: record, now: now)
                if record.exitCode == 0 && !record.timedOut {
                    Label(status.label, systemImage: "checkmark.seal")
                        .foregroundStyle(.green)
                        .help(status.detail)
                        .accessibilityHint(Text(status.detail))
                } else {
                    Label(status.label, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                        .help(status.detail)
                        .accessibilityHint(Text(status.detail))
                }
            } else {
                Label(localizer.text("job.noRecentRuns"), systemImage: "clock")
                    .foregroundStyle(.secondary)
            }
        }
        .font(.caption)
    }

    private func commandLine(_ job: ScriptJob) -> String {
        let prefix = job.requiresAdministratorPrivileges ? "sudo " : ""
        return prefix + ([job.command] + job.arguments).joined(separator: " ")
    }
}
