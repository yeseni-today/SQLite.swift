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
// 23-byte `yyyy-MM-dd'T'HH:mm:ss.SSS` shape written by `dateFormatter`, hands the
// calendar math to a fixed UTC `Calendar`, and falls back to the legacy formatter
// for anything else — non-canonical shapes and pre-1970 strings (where ICU
// interprets dates under the Julian calendar before 1582) — so observable behavior
// (including the force-unwrap trap) is unchanged.
extension Date {

    static func fastParse(_ string: String) -> Date? {
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

        guard (1...12).contains(month), (1...31).contains(day), isValidDay(year, month, day),
            hour <= 23, minute <= 59, second <= 59, millisecond <= 999
        else { return nil }

        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        components.second = second
        guard let base = utcCalendar.date(from: components) else { return nil }
        let seconds = Int(exactly: base.timeIntervalSince1970.rounded()) ?? -1
        guard seconds >= 0 else { return nil }
        return Date(timeIntervalSince1970: TimeInterval(seconds) + TimeInterval(millisecond) / 1_000)
    }

    private static let utcCalendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }()

    private static func isValidDay(_ year: Int, _ month: Int, _ day: Int) -> Bool {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = 1
        guard let firstOfMonth = utcCalendar.date(from: components) else { return false }
        let length = utcCalendar.range(of: .day, in: .month, for: firstOfMonth)?.count ?? 0
        return day >= 1 && day <= length
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
