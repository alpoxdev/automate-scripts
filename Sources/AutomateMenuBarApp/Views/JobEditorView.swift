import AutomateCore
import AppKit
import SwiftUI

struct JobEditorView: View {
    let localizer: Localizer
    let existingJob: ScriptJob?
    let onCancel: () -> Void
    let onSave: (ScriptJob) -> Void

    @State private var name: String
    @State private var command: String
    @State private var arguments: String
    @State private var workingDirectory: String
    @State private var requiresAdministratorPrivileges: Bool
    @State private var inputRequired: Bool
    @State private var defaultAnswer: String
    @State private var answerChoices: String
    @State private var defaultChoice: String
    @State private var schedule: SchedulePreset
    @State private var showsAdvanced = false

    init(
        localizer: Localizer = Localizer(),
        job: ScriptJob? = nil,
        onCancel: @escaping () -> Void = {},
        onSave: @escaping (ScriptJob) -> Void
    ) {
        self.localizer = localizer
        self.existingJob = job
        self.onCancel = onCancel
        self.onSave = onSave
        _name = State(initialValue: job?.name ?? "")
        _command = State(initialValue: job?.command ?? "")
        _arguments = State(initialValue: job?.arguments.joined(separator: " ") ?? "")
        _workingDirectory = State(initialValue: job?.workingDirectory ?? AppPaths.defaultWorkingDirectory().path)
        _requiresAdministratorPrivileges = State(initialValue: job?.requiresAdministratorPrivileges ?? false)
        _inputRequired = State(initialValue: job?.inputPolicy.requirement == .required)
        _defaultAnswer = State(initialValue: job?.inputPolicy.defaultAnswer ?? "")
        _answerChoices = State(initialValue: Self.formatAnswerChoices(job?.inputPolicy.answerChoices ?? []))
        _defaultChoice = State(initialValue: job?.inputPolicy.defaultChoiceID ?? "")
        _schedule = State(initialValue: job?.schedule ?? .manualOnly)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(existingJob == nil ? localizer.text("editor.addTitle") : localizer.text("editor.editTitle"))
                    .font(.title3.weight(.semibold))
                Text(localizer.text("editor.subtitle"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 10) {
                labeledTextField(localizer.text("field.name"), text: $name, prompt: "backup")
                commandField
                Toggle(localizer.text("field.sudo"), isOn: $requiresAdministratorPrivileges)
                Text(localizer.text("field.sudoHelp"))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 10) {
                Button {
                    withAnimation(.easeInOut(duration: 0.16)) {
                        showsAdvanced.toggle()
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: showsAdvanced ? "chevron.down" : "chevron.right")
                            .font(.caption.weight(.semibold))
                            .frame(width: 12)
                        Text(localizer.text("editor.advanced"))
                            .font(.caption.weight(.semibold))
                        Spacer()
                    }
                    .padding(.vertical, 8)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(.isButton)

                if showsAdvanced {
                    advancedOptions
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }

            HStack {
                Button(localizer.text("common.cancel")) { onCancel() }
                Spacer()
                Button(localizer.text("common.save")) { onSave(makeJob()) }
                    .buttonStyle(.borderedProminent)
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }

    private var advancedOptions: some View {
        VStack(alignment: .leading, spacing: 10) {
            labeledTextField(localizer.text("field.arguments"), text: $arguments, prompt: "--flag value")
            labeledTextField(localizer.text("field.workingDirectory"), text: $workingDirectory, prompt: AppPaths.defaultWorkingDirectory().path)

            VStack(alignment: .leading, spacing: 8) {
                Toggle(localizer.text("field.inputRequired"), isOn: $inputRequired)
                labeledTextField(localizer.text("field.defaultAnswer"), text: $defaultAnswer, prompt: "y")
                labeledTextField(localizer.text("field.answerChoices"), text: $answerChoices, prompt: "yes=y, no=n")
                labeledTextField(localizer.text("field.defaultChoice"), text: $defaultChoice, prompt: "yes")
                Text(localizer.text("field.answerChoicesHelp"))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(12)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))

            VStack(alignment: .leading, spacing: 8) {
                Text(localizer.text("schedule.picker.title"))
                    .font(.headline)
                SchedulePickerView(schedule: $schedule, localizer: localizer)
                    .padding(12)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
    }

    private var commandField: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(localizer.text("field.command")).font(.caption.weight(.medium)).foregroundStyle(.secondary)
            HStack(spacing: 8) {
                TextField("/path/to/script.sh", text: $command)
                    .textFieldStyle(.roundedBorder)
                Button {
                    chooseScript()
                } label: {
                    Label(localizer.text("common.choose"), systemImage: "folder")
                        .labelStyle(.iconOnly)
                }
                .help(localizer.text("common.choose"))
            }
        }
    }

    private func labeledTextField(_ title: String, text: Binding<String>, prompt: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption.weight(.medium)).foregroundStyle(.secondary)
            TextField(prompt, text: text)
                .textFieldStyle(.roundedBorder)
        }
    }

    private func chooseScript() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.prompt = localizer.text("common.choose")
        if panel.runModal() == .OK, let url = panel.url {
            command = url.path
            if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                name = url.deletingPathExtension().lastPathComponent
            }
            if workingDirectory.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                workingDirectory = AppPaths.defaultWorkingDirectory().path
            }
        }
    }

    private func makeJob() -> ScriptJob {
        let invocation = CommandLineParser.normalized(commandText: command, argumentsText: arguments)
        let cwd = workingDirectory.trimmingCharacters(in: .whitespacesAndNewlines)
        if var existingJob {
            existingJob.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
            existingJob.command = invocation.command
            existingJob.arguments = invocation.arguments
            existingJob.workingDirectory = cwd.isEmpty ? nil : cwd
            existingJob.requiresAdministratorPrivileges = requiresAdministratorPrivileges
            existingJob.inputPolicy = makeInputPolicy()
            existingJob.schedule = schedule
            return existingJob
        }
        return ScriptJob(
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            command: invocation.command,
            arguments: invocation.arguments,
            workingDirectory: cwd.isEmpty ? nil : cwd,
            requiresAdministratorPrivileges: requiresAdministratorPrivileges,
            inputPolicy: makeInputPolicy(),
            schedule: schedule
        )
    }

    private func makeInputPolicy() -> ScriptInputPolicy {
        let answer = defaultAnswer.trimmingCharacters(in: .whitespacesAndNewlines)
        let defaultChoiceID = defaultChoice.trimmingCharacters(in: .whitespacesAndNewlines)
        let choices = Self.parseAnswerChoices(answerChoices)
        let hasInput = inputRequired || !answer.isEmpty || !choices.isEmpty || !defaultChoiceID.isEmpty
        guard hasInput else { return .none }
        return ScriptInputPolicy(
            requirement: inputRequired ? .required : .optional,
            defaultAnswer: answer.isEmpty ? nil : answer,
            answerChoices: choices,
            defaultChoiceID: defaultChoiceID.isEmpty ? nil : defaultChoiceID
        )
    }

    private static func parseAnswerChoices(_ text: String) -> [ScriptAnswerChoice] {
        text.split(separator: ",")
            .compactMap { raw -> ScriptAnswerChoice? in
                let parts = raw.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
                guard parts.count == 2 else { return nil }
                let label = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
                let value = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
                guard !label.isEmpty else { return nil }
                return ScriptAnswerChoice(label: label, value: value)
            }
    }

    private static func formatAnswerChoices(_ choices: [ScriptAnswerChoice]) -> String {
        choices.map { "\($0.label)=\($0.value)" }.joined(separator: ", ")
    }
}
