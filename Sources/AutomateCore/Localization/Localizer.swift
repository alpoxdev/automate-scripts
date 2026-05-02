import Foundation

public enum AppLanguage: String, Codable, CaseIterable, Sendable {
    case english = "en"
    case korean = "ko"

    public static func system(preferredLanguages: [String] = Locale.preferredLanguages) -> AppLanguage {
        for identifier in preferredLanguages {
            if let language = supportedLanguage(for: identifier) {
                return language
            }
        }
        return .english
    }

    public static func system(locale: Locale) -> AppLanguage {
        supportedLanguage(for: locale.identifier) ?? .english
    }

    private static func supportedLanguage(for identifier: String) -> AppLanguage? {
        let code = Locale(identifier: identifier).language.languageCode?.identifier ?? identifier
        return allCases.first { language in
            code.caseInsensitiveCompare(language.rawValue) == .orderedSame
        }
    }
}

public struct RunStatusPresentation: Equatable, Sendable {
    public var label: String
    public var detail: String

    public init(label: String, detail: String) {
        self.label = label
        self.detail = detail
    }
}

public struct Localizer: Sendable {
    public let language: AppLanguage
    public init(language: AppLanguage = .system()) { self.language = language }

    public func text(_ key: String) -> String {
        Self.table[language]?[key] ?? Self.table[.english]?[key] ?? key
    }

    public func scheduleDescription(_ preset: SchedulePreset) -> String {
        switch preset {
        case .manualOnly: text("schedule.manual")
        case .atLogin: text("schedule.login")
        case .everyMinutes(let minutes): String(format: text("schedule.everyMinutes"), minutes)
        case .hourly(let minute): String(format: text("schedule.hourly"), minute)
        case .daily(let hour, let minute): String(format: text("schedule.daily"), hour, minute)
        case .weekly(let weekday, let hour, let minute): String(format: text("schedule.weekly"), weekday.localized(language), hour, minute)
        case .monthly(let day, let hour, let minute): String(format: text("schedule.monthly"), day, hour, minute)
        }
    }

    public func runStatusPresentation(for record: RunRecord, now: Date = Date(), timeZone: TimeZone = .current) -> RunStatusPresentation {
        let relative = relativeRunTime(since: record.finishedAt, now: now)
        let label = if record.exitCode == 0 && !record.timedOut {
            String(format: text("job.lastSuccessRelative"), relative)
        } else {
            String(format: text("job.lastFailureRelative"), relative, record.exitCode)
        }
        let detail = String(format: text("job.lastRunAt"), absoluteRunTime(record.finishedAt, timeZone: timeZone))
        return RunStatusPresentation(label: label, detail: detail)
    }

    public func relativeRunTime(since date: Date, now: Date = Date()) -> String {
        let elapsed = max(0, Int(now.timeIntervalSince(date).rounded(.down)))
        switch elapsed {
        case 0..<5:
            return text("time.justNow")
        case 5..<60:
            return String(format: text("time.secondsAgo"), elapsed)
        case 60..<3_600:
            return String(format: text("time.minutesAgo"), max(1, elapsed / 60))
        case 3_600..<86_400:
            return String(format: text("time.hoursAgo"), max(1, elapsed / 3_600))
        default:
            return String(format: text("time.daysAgo"), max(1, elapsed / 86_400))
        }
    }

