import Foundation

public enum Weekday: Int, Codable, CaseIterable, Sendable {
    case sunday = 1, monday, tuesday, wednesday, thursday, friday, saturday

    public init?(token: String) {
        switch token.lowercased() {
        case "sun", "sunday", "일", "일요일": self = .sunday
        case "mon", "monday", "월", "월요일": self = .monday
        case "tue", "tuesday", "화", "화요일": self = .tuesday
        case "wed", "wednesday", "수", "수요일": self = .wednesday
        case "thu", "thursday", "목", "목요일": self = .thursday
        case "fri", "friday", "금", "금요일": self = .friday
        case "sat", "saturday", "토", "토요일": self = .saturday
        default: return nil
        }
    }

    public func localized(_ language: AppLanguage) -> String {
        switch (language, self) {
        case (.korean, .sunday): "일요일"
        case (.korean, .monday): "월요일"
        case (.korean, .tuesday): "화요일"
        case (.korean, .wednesday): "수요일"
        case (.korean, .thursday): "목요일"
        case (.korean, .friday): "금요일"
        case (.korean, .saturday): "토요일"
        case (_, .sunday): "Sunday"
        case (_, .monday): "Monday"
        case (_, .tuesday): "Tuesday"
        case (_, .wednesday): "Wednesday"
        case (_, .thursday): "Thursday"
        case (_, .friday): "Friday"
        case (_, .saturday): "Saturday"
        }
    }
}
