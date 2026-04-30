import AutomateCore
import SwiftUI

struct SchedulePickerView: View {
    @Binding var schedule: SchedulePreset
    let localizer: Localizer
    @State private var kind = "manual"
    @State private var time = Date()
    @State private var interval = 15
    @State private var weekday = Weekday.monday
    @State private var monthDay = 1

    init(schedule: Binding<SchedulePreset>, localizer: Localizer = Localizer()) {
        self._schedule = schedule
        self.localizer = localizer
    }

    var body: some View {
        VStack(alignment: .leading) {
            Picker(localizer.text("schedule.picker.title"), selection: $kind) {
                Text(localizer.text("schedule.kind.manual")).tag("manual")
                Text(localizer.text("schedule.kind.login")).tag("login")
                Text(localizer.text("schedule.kind.minutes")).tag("minutes")
                Text(localizer.text("schedule.kind.hourly")).tag("hourly")
                Text(localizer.text("schedule.kind.daily")).tag("daily")
                Text(localizer.text("schedule.kind.weekly")).tag("weekly")
                Text(localizer.text("schedule.kind.monthly")).tag("monthly")
            }
            .onChange(of: kind) { _ in apply() }

            if kind == "minutes" {
                Picker(localizer.text("schedule.interval"), selection: $interval) {
                    ForEach([5, 10, 15, 30], id: \.self) { Text(localizer.scheduleDescription(.everyMinutes($0))).tag($0) }
                }.onChange(of: interval) { _ in apply() }
            }
            if kind == "hourly" {
                Stepper(String(format: localizer.text("schedule.hourly"), Calendar.current.component(.minute, from: time)), value: Binding(
                    get: { Calendar.current.component(.minute, from: time) },
                    set: { minute in setTime(hour: Calendar.current.component(.hour, from: time), minute: minute) }
                ), in: 0...59).onChange(of: time) { _ in apply() }
            }
            if ["daily", "weekly", "monthly"].contains(kind) {
                DatePicker(localizer.text("schedule.time"), selection: $time, displayedComponents: .hourAndMinute).onChange(of: time) { _ in apply() }
            }
            if kind == "weekly" {
                Picker(localizer.text("schedule.weekday"), selection: $weekday) {
                    ForEach(Weekday.allCases, id: \.self) { Text($0.localized(localizer.language)).tag($0) }
                }.onChange(of: weekday) { _ in apply() }
            }
            if kind == "monthly" {
                Stepper(String(format: localizer.text("schedule.day"), monthDay), value: $monthDay, in: 1...28).onChange(of: monthDay) { _ in apply() }
            }
            Text(localizer.text("schedule.cronHidden"))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .onAppear { syncFromSchedule() }
    }

    private func apply() {
        let parts = Calendar.current.dateComponents([.hour, .minute], from: time)
        let hour = parts.hour ?? 9
        let minute = parts.minute ?? 0
        switch kind {
        case "login": schedule = .atLogin
        case "minutes": schedule = .everyMinutes(interval)
        case "hourly": schedule = .hourly(minute: minute)
        case "daily": schedule = .daily(hour: hour, minute: minute)
        case "weekly": schedule = .weekly(weekday: weekday, hour: hour, minute: minute)
        case "monthly": schedule = .monthly(day: monthDay, hour: hour, minute: minute)
        default: schedule = .manualOnly
        }
    }

    private func setTime(hour: Int, minute: Int) {
        var components = Calendar.current.dateComponents([.year, .month, .day], from: time)
        components.hour = hour
        components.minute = minute
        time = Calendar.current.date(from: components) ?? time
        apply()
    }

    private func syncFromSchedule() {
        switch schedule {
        case .manualOnly:
            kind = "manual"
        case .atLogin:
            kind = "login"
        case .everyMinutes(let minutes):
            kind = "minutes"
            interval = minutes
        case .hourly(let minute):
            kind = "hourly"
            setTime(hour: Calendar.current.component(.hour, from: time), minute: minute)
        case .daily(let hour, let minute):
            kind = "daily"
            setTime(hour: hour, minute: minute)
        case .weekly(let selectedWeekday, let hour, let minute):
            kind = "weekly"
            weekday = selectedWeekday
            setTime(hour: hour, minute: minute)
        case .monthly(let day, let hour, let minute):
            kind = "monthly"
            monthDay = day
            setTime(hour: hour, minute: minute)
        }
        apply()
    }
}