    public func absoluteRunTime(_ date: Date, timeZone: TimeZone = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: language == .korean ? "ko_KR" : "en_US")
        formatter.timeZone = timeZone
        formatter.dateStyle = .medium
        formatter.timeStyle = .medium
        return formatter.string(from: date)
    }

    public static let table: [AppLanguage: [String: String]] = [
        .english: [
            "app.name": "Automate Scripts",
            "job.added": "Added job '%@'.",
            "job.updated": "Updated job '%@'.",
            "job.removed": "Removed job '%@'.",
            "job.notFound": "Job not found: %@",
            "job.enabled": "Enabled job '%@'.",
            "job.disabled": "Disabled job '%@'.",
            "list.empty": "No jobs yet.",
            "run.completed": "Run completed with exit code %d.",
            "doctor.ok": "Doctor checks passed.",
            "schedule.manual": "Manual only",
            "schedule.login": "At login",
            "schedule.everyMinutes": "Every %d minutes",
            "schedule.hourly": "Hourly at minute %02d",
            "schedule.daily": "Every day at %02d:%02d",
            "schedule.weekly": "Every %@ at %02d:%02d",
            "schedule.monthly": "Every month on day %d at %02d:%02d",
            "sync.dryRun": "Dry run: %@",
            "common.reload": "Reload",
            "common.settings": "Settings",
            "common.quit": "Quit",
            "common.run": "Run",
            "common.edit": "Edit",
            "common.cancel": "Cancel",
            "common.enable": "Enable",
            "common.disable": "Disable",
            "common.save": "Save",
            "common.choose": "Choose",
            "common.logs": "Logs",
            "field.name": "Name",
            "field.command": "Script or command",
            "field.arguments": "Arguments",
            "field.workingDirectory": "Working directory",
            "field.sudo": "Run with administrator privileges",
            "field.sudoHelp": "The app asks through macOS authorization once and reuses that authorization while Automate Scripts is open.",
            "field.inputRequired": "Input answer is required",
            "field.defaultAnswer": "Default input answer",
            "field.answerChoices": "Answer choices",
            "field.defaultChoice": "Default choice",
            "field.answerChoicesHelp": "Use comma-separated label=value pairs. Manual runs with multiple choices ask you to pick one.",
            "panel.jobs": "Jobs",
            "panel.add": "Add Script",
            "panel.settings": "Settings",
            "stat.jobs": "Jobs",
            "stat.enabled": "Enabled",
            "stat.failures": "Failures",
            "stat.running": "Running",
            "empty.title": "No scripts yet",
            "empty.subtitle": "Add your first automation script and choose a friendly schedule preset. No cron syntax required.",
            "editor.addTitle": "Add script",
            "editor.editTitle": "Edit script",
            "editor.subtitle": "Pick the script first. Arguments, folder, and schedule are optional.",
            "editor.advanced": "Advanced options",
            "settings.title": "Settings",
            "settings.subtitle": "Control app behavior and inspect where Automate Scripts stores data.",
            "settings.language": "Language",
            "settings.launchAtLogin": "Launch at login",
            "login.status.enabled": "Launch at login is enabled.",
            "login.status.disabled": "Launch at login is off.",
            "login.status.notRegistered": "Launch at login is not registered yet.",
            "login.status.requiresApproval": "macOS requires approval in Login Items.",
            "login.status.unsupported": "Launch at login is unsupported on this macOS version.",
            "login.status.unknown": "Launch at login status: %@",
            "login.help": "This starts Automate Scripts after user login. It does not install a root daemon or run before login.",
            "login.openSettings": "Open Login Items Settings",
            "login.error": "Could not update launch-at-login: %@",
            "settings.scheduler": "Scheduler",
            "settings.schedulerBackend": "Scheduler backend: LaunchAgent dry-run safe by default",
            "settings.storePath": "Job store",
            "settings.logPath": "Run logs",
            "settings.noCron": "Raw cron expressions are intentionally hidden. Use friendly schedule presets to avoid broken schedules.",
            "settings.backgroundMode": "Run as background menu-bar app",
            "settings.backgroundHelp": "Automate Scripts is configured as a menu-bar utility and does not need to stay in the Dock.",
            "logs.retentionDays": "Stash logs older than %d days",
            "logs.stashNow": "Stash old logs now",
            "logs.stashPath": "Log stash",
            "logs.stashedSummary": "Stashed %d old runs.",
            "logs.title": "Run logs — %@",
            "logs.historyTitle": "Run history — %@",
            "logs.back": "Back",
            "logs.runCount": "%d runs",
            "logs.allRuns": "All runs",
            "logs.selectedRun": "Selected run",
            "logs.duration": "%.1fs",
            "logs.noRuns": "No runs yet",
            "logs.noRunsHelp": "Run this script once to see stdout and stderr here.",
            "logs.empty": "No output captured.",
            "logs.stdout": "stdout",
            "logs.stderr": "stderr",
            "logs.reveal": "Reveal files",
            "footer.safeScheduling": "Friendly schedules only · app-managed LaunchAgents",
            "schedule.picker.title": "Schedule",
            "schedule.kind.manual": "Manual only",
            "schedule.kind.login": "At login",
            "schedule.kind.minutes": "Every N minutes",
            "schedule.kind.hourly": "Hourly",
            "schedule.kind.daily": "Daily",
            "schedule.kind.weekly": "Weekly",
            "schedule.kind.monthly": "Monthly",
            "schedule.interval": "Interval",
            "schedule.time": "Time",
            "schedule.weekday": "Weekday",
            "schedule.day": "Day %d",
            "schedule.cronHidden": "Cron expressions are intentionally hidden. Choose a friendly preset instead.",
            "job.addNew": "Add job",
            "job.delete": "Delete",
            "job.running": "Running…",
            "job.lastFailure": "Last run failed with exit code %d",
            "job.lastSuccess": "Last run succeeded",
            "job.lastFailureRelative": "Ran %@ — failed with exit code %d",
            "job.lastSuccessRelative": "Ran %@ — succeeded",
            "job.lastRunAt": "Last run: %@",
            "job.noRecentRuns": "No recent runs",
            "time.justNow": "just now",
            "time.secondsAgo": "%d seconds ago",
            "time.minutesAgo": "%d minutes ago",
            "time.hoursAgo": "%d hours ago",
            "time.daysAgo": "%d days ago",
            "run.exitCode": "Exit code: %d",
            "run.jobExit": "%@ exited with code %d",
            "run.chooseAnswerTitle": "Choose input answer",
            "run.chooseAnswerMessage": "Select the answer to send to '%@'.",
            "run.stdout": "stdout: %@",
            "run.stderr": "stderr: %@",
            "notification.runSuccess.title": "%@ finished",
            "notification.runSuccess.body": "%@ completed successfully with exit code %d.",
            "notification.runFailure.title": "%@ failed",
            "notification.runFailure.body": "%@ finished with exit code %d.",
            "notification.runTimedOut.body": "%@ timed out before completion with exit code %d.",
            "notification.runStartFailed.title": "%@ could not start",
            "notification.runStartFailed.body": "%@ could not start: %@",
            "sudo.authorizing": "Requesting administrator privileges…",
            "sudo.ready": "Administrator privileges are ready.",
            "status.ready": "Ready",
            "language.english": "English",
            "language.korean": "Korean",
            "update.version": "Version %@",
            "update.idle": "Update check is idle.",
            "update.checking": "Checking for updates…",
            "update.upToDate": "Automate Scripts is up to date.",
            "update.available": "Update %@ is available.",
            "update.button": "Update",
            "update.installing": "Installing %@…",
            "update.noCompatibleAsset": "Update %@ is available, but no compatible download was found.",
            "update.developmentBuild": "Development build; latest release is %@.",
            "update.failed": "Update failed: %@",
            "update.invalidVersion": "Release tag is not a semantic version: %@",
            "update.restartSoon": "Restarting to finish update…",
            "error.rawCronUnsupported": "Raw cron expressions are not supported in the default UX. Use schedule presets."
        ],
        .korean: [
            "app.name": "자동화 스크립트",
            "job.added": "'%@' 작업을 추가했습니다.",
            "job.updated": "'%@' 작업을 수정했습니다.",
            "job.removed": "'%@' 작업을 삭제했습니다.",
            "job.notFound": "작업을 찾을 수 없습니다: %@",
            "job.enabled": "'%@' 작업을 활성화했습니다.",
            "job.disabled": "'%@' 작업을 비활성화했습니다.",
            "list.empty": "아직 작업이 없습니다.",
            "run.completed": "실행이 종료 코드 %d로 완료되었습니다.",
            "doctor.ok": "진단 검사를 통과했습니다.",
            "schedule.manual": "수동 실행만",
            "schedule.login": "로그인 시",
            "schedule.everyMinutes": "매 %d분",
            "schedule.hourly": "매시간 %02d분",
            "schedule.daily": "매일 %02d:%02d",
            "schedule.weekly": "매주 %@ %02d:%02d",
            "schedule.monthly": "매월 %d일 %02d:%02d",
            "sync.dryRun": "드라이런: %@",
            "common.reload": "새로고침",
            "common.settings": "설정",
            "common.quit": "종료",
            "common.run": "실행",
            "common.edit": "편집",
            "common.cancel": "취소",
            "common.enable": "활성화",
            "common.disable": "비활성화",
            "common.save": "저장",
            "common.choose": "선택",
            "common.logs": "로그",
            "field.name": "이름",
            "field.command": "스크립트 또는 명령",
            "field.arguments": "인자",
            "field.workingDirectory": "작업 폴더",
            "field.sudo": "관리자 권한으로 실행",
            "field.sudoHelp": "macOS 권한 창으로 처음 한 번 승인받고 앱이 열려 있는 동안 그 권한을 재사용합니다.",
            "field.inputRequired": "입력 답변 필수",
            "field.defaultAnswer": "기본 입력 답변",
            "field.answerChoices": "답변 선택지",
            "field.defaultChoice": "기본 선택지",
            "field.answerChoicesHelp": "쉼표로 구분한 label=value 형식으로 입력하세요. 선택지가 여러 개인 수동 실행은 실행 전에 선택합니다.",
            "panel.jobs": "작업",
            "panel.add": "스크립트 추가",
            "panel.settings": "설정",
            "stat.jobs": "작업",
            "stat.enabled": "활성",
            "stat.failures": "실패",
            "stat.running": "실행 중",
            "empty.title": "아직 스크립트가 없습니다",
            "empty.subtitle": "첫 자동화 스크립트를 추가하고 쉬운 스케줄 프리셋을 선택하세요. cron 문법은 필요 없습니다.",
            "editor.addTitle": "스크립트 추가",
            "editor.editTitle": "스크립트 편집",
            "editor.subtitle": "먼저 스크립트만 선택하세요. 인자, 폴더, 스케줄은 선택 사항입니다.",
            "editor.advanced": "고급 옵션",
            "settings.title": "설정",
            "settings.subtitle": "앱 동작을 조정하고 Automate Scripts가 데이터를 저장하는 위치를 확인합니다.",
            "settings.language": "언어",
            "settings.launchAtLogin": "로그인 시 실행",
            "login.status.enabled": "로그인 시 실행이 켜져 있습니다.",
            "login.status.disabled": "로그인 시 실행이 꺼져 있습니다.",
            "login.status.notRegistered": "로그인 시 실행이 아직 등록되지 않았습니다.",
            "login.status.requiresApproval": "macOS 로그인 항목에서 승인이 필요합니다.",
            "login.status.unsupported": "이 macOS 버전에서는 로그인 시 실행을 지원하지 않습니다.",
            "login.status.unknown": "로그인 시 실행 상태: %@",
            "login.help": "사용자 로그인 후 Automate Scripts를 시작합니다. root 데몬을 설치하거나 로그인 전에 실행하지 않습니다.",
            "login.openSettings": "로그인 항목 설정 열기",
            "login.error": "로그인 시 실행을 변경할 수 없습니다: %@",
            "settings.scheduler": "스케줄러",
            "settings.schedulerBackend": "스케줄러 백엔드: LaunchAgent 드라이런 기본 안전 모드",
            "settings.storePath": "작업 저장소",
            "settings.logPath": "실행 로그",
            "settings.noCron": "cron 표현식은 의도적으로 숨겨져 있습니다. 쉬운 스케줄 프리셋으로 잘못된 스케줄을 방지하세요.",
            "settings.backgroundMode": "백그라운드 메뉴바 앱으로 실행",
            "settings.backgroundHelp": "Automate Scripts는 메뉴바 유틸리티로 설정되어 Dock에 계속 표시될 필요가 없습니다.",
            "logs.retentionDays": "%d일 지난 로그 stash",
            "logs.stashNow": "오래된 로그 지금 stash",
            "logs.stashPath": "로그 stash",
            "logs.stashedSummary": "오래된 실행 %d개를 stash했습니다.",
            "logs.title": "실행 로그 — %@",
            "logs.historyTitle": "실행 기록 — %@",
            "logs.back": "뒤로",
            "logs.runCount": "%d회 실행",
            "logs.allRuns": "모든 실행 기록",
            "logs.selectedRun": "선택한 실행",
            "logs.duration": "%.1f초",
            "logs.noRuns": "아직 실행 기록이 없습니다",
            "logs.noRunsHelp": "스크립트를 한 번 실행하면 표준 출력과 표준 오류가 여기에 표시됩니다.",
            "logs.empty": "캡처된 출력이 없습니다.",
            "logs.stdout": "표준 출력",
            "logs.stderr": "표준 오류",
            "logs.reveal": "파일 보기",
            "footer.safeScheduling": "쉬운 스케줄만 사용 · 앱 관리 LaunchAgent",
            "schedule.picker.title": "스케줄",
            "schedule.kind.manual": "수동 실행만",
            "schedule.kind.login": "로그인 시",
            "schedule.kind.minutes": "매 N분",
            "schedule.kind.hourly": "매시간",
            "schedule.kind.daily": "매일",
            "schedule.kind.weekly": "매주",
            "schedule.kind.monthly": "매월",
            "schedule.interval": "간격",
            "schedule.time": "시간",
            "schedule.weekday": "요일",
            "schedule.day": "%d일",
            "schedule.cronHidden": "cron 표현식은 숨겨져 있습니다. 쉬운 프리셋을 선택하세요.",
            "job.addNew": "작업 추가",
            "job.delete": "삭제",
            "job.running": "실행 중…",
            "job.lastFailure": "최근 실행 실패: 종료 코드 %d",
            "job.lastSuccess": "최근 실행 성공",
            "job.lastFailureRelative": "%@ 실행 실패: 종료 코드 %d",
            "job.lastSuccessRelative": "%@ 실행 성공",
            "job.lastRunAt": "마지막 실행: %@",
            "job.noRecentRuns": "최근 실행 없음",
            "time.justNow": "방금 전",
            "time.secondsAgo": "%d초 전",
            "time.minutesAgo": "%d분 전",
            "time.hoursAgo": "%d시간 전",
            "time.daysAgo": "%d일 전",
            "run.exitCode": "종료 코드: %d",
            "run.jobExit": "%@ 작업이 종료 코드 %d로 끝났습니다",
            "run.chooseAnswerTitle": "입력 답변 선택",
            "run.chooseAnswerMessage": "'%@' 작업에 보낼 답변을 선택하세요.",
            "run.stdout": "표준 출력: %@",
            "run.stderr": "표준 오류: %@",
            "notification.runSuccess.title": "%@ 완료",
            "notification.runSuccess.body": "%@ 작업이 종료 코드 %d로 성공했습니다.",
            "notification.runFailure.title": "%@ 실패",
            "notification.runFailure.body": "%@ 작업이 종료 코드 %d로 끝났습니다.",
            "notification.runTimedOut.body": "%@ 작업이 시간 초과로 종료 코드 %d를 반환했습니다.",
            "notification.runStartFailed.title": "%@ 시작 실패",
            "notification.runStartFailed.body": "%@ 작업을 시작하지 못했습니다: %@",
            "sudo.authorizing": "관리자 권한을 요청하는 중…",
            "sudo.ready": "관리자 권한이 준비되었습니다.",
            "status.ready": "준비됨",
            "language.english": "영어",
            "language.korean": "한국어",
            "update.version": "버전 %@",
            "update.idle": "업데이트 확인 대기 중입니다.",
            "update.checking": "업데이트 확인 중…",
            "update.upToDate": "Automate Scripts가 최신 버전입니다.",
            "update.available": "%@ 업데이트가 있습니다.",
            "update.button": "업데이트",
            "update.installing": "%@ 설치 중…",
            "update.noCompatibleAsset": "%@ 업데이트가 있지만 호환되는 다운로드를 찾지 못했습니다.",
            "update.developmentBuild": "개발 빌드입니다. 최신 릴리즈는 %@입니다.",
            "update.failed": "업데이트 실패: %@",
            "update.invalidVersion": "릴리즈 태그가 semantic version이 아닙니다: %@",
            "update.restartSoon": "업데이트 완료를 위해 다시 시작합니다…",
            "error.rawCronUnsupported": "기본 UX에서는 cron 표현식을 직접 입력하지 않습니다. 스케줄 프리셋을 사용하세요."
        ]
    ]
}
