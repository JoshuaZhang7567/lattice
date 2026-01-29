import SwiftUI
import SwiftData
import GoogleSignIn
import GoogleSignInSwift
import GoogleAPIClientForREST_Calendar

struct ContentView: View {
    @Environment(CalendarManager.self) var calendarManager
    @Environment(\.modelContext) var modelContext
    
    // NAVIGATION STATE (0=Tasks, 1=Schedule, 2=Archive)
    @State private var selectedTab: Int = 1
    @State private var isMovingForward: Bool = true // Explicitly track direction
    @State private var showNewTask = false
    
    
    // ACTIVE TASKS
    @Query(filter: #Predicate<LatticeTask> { !$0.isArchived },
           sort: \LatticeTask.targetDate,
           order: .forward)
    var tasks: [LatticeTask]
    
    // ARCHIVED TASKS
    @Query(filter: #Predicate<LatticeTask> { $0.isArchived },
           sort: \LatticeTask.dateCreated,
           order: .reverse)
    var archivedTasks: [LatticeTask]

    var body: some View {
        NavigationStack {
            if calendarManager.user != nil {
                
                ZStack {
                    // --- BACKGROUND ---
                    LinearGradient(
                        colors: [Color(red: 0.1, green: 0.1, blue: 0.2), Color.black, Color(red: 0.05, green: 0.05, blue: 0.1)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    ).ignoresSafeArea()
                    
                    Circle().fill(Color.blue.opacity(0.15)).frame(width: 300, height: 300)
                        .blur(radius: 60).offset(x: -100, y: -250)
                    
                    VStack(spacing: 0) {
                        
                        // 1. HEADER & 3-WAY TOGGLE
                        VStack(spacing: 20) {
                            Text("LATTICE")
                                .font(.system(size: 14, weight: .bold, design: .monospaced))
                                .tracking(4)
                                .foregroundColor(.white.opacity(0.6))
                                .padding(.top, 10)
                            
                            // THE GLASS TOGGLE
                            HStack(spacing: 0) {
                                toggleButton(title: "Tasks", index: 0)
                                toggleButton(title: "Schedule", index: 1)
                                toggleButton(title: "Archive", index: 2)
                            }
                            .padding(4)
                            .background(Color.black.opacity(0.3))
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                            .overlay(RoundedRectangle(cornerRadius: 14).stroke(.white.opacity(0.1), lineWidth: 0.5))
                            .padding(.horizontal, 40)
                        }
                        .padding(.bottom, 10)
                        
                        // 2. THE VIEWS
                        ZStack {
                            if selectedTab == 0 {
                                TaskPageView(tasks: tasks, showNewTask: $showNewTask, modelContext: modelContext)
                                    .transition(slideTransition)
                            } else if selectedTab == 1 {
                                let allRelevantTasks = tasks + archivedTasks // Simplified filtering for now, manager handles dates
                                let cal = Calendar.current
                                let now = Date()
                                let alignedNow = cal.date(bySettingHour: cal.component(.hour, from: now), minute: 0, second: 0, of: now) ?? now
                                let startWindow = cal.date(byAdding: .hour, value: -12, to: alignedNow)!
                                CalendarPageView(items: calendarManager.dailySchedule, allTasks: allRelevantTasks, rangeStart: startWindow)
                                    .transition(slideTransition)
                            } else {
                                ArchivePageView(tasks: archivedTasks, modelContext: modelContext)
                                    .transition(slideTransition)
                            }
                        }
                        .animation(.easeInOut(duration: 0.25), value: selectedTab)
                    }
                    
                    // --- NEW TASK POPUP ---
                    if showNewTask && selectedTab == 0 {
                        NewTaskOverlay(isPresented: $showNewTask) { title, date, minutes in
                            let newTask = LatticeTask(title: title, durationMinutes: minutes, targetDate: date)
                            withAnimation { modelContext.insert(newTask) }
                        }
                        .transition(.scale(scale: 0.9).combined(with: .opacity))
                        .zIndex(2)
                    }
                }
                .preferredColorScheme(.dark)
                .onAppear {
                    refreshSchedule()
                }
                // TRIGGERS
                .onChange(of: tasks) { _, _ in refreshSchedule() }
                .onChange(of: archivedTasks) { _, _ in refreshSchedule() }
                .onChange(of: calendarManager.rawGoogleEvents) { _, _ in refreshSchedule() }
            } else {
                // LOGGED OUT
                VStack(spacing: 24) {
                    Spacer()
                    Text("Lattice").font(.system(size: 44, weight: .ultraLight, design: .serif)).foregroundStyle(.white)
                    GoogleSignInButton(scheme: .dark, style: .wide, state: .normal) { signIn() }
                        .frame(width: 280, height: 60)
                    Spacer()
                }
                .background(Color.black.ignoresSafeArea())
                .onAppear { calendarManager.checkPreviousSignIn() }
            }
        }
    }
    
    func toggleButton(title: String, index: Int) -> some View {
        Button {
            if selectedTab != index {
                // 1. Determine direction before the change
                isMovingForward = index > selectedTab
                
                // 2. Trigger the animation
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    selectedTab = index
                }
            }
        } label: {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundColor(selectedTab == index ? .white : .white.opacity(0.4))
                .frame(maxWidth: .infinity)
                .frame(height: 32)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.white.opacity(0.15))
                        .opacity(selectedTab == index ? 1 : 0)
                )
        }
    }
    
    var slideTransition: AnyTransition {
        .asymmetric(
            insertion: .move(edge: isMovingForward ? .trailing : .leading).combined(with: .opacity),
            removal: .move(edge: isMovingForward ? .leading : .trailing).combined(with: .opacity)
        )
    }
    
    func signIn() {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let rootVC = windowScene.windows.first?.rootViewController else { return }
        let calendarScope = "https://www.googleapis.com/auth/calendar.events"
        GIDSignIn.sharedInstance.signIn(withPresenting: rootVC, hint: nil, additionalScopes: [calendarScope]) { result, error in
            if let user = result?.user {
                calendarManager.setup(with: user)
                calendarManager.fetchTodayEvents()
            }
        }
    }
    
    func refreshSchedule() {
        // Snap to current hour to align grid lines
        let now = Date()
        let cal = Calendar.current
        let hour = cal.component(.hour, from: now)
        let alignedNow = cal.date(bySettingHour: hour, minute: 0, second: 0, of: now)!
        
        // 12 hours before, 12 hours after
        let start = cal.date(byAdding: .hour, value: -12, to: alignedNow)!
        let end = cal.date(byAdding: .hour, value: 12, to: alignedNow)!
        
        // Include tasks that are active OR archived recently
        let allRelevantTasks = tasks + archivedTasks
        calendarManager.generateSchedule(with: allRelevantTasks, rangeStart: start, rangeEnd: end)
    }
}


