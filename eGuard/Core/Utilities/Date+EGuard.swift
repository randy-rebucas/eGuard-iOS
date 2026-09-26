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
