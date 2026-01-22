//
//  LatticeTask.swift
//  lattice
//
//  Created by Joshua Zhang on 2026-01-21.
//

import Foundation
import SwiftData

@Model
final class LatticeTask {
    var title: String
    var durationMinutes: Int
    var dateCreated: Date
    var targetDate: Date // <--- NEW: Stores the scheduled date/time
    var isScheduled: Bool = false
    var isArchived: Bool = false
    
    init(title: String, durationMinutes: Int = 60, targetDate: Date = Date()) {
        self.title = title
        self.durationMinutes = durationMinutes
        self.dateCreated = Date()
        self.targetDate = targetDate
        self.isArchived = false
    }
}