// MARK: - SUBVIEW 1: TASK LIST (Unchanged)
struct TaskPageView: View {
    var tasks: [LatticeTask]
    @Binding var showNewTask: Bool
    var modelContext: ModelContext
    @Environment(CalendarManager.self) var calendarManager
    
    var body: some View {
        VStack(spacing: 0) {
            List {
                Color.clear.frame(height: 10).listRowBackground(Color.clear).listRowSeparator(.hidden)
                
                ForEach(tasks) { task in
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(task.title)
                                .font(.system(size: 17, weight: .medium))
                                .foregroundColor(.white.opacity(0.9))
                            
                            Text(task.targetDate.formatted(date: .abbreviated, time: .shortened))
                                .font(.caption)
                                .foregroundColor(.gray)
                        }
                        .padding(.vertical, 18)
                        .padding(.horizontal, 20)
                        
                        Spacer()
                        
                        Text("\(task.durationMinutes / 60)h")
                            .font(.caption)
                            .fontWeight(.bold)
                            .padding(8)
                            .background(Color.black.opacity(0.3))
                            .cornerRadius(8)
                            .foregroundColor(.white.opacity(0.7))
                            .padding(.trailing, 15)
                    }
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(.white.opacity(0.15), lineWidth: 0.5))
                    .shadow(color: .black.opacity(0.2), radius: 10, x: 0, y: 5)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 8, leading: 20, bottom: 8, trailing: 20))
                    
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) {
                            withAnimation(.easeInOut(duration: 0.6)) { modelContext.delete(task) }
                        } label: { Label("Delete", systemImage: "trash.fill") }.tint(.red)
                    }
                    .swipeActions(edge: .leading, allowsFullSwipe: true) {
                        Button(role: .destructive) {
                            withAnimation(.easeInOut(duration: 0.6)) { 
                                task.isArchived = true
                                calendarManager.registerUndo(.archive(task.persistentModelID))
                            }
                        } label: { Label("Archive", systemImage: "archivebox.fill") }.tint(.blue)
                    }
                }
                
                Color.clear.frame(height: 80).listRowBackground(Color.clear).listRowSeparator(.hidden)
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .scrollIndicators(.hidden)
            .animation(.default, value: tasks)
            .mask(
                VStack(spacing: 0) {
                    LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom).frame(height: 40)
                    Rectangle().fill(.black)
                    LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom).frame(height: 60)
                }
            )
            
            Button(action: {
                let generator = UIImpactFeedbackGenerator(style: .soft)
                generator.impactOccurred()
                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                    showNewTask = true
                }
            }) {
                HStack {
                    Image(systemName: "plus").font(.system(size: 18, weight: .semibold))
                    Text("New Task").font(.system(size: 16, weight: .semibold))
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .background(LinearGradient(colors: [Color(red: 0.2, green: 0.4, blue: 0.9), Color.blue], startPoint: .topLeading, endPoint: .bottomTrailing))
                .clipShape(RoundedRectangle(cornerRadius: 20))
                .overlay(RoundedRectangle(cornerRadius: 20).stroke(.white.opacity(0.2), lineWidth: 1))
                .shadow(color: .blue.opacity(0.3), radius: 20, x: 0, y: 10)
            }
            .padding(.horizontal, 40)
            .padding(.bottom, 20)
        }
    }
}

