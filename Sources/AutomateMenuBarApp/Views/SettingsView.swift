import AutomateCore
import SwiftUI

struct SettingsView: View {
    @ObservedObject var model: MenuBarModel
    @State private var loginItemState = LoginItemService().state()
    @State private var launchAtLogin = LoginItemService().state().isEnabled
    private let loginItemService = LoginItemService()

    var body: some View {
        let localizer = model.localizer
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(localizer.text("settings.title"))
                    .font(.title3.weight(.semibold))
                Text(localizer.text("settings.subtitle"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            settingsCard {
                Picker(localizer.text("settings.language"), selection: $model.language) {
                    Text(localizer.text("language.english")).tag(AppLanguage.english)
                    Text(localizer.text("language.korean")).tag(AppLanguage.korean)
                }
                .pickerStyle(.segmented)

                Toggle(localizer.text("settings.launchAtLogin"), isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { enabled in
                        setLaunchAtLogin(enabled, localizer: localizer)
                    }
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: loginItemState.needsUserAction ? "exclamationmark.triangle.fill" : "checkmark.circle")
                        .foregroundStyle(loginItemState.needsUserAction ? .orange : .secondary)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(loginItemState.title(localizer: localizer))
                            .font(.caption.weight(.semibold))
                        Text(localizer.text("login.help"))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                Button {
                    loginItemService.openLoginItemsSettings()
                } label: {
                    Label(localizer.text("login.openSettings"), systemImage: "gearshape")
                }
                .controlSize(.small)
            }

            settingsCard {
                infoRow(localizer.text("settings.scheduler"), localizer.text("settings.schedulerBackend"), icon: "calendar.badge.clock")
                infoRow(localizer.text("settings.storePath"), model.storePath, icon: "externaldrive")
                infoRow(localizer.text("settings.logPath"), model.logPath, icon: "doc.text")
                infoRow(localizer.text("logs.stashPath"), model.stashPath, icon: "archivebox")
            }

            settingsCard {
                Toggle(localizer.text("settings.backgroundMode"), isOn: $model.settings.runsInBackground)
                    .onChange(of: model.settings.runsInBackground) { _ in model.saveSettings() }
                Text(localizer.text("settings.backgroundHelp"))
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                Stepper(
                    String(format: localizer.text("logs.retentionDays"), model.settings.logRetentionDays),
                    value: $model.settings.logRetentionDays,
                    in: 1...365
                )
                .onChange(of: model.settings.logRetentionDays) { _ in model.saveSettings() }

                Button {
                    model.stashOldLogs()
                } label: {
                    Label(localizer.text("logs.stashNow"), systemImage: "archivebox")
                }
                .controlSize(.small)
            }

            Text(localizer.text("settings.noCron"))
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.blue.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .onAppear {
            refreshLoginItemState()
        }
    }

    private func setLaunchAtLogin(_ enabled: Bool, localizer: Localizer) {
        do {
            try loginItemService.setEnabled(enabled)
            refreshLoginItemState()
            model.lastMessage = loginItemState.title(localizer: localizer)
        } catch {
            refreshLoginItemState()
            launchAtLogin = loginItemState.isEnabled
            model.lastMessage = String(format: localizer.text("login.error"), error.localizedDescription)
        }
    }

    private func refreshLoginItemState() {
        loginItemState = loginItemService.state()
        launchAtLogin = loginItemState.isEnabled
    }

    private func settingsCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            content()
        }
        .padding(14)
        .background(.background, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }

    private func infoRow(_ title: String, _ value: String, icon: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(.blue)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.caption.weight(.semibold))
                Text(value)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .lineLimit(2)
            }
        }
    }
}
