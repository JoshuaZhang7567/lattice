import SwiftUI
import SwiftData
import GoogleSignIn
import GoogleSignInSwift
import GoogleAPIClientForREST_Calendar

struct ContentView: View {
    @Environment(CalendarManager.self) var calendarManager
    @Environment(\.modelContext) var modelContext
    
    // NAVIGATION STATE (0=Tasks, 1=Schedule, 2=Archive)
    @State private var selectedTab: Int = 0
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
                                    .transition(.opacity.combined(with: .move(edge: .leading)))
                            } else if selectedTab == 1 {
                                CalendarPageView(items: calendarManager.dailySchedule, allTasks: tasks)
                                    .transition(.opacity.combined(with: .move(edge: .trailing)))
                            } else {
                                ArchivePageView(tasks: archivedTasks, modelContext: modelContext)
                                    .transition(.opacity.combined(with: .move(edge: .trailing)))
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
                // TRIGGERS
                .onChange(of: tasks) { _, newTasks in calendarManager.generateSchedule(with: newTasks, dayStartHour: 8, dayEndHour: 20) }
                .onChange(of: calendarManager.rawGoogleEvents) { _, _ in calendarManager.generateSchedule(with: tasks, dayStartHour: 8, dayEndHour: 20) }
                
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
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { selectedTab = index }
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
}
// MARK: - SUBVIEW 1: TASK LIST (Unchanged)
struct TaskPageView: View {
    var tasks: [LatticeTask]
    @Binding var showNewTask: Bool
    var modelContext: ModelContext
    
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
                            withAnimation(.easeInOut(duration: 0.6)) { task.isArchived = true }
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
import SwiftUI
import GoogleAPIClientForREST_Calendar

struct CalendarPageView: View {
    var items: [CalendarItem]
    var allTasks: [LatticeTask]
    @Environment(CalendarManager.self) var calendarManager
    
    // Alert State
    @State private var taskToArchive: LatticeTask?
    @State private var showArchiveAlert = false
    
    // Config
    let hourHeight: CGFloat = 80
    let timeColumnWidth: CGFloat = 60
    let hours = Array(0...24)
    private let calendar = Calendar.current
    
    func formatHour(_ hour: Int) -> String {
        let startOfDay = calendar.startOfDay(for: Date())
        if let date = calendar.date(byAdding: .hour, value: hour, to: startOfDay) {
            return date.formatted(.dateTime.hour().minute())
        }
        return "\(hour):00"
    }
    
    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            ScrollView {
                ZStack(alignment: .topLeading) {
                    
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
                    ForEach(Array(items.enumerated()), id: \.offset) { (index, item) in
                        switch item {
                        case .event(let event):
                            renderGoogleEvent(event)
                        case .task(let task, let date):
                            SwipeableTaskCard(
                                task: task,
                                startTime: date,
                                hourHeight: hourHeight,
                                timeColumnWidth: timeColumnWidth,
                                onSwipeRight: {
                                    withAnimation {
                                        calendarManager.swipeRight(on: date)
                                        calendarManager.generateSchedule(with: allTasks, dayStartHour: 8, dayEndHour: 20)
                                    }
                                },
                                onSwipeLeft: {
                                    withAnimation {
                                        calendarManager.swipeLeft(on: date)
                                        calendarManager.generateSchedule(with: allTasks, dayStartHour: 8, dayEndHour: 20)
                                    }
                                }
                            )
                            .onTapGesture {
                                taskToArchive = task
                                showArchiveAlert = true
                            }
                        }
                    }
                    
                    CurrentTimeLine(hourHeight: hourHeight, gridTopPadding: 20)
                }
                .frame(height: CGFloat(hours.count) * hourHeight + 100)
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
            
            // Refresh Button
            Button(action: {
                let generator = UIImpactFeedbackGenerator(style: .medium)
                generator.impactOccurred()
                withAnimation {
                    calendarManager.resetDailyState()
                    calendarManager.generateSchedule(with: allTasks, dayStartHour: 8, dayEndHour: 20)
                }
            }) {
                Image(systemName: "arrow.counterclockwise")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 50, height: 50)
                    .background(Circle().fill(Color.blue).shadow(color: .blue.opacity(0.4), radius: 8, x: 0, y: 4))
                    .overlay(Circle().stroke(Color.white.opacity(0.2), lineWidth: 1))
            }
            .padding(.trailing, 25)
            .padding(.bottom, 25)
        }
        .confirmationDialog("Archive Task?", isPresented: $showArchiveAlert, titleVisibility: .visible) {
            Button("Archive Task", role: .destructive) {
                if let task = taskToArchive {
                    withAnimation {
                        task.isArchived = true
                    }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will move the task to the Archive.")
        }
    }
    
    @ViewBuilder
    func renderGoogleEvent(_ event: GTLRCalendar_Event) -> some View {
        if let start = event.start?.dateTime?.date,
           let end = event.end?.dateTime?.date,
           calendar.isDateInToday(start) {
            
            let pos = calculatePosition(start: start, end: end)
            
            EventCard(title: event.summary ?? "Event", location: event.location, color: .blue)
                .frame(height: pos.height - 2)
                .padding(.leading, timeColumnWidth + 10)
                .padding(.trailing, 10)
                .offset(y: pos.y)
        }
    }
    
    func calculatePosition(start: Date, end: Date) -> (y: CGFloat, height: CGFloat) {
        let startHour = calendar.component(.hour, from: start)
        let startMinute = calendar.component(.minute, from: start)
        let endHour = calendar.component(.hour, from: end)
        let endMinute = calendar.component(.minute, from: end)
        
        let startY = (CGFloat(startHour) * hourHeight) + (CGFloat(startMinute) / 60.0 * hourHeight) + 20
        let startDecimal = CGFloat(startHour) + CGFloat(startMinute) / 60.0
        let endDecimal = CGFloat(endHour) + CGFloat(endMinute) / 60.0
        let height = max((endDecimal - startDecimal) * hourHeight, 30)
        return (startY, height)
    }
}
// MARK: - NEW: ANIMATED SWIPE CARD
struct SwipeableTaskCard: View {
    let task: LatticeTask
    let startTime: Date
    let hourHeight: CGFloat
    let timeColumnWidth: CGFloat
    