// MARK: - SUBVIEW 2: TIMELINE CALENDAR PAGE (UPDATED)
struct CalendarPageView: View {
    var items: [CalendarItem]
    var allTasks: [LatticeTask]
    @Environment(CalendarManager.self) var calendarManager
    @Environment(\.modelContext) var modelContext // Needed for Undo (unarchive)
    
    // Config
    // Config
    let hourHeight: CGFloat = 80
    let timeColumnWidth: CGFloat = 60
    
    // Rolling Window Config
    // rangeStart is the "top" of the view (e.g. 12 hours ago)
    var rangeStart: Date 
    
    // We display 25 hours to cover the full window [-12...12] inclusive or similar
    // Actually, user asked for 12 before and 12 after -> 24 hours total span? 
    // Or [-12...+12] = 24 hour span centered on now.
    // Let's us indices 0 to 24, where 0 = rangeStart.
    let hours = Array(0...24)
    private let calendar = Calendar.current
    
    func formatHour(_ offset: Int) -> String {
        // hour is explicitly rangeStart + offset hours
        if let date = calendar.date(byAdding: .hour, value: offset, to: rangeStart) {
            return date.formatted(.dateTime.hour().minute())
        }
        return ""
    }
    
    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            ScrollViewReader { proxy in
                ScrollView {
                ZStack(alignment: .topLeading) {
                    
                    // SCROLL ANCHORS (Invisible VStack for reliable scrolling)
                    VStack(spacing: 0) {
                        ForEach(hours, id: \.self) { hour in
                            Color.clear
                                .frame(height: hourHeight)
                                .id(hour)
                        }
                    }
                    
                    // GRID
                    ZStack(alignment: .topLeading) {
                        Path { path in
                            for hour in hours {
                                let y = CGFloat(hour) * hourHeight
                                path.move(to: CGPoint(x: timeColumnWidth, y: y))
                                path.addLine(to: CGPoint(x: 4000, y: y))
                            }
                        }
                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                        
                        ForEach(hours, id: \.self) { hour in
                            Text(formatHour(hour))
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.white.opacity(0.5))
                                .frame(width: timeColumnWidth, alignment: .trailing)
                                .padding(.trailing, 8)
                                .offset(y: (CGFloat(hour) * hourHeight) - 6)
                        }
                    }
                    .padding(.top, 20)
                    
                    // EVENTS & TASKS
                    // Inside CalendarPageView -> ScrollView -> ZStack
                    ForEach(items) { item in
                        switch item {
                        case .event(let event):
                            renderGoogleEvent(event)
                        case .task(let task, let date):
                            SwipeableTaskCard(
                                task: task,
                                startTime: date,
                                hourHeight: hourHeight,
                                timeColumnWidth: timeColumnWidth,
                                rangeStart: rangeStart, // Pass it down
                                onSwipeRight: {
                                    withAnimation {
                                        calendarManager.swipeRight(on: date)
                                        // trigger refresh via parent binding or direct call? 
                                        // Ideally call refreshSchedule() from VM but VM doesn't know tasks.
                                        // We updated swipeRight to just update offsets. 
                                        // The view will re-render if it observes VM. 
                                        // BUT we need to regenerate schedule.
                                        // Let's call the passed closure or rely on onChange? 
                                        // Actually, VM.swipeRight updates published props. 
                                        // But generateSchedule must be called.
                                        // Let's use a closure in VM or just rely on parent Refresh logic... 
                                        // Parent Refresh sees changes in VM? No generateSchedule IS the manual refresh.
                                        // Quick fix: pass refresh callback or access parent func?
                                        // We can just call generateSchedule here with same params since we have them in scope?
                                        // NO, we don't have 'allTasks' and 'rangeStart' effectively here? 
                                        // Actually 'allTasks' and 'rangeStart' ARE available in CalendarPageView.
                                        let end = Calendar.current.date(byAdding: .hour, value: 24, to: rangeStart)!
                                        calendarManager.generateSchedule(with: allTasks, rangeStart: rangeStart, rangeEnd: end)
                                    }
                                },
                                onSwipeLeft: {
                                    withAnimation {
                                        // Logic for delete or snooze
                                        calendarManager.swipeLeft(on: date)
                                        let end = Calendar.current.date(byAdding: .hour, value: 24, to: rangeStart)!
                                        calendarManager.generateSchedule(with: allTasks, rangeStart: rangeStart, rangeEnd: end)
                                    }
                                }
                            )

                            // --- SIMPLIFIED TAP: TOGGLE ARCHIVE ---
                            .onTapGesture {
                                let generator = UIImpactFeedbackGenerator(style: .medium)
                                generator.impactOccurred()
                                withAnimation {
                                    task.isArchived.toggle()
                                    // Register Undo if we just archived it (was false, now true)
                                    // Wait, isArchived.toggle() flips it.
                                    // If it BECAME archived (true), we register undo.
                                    // If unarchived, we don't strictly need to register undo here unless we want redo? 
                                    // Plan says "revert actions... archive". So if I archive, I can undo.
                                    if task.isArchived {
                                         calendarManager.registerUndo(.archive(task.persistentModelID))
                                    }
                                }
                            }
                        }
                    }
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
                    
                    CurrentTimeLine(hourHeight: hourHeight, gridTopPadding: 20, rangeStart: rangeStart)
                }
                .frame(height: CGFloat(hours.count) * hourHeight + 100)
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
            .onAppear {
                DispatchQueue.main.async {
                    // Scroll to center (12 hours in)
                    proxy.scrollTo(12, anchor: .center)
                }
            }
        }
            
