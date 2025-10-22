import XCTest
@testable import SQLite

class DateAndTimeFunctionsTests: XCTestCase {

    func test_date() {
        assertSQL("date('now')", SQLiteDateFunctions.date("now"))
        assertSQL("date('now', 'localtime')", SQLiteDateFunctions.date("now", "localtime"))
    }

    func test_time() {
        assertSQL("time('now')", SQLiteDateFunctions.time("now"))
        assertSQL("time('now', 'localtime')", SQLiteDateFunctions.time("now", "localtime"))
    }

    func test_datetime() {
        assertSQL("datetime('now')", SQLiteDateFunctions.datetime("now"))
        assertSQL("datetime('now', 'localtime')", SQLiteDateFunctions.datetime("now", "localtime"))
    }

    func test_julianday() {
        assertSQL("julianday('now')", SQLiteDateFunctions.julianday("now"))
        assertSQL("julianday('now', 'localtime')", SQLiteDateFunctions.julianday("now", "localtime"))
    }

    func test_strftime() {
        assertSQL("strftime('%Y-%m-%d', 'now')", SQLiteDateFunctions.strftime("%Y-%m-%d", "now"))
        assertSQL("strftime('%Y-%m-%d', 'now', 'localtime')", SQLiteDateFunctions.strftime("%Y-%m-%d", "now", "localtime"))
    }
}

class DateExtensionTests: XCTestCase {
    func test_time() {
        assertSQL("time('1970-01-01T00:00:00.000')", Date(timeIntervalSince1970: 0).time)
    }

    func test_date() {
        assertSQL("date('1970-01-01T00:00:00.000')", Date(timeIntervalSince1970: 0).date)
    }

    func test_datetime() {
        assertSQL("datetime('1970-01-01T00:00:00.000')", Date(timeIntervalSince1970: 0).datetime)
    }

    func test_julianday() {
        assertSQL("julianday('1970-01-01T00:00:00.000')", Date(timeIntervalSince1970: 0).julianday)
    }
}

class DateExpressionTests: XCTestCase {
    func test_date() {
        assertSQL("date(\"date\")", date.date)
    }

    func test_time() {
        assertSQL("time(\"date\")", date.time)
    }

    func test_datetime() {
        assertSQL("datetime(\"date\")", date.datetime)
    }

    func test_julianday() {
        assertSQL("julianday(\"date\")", date.julianday)
    }
}
