import XCTest
@testable import SQLite

/// DateCodecTests pins the fast parser to the legacy `dateFormatter`: identical
/// decoded values for the canonical shape, and a fallback to the legacy path
/// (identical behavior, including its force-unwrap trap) for everything else.
/// The serialization side stays on the legacy formatter — formatting measures
/// ~1 µs and needs no fast path.
class DateCodecTests: XCTestCase {

    /// Deterministic samples (reproducible LCG): random instants 1970–2099 plus
    /// exact edges — epoch zero, leap days, century boundary, millisecond edges,
    /// and the 4-digit year limit.
    static var samples: [Date] {
        var seed: UInt64 = 0x9E37_79B9_7F4A_7C15
        func next() -> UInt64 {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return seed
        }
        var dates: [Date] = [
            Date(timeIntervalSince1970: 0),                       // 1970-01-01T00:00:00.000 (domain edge)
            Date(timeIntervalSince1970: 0.001),
            Date(timeIntervalSince1970: 1_709_164_800),           // 2024-02-29T00:00:00.000 (leap)
            Date(timeIntervalSince1970: 4_107_542_368),           // 2100-02-29 doesn't exist (century)
            Date(timeIntervalSince1970: 2_556_142_399.999),       // 2050-12-31T23:59:59.999
            Date(timeIntervalSince1970: 1_735_689_599.999),
            Date(timeIntervalSince1970: 1_735_689_599.000),
            Date(timeIntervalSince1970: 1_735_689_599.123),
            Date(timeIntervalSince1970: 253_402_300_799.999),     // 9999-12-31T23:59:59.999
        ]
        for _ in 0..<10_000 {
            let seconds = Double(next() % 4_102_752_000)          // 1970-01-01 … 2099-12-31
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
            "2026-11-32T21:16:06.123",         // day 32
            "2026-11-00T21:16:06.123",         // day 0
            "2026-11-11T24:16:06.123",         // hour 24
            "2026-11-11T21:60:06.123",         // minute 60
            "2026-11-11T21:16:60.123",         // second 60 (leap second) — falls back to legacy
            "2026-11-11T21:16:06.1000",        // four-digit fraction
            "20x6-11-11T21:16:06.123",         // letter in digits
        ]
        for string in nonCanonical {
            XCTAssertNil(Date.fastParse(string), "non-canonical shape accepted: \(string)")
        }
        // Legal leap-day and regular shapes stay on the fast path.
        XCTAssertNotNil(Date.fastParse("2024-02-29T21:16:06.123"))
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
        // Guard against regressions: legacy parse costs ≈45 µs; the fast path
        // (byte validation + fixed-UTC Calendar) must stay well under 5 µs.
        let string = "2026-11-11T21:16:06.123"
        let start = CFAbsoluteTimeGetCurrent()
        for _ in 0..<10_000 {
            _ = Date.fastParse(string)
        }
        let average = (CFAbsoluteTimeGetCurrent() - start) / 10_000 * 1_000_000
        XCTAssertLessThan(average, 5, "fast path regressed: \(average) µs per call")
    }

}