            // Undo Button (Replaces Refresh)
            Button(action: {
                let generator = UIImpactFeedbackGenerator(style: .medium)
                generator.impactOccurred()
                withAnimation {
                    // Attempt Undo
                    if calendarManager.undo(context: modelContext) {
                        // If successful, regenerate schedule
                        let end = Calendar.current.date(byAdding: .hour, value: 24, to: rangeStart)!
                        calendarManager.generateSchedule(with: allTasks, rangeStart: rangeStart, rangeEnd: end)
                    }
                }
            }) {
                Image(systemName: "arrow.uturn.backward")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(calendarManager.undoStack.isEmpty ? .white.opacity(0.3) : .white)
                    .frame(width: 50, height: 50)
                    .background(Circle().fill(calendarManager.undoStack.isEmpty ? Color.gray.opacity(0.3) : Color.blue).shadow(color: calendarManager.undoStack.isEmpty ? .clear : .blue.opacity(0.4), radius: 8, x: 0, y: 4))
                    .overlay(Circle().stroke(Color.white.opacity(0.2), lineWidth: 1))
            }
            .disabled(calendarManager.undoStack.isEmpty)
            .padding(.trailing, 25)
            .padding(.bottom, 25)
        }
    }
    
    @ViewBuilder
    func renderGoogleEvent(_ event: GTLRCalendar_Event) -> some View {
        if let start = event.start?.dateTime?.date,
           let end = event.end?.dateTime?.date,
           calendar.isDateInToday(start) {
            
            
            let pos = calculatePosition(start: start, end: end)
            if pos.y >= 0 { // Simple check if it's within our window approx
                EventCard(title: event.summary ?? "Event", location: event.location, color: .blue)
                    .frame(height: pos.height - 2)
                    .padding(.leading, timeColumnWidth + 10)
                    .padding(.trailing, 10)
                    .offset(y: pos.y)
            }
        }
    }
    
    func calculatePosition(start: Date, end: Date) -> (y: CGFloat, height: CGFloat) {
        // Calculate offset relative to rangeStart
        let diff = start.timeIntervalSince(rangeStart)
        let hoursFromStart = diff / 3600.0
        
        // Duration
        let duration = end.timeIntervalSince(start)
        let durationHours = duration / 3600.0
        
        let startY = (CGFloat(hoursFromStart) * hourHeight) + 20
        let height = max(CGFloat(durationHours) * hourHeight, 30)
        return (startY, height)
    }
}
// MARK: - NEW: ANIMATED SWIPE CARD
struct SwipeableTaskCard: View {
    let task: LatticeTask
    let startTime: Date
    let hourHeight: CGFloat
    let timeColumnWidth: CGFloat
    
