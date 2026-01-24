//
//  NewTaskOverlay.swift
//  lattice
//
//  Created by Joshua Zhang on 2026-01-22.
//

import SwiftUI

struct NewTaskOverlay: View {
    @Binding var isPresented: Bool
    var onSave: (String, Date, Int) -> Void
    
    @State private var title: String = ""
    @State private var selectedDate: Date = Date()
    @State private var durationHours: Double = 1.0
    
    var body: some View {
        ZStack {
            // Background Dim
            Color.black.opacity(0.6)
                .ignoresSafeArea()
                .onTapGesture {
                    withAnimation { isPresented = false }
                }
            
            // COMPACT GLASS CARD
            VStack(spacing: 16) { // Reduced spacing from 20
                
                // 1. Header & Title Input
                VStack(alignment: .leading, spacing: 8) {
                    Text("New Task")
                        .font(.headline)
                        .foregroundColor(.gray)
                        .textCase(.uppercase)
                        .tracking(2)
                    
                    TextField("", text: $title, prompt: Text("What needs doing?").foregroundColor(.white.opacity(0.5)))
                        .font(.system(size: 22, weight: .semibold)) // Bigger font for input
                        .foregroundColor(.white)
                        .submitLabel(.done)
                }
                
                Divider().background(Color.white.opacity(0.2))
            
                
                // 2. Date Picker (COMPACT ROW)
                HStack {
                    Image(systemName: "calendar.badge.clock") // Changed icon to indicate deadline
                        .foregroundColor(.red) // Red to indicate urgency/deadline
                    Text("Due Date") // CHANGED FROM "Start Time"
                        .foregroundColor(.white.opacity(0.8))
                    Spacer()
                    DatePicker("", selection: $selectedDate)
                        .labelsHidden()
                        .colorScheme(.dark)
                }
                .padding(.vertical, 4)
                
                // 3. Duration Slider (COMPACT ROW)
                VStack(spacing: 8) {
                    HStack {
                        Image(systemName: "clock")
                            .foregroundColor(.blue)
                        Text("Duration")
                            .foregroundColor(.white.opacity(0.8))
                        Spacer()
                        Text("\(String(format: "%g", durationHours))h")
                            .font(.headline)
                            .foregroundColor(.blue)
                            .monospacedDigit()
                    }
                    
                    Slider(value: $durationHours, in: 0.5...8, step: 0.5)
                        .tint(.blue)
                }
                .padding(.vertical, 4)
                
                // 4. Action Buttons
                HStack(spacing: 12) {
                    Button {
                        withAnimation { isPresented = false }
                    } label: {
                        Text("Cancel")
                            .font(.subheadline.weight(.medium))
                            .foregroundColor(.white.opacity(0.6))
                            .frame(maxWidth: .infinity)
                            .frame(height: 44)
                            .background(Color.white.opacity(0.1))
                            .cornerRadius(12)
                    }
                    
                    Button {
                        let minutes = Int(durationHours * 60)
                        onSave(title.isEmpty ? "Untitled Task" : title, selectedDate, minutes)
                        withAnimation { isPresented = false }
                    } label: {
                        Text("Create Task")
                            .font(.subheadline.weight(.bold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 44)
                            .background(Color.blue)
                            .cornerRadius(12)
                    }
                }
                .padding(.top, 8)
            }
            .padding(20) // Tighter outer padding
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(.white.opacity(0.15), lineWidth: 0.5)
            )
            .shadow(color: .black.opacity(0.5), radius: 30, x: 0, y: 15)
            .padding(.horizontal, 30) // Keeps it from touching screen edges
        }
    }
}
