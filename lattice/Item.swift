//
//  Item.swift
//  lattice
//
//  Created by Joshua Zhang on 2026-01-21.
//

import Foundation
import SwiftData

@Model
final class Item {
    var timestamp: Date
    
    init(timestamp: Date) {
        self.timestamp = timestamp
    }
}