    // ADDED rangeStart
    var rangeStart: Date 
    
    var onSwipeRight: () -> Void // Suggest Next
    var onSwipeLeft: () -> Void  // Block 1 Hour
    
    @State private var offset: CGFloat = 0
    @State private var isVisible: Bool = true
    private let calendar = Calendar.current
    
    var body: some View {
        let end = startTime.addingTimeInterval(Double(task.durationMinutes) * 60)
        let pos = calculateLocalPosition(start: startTime, end: end)
        
        ZStack {
            // --- BACKGROUND LAYER (Actions) ---
            ZStack {
                // Blue: Suggest Next (Right Swipe)
                Rectangle().fill(Color.blue)
                    .overlay(Image(systemName: "arrow.right.circle.fill").foregroundColor(.white).padding(.leading, 20), alignment: .leading)
                    .opacity(offset > 0 ? 1 : 0)
                
                // Red: Block Slot (Left Swipe)
                Rectangle().fill(Color.red)
                    .overlay(Image(systemName: "hand.raised.fill").foregroundColor(.white).padding(.trailing, 20), alignment: .trailing)
                    .opacity(offset < 0 ? 1 : 0)
            }
            .cornerRadius(6)
            .padding(.leading, timeColumnWidth + 10)
            .padding(.trailing, 10)

            // --- FOREGROUND CARD ---
            EventCard(
                title: task.title,
                location: "Suggested",
                color: .green,
                isArchived: task.isArchived,
                onCheckmarkTap: {
                    withAnimation(.spring()) {
                        task.isArchived.toggle()
                    }
                }
            )
            .padding(.leading, timeColumnWidth + 10)
            .padding(.trailing, 10)
            .offset(x: offset)
            .gesture(
                DragGesture()
                    .onChanged { gesture in
                        if !task.isArchived {
                            offset = gesture.translation.width
                        }
                    }
                    .onEnded { gesture in
                        if gesture.translation.width > 100 {
                            // Suggest Next Task: Slide out -> Fade Out -> Update
                            withAnimation(.easeOut(duration: 0.2)) { offset = 500 }
                            
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                withAnimation(.easeOut(duration: 0.2)) { isVisible = false }
                            }
                            
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                                onSwipeRight()
                                // Safeguard: Reset state if view is reused (e.g. same task or no change)
                                withAnimation(.spring()) {
                                    isVisible = true
                                    offset = 0
                                }
                            }
                        } else if gesture.translation.width < -100 {
                            // Block this hour: Slide out -> Fade Out -> Update
                            withAnimation(.easeOut(duration: 0.2)) { offset = -500 }
                            
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                withAnimation(.easeOut(duration: 0.2)) { isVisible = false }
                            }
                            
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                                onSwipeLeft()
                                // Safeguard: Reset state if view is reused
                                withAnimation(.spring()) {
                                    isVisible = true
                                    offset = 0
                                }
                            }
                        } else {
                            withAnimation(.spring()) { offset = 0 }
                        }
                    }
            )
        }
        .frame(height: pos.height - 2)
        .offset(y: pos.y)
        .opacity(isVisible ? 1 : 0)
        .onChange(of: startTime) { _, _ in
            // Data updated (New Y position).
            // Reset X-offset instantly while hidden.
            var transaction = Transaction(animation: .none)
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                isVisible = false // Ensure hidden
                offset = 0 
            }
            
            // Fade back in
            withAnimation(.easeIn(duration: 0.3).delay(0.05)) {
                isVisible = true
            }
        }
    }
    
    func calculateLocalPosition(start: Date, end: Date) -> (y: CGFloat, height: CGFloat) {
        let diff = start.timeIntervalSince(rangeStart)
        let hoursFromStart = diff / 3600.0
        let duration = end.timeIntervalSince(start)
        let durationHours = duration / 3600.0
        
        let startY = (CGFloat(hoursFromStart) * hourHeight) + 20
        let height = max(CGFloat(durationHours) * hourHeight, 30)
        return (startY, height)
    }
    

}
// MARK: - HELPER: GENERIC EVENT CARD
struct EventCard: View {
    var title: String
    var location: String?
    var color: Color
    var isArchived: Bool = false
    var onCheckmarkTap: (() -> Void)?

