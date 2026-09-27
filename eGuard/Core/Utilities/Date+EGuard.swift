import Foundation

nonisolated extension Date {
    /// "Today, 7:42 PM", "Yesterday, 7:42 PM", or "Sep 24, 7:42 PM".
    func verifiedDescription(relativeTo now: Date = .now, calendar: Calendar = .current) -> String {
        let time = formatted(date: .omitted, time: .shortened)
        if calendar.isDate(self, inSameDayAs: now) {
            return "Today, \(time)"
        }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now),
           calendar.isDate(self, inSameDayAs: yesterday) {
            return "Yesterday, \(time)"
        }
        return "\(formatted(.dateTime.month(.abbreviated).day())), \(time)"
    }

    /// "2 hours ago", "Yesterday, 8:14 PM", or "Sep 24, 8:14 PM".
    func relativeDescription(relativeTo now: Date = .now, calendar: Calendar = .current) -> String {
        let elapsed = now.timeIntervalSince(self)
        if elapsed < 60 { return "Just now" }
        if elapsed < 3600 {
            let minutes = Int(elapsed / 60)
            return minutes == 1 ? "1 minute ago" : "\(minutes) minutes ago"
        }
        if calendar.isDate(self, inSameDayAs: now) {
            let hours = Int(elapsed / 3600)
            return hours == 1 ? "1 hour ago" : "\(hours) hours ago"
        }
        return verifiedDescription(relativeTo: now, calendar: calendar)
    }

    /// "Today", "Yesterday", or "Sep 24" for grouping lists by day.
    func dayGroupTitle(relativeTo now: Date = .now, calendar: Calendar = .current) -> String {
        if calendar.isDate(self, inSameDayAs: now) { return "Today" }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now),
           calendar.isDate(self, inSameDayAs: yesterday) {
            return "Yesterday"
        }
        return formatted(.dateTime.month(.abbreviated).day())
    }

    /// "Good morning", "Good afternoon", or "Good evening".
    func greeting(calendar: Calendar = .current) -> String {
        let hour = calendar.component(.hour, from: self)
        switch hour {
        case 5..<12: return "Good morning"
        case 12..<17: return "Good afternoon"
        default: return "Good evening"
        }
    }
}
