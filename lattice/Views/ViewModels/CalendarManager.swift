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

// Model for Google Calendar entries
struct GoogleCalendarEntry: Identifiable, Hashable {
    let id: String
    let summary: String
    let colorHex: String?
    let isPrimary: Bool
    
    var displayColor: Color {
        guard let hex = colorHex else { return .blue }
        return Color(hex: hex) ?? .blue
    }
}

extension Color {
    init?(hex: String) {
        var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        hexSanitized = hexSanitized.replacingOccurrences(of: "#", with: "")
        
        var rgb: UInt64 = 0
        guard Scanner(string: hexSanitized).scanHexInt64(&rgb) else { return nil }
        
        let r = Double((rgb & 0xFF0000) >> 16) / 255.0
        let g = Double((rgb & 0x00FF00) >> 8) / 255.0
        let b = Double(rgb & 0x0000FF) / 255.0
        
        self.init(red: r, green: g, blue: b)
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
    
    // Track scheduled task placements to prevent rearrangement on refresh
    // Maps task PersistentIdentifier -> scheduled start time
    var scheduledTaskPlacements: [PersistentIdentifier: Date] = [:]
    
    // Calendar Selection
    var availableCalendars: [GoogleCalendarEntry] = []
    var selectedCalendarIds: Set<String> {
        didSet {
            UserDefaults.standard.set(Array(selectedCalendarIds), forKey: "selectedCalendarIds")
        }
    }
    
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
        
        // Load saved calendar selection
        if let savedIds = UserDefaults.standard.array(forKey: "selectedCalendarIds") as? [String] {
            self.selectedCalendarIds = Set(savedIds)
        } else {
            // Default to primary calendar
            self.selectedCalendarIds = ["primary"]
        }
    }
    
    // --- AUTH & FETCH (Unchanged) ---
    func checkPreviousSignIn() {
        GIDSignIn.sharedInstance.restorePreviousSignIn { user, error in
            if let user = user {
                self.setup(with: user)
                self.fetchCalendarList()
                self.fetchTodayEvents()
            }
        }
    }
    
    func setup(with user: GIDGoogleUser) {
        self.user = user
        self.service.authorizer = user.fetcherAuthorizer
    }
    
    // Fetch list of all available calendars
    func fetchCalendarList() {
        guard user != nil else { return }
        
        let query = GTLRCalendarQuery_CalendarListList.query()
        
        service.executeQuery(query) { ticket, result, error in
            if let error = error { return }
            
            if let list = result as? GTLRCalendar_CalendarList, let items = list.items {
                DispatchQueue.main.async {
                    self.availableCalendars = items.compactMap { entry in
                        guard let id = entry.identifier, let summary = entry.summary else { return nil }
                        return GoogleCalendarEntry(
                            id: id,
                            summary: summary,
                            colorHex: entry.backgroundColor,
                            isPrimary: entry.primary?.boolValue ?? false
                        )
                    }
                    
                    // If no calendars selected yet, default to primary
                    if self.selectedCalendarIds.isEmpty || self.selectedCalendarIds == ["primary"] {
                        if let primaryCal = self.availableCalendars.first(where: { $0.isPrimary }) {
                            self.selectedCalendarIds = [primaryCal.id]
                        } else if let firstCal = self.availableCalendars.first {
                            self.selectedCalendarIds = [firstCal.id]
                        }
                    }
                }
            }
        }
    }
    
    // Toggle calendar selection
    func toggleCalendarSelection(id: String) {
        if selectedCalendarIds.contains(id) {
            // Don't allow deselecting the last calendar
            if selectedCalendarIds.count > 1 {
                selectedCalendarIds.remove(id)
            }
        } else {
            selectedCalendarIds.insert(id)
        }
    }
    
    func fetchTodayEvents() {
        guard user != nil else { return }
        
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: Date())
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!
        
        // Clear existing events before fetching
        var allEvents: [GTLRCalendar_Event] = []
        let group = DispatchGroup()
        
        for calendarId in selectedCalendarIds {
            group.enter()
            
            let query = GTLRCalendarQuery_EventsList.query(withCalendarId: calendarId)
            query.timeMin = GTLRDateTime(date: startOfDay)
            query.timeMax = GTLRDateTime(date: endOfDay)
            query.singleEvents = true
            query.orderBy = kGTLRCalendarOrderByStartTime
            
            service.executeQuery(query) { ticket, result, error in
                if let list = result as? GTLRCalendar_Events, let items = list.items {
                    DispatchQueue.main.async {
                        allEvents.append(contentsOf: items)
                    }
                }
                group.leave()
            }
        }
        
