//
// SQLite.swift
// https://github.com/stephencelis/SQLite.swift
// Copyright © 2014-2015 Stephen Celis.
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
// THE SOFTWARE.
//

import Foundation

extension Data: Value {

    public static var declaredDatatype: String {
        Blob.declaredDatatype
    }

    public static func fromDatatypeValue(_ dataValue: Blob) -> Data {
        Data(dataValue.bytes)
    }

    public var datatypeValue: Blob {
        withUnsafeBytes { (pointer: UnsafeRawBufferPointer) -> Blob in
            Blob(bytes: pointer.baseAddress!, length: count)
        }
    }

}

extension Date: Value {

    public static var declaredDatatype: String {
        String.declaredDatatype
    }

    public static func fromDatatypeValue(_ stringValue: String) -> Date {
        if let date = fastParse(stringValue) { return date }
        return dateFormatter.date(from: stringValue)!
    }

    public var datatypeValue: String {
        dateFormatter.string(from: self)
    }

}

// MARK: - Fast UTC millisecond parser

// Decoding via `dateFormatter` costs ~45 µs per column (ICU parse) and dominates row
// decoding for large batches; `ISO8601DateFormatter` parses no faster and rejects
// the stored no-suffix shape. The fast path below accepts exactly the canonical
// 23-byte `yyyy-MM-dd'T'HH:mm:ss.SSS` shape written by `dateFormatter` and falls
// back to the legacy formatter for anything else — non-canonical shapes and
// pre-1970 strings (where ICU interprets dates under the Julian calendar before
// 1582) — so observable behavior (including the force-unwrap trap) is unchanged.
// The calendar math is pure integer arithmetic (Howard Hinnant's days_from_civil):
// no shared mutable state, safe for concurrent connections, and pinned to the
// legacy formatter by whole-domain differential tests (1970–9999).
extension Date {

    /// Non-trapping parse of the canonical `yyyy-MM-dd'T'HH:mm:ss.SSS` (UTC) shape;
    /// nil for every other shape. Equivalent to `Date.fromDatatypeValue` on success.
    public static func fastParse(_ string: String) -> Date? {
        let bytes = Array(string.utf8)
        guard bytes.count == 23,
            bytes[4] == 45, bytes[7] == 45, bytes[10] == 84,
            bytes[13] == 58, bytes[16] == 58, bytes[19] == 46
        else { return nil }

        func number(_ range: Range<Int>) -> Int? {
            var value = 0
            for index in range {
                let digit = bytes[index]
                guard digit >= 48, digit <= 57 else { return nil }
                value = value * 10 + Int(digit &- 48)
            }
            return value
        }

        guard let year = number(0..<4), let month = number(5..<7), let day = number(8..<10),
            let hour = number(11..<13), let minute = number(14..<16), let second = number(17..<19),
            let millisecond = number(20..<23)
        else { return nil }

        guard (1...12).contains(month), (1...31).contains(day), day <= days(inYear: year, month: month),
            hour <= 23, minute <= 59, second <= 59, millisecond <= 999
        else { return nil }

        let days = daysFromCivil(year: year, month: month, day: day)
        let seconds = days * 86_400 &+ hour &* 3_600 &+ minute &* 60 &+ second
        guard seconds >= 0 else { return nil }
        return Date(timeIntervalSince1970: TimeInterval(seconds) + TimeInterval(millisecond) / 1_000)
    }

    private static func days(inYear year: Int, month: Int) -> Int {
        let leap = year % 4 == 0 && (year % 100 != 0 || year % 400 == 0)
        return month == 2 ? (leap ? 29 : 28) : 30 + (month + (month > 7 ? 1 : 0)) % 2
    }

    /// Howard Hinnant's `days_from_civil`, days since 1970-01-01 for a proleptic
    /// Gregorian date.
    private static func daysFromCivil(year y0: Int, month: Int, day: Int) -> Int {
        let y = y0 &- (month <= 2 ? 1 : 0)
        let era = (y >= 0 ? y : y - 399) / 400
        let yoe = y - era * 400
        let doy = (153 * (month + (month > 2 ? -3 : 9)) + 2) / 5 + day - 1
        let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
        return era * 146_097 + doe - 719_468
    }

}

/// A global date formatter used to serialize and deserialize `NSDate` objects.
/// If multiple date formats are used in an application’s database(s), use a
/// custom `Value` type per additional format.
public let dateFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSS"
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    return formatter
}()

extension UUID: Value {

    public static var declaredDatatype: String {
        String.declaredDatatype
    }

    public static func fromDatatypeValue(_ stringValue: String) -> UUID {
        UUID(uuidString: stringValue)!
    }

    public var datatypeValue: String {
        uuidString
    }

}

extension URL: Value {

    public static var declaredDatatype: String {
        String.declaredDatatype
    }

    public static func fromDatatypeValue(_ stringValue: String) -> URL {
        URL(string: stringValue)!
    }

    public var datatypeValue: String {
        absoluteString
    }

}
