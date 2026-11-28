/*
 * Atoll (DynamicIsland)
 * Copyright (C) 2024-2026 Atoll Contributors
 *
 * Originally from boring.notch project
 * Modified and adapted for Atoll (DynamicIsland)
 * See NOTICE for details.
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program. If not, see <https://www.gnu.org/licenses/>.
 */

import Foundation
import os

/// Shared `DateFormatter`s for hot paths such as SwiftUI bodies, so a formatter
/// isn't allocated per cell per render. Formatters use the current locale and
/// time zone, so the cache is dropped whenever either changes.
enum CachedDateFormatter {
    private static let storage = OSAllocatedUnfairLock(uncheckedState: [String: DateFormatter]())
    private static let invalidationObservers: [NSObjectProtocol] = [
        NSLocale.currentLocaleDidChangeNotification,
        .NSSystemTimeZoneDidChange
    ].map { name in
        NotificationCenter.default.addObserver(forName: name, object: nil, queue: nil) { _ in
            storage.withLockUnchecked { $0.removeAll() }
        }
    }

    static func formatter(_ key: String, configure: (DateFormatter) -> Void) -> DateFormatter {
        _ = invalidationObservers
        return storage.withLockUnchecked { cache in
            if let cached = cache[key] { return cached }
            let formatter = DateFormatter()
            configure(formatter)
            cache[key] = formatter
            return formatter
        }
    }

    static func string(from date: Date, format: String) -> String {
        formatter(format) { $0.dateFormat = format }.string(from: date)
    }
}

extension Date {
    static var yesterday: Date { return Date().dayBefore }
    static var tomorrow:  Date { return Date().dayAfter }
    var dayBefore: Date {
        return Calendar.current.date(byAdding: .day, value: -1, to: noon)!
    }
    var dayAfter: Date {
        return Calendar.current.date(byAdding: .day, value: 1, to: noon)!
    }
    var noon: Date {
        return Calendar.current.date(bySettingHour: 12, minute: 0, second: 0, of: self)!
    }
    
    var date: String {
        CachedDateFormatter.string(from: self, format: "dd")
    }
    
    var month: String {
        CachedDateFormatter.string(from: self, format: "MMMM")
    }
    
    func dayOfTheWeek(dayOfWeek: Int) -> String {
        let date = Calendar.current.date(bySetting: .weekday, value: dayOfWeek, of: self) ?? self
        return CachedDateFormatter.string(from: date, format: "EEE")
    }
}

extension NSSize {
    var s: String { "\(width.i)×\(height.i)" }
    
    var aspectRatio: Double {
        width / height
    }
    func scaled(by factor: Double) -> CGSize {
        CGSize(width: (width * factor).evenInt, height: (height * factor).evenInt)
    }
    
}

extension Int {
    var s: String {
        String(self)
    }
    var d: Double {
        Double(self)
    }
}

extension Double {
    @inline(__always) @inlinable var intround: Int {
        rounded().i
    }
    
    @inline(__always) @inlinable var i: Int {
        Int(self)
    }
    
    var evenInt: Int {
        let x = intround
        return x + x % 2
    }
}

extension CGFloat {
    @inline(__always) @inlinable var intround: Int {
        rounded().i
    }
    
    @inline(__always) @inlinable var i: Int {
        Int(self)
    }
    
    var evenInt: Int {
        let x = intround
        return x + x % 2
    }
}
