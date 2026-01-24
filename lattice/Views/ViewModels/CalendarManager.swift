import Foundation
import SwiftUI
import GoogleSignIn
import GoogleAPIClientForREST_Calendar
import SwiftData

enum CalendarItem: Identifiable {
    case event(GTLRCalendar_Event)
    case task(LatticeTask, Date)
    
    var id: String {
        switch self {
        case .event(let e): return e.identifier ?? UUID().uuidString
        case .task(let t, let d): return "\(t.persistentModelID)-\(d)"
        }
    }
}

@Observable
class CalendarManager {
    var user: GIDGoogleUser?
    var rawGoogleEvents: [GTLRCalendar_Event] = []
    var dailySchedule: [CalendarItem] = []
    
    // Interaction State
    var slotOffsets: [Date: Int] = [:]
    var blockedSlots: Set<Date> = []
    
    private let service = GTLRCalendarService()
    
    // --- AUTH & FETCH (Unchanged) ---
    func checkPreviousSignIn() {
        GIDSignIn.sharedInstance.restorePreviousSignIn { user, error in
            if let user = user { self.setup(with: user); self.fetchTodayEvents() }
        }
    }
    
    func setup(with user: GIDGoogleUser) {
        self.user = user
        self.service.authorizer = user.fetcherAuthorizer
    }
    
    func fetchTodayEvents() {
        guard user != nil else { return }
        let query = GTLRCalendarQuery_EventsList.query(withCalendarId: "primary")
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: Date())
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!
        
        query.timeMin = GTLRDateTime(date: startOfDay)
        query.timeMax = GTLRDateTime(date: endOfDay)
        query.singleEvents = true
        query.orderBy = kGTLRCalendarOrderByStartTime
        
        service.executeQuery(query) { ticket, result, error in
            if let list = result as? GTLRCalendar_Events, let items = list.items {
                DispatchQueue.main.async {
                    self.rawGoogleEvents = items
                }
            }
        }
    }
    
    // UPDATED: Accepts start/end hour to filter the day's timeline
    func generateSchedule(with tasks: [LatticeTask], dayStartHour: Int, dayEndHour: Int) {
        let calendar = Calendar.current
        var mixedSchedule: [CalendarItem] = []
        
        // 1. Add Fixed Events
        for event in rawGoogleEvents {
            if let start = event.start?.dateTime?.date, calendar.isDateInToday(start) {
                mixedSchedule.append(.event(event))
            }
        }
        
        // 2. Sort Tasks by Deadline
        let sortedTasks = tasks.sorted {
            ($0.targetDate) < ($1.targetDate)
        }
        
        // 3. Define Day Boundaries using CUSTOM SETTINGS
        // Ensure end is always at least 1 hour after start
        let safeEndHour = max(dayEndHour, dayStartHour + 1)
        
        let dayStart = calendar.date(bySettingHour: dayStartHour, minute: 0, second: 0, of: Date())!
        let dayEnd = calendar.date(bySettingHour: safeEndHour, minute: 0, second: 0, of: Date())!
        
        // 4. Flatten Google Events (Fixes Overlap Bug)
        var rawRanges: [(Date, Date)] = []
        for event in rawGoogleEvents {
            if let start = event.start?.dateTime?.date, let end = event.end?.dateTime?.date {
                rawRanges.append((start, end))
            }
        }
        let busyRanges = flattenRanges(rawRanges)
        
        // 5. Scan for Gaps
        var currentTime = dayStart
        // Don't schedule in the past if today
        if calendar.isDateInToday(Date()) && currentTime < Date() {
            currentTime = Date()
        }
        
        // Round up to next 15 min
        let minute = calendar.component(.minute, from: currentTime)
        let remainder = 15 - (minute % 15)
        if remainder < 15 {
            currentTime = calendar.date(byAdding: .minute, value: remainder, to: currentTime)!
        }

        var usedTaskIDs = Set<PersistentIdentifier>()
        
        while currentTime < dayEnd {
            // Check overlap
            if let overlap = busyRanges.first(where: { $0.0 <= currentTime && $0.1 > currentTime }) {
                currentTime = overlap.1
                continue
            }
            
            let nextBusyStart = busyRanges.first(where: { $0.0 > currentTime })?.0 ?? dayEnd
            let gapDuration = nextBusyStart.timeIntervalSince(currentTime)
            
            // IMPROVED BLOCK CHECK: Check if any blocked slot falls within the current hour
            if blockedSlots.contains(where: { calendar.isDate($0, equalTo: currentTime, toGranularity: .hour) }) {
                currentTime = calendar.date(byAdding: .hour, value: 1, to: currentTime)!
                continue
            }
                
            // Find candidates
            let candidates = sortedTasks.filter { task in
                    let taskDuration = Double(task.durationMinutes) * 60
                    let fitsInGap = taskDuration <= gapDuration
                    let isUnused = !usedTaskIDs.contains(task.persistentModelID)
                    
                    // If it's already archived, we still want it to "show up" where it was originally placed
                    // OR simply include it in the pool.
                    return fitsInGap && isUnused
            }
            
            if !candidates.isEmpty {
                let offset = slotOffsets[currentTime] ?? 0
                let selectedIndex = offset % candidates.count
                let selectedTask = candidates[selectedIndex]
                
                mixedSchedule.append(.task(selectedTask, currentTime))
                usedTaskIDs.insert(selectedTask.persistentModelID)
                
                // Advance time (Duration + 15m Buffer)
                currentTime = currentTime.addingTimeInterval(Double(selectedTask.durationMinutes) * 60 + 900)
            } else {
                // No task fits, step forward 30m
                currentTime = currentTime.addingTimeInterval(1800)
            }
        }
        
        self.dailySchedule = mixedSchedule
    }
    
    // Helper to merge overlapping events (e.g. 2-3pm and 2:30-3:30pm -> 2-3:30pm)
    private func flattenRanges(_ ranges: [(Date, Date)]) -> [(Date, Date)] {
        guard !ranges.isEmpty else { return [] }
        let sorted = ranges.sorted { $0.0 < $1.0 }
        var result: [(Date, Date)] = [sorted[0]]
        
        for i in 1..<sorted.count {
            let current = sorted[i]
            let last = result.last!
            
            if current.0 < last.1 {
                // Overlap detected: Extend the last block if needed
                result[result.count - 1] = (last.0, max(last.1, current.1))
            } else {
                // No overlap, add new block
                result.append(current)
            }
        }
        return result
    }
    
    // --- ACTIONS ---
    func swipeRight(on slotTime: Date) {
        let current = slotOffsets[slotTime] ?? 0
        slotOffsets[slotTime] = current + 1
    }
    
    func swipeLeft(on slotTime: Date) {
        blockedSlots.insert(slotTime)
    }
    
    func resetDailyState() {
            slotOffsets.removeAll()
            blockedSlots.removeAll()
    }
}