    var body: some View {
        HStack(alignment: .center, spacing: 0) {
            Rectangle()
                .fill(isArchived ? Color.gray.opacity(0.4) : color.opacity(0.8))
                .frame(width: 4)
            
            if let onCheckmarkTap = onCheckmarkTap {
                Button(action: onCheckmarkTap) {
                    Image(systemName: isArchived ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 18))
                        .foregroundColor(isArchived ? .green : .white.opacity(0.4))
                }
                .padding(.leading, 10)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(isArchived ? .white.opacity(0.3) : .white)
                    .strikethrough(isArchived)
                
                if let location = location {
                    Text(location)
                        .font(.system(size: 10))
                        .foregroundColor(.white.opacity(0.3))
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            
            Spacer()
        }
        .background(isArchived ? Color.white.opacity(0.05) : Color.white.opacity(0.1))
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.1), lineWidth: 0.5))
    }
}
// MARK: - HELPER: CURRENT TIME LINE (Unchanged)
struct CurrentTimeLine: View {
    let hourHeight: CGFloat
    let gridTopPadding: CGFloat
    @State private var offset: CGFloat = 0
    
    var body: some View {
        HStack(spacing: 0) {
            Circle()
                .fill(Color.red)
                .frame(width: 6, height: 6)
                .shadow(color: .red.opacity(0.5), radius: 4)
            
            Rectangle()
                .fill(LinearGradient(
                    colors: [.red, .red.opacity(0.1)],
                    startPoint: .leading,
                    endPoint: .trailing
                ))
                .frame(height: 1)
        }
        .offset(y: offset)
        .onAppear {
            updatePosition()
            Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { _ in
                withAnimation { updatePosition() }
            }
        }
    }
    
    // ADDED rangeStart
    var rangeStart: Date?
    
    func updatePosition() {
        let now = Date()
        if let start = rangeStart {
             let diff = now.timeIntervalSince(start)
             let hours = diff / 3600.0
             offset = (CGFloat(hours) * hourHeight) + gridTopPadding
        } else {
             // Fallback
             let cal = Calendar.current
             let hour = cal.component(.hour, from: now)
             let minute = cal.component(.minute, from: now)
             offset = (CGFloat(hour) * hourHeight) + (CGFloat(minute) / 60.0 * hourHeight) + gridTopPadding
        }
    }
}

