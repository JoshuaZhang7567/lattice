import SwiftUI
import SwiftData
import GoogleSignIn
import GoogleSignInSwift
import GoogleAPIClientForREST_Calendar

struct ContentView: View {
    @Environment(CalendarManager.self) var calendarManager
    @Environment(\.modelContext) var modelContext
    
    // NAVIGATION STATE
    @State private var selectedTab: Int = 0
    @State private var showNewTask = false
    
    @Query(filter: #Predicate<LatticeTask> { !$0.isArchived },
           sort: \LatticeTask.dateCreated,
           order: .reverse)
    var tasks: [LatticeTask]

    var body: some View {
        NavigationStack {
            if calendarManager.user != nil {
                
                ZStack {
                    // --- GLOBAL BACKGROUND ---
                    LinearGradient(
                        colors: [
                            Color(red: 0.1, green: 0.1, blue: 0.2),
                            Color.black,
                            Color(red: 0.05, green: 0.05, blue: 0.1)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .ignoresSafeArea()
                    
                    Circle()
                        .fill(Color.blue.opacity(0.15))
                        .frame(width: 300, height: 300)
                        .blur(radius: 60)
                        .offset(x: -100, y: -250)
                    
                    // --- MAIN CONTENT ---
                    VStack(spacing: 0) {
                        
                        // 1. CUSTOM GLASS HEADER & TOGGLE
                        VStack(spacing: 20) {
                            Text("LATTICE")
                                .font(.system(size: 14, weight: .bold, design: .monospaced))
                                .tracking(4)
                                .foregroundColor(.white.opacity(0.6))
                                .padding(.top, 10)
                            
                            // THE GLASS TOGGLE
                            HStack(spacing: 0) {
                                Button {
                                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                        selectedTab = 0
                                    }
                                } label: {
                                    Text("Tasks")
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundColor(selectedTab == 0 ? .white : .white.opacity(0.4))
                                        .frame(maxWidth: .infinity)
                                        .frame(height: 32)
                                        .background(
                                            RoundedRectangle(cornerRadius: 10)
                                                .fill(Color.white.opacity(0.15))
                                                .opacity(selectedTab == 0 ? 1 : 0)
                                        )
                                }
                                
                                Button {
                                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                        selectedTab = 1
                                    }
                                } label: {
                                    Text("Schedule")
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundColor(selectedTab == 1 ? .white : .white.opacity(0.4))
                                        .frame(maxWidth: .infinity)
                                        .frame(height: 32)
                                        .background(
                                            RoundedRectangle(cornerRadius: 10)
                                                .fill(Color.white.opacity(0.15))
                                                .opacity(selectedTab == 1 ? 1 : 0)
                                        )
                                }
                            }
                            .padding(4)
                            .background(Color.black.opacity(0.3))
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                            .overlay(
                                RoundedRectangle(cornerRadius: 14)
                                    .stroke(.white.opacity(0.1), lineWidth: 0.5)
                            )
                            .padding(.horizontal, 60)
                        }
                        .padding(.bottom, 10)
                        
                        // 2. THE VIEWS
                        ZStack {
                            if selectedTab == 0 {
                                TaskPageView(tasks: tasks, showNewTask: $showNewTask, modelContext: modelContext)
                                    .transition(.opacity.combined(with: .move(edge: .leading)))
                            } else {
                                // NEW TIMELINE VIEW
                                CalendarPageView(events: calendarManager.events)
                                    .transition(.opacity.combined(with: .move(edge: .trailing)))
                            }
                        }
                        .animation(.easeInOut(duration: 0.25), value: selectedTab)
                    }
                    
                    // --- POPUP ---
                    if showNewTask {
                        NewTaskOverlay(isPresented: $showNewTask) { title, date, minutes in
                            let newTask = LatticeTask(title: title, durationMinutes: minutes, targetDate: date)
                            withAnimation {
                                modelContext.insert(newTask)
                            }
                        }
                        .transition(.scale(scale: 0.9).combined(with: .opacity))
                        .zIndex(2)
                    }
                }
                .preferredColorScheme(.dark)
                
            } else {
                // LOGGED OUT
                VStack(spacing: 24) {
                    Spacer()
                    Text("Lattice")
                        .font(.system(size: 44, weight: .ultraLight, design: .serif))
                        .foregroundStyle(.white)
                    
                    GoogleSignInButton(scheme: .dark, style: .wide, state: .normal) {
                        signIn()
                    }
                    .frame(width: 280, height: 60)
                    Spacer()
                }
                .background(Color.black.ignoresSafeArea())
                .onAppear {
                    calendarManager.checkPreviousSignIn()
                }
            }
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

// MARK: - SUBVIEW 2: TIMELINE CALENDAR PAGE
struct CalendarPageView: View {
    var events: [GTLRCalendar_Event]
    
    // Config
    let hourHeight: CGFloat = 80
    let timeColumnWidth: CGFloat = 60
    let hours = Array(0...24)
    
    // Cache calendar for performance
    private let calendar = Calendar.current
    
    // Helper: "13:00" -> "1 PM"
    func formatHour(_ hour: Int) -> String {
        let startOfDay = calendar.startOfDay(for: Date())
        if let date = calendar.date(byAdding: .hour, value: hour, to: startOfDay) {
            return date.formatted(.dateTime.hour().minute())
        }
        return "\(hour):00"
    }
    
    var body: some View {
        ScrollView {
            ZStack(alignment: .topLeading) {
                
                // --- LAYER 1: THE GRID ---
                ZStack(alignment: .topLeading) {
                    // Lines
                    Path { path in
                        for hour in hours {
                            let y = CGFloat(hour) * hourHeight
                            path.move(to: CGPoint(x: timeColumnWidth, y: y))
                            path.addLine(to: CGPoint(x: 4000, y: y))
                        }
                    }
                    .stroke(Color.white.opacity(0.1), lineWidth: 1)
                    
                    // Labels
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
                
                // --- LAYER 2: THE EVENTS ---
                ForEach(events, id: \.identifier) { event in
                    if let start = event.start?.dateTime?.date,
                       let end = event.end?.dateTime?.date,
                       calendar.isDateInToday(start) {
                        
                        let startHour = calendar.component(.hour, from: start)
                        let startMinute = calendar.component(.minute, from: start)
                        let endHour = calendar.component(.hour, from: end)
                        let endMinute = calendar.component(.minute, from: end)
                        
                        let startY = (CGFloat(startHour) * hourHeight) + (CGFloat(startMinute) / 60.0 * hourHeight) + 20
                        
                        let startDecimal = CGFloat(startHour) + CGFloat(startMinute) / 60.0
                        let endDecimal = CGFloat(endHour) + CGFloat(endMinute) / 60.0
                        let height = max((endDecimal - startDecimal) * hourHeight, 25)
                        
                        EventCard(event: event)
                            .frame(height: height - 2)
                            .padding(.leading, timeColumnWidth + 10)
                            .padding(.trailing, 10)
                            .offset(y: startY)
                    }
                }
                
                // --- LAYER 3: CURRENT TIME ---
                CurrentTimeLine(hourHeight: hourHeight, gridTopPadding: 20)
            }
            .frame(height: CGFloat(hours.count) * hourHeight + 100)
            .frame(maxWidth: .infinity) // Ensure it fills width too
        }
        .scrollIndicators(.hidden)
    }
}

// MARK: - HELPER: THE "GLASS" EVENT CARD
struct EventCard: View {
    var event: GTLRCalendar_Event
    
    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            // Accent Bar (Visual cue for "Event")
            Rectangle()
                .fill(Color.blue.opacity(0.8))
                .frame(width: 3)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(event.summary ?? "Untitled")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white.opacity(0.95))
                    .lineLimit(1)
                
                if let location = event.location {
                    Text(location)
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.6))
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            
            Spacer()
        }
        // STYLE: Match the Task List Texture
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(.white.opacity(0.15), lineWidth: 0.5)
        )
        // Shadow helps separate overlapping cards
        .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 2)
    }
}

// MARK: - HELPER: CURRENT TIME LINE
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
        
        // Match the grid logic exactly
        offset = (CGFloat(hour) * hourHeight) + (CGFloat(minute) / 60.0 * hourHeight) + gridTopPadding
    }
}
