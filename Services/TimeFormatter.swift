//
//  TimeFormatter.swift
//  Shaw
//

import Foundation

class TimeFormatter {
    static let shared = TimeFormatter()
    
    private let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter
    }()
    
    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
    
    private init() {}
    
    func relativeTime(from date: Date) -> String {
        let now = Date()
        let calendar = Calendar.current
        
        // If same day, show time only
        if calendar.isDateInToday(date) {
            let timeFormatter = DateFormatter()
            timeFormatter.timeStyle = .short
            return timeFormatter.string(from: date)
        }
        
        // If yesterday
        if calendar.isDateInYesterday(date) {
            return "Yesterday"
        }
        
        // If within last week, show day name
        if let days = calendar.dateComponents([.day], from: date, to: now).day, days < 7 {
            let weekdayFormatter = DateFormatter()
            weekdayFormatter.dateFormat = "EEEE"
            return weekdayFormatter.string(from: date)
        }
        
        // Otherwise use relative formatter
        return relativeFormatter.localizedString(for: date, relativeTo: now)
    }
    
    func fullDate(_ date: Date) -> String {
        return dateFormatter.string(from: date)
    }
}