    var onSwipeRight: () -> Void
    var onSwipeLeft: () -> Void
    
    @State private var offset: CGSize = .zero
    private let calendar = Calendar.current
    
    var body: some View {
        let end = startTime.addingTimeInterval(Double(task.durationMinutes) * 60)
        let pos = calculatePosition(start: startTime, end: end)
        
        EventCard(title: task.title, location: "Suggested (Deadline: \(task.targetDate.formatted(date: .omitted, time: .shortened)))", color: .green)
            .frame(height: pos.height - 2)
            .padding(.leading, timeColumnWidth + 10)
            .padding(.trailing, 10)
            .offset(y: pos.y)
            // ANIMATION OFFSET
            .offset(x: offset.width, y: 0)
            .rotationEffect(.degrees(Double(offset.width / 20)))
            .opacity(2 - Double(abs(offset.width / 100))) // Fade out as you drag
            .gesture(
                DragGesture()
                    .onChanged { gesture in
                        withAnimation(.interactiveSpring()) {
                            offset = gesture.translation
                        }
                    }
                    .onEnded { gesture in
                        if gesture.translation.width > 100 {
                            // Trigger Right Action
                            withAnimation(.easeOut(duration: 0.2)) {
                                offset.width = 500 // Fly off screen
                            }
                            // Wait for animation then reset & callback
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                                onSwipeRight()
                                offset = .zero
                            }
                        } else if gesture.translation.width < -100 {
                            // Trigger Left Action
                            withAnimation(.easeOut(duration: 0.2)) {
                                offset.width = -500 // Fly off screen
                            }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                                onSwipeLeft()
                                offset = .zero
                            }
                        } else {
                            // Snap back if scroll wasn't far enough
                            withAnimation(.spring()) {
                                offset = .zero
                            }
                        }
                    }
            )
    }
    
    // Duplicate math helper needed inside this struct
    func calculatePosition(start: Date, end: Date) -> (y: CGFloat, height: CGFloat) {
        let startHour = calendar.component(.hour, from: start)
        let startMinute = calendar.component(.minute, from: start)
        let endHour = calendar.component(.hour, from: end)
        let endMinute = calendar.component(.minute, from: end)
        
        let startY = (CGFloat(startHour) * hourHeight) + (CGFloat(startMinute) / 60.0 * hourHeight) + 20
        let startDecimal = CGFloat(startHour) + CGFloat(startMinute) / 60.0
        let endDecimal = CGFloat(endHour) + CGFloat(endMinute) / 60.0
        let height = max((endDecimal - startDecimal) * hourHeight, 30)
        return (startY, height)
    }
}
// MARK: - HELPER: GENERIC EVENT CARD
struct EventCard: View {
    var title: String
    var location: String?
    var color: Color
    
    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            // Accent Bar
            Rectangle()
                .fill(color.opacity(0.8))
                .frame(width: 3)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white.opacity(0.95))
                    .lineLimit(1)
                
                if let location = location {
                    Text(location)
                        .font(.system(size: 10))
                        .foregroundColor(.white.opacity(0.6))
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            
            Spacer()
        }
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(color.opacity(0.3), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.3), radius: 2, x: 0, y: 1)
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
    
    func updatePosition() {
        let now = Date()
        let cal = Calendar.current
        let hour = cal.component(.hour, from: now)
        let minute = cal.component(.minute, from: now)
        offset = (CGFloat(hour) * hourHeight) + (CGFloat(minute) / 60.0 * hourHeight) + gridTopPadding
    }
}

