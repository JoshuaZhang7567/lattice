//
//  latticeApp.swift
//  lattice
//
//  Created by Joshua Zhang on 2026-01-21.
//

import SwiftUI
import SwiftData
import GoogleSignIn

@main
struct latticeApp: App {
    // Initialize your Calendar Manager
    @State private var calendarManager = CalendarManager()

    var body: some Scene {
        WindowGroup {
            ContentView()
                // Pass the manager to your views
                .environment(calendarManager)
                // Handle the return from Google Sign-In website
                .onOpenURL { url in
                    GIDSignIn.sharedInstance.handle(url)
                }
        }
        // Initialize the Database
        .modelContainer(for: LatticeTask.self)
    }
}


//old code from project creation

/*
import SwiftUI
import SwiftData

@main
struct latticeApp: App {
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Item.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(sharedModelContainer)
    }
}
*/
