import SwiftUI
import SwiftData
import GoogleSignIn
import GoogleSignInSwift
import GoogleAPIClientForREST_Calendar

struct ContentView: View {
    @Environment(CalendarManager.self) var calendarManager
    @Environment(\.modelContext) var modelContext
    
    // Popup State
    @State private var showNewTask = false
    
    // SwiftData Query
    @Query(filter: #Predicate<LatticeTask> { !$0.isArchived },
           sort: \LatticeTask.dateCreated,
           order: .reverse)
    var tasks: [LatticeTask]

    var body: some View {
        NavigationStack {
            if calendarManager.user != nil {
                
                ZStack {
                    // --- 1. GLOBAL BACKGROUND (Stationary) ---
                    // The pages will slide OVER this background
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
                    
                    // --- 2. SWIPEABLE PAGES ---
                    TabView {
                        
                        // PAGE 1: TASKS
                        TaskPageView(tasks: tasks, showNewTask: $showNewTask, modelContext: modelContext)
                            .tag(0)
                        
                        // PAGE 2: CALENDAR
                        CalendarPageView(events: calendarManager.events)
                            .tag(1)
                        
                    }
                    .tabViewStyle(.page(indexDisplayMode: .always)) // Enables the swipe dots
                    .ignoresSafeArea(.container, edges: .bottom)
                    
                    // --- 3. POPUP OVERLAY ---
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
                // LOGGED OUT VIEW
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
                .preferredColorScheme(.dark)
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

// MARK: - SUBVIEW 1: TASK PAGE
struct TaskPageView: View {
    var tasks: [LatticeTask]
    @Binding var showNewTask: Bool
    var modelContext: ModelContext
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("TASKS")
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                    .tracking(4)
                    .foregroundColor(.white.opacity(0.6))
                Spacer()
            }
            .padding(.top, 20)
            .padding(.horizontal, 30)
            .padding(.bottom, 10)
            
            // List
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
                    .transition(.asymmetric(insertion: .identity, removal: .move(edge: .leading)))
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
            
            // Create Button
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

// MARK: - SUBVIEW 2: CALENDAR PAGE
struct CalendarPageView: View {
    // We use the raw Google Events here
    var events: [GTLRCalendar_Event]
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("SCHEDULE")
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                    .tracking(4)
                    .foregroundColor(.white.opacity(0.6))
                Spacer()
            }
            .padding(.top, 20)
            .padding(.horizontal, 30)
            .padding(.bottom, 10)
            
            // Event List
            if events.isEmpty {
                VStack {
                    Spacer()
                    Image(systemName: "calendar")
                        .font(.system(size: 50))
                        .foregroundColor(.white.opacity(0.2))
                        .padding(.bottom, 10)
                    Text("No events today")
                        .foregroundColor(.white.opacity(0.4))
                    Spacer()
                }
            } else {
                List {
                    Color.clear.frame(height: 10).listRowBackground(Color.clear).listRowSeparator(.hidden)
                    
                    ForEach(events, id: \.identifier) { event in
                        HStack {
                            // Time Column
                            VStack(alignment: .center) {
                                if let start = event.start?.dateTime?.date {
                                    Text(start.formatted(date: .omitted, time: .shortened))
                                        .font(.caption2)
                                        .fontWeight(.bold)
                                        .foregroundColor(.white)
                                } else {
                                    Text("ALL DAY")
                                        .font(.caption2)
                                        .fontWeight(.bold)
                                        .foregroundColor(.white.opacity(0.7))
                                }
                            }
                            .frame(width: 60)
                            
                            // Event Details
                            VStack(alignment: .leading, spacing: 4) {
                                Text(event.summary ?? "Untitled")
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundColor(.white.opacity(0.9))
                                
                                if let end = event.end?.dateTime?.date {
                                    Text("Ends at \(end.formatted(date: .omitted, time: .shortened))")
                                        .font(.caption)
                                        .foregroundColor(.gray)
                                }
                            }
                            .padding(.vertical, 16)
                            
                            Spacer()
                        }
                        .padding(.horizontal, 10)
                        .background(.ultraThinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        // Gold/Orange border to distinguish from Tasks
                        .overlay(RoundedRectangle(cornerRadius: 16).stroke(.orange.opacity(0.15), lineWidth: 0.5))
                        .shadow(color: .black.opacity(0.2), radius: 10, x: 0, y: 5)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 8, leading: 20, bottom: 8, trailing: 20))
                    }
                    
                    Color.clear.frame(height: 40).listRowBackground(Color.clear).listRowSeparator(.hidden)
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .scrollIndicators(.hidden)
                .mask(
                    VStack(spacing: 0) {
                        LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom).frame(height: 40)
                        Rectangle().fill(.black)
                        LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom).frame(height: 60)
                    }
                )
            }
        }
    }
}
