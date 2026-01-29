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
        case .task(let t, _): return String(describing: t.persistentModelID)
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
    
    // Preferences (Persisted)
    var dayStartHour: Int {
        didSet { UserDefaults.standard.set(dayStartHour, forKey: "dayStartHour") }
    }
    var dayEndHour: Int {
        didSet { UserDefaults.standard.set(dayEndHour, forKey: "dayEndHour") }
    }
    
    private let service = GTLRCalendarService()
    
    init() {
        self.dayStartHour = UserDefaults.standard.object(forKey: "dayStartHour") as? Int ?? 9
        self.dayEndHour = UserDefaults.standard.object(forKey: "dayEndHour") as? Int ?? 17
    }
    
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
    
    // UPDATED: Accepts specific Date range for rolling windows
    func generateSchedule(with tasks: [LatticeTask], rangeStart: Date, rangeEnd: Date) {
        let calendar = Calendar.current
        var mixedSchedule: [CalendarItem] = []
        
        // 1. Add Fixed Events (Filter by range)
        for event in rawGoogleEvents {
            if let start = event.start?.dateTime?.date, start >= rangeStart && start < rangeEnd {
                mixedSchedule.append(.event(event))
            }
        }
        
        // 2. Sort Tasks by Deadline (Deterministic Tie-Breaker)
        let sortedTasks = tasks.sorted {
            if $0.targetDate != $1.targetDate {
                return $0.targetDate < $1.targetDate
            }
            // Tie-breaker: Use persistent ID string representation (or creation date if available)
            // Assuming stable sort is needed regardless of active/archive status.
            return String(describing: $0.persistentModelID) < String(describing: $1.persistentModelID)
        }
        
        // 3. Define Day Boundaries using passed range
        let dayStart = rangeStart
        let dayEnd = rangeEnd
        
        // 4. Flatten Google Events (Fixes Overlap Bug)
        var rawRanges: [(Date, Date)] = []
        for event in rawGoogleEvents {
            if let start = event.start?.dateTime?.date, let end = event.end?.dateTime?.date {
                // Only consider events relevant to our window
                if end > rangeStart && start < rangeEnd {
                    rawRanges.append((start, end))
                }
            }
        }
        let busyRanges = flattenRanges(rawRanges)
        
        // 5. Scan for Gaps
        // Start scheduling from 'now' or start of range.
        // Truncate 'now' to minute to ensure stable keys for slotOffsets (ignoring seconds)
        let now = Date()
        let cleanNow = calendar.date(bySetting: .second, value: 0, of: now) ?? now
        var currentTime = dateMax(dayStart, cleanNow)
        
        // Round up to next 15 min
        let minute = calendar.component(.minute, from: currentTime)
        let remainder = 15 - (minute % 15)
        if remainder > 0 && remainder < 15 {
             currentTime = calendar.date(byAdding: .minute, value: remainder, to: currentTime)!
        }
        
        // Ensure seconds are 0
        currentTime = calendar.date(bySetting: .second, value: 0, of: currentTime) ?? currentTime
        currentTime = calendar.date(bySetting: .nanosecond, value: 0, of: currentTime) ?? currentTime

        var usedTaskIDs = Set<PersistentIdentifier>()
        
        while currentTime < dayEnd {
             // CONSTRAINT CHECK:
             let currentHour = calendar.component(.hour, from: currentTime)
             
             // If before start hour, jump to start hour of TODAY (or current day being scanned)
             if currentHour < dayStartHour {
                 // Set to dayStartHour:00
                 currentTime = calendar.date(bySettingHour: dayStartHour, minute: 0, second: 0, of: currentTime)!
                 // If we jumped backwards (rare if we started at 'now' which was > start), fix it?
                 // Actually if 'now' is 7am and start is 9am, we jump to 9am. Correct.
                 // If 'now' is 8pm and start is 9am... we are > start.
             }
             // If after end hour, jump to start hour of TOMORROW
             else if currentHour >= dayEndHour {
                 let tomorrow = calendar.date(byAdding: .day, value: 1, to: currentTime)!
                 currentTime = calendar.date(bySettingHour: dayStartHour, minute: 0, second: 0, of: tomorrow)!
                 continue
             }
            
            // Check overlap
            if let overlap = busyRanges.first(where: { $0.0 <= currentTime && $0.1 > currentTime }) {
                currentTime = overlap.1
                continue
            }
            
            let nextBusyStart = busyRanges.first(where: { $0.0 > currentTime })?.0 ?? dayEnd
            // ALSO cap gap by End of Day logic?
            // If nextBusyStart is tomorrow, but we must stop at dayEndHour...
            // Logic handled by loop check + 'after end hour' check next iteration?
            // Actually, if we schedule a task that goes past dayEndHour, is that allowed?
            // Preferably not.
            
            // Determine effective gap end
            var effectiveGapEnd = nextBusyStart
            
            // Calculate time until dayEndHour for current day
            if let endOfWindow = calendar.date(bySettingHour: dayEndHour, minute: 0, second: 0, of: currentTime) {
                // If endOfWindow is in past relative to currentTime (e.g. we are at 8pm, end is 5pm), loop handles it above.
                // If we are at 2pm, end is 5pm.
                if endOfWindow > currentTime {
                    effectiveGapEnd = min(nextBusyStart, endOfWindow)
                }
            }
            
            let gapDuration = effectiveGapEnd.timeIntervalSince(currentTime)
            
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
                    
                    return fitsInGap && isUnused
            }
            
            if !candidates.isEmpty {
                let offset = slotOffsets[currentTime] ?? 0
                let selectedIndex = offset % candidates.count
                let selectedTask = candidates[selectedIndex]
                
                mixedSchedule.append(.task(selectedTask, currentTime))
                usedTaskIDs.insert(selectedTask.persistentModelID)
                
                // Advance time (Duration only, no buffer)
                currentTime = currentTime.addingTimeInterval(Double(selectedTask.durationMinutes) * 60)
            } else {
                // No task fits, step forward 30m
                currentTime = currentTime.addingTimeInterval(1800)
            }
        }
        
        self.dailySchedule = mixedSchedule
    }
    
    // Helper to merge overlapping events
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
    
    // --- UNDO SYSTEM ---
    enum UndoAction {
        case swipeRight(Date)
        case swipeLeft(Date)
        case archive(PersistentIdentifier)
    }
    
    var undoStack: [UndoAction] = []
    
    func registerUndo(_ action: UndoAction) {
        undoStack.append(action)
    }
    
    func undo(context: ModelContext) -> Bool {
        guard let action = undoStack.popLast() else { return false }
        
        switch action {
        case .swipeRight(let date):
            // Revert swipe right (decrement offset)
            if let count = slotOffsets[date], count > 0 {
                slotOffsets[date] = count - 1
            }
            return true
            
        case .swipeLeft(let date):
            // Revert swipe left (unblock slot)
            blockedSlots.remove(date)
            return true
            
        case .archive(let id):
            // Revert archive (Fetch task and unarchive)
            // We need to find the task by ID.
            // Since we can't easily query by ID synchronously without descriptors or loop...
            // We rely on the caller or context to help? 
            // ModelContext doesn't have a simple "fetch by ID" without a descriptor.
            // However, we can use a FetchDescriptor.
            let descriptor = FetchDescriptor<LatticeTask>(predicate: #Predicate { $0.persistentModelID == id })
            if let task = try? context.fetch(descriptor).first {
                task.isArchived = false
                return true
            }
            return false
        }
    }
    
    // --- ACTIONS ---
    func swipeRight(on slotTime: Date) {
        let current = slotOffsets[slotTime] ?? 0
        slotOffsets[slotTime] = current + 1
        registerUndo(.swipeRight(slotTime))
    }
    
    func swipeLeft(on slotTime: Date) {
        blockedSlots.insert(slotTime)
        registerUndo(.swipeLeft(slotTime))
    }
    
    func resetDailyState() {
            slotOffsets.removeAll()
            blockedSlots.removeAll()
            undoStack.removeAll()
    }
    
    func signOut() {
        GIDSignIn.sharedInstance.signOut()
        user = nil
        rawGoogleEvents = []
        dailySchedule = []
        resetDailyState()
    }
    
    private func dateMax(_ d1: Date, _ d2: Date) -> Date {
        return d1 > d2 ? d1 : d2
    }
}
