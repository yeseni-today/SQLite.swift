import Dispatch
import XCTest
@testable import SQLite

/// DateCodecTests pins the fast parser to the legacy `dateFormatter`: identical
/// decoded values for the canonical shape across the whole 1970–9999 domain, and
/// a fallback to the legacy path (identical behavior, including its force-unwrap
/// trap) for everything else. The serialization side stays on the legacy
/// formatter — formatting measures ~1 µs and needs no fast path.
class DateCodecTests: XCTestCase {

    /// Deterministic samples (reproducible LCG over the full 1970–9999 domain)
    /// plus exact edges — epoch zero, leap days, the century boundary, year-end
    /// milliseconds, and the 4-digit year limit. Edge dates are built through the
    /// legacy formatter itself so the expected values can never drift.
    static var samples: [Date] {
        var seed: UInt64 = 0x9E37_79B9_7F4A_7C15
        func next() -> UInt64 {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return seed
        }
        let edges = [
            "1970-01-01T00:00:00.000",
            "1970-01-01T00:00:00.001",
            "2024-02-29T00:00:00.000",
            "2024-02-29T23:59:59.999",
            "2100-02-28T23:59:59.999",
            "9996-02-29T12:00:00.000",
            "9999-12-31T23:59:59.999",
            "2050-12-31T23:59:59.999"
        ]
        var dates = edges.compactMap { dateFormatter.date(from: $0) }
        for _ in 0..<10_000 {
            let seconds = Double(next() % 253_402_300_800)   // 1970-01-01 … 9999-12-31
            let millisecond = Double(next() % 1_000) / 1_000.0
            dates.append(Date(timeIntervalSince1970: seconds + millisecond))
        }
        return dates
    }

    func testFastParseAgreesWithLegacyForCanonicalShape() {
        for date in Self.samples {
            let string = dateFormatter.string(from: date)
            guard let fast = Date.fastParse(string) else {
                XCTFail("canonical shape rejected: \(string)")
                continue
            }
            XCTAssertEqual(fast, dateFormatter.date(from: string)!, "parse mismatch for \(string)")
        }
    }

    func testValueRoundTripIsIdempotent() {
        for date in Self.samples {
            let string = date.datatypeValue
            XCTAssertEqual(Date.fromDatatypeValue(string).datatypeValue, string,
                "round trip not idempotent for \(string)")
        }
    }

    func testFastParseRejectsNonCanonicalShapes() {
        let nonCanonical = [
            "2026-11-11T21:16:06",             // missing milliseconds
            "2026-11-11T21:16:06.123Z",        // trailing Z
            "2026-11-11T21:16:06.123456",      // microseconds
            "2026-11-11 21:16:06.123",         // space separator
            "2026-11-11T21:16:06.12",          // two-digit fraction
            "2026-13-11T21:16:06.123",         // month 13
            "2026-00-11T21:16:06.123",         // month 0
            "2026-02-30T21:16:06.123",         // February 30
            "2023-02-29T21:16:06.123",         // non-leap February 29
            "2100-02-29T21:16:06.123",         // century non-leap February 29
            "2026-11-32T21:16:06.123",         // day 32
            "2026-11-00T21:16:06.123",         // day 0
            "2026-11-11T24:16:06.123",         // hour 24
            "2026-11-11T21:60:06.123",         // minute 60
            "2026-11-11T21:16:60.123",         // second 60 (leap second) — falls back to legacy
            "2026-11-11T21:16:06.1000",        // four-digit fraction
            "20x6-11-11T21:16:06.123"          // letter in digits
        ]
        for string in nonCanonical {
            XCTAssertNil(Date.fastParse(string), "non-canonical shape accepted: \(string)")
        }
        // Legal leap-day and regular shapes stay on the fast path.
        XCTAssertNotNil(Date.fastParse("2024-02-29T21:16:06.123"))
        XCTAssertNotNil(Date.fastParse("2100-02-28T21:16:06.123"))
        XCTAssertNotNil(Date.fastParse("2026-11-11T21:16:06.100"))
    }

    /// Before 1970 the legacy formatter interprets strings under the Julian
    /// calendar before 1582 and has implementation-defined negative-epoch edges;
    /// the fast path must refuse the whole domain and delegate.
    func testFastParseFallsBackBeforeEpoch() {
        XCTAssertNil(Date.fastParse("1969-12-31T23:59:59.999"))
        XCTAssertNil(Date.fastParse("1582-10-15T00:00:00.000"))
        XCTAssertNil(Date.fastParse("0001-01-03T00:00:00.000"))
        XCTAssertNotNil(Date.fastParse("1970-01-01T00:00:00.000"))
    }

    func testFastPathPerformance() {
        // Guard against regressions: legacy parse costs ≈45 µs; the integer fast
        // path measures well under 1 µs. The ceiling leaves room for slow CI.
        let string = "2026-11-11T21:16:06.123"
        let start = DispatchTime.now().uptimeNanoseconds
        for _ in 0..<10_000 {
            _ = Date.fastParse(string)
        }
        let average = Double(DispatchTime.now().uptimeNanoseconds - start) / 10_000 / 1_000
        XCTAssertLessThan(average, 10, "fast path regressed: \(average) µs per call")
    }

}
