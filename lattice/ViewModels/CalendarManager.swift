//
//  CalendarManager.swift
//  lattice
//
//  Created by Joshua Zhang on 2026-01-21.
//


import Foundation
import GoogleSignIn
import GoogleAPIClientForREST_Calendar

@Observable
class CalendarManager {
    // 1. Add this variable to track login state
    var user: GIDGoogleUser?
    
    private let service = GTLRCalendarService()
    var events: [GTLRCalendar_Event] = []
    
    func setup(with user: GIDGoogleUser) {
        // 2. Save the user here
        self.user = user
        service.authorizer = user.fetcherAuthorizer
    }
    
    func fetchTodayEvents() {
        let query = GTLRCalendarQuery_EventsList.query(withCalendarId: "primary")
        
        // precise time configuration for "Today"
        let startOfDay = Calendar.current.startOfDay(for: Date())
        query.timeMin = GTLRDateTime(date: startOfDay)
        query.singleEvents = true
        query.orderBy = kGTLRCalendarOrderByStartTime
        
        service.executeQuery(query) { [weak self] _, result, error in
            if let error = error {
                print("Error fetching events: \(error.localizedDescription)")
                return
            }
            
            if let calendarEvents = result as? GTLRCalendar_Events {
                self?.events = calendarEvents.items ?? []
                print("Success! Fetched \(self?.events.count ?? 0) events.")
            }
        }
    }
    
    // 3. Add this function to check for saved logins on startup
    func checkPreviousSignIn() {
        GIDSignIn.sharedInstance.restorePreviousSignIn { [weak self] user, error in
            if let user = user {
                self?.setup(with: user)
                self?.fetchTodayEvents()
            }
        }
    }
}

