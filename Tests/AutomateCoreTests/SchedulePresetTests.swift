import AutomateCore
import XCTest

final class SchedulePresetTests: XCTestCase {
    func testCodableRoundTrip() throws {
        let presets: [SchedulePreset] = [
            .manualOnly,
            .atLogin,
            .everyMinutes(15),
            .hourly(minute: 5),
            .daily(hour: 9, minute: 30),
            .weekly(weekday: .monday, hour: 8, minute: 0),
            .monthly(day: 28, hour: 23, minute: 59)
        ]
        let data = try JSONEncoder().encode(presets)
        let decoded = try JSONDecoder().decode([SchedulePreset].self, from: data)
        XCTAssertEqual(decoded, presets)
    }

    func testValidationRejectsRawLikeUnsupportedIntervals() {
        XCTAssertThrowsError(try SchedulePreset.everyMinutes(7).validate())
        XCTAssertThrowsError(try SchedulePreset.daily(hour: 24, minute: 0).validate())
        XCTAssertThrowsError(try SchedulePreset.monthly(day: 31, hour: 9, minute: 0).validate())
    }

    func testLocalizedScheduleDescriptions() {
        XCTAssertEqual(Localizer(language: .english).scheduleDescription(.daily(hour: 9, minute: 0)), "Every day at 09:00")
        XCTAssertEqual(Localizer(language: .korean).scheduleDescription(.weekly(weekday: .monday, hour: 8, minute: 30)), "매주 월요일 08:30")
    }

    func testRelativeRunStatusIncludesElapsedTimeAndOutcome() {
        let now = Date(timeIntervalSince1970: 1_800)
        let record = RunRecord(
            jobID: UUID(),
            jobName: "backup",
            startedAt: now.addingTimeInterval(-370),
            finishedAt: now.addingTimeInterval(-125),
            exitCode: 0,
            stdoutPath: nil,
            stderrPath: nil
        )

        let presentation = Localizer(language: .korean).runStatusPresentation(for: record, now: now, timeZone: TimeZone(secondsFromGMT: 0)!)
        XCTAssertEqual(presentation.label, "2분 전 실행 성공")
        XCTAssertTrue(presentation.detail.contains("마지막 실행:"))
    }

    func testRelativeRunStatusIncludesFailureCode() {
        let now = Date(timeIntervalSince1970: 1_800)
        let record = RunRecord(
            jobID: UUID(),
            jobName: "sync",
            startedAt: now.addingTimeInterval(-10),
            finishedAt: now.addingTimeInterval(-10),
            exitCode: 127,
            stdoutPath: nil,
            stderrPath: nil
        )

        let presentation = Localizer(language: .korean).runStatusPresentation(for: record, now: now, timeZone: TimeZone(secondsFromGMT: 0)!)
        XCTAssertEqual(presentation.label, "10초 전 실행 실패: 종료 코드 127")
        XCTAssertTrue(presentation.detail.contains("마지막 실행:"))
    }

    func testRelativeRunTimeUsesHoursAndDays() {
        let localizer = Localizer(language: .korean)
        let now = Date(timeIntervalSince1970: 200_000)
        XCTAssertEqual(localizer.relativeRunTime(since: now.addingTimeInterval(-3_600), now: now), "1시간 전")
        XCTAssertEqual(localizer.relativeRunTime(since: now.addingTimeInterval(-172_800), now: now), "2일 전")
    }
}

final class LocalizerCoverageTests: XCTestCase {
    func testDefaultLanguageUsesPreferredSupportedLanguageThenEnglishFallback() {
        XCTAssertEqual(AppLanguage.system(preferredLanguages: ["ko-KR", "en-US"]), .korean)
        XCTAssertEqual(AppLanguage.system(preferredLanguages: ["ja-JP", "fr-FR"]), .english)
        XCTAssertEqual(AppLanguage.system(preferredLanguages: []), .english)
    }

    func testCoreUserFacingKeysExistInEnglishAndKorean() {
        let keys = [
            "common.reload", "common.settings", "common.quit", "common.run", "common.enable", "common.disable", "common.save",
            "common.edit", "common.cancel", "common.choose", "common.logs", "field.name", "field.command", "field.arguments", "field.workingDirectory", "field.sudo", "field.sudoHelp", "field.inputRequired", "field.defaultAnswer", "field.answerChoices", "field.defaultChoice", "field.answerChoicesHelp",
            "panel.jobs", "panel.add", "panel.settings", "stat.jobs", "stat.enabled", "stat.failures", "stat.running",
            "empty.title", "empty.subtitle", "editor.addTitle", "editor.editTitle", "editor.subtitle", "editor.advanced",
            "settings.title", "settings.subtitle", "settings.language", "settings.launchAtLogin",
            "login.status.enabled", "login.status.disabled", "login.status.notRegistered", "login.status.requiresApproval", "login.status.unsupported", "login.status.unknown", "login.help", "login.openSettings", "login.error",
            "settings.scheduler", "settings.schedulerBackend", "settings.storePath", "settings.logPath", "settings.noCron", "footer.safeScheduling",
            "settings.backgroundMode", "settings.backgroundHelp", "logs.retentionDays", "logs.stashNow", "logs.stashPath", "logs.stashedSummary",
            "logs.title", "logs.historyTitle", "logs.back", "logs.runCount", "logs.allRuns", "logs.selectedRun", "logs.duration", "logs.noRuns", "logs.noRunsHelp", "logs.empty", "logs.stdout", "logs.stderr", "logs.reveal",
            "schedule.picker.title", "schedule.kind.manual", "schedule.kind.login", "schedule.kind.minutes", "schedule.kind.hourly", "schedule.kind.daily", "schedule.kind.weekly", "schedule.kind.monthly", "schedule.interval", "schedule.time", "schedule.weekday", "schedule.day", "schedule.cronHidden",
            "job.added", "job.updated", "job.addNew", "job.delete", "job.running", "job.lastFailure", "job.lastSuccess", "job.lastFailureRelative", "job.lastSuccessRelative", "job.lastRunAt", "job.noRecentRuns", "time.justNow", "time.secondsAgo", "time.minutesAgo", "time.hoursAgo", "time.daysAgo",
            "run.exitCode", "run.jobExit", "run.chooseAnswerTitle", "run.chooseAnswerMessage", "run.stdout", "run.stderr", "sudo.authorizing", "sudo.ready", "status.ready", "language.english", "language.korean",
            "update.version", "update.idle", "update.checking", "update.upToDate", "update.available", "update.button", "update.installing", "update.noCompatibleAsset", "update.developmentBuild", "update.failed", "update.invalidVersion", "update.restartSoon"
        ]
        for language in AppLanguage.allCases {
            let localizer = Localizer(language: language)
            for key in keys {
                XCTAssertNotEqual(localizer.text(key), key, "Missing localization for \(key) in \(language.rawValue)")
            }
        }
    }
}
