//
//  ArchivePageView.swift
//  lattice
//
//  Created by Joshua Zhang on 2026-01-23.
//

import SwiftUI
import SwiftData

struct ArchivePageView: View {
    var tasks: [LatticeTask]
    var modelContext: ModelContext
    
    // Filter for Past Week
    var recentArchivedTasks: [LatticeTask] {
        let oneWeekAgo = Date().addingTimeInterval(-604800) // 7 days
        return tasks.filter { $0.dateCreated > oneWeekAgo }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            if recentArchivedTasks.isEmpty {
                VStack(spacing: 15) {
                    Spacer()
                    Image(systemName: "archivebox")
                        .font(.system(size: 50))
                        .foregroundColor(.white.opacity(0.2))
                    Text("No archived tasks this week")
                        .foregroundColor(.white.opacity(0.4))
                    Spacer()
                }
            } else {
                List {
                    Color.clear.frame(height: 10).listRowBackground(Color.clear).listRowSeparator(.hidden)
                    
                    ForEach(recentArchivedTasks) { task in
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(task.title)
                                    .font(.system(size: 17, weight: .medium))
                                    .foregroundColor(.white.opacity(0.6))
                                    .strikethrough()
                                
                                Text("Completed")
                                    .font(.caption)
                                    .foregroundColor(.green.opacity(0.8))
                            }
                            .padding(.vertical, 18)
                            .padding(.horizontal, 20)
                            
                            Spacer()
                            
                            // Restore Button
                            Button {
                                withAnimation { task.isArchived = false }
                            } label: {
                                Image(systemName: "arrow.uturn.backward")
                                    .foregroundColor(.blue)
                                    .padding()
                            }
                        }
                        .background(.ultraThinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .overlay(RoundedRectangle(cornerRadius: 16).stroke(.white.opacity(0.05), lineWidth: 0.5))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 8, leading: 20, bottom: 8, trailing: 20))
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
    }
}
