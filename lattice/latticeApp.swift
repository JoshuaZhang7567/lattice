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