        group.notify(queue: .main) {
            // Sort events by start time
            self.rawGoogleEvents = allEvents.sorted { e1, e2 in
                let d1 = e1.start?.dateTime?.date ?? e1.start?.date?.date ?? Date.distantFuture
                let d2 = e2.start?.dateTime?.date ?? e2.start?.date?.date ?? Date.distantFuture
                return d1 < d2
            }
        }
    }
    
    // UPDATED: Accepts specific Date range for rolling windows
    // Now preserves task placements to prevent rearrangement on refresh
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
            return String(describing: $0.persistentModelID) < String(describing: $1.persistentModelID)
        }
        
        // 3. Define Day Boundaries using passed range
        let dayStart = rangeStart
        let dayEnd = rangeEnd
        
        // 4. Flatten Google Events (Fixes Overlap Bug)
        var rawRanges: [(Date, Date)] = []
        for event in rawGoogleEvents {
            if let start = event.start?.dateTime?.date, let end = event.end?.dateTime?.date {
                if end > rangeStart && start < rangeEnd {
                    rawRanges.append((start, end))
                }
            }
        }
        let busyRanges = flattenRanges(rawRanges)
        
        let now = Date()
        let cleanNow = calendar.date(bySetting: .second, value: 0, of: now) ?? now
        
        // === PHASE 1: Honor existing valid placements ===
        var usedTaskIDs = Set<PersistentIdentifier>()
        var occupiedRanges: [(Date, Date)] = [] // Track slots used by persisted tasks
        
        // Clean up stale placements (for archived tasks or tasks in the past)
        var placementsToRemove: [PersistentIdentifier] = []
        for (taskID, scheduledTime) in scheduledTaskPlacements {
            // Find the task
            guard let task = sortedTasks.first(where: { $0.persistentModelID == taskID }) else {
                // Task no longer exists or isn't in our list
                placementsToRemove.append(taskID)
                continue
            }
            
            let taskEnd = scheduledTime.addingTimeInterval(Double(task.durationMinutes) * 60)
            
            // Remove placement if:
            // 1. Scheduled time is in the past (ended before now) AND task is not archived
            //    (archived tasks in the past stay visible as historical record)
            // 2. Slot is now blocked
            // 3. Slot overlaps with a busy range (new calendar event)
            // NOTE: Archived tasks keep their placements to stay visible (greyed out)
            let isInPast = taskEnd < cleanNow && !task.isArchived
            let isBlocked = blockedSlots.contains(where: { calendar.isDate($0, equalTo: scheduledTime, toGranularity: .hour) })
            let overlapsWithBusy = busyRanges.contains(where: { $0.0 < taskEnd && $0.1 > scheduledTime })
            
            if isInPast || isBlocked || overlapsWithBusy {
                placementsToRemove.append(taskID)
            }
        }
        
        for taskID in placementsToRemove {
            scheduledTaskPlacements.removeValue(forKey: taskID)
        }
        
        // Add tasks with valid existing placements to the schedule
        for task in sortedTasks {
            if let scheduledTime = scheduledTaskPlacements[task.persistentModelID] {
                // Verify it's within our display range
                if scheduledTime >= rangeStart && scheduledTime < rangeEnd {
                    mixedSchedule.append(.task(task, scheduledTime))
                    usedTaskIDs.insert(task.persistentModelID)
                    let taskEnd = scheduledTime.addingTimeInterval(Double(task.durationMinutes) * 60)
                    occupiedRanges.append((scheduledTime, taskEnd))
                }
            }
        }
        
        // Flatten occupied ranges for collision detection
        let allBusyRanges = flattenRanges(busyRanges + occupiedRanges)
        
        // === PHASE 2: Schedule remaining tasks (only those without placements) ===
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
        
        while currentTime < dayEnd {
             let currentHour = calendar.component(.hour, from: currentTime)
             
             if currentHour < dayStartHour {
                 currentTime = calendar.date(bySettingHour: dayStartHour, minute: 0, second: 0, of: currentTime)!
             }
             else if currentHour >= dayEndHour {
                 let tomorrow = calendar.date(byAdding: .day, value: 1, to: currentTime)!
                 currentTime = calendar.date(bySettingHour: dayStartHour, minute: 0, second: 0, of: tomorrow)!
                 continue
             }
            
            // Check overlap with all busy ranges (including tasks already placed)
            if let overlap = allBusyRanges.first(where: { $0.0 <= currentTime && $0.1 > currentTime }) {
                currentTime = overlap.1
                continue
            }
            
            let nextBusyStart = allBusyRanges.first(where: { $0.0 > currentTime })?.0 ?? dayEnd
            
            var effectiveGapEnd = nextBusyStart
            if let endOfWindow = calendar.date(bySettingHour: dayEndHour, minute: 0, second: 0, of: currentTime) {
                if endOfWindow > currentTime {
                    effectiveGapEnd = min(nextBusyStart, endOfWindow)
                }
            }
            
            let gapDuration = effectiveGapEnd.timeIntervalSince(currentTime)
            
            if blockedSlots.contains(where: { calendar.isDate($0, equalTo: currentTime, toGranularity: .hour) }) {
                currentTime = calendar.date(byAdding: .hour, value: 1, to: currentTime)!
                continue
            }
                
            // Find candidates (only tasks without existing placements)
            let candidates = sortedTasks.filter { task in
                    let taskDuration = Double(task.durationMinutes) * 60
                    let fitsInGap = taskDuration <= gapDuration
                    let isUnused = !usedTaskIDs.contains(task.persistentModelID)
                    let hasNoPlacement = scheduledTaskPlacements[task.persistentModelID] == nil
                    let isNotArchived = !task.isArchived
                    
                    return fitsInGap && isUnused && hasNoPlacement && isNotArchived
            }
            
            if !candidates.isEmpty {
                let offset = slotOffsets[currentTime] ?? 0
                let selectedIndex = offset % candidates.count
                let selectedTask = candidates[selectedIndex]
                
                mixedSchedule.append(.task(selectedTask, currentTime))
                usedTaskIDs.insert(selectedTask.persistentModelID)
                
                // Store the placement for persistence
                scheduledTaskPlacements[selectedTask.persistentModelID] = currentTime
                
                currentTime = currentTime.addingTimeInterval(Double(selectedTask.durationMinutes) * 60)
            } else {
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
        // swipeRight: slot time, task ID that was displaced, its original placement time
        case swipeRight(slotTime: Date, taskID: PersistentIdentifier, originalPlacement: Date)
        // swipeLeft: slot time, task ID that was displaced, its original placement time
        case swipeLeft(slotTime: Date, taskID: PersistentIdentifier, originalPlacement: Date)
        case archive(PersistentIdentifier)
    }
    
    var undoStack: [UndoAction] = []
    
    func registerUndo(_ action: UndoAction) {
        undoStack.append(action)
    }
    
    func undo(context: ModelContext) -> Bool {
        guard let action = undoStack.popLast() else { return false }
        
        switch action {
        case .swipeRight(let slotTime, let taskID, let originalPlacement):
            // Revert swipe right: decrement offset and restore task placement
            if let count = slotOffsets[slotTime], count > 0 {
                slotOffsets[slotTime] = count - 1
            }
            
            // Clear any task that was placed at the original slot (to avoid overlap)
            for (id, placement) in scheduledTaskPlacements {
                if placement == originalPlacement && id != taskID {
                    scheduledTaskPlacements.removeValue(forKey: id)
                    break
                }
            }
            
            // Restore the task's original placement
            scheduledTaskPlacements[taskID] = originalPlacement
            return true
            
        case .swipeLeft(let slotTime, let taskID, let originalPlacement):
            // Revert swipe left: unblock slot and restore task placement
            blockedSlots.remove(slotTime)
            // Restore the task's original placement
            scheduledTaskPlacements[taskID] = originalPlacement
            return true
            
        case .archive(let id):
            let descriptor = FetchDescriptor<LatticeTask>(predicate: #Predicate { $0.persistentModelID == id })
            if let task = try? context.fetch(descriptor).first {
                task.isArchived = false
                return true
            }
            return false
        }
    }
    
    // --- ACTIONS ---
    // Swipe right: Swap to different task for this slot
    // Clears the current task's placement so it gets rescheduled elsewhere
    func swipeRight(on slotTime: Date, taskID: PersistentIdentifier) {
        let current = slotOffsets[slotTime] ?? 0
        slotOffsets[slotTime] = current + 1
        
        // Record the original placement for undo, then clear it
        let originalPlacement = scheduledTaskPlacements[taskID] ?? slotTime
        scheduledTaskPlacements.removeValue(forKey: taskID)
        
        registerUndo(.swipeRight(slotTime: slotTime, taskID: taskID, originalPlacement: originalPlacement))
    }
    
    // Swipe left: Block this hour and reschedule the task
    func swipeLeft(on slotTime: Date, taskID: PersistentIdentifier) {
        blockedSlots.insert(slotTime)
        
        // Record the original placement for undo, then clear it
        let originalPlacement = scheduledTaskPlacements[taskID] ?? slotTime
        scheduledTaskPlacements.removeValue(forKey: taskID)
        
        registerUndo(.swipeLeft(slotTime: slotTime, taskID: taskID, originalPlacement: originalPlacement))
    }
    
    func resetDailyState() {
        slotOffsets.removeAll()
        blockedSlots.removeAll()
        undoStack.removeAll()
        scheduledTaskPlacements.removeAll()
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
