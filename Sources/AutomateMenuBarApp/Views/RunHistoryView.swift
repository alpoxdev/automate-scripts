import AutomateCore
import AppKit
import SwiftUI

struct RunHistoryView: View {
    let job: ScriptJob
    let records: [RunRecord]
    let localizer: Localizer
    let onBack: () -> Void
    @State private var selectedRecordID: UUID?

    private var selectedRecord: RunRecord? {
        guard let selectedRecordID else { return records.first }
        return records.first { $0.id == selectedRecordID } ?? records.first
    }

    init(
        job: ScriptJob,
        records: [RunRecord],
        localizer: Localizer = Localizer(),
        onBack: @escaping () -> Void = {}
    ) {
        self.job = job
        self.records = records
        self.localizer = localizer
        self.onBack = onBack
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            if records.isEmpty {
                emptyState
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    runList
                    if let selectedRecord {
                        logDetail(for: selectedRecord)
                    }
                }
            }
        }
        .onAppear {
            selectedRecordID = selectedRecordID ?? records.first?.id
        }
        .onChange(of: records.map(\.id)) { ids in
            guard let selectedRecordID, ids.contains(selectedRecordID) else {
                self.selectedRecordID = ids.first
                return
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Button {
                    onBack()
                } label: {
                    Label(localizer.text("logs.back"), systemImage: "chevron.left")
                }
                .controlSize(.small)
                .buttonStyle(.bordered)

                Spacer()
            }

            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(String(format: localizer.text("logs.historyTitle"), job.name))
                        .font(.title3.weight(.semibold))
                    Text(String(format: localizer.text("logs.runCount"), records.count))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if let selectedRecord {
                    Button(localizer.text("logs.reveal")) {
                        revealLogs(for: selectedRecord)
                    }
                    .controlSize(.small)
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 32))
                .foregroundStyle(.secondary)
            Text(localizer.text("logs.noRuns"))
                .font(.headline)
            Text(localizer.text("logs.noRunsHelp"))
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: 260)
        .padding()
        .background(.background, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }

    private var runList: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(localizer.text("logs.allRuns"))
                .font(.headline)

            ForEach(records) { record in
                Button {
                    selectedRecordID = record.id
                } label: {
                    runRow(record)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func runRow(_ record: RunRecord) -> some View {
        let failed = record.exitCode != 0 || record.timedOut
        let selected = selectedRecord?.id == record.id

        return HStack(alignment: .top, spacing: 10) {
            Image(systemName: failed ? "xmark.circle.fill" : "checkmark.circle.fill")
                .foregroundStyle(failed ? .red : .green)
            VStack(alignment: .leading, spacing: 2) {
                Text(localizer.runHistoryTimestamp(record.startedAt))
                    .font(.caption.weight(.semibold))
                Text(String(format: localizer.text("run.exitCode"), record.exitCode))
                    .font(.caption2)
                    .foregroundStyle(failed ? .red : .secondary)
            }
            Spacer()
            Text(String(format: localizer.text("logs.duration"), record.duration))
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .padding(10)
        .background(selected ? Color.accentColor.opacity(0.14) : Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(selected ? Color.accentColor.opacity(0.35) : Color.primary.opacity(0.06), lineWidth: 1)
        )
    }

    private func logDetail(for record: RunRecord) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(localizer.text("logs.selectedRun"))
                    .font(.headline)
                Spacer()
                Text(localizer.runHistoryTimestamp(record.startedAt))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            logSection(title: localizer.text("logs.stdout"), path: record.stdoutPath)
            logSection(title: localizer.text("logs.stderr"), path: record.stderrPath)
        }
        .padding(12)
        .background(.background, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }

    private func logSection(title: String, path: String?) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(logText(path))
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }

    private func logText(_ path: String?) -> String {
        guard let path, FileManager.default.fileExists(atPath: path) else {
            return localizer.text("logs.empty")
        }
        return (try? String(contentsOfFile: path, encoding: .utf8)).flatMap {
            $0.isEmpty ? nil : $0
        } ?? localizer.text("logs.empty")
    }

    private func revealLogs(for record: RunRecord) {
        let paths = [record.stdoutPath, record.stderrPath].compactMap { $0 }.map(URL.init(fileURLWithPath:))
        guard !paths.isEmpty else { return }
        NSWorkspace.shared.activateFileViewerSelecting(paths)
    }
}
