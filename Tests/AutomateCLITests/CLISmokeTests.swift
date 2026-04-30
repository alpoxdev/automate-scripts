import AutomateCore
import XCTest

final class CLISmokeTests: XCTestCase {
    func testLocalizerHasCronUnsupportedMessageInBothLanguages() {
        XCTAssertTrue(Localizer(language: .english).text("error.rawCronUnsupported").contains("Raw cron"))
        XCTAssertTrue(Localizer(language: .korean).text("error.rawCronUnsupported").contains("cron"))
    }
}
