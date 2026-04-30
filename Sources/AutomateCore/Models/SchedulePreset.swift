import Foundation

public enum SchedulePreset: Codable, Equatable, Sendable {
    case manualOnly
    case atLogin
    case everyMinutes(Int)
    case hourly(minute: Int)
    case daily(hour: Int, minute: Int)
    case weekly(weekday: Weekday, hour: Int, minute: Int)
    case monthly(day: Int, hour: Int, minute: Int)

    private enum Kind: String, Codable { case manualOnly, atLogin, everyMinutes, hourly, daily, weekly, monthly }
    private enum CodingKeys: String, CodingKey { case kind, intervalMinutes, minute, hour, weekday, day }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        switch try c.decode(Kind.self, forKey: .kind) {
        case .manualOnly: self = .manualOnly
        case .atLogin: self = .atLogin
        case .everyMinutes: self = .everyMinutes(try c.decode(Int.self, forKey: .intervalMinutes))
        case .hourly: self = .hourly(minute: try c.decode(Int.self, forKey: .minute))
        case .daily: self = .daily(hour: try c.decode(Int.self, forKey: .hour), minute: try c.decode(Int.self, forKey: .minute))
        case .weekly:
            self = .weekly(
                weekday: try c.decode(Weekday.self, forKey: .weekday),
                hour: try c.decode(Int.self, forKey: .hour),
                minute: try c.decode(Int.self, forKey: .minute)
            )
        case .monthly: self = .monthly(day: try c.decode(Int.self, forKey: .day), hour: try c.decode(Int.self, forKey: .hour), minute: try c.decode(Int.self, forKey: .minute))
        }
        try validate()
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .manualOnly: try c.encode(Kind.manualOnly, forKey: .kind)
        case .atLogin: try c.encode(Kind.atLogin, forKey: .kind)
        case .everyMinutes(let interval):
            try c.encode(Kind.everyMinutes, forKey: .kind); try c.encode(interval, forKey: .intervalMinutes)
        case .hourly(let minute):
            try c.encode(Kind.hourly, forKey: .kind); try c.encode(minute, forKey: .minute)
        case .daily(let hour, let minute):
            try c.encode(Kind.daily, forKey: .kind); try c.encode(hour, forKey: .hour); try c.encode(minute, forKey: .minute)
        case .weekly(let weekday, let hour, let minute):
            try c.encode(Kind.weekly, forKey: .kind); try c.encode(weekday, forKey: .weekday); try c.encode(hour, forKey: .hour); try c.encode(minute, forKey: .minute)
        case .monthly(let day, let hour, let minute):
            try c.encode(Kind.monthly, forKey: .kind); try c.encode(day, forKey: .day); try c.encode(hour, forKey: .hour); try c.encode(minute, forKey: .minute)
        }
    }

    public func validate() throws {
        func validHour(_ hour: Int) -> Bool { (0...23).contains(hour) }
        func validMinute(_ minute: Int) -> Bool { (0...59).contains(minute) }
        switch self {
        case .manualOnly, .atLogin: return
        case .everyMinutes(let interval):
            guard [5, 10, 15, 30].contains(interval) else { throw ScheduleValidationError.unsupportedInterval(interval) }
        case .hourly(let minute):
            guard validMinute(minute) else { throw ScheduleValidationError.invalidMinute(minute) }
        case .daily(let hour, let minute), .weekly(_, let hour, let minute):
            guard validHour(hour) else { throw ScheduleValidationError.invalidHour(hour) }
            guard validMinute(minute) else { throw ScheduleValidationError.invalidMinute(minute) }
        case .monthly(let day, let hour, let minute):
            guard (1...28).contains(day) else { throw ScheduleValidationError.invalidMonthDay(day) }
            guard validHour(hour) else { throw ScheduleValidationError.invalidHour(hour) }
            guard validMinute(minute) else { throw ScheduleValidationError.invalidMinute(minute) }
        }
    }
}

public enum ScheduleValidationError: Error, Equatable, LocalizedError, Sendable {
    case unsupportedInterval(Int)
    case invalidMinute(Int)
    case invalidHour(Int)
    case invalidMonthDay(Int)

    public var errorDescription: String? {
        switch self {
        case .unsupportedInterval(let value): "Unsupported interval: \(value). Use one of 5, 10, 15, 30."
        case .invalidMinute(let value): "Invalid minute: \(value). Use 0...59."
        case .invalidHour(let value): "Invalid hour: \(value). Use 0...23."
        case .invalidMonthDay(let value): "Invalid month day: \(value). Use 1...28."
        }
    }
}
