import SwiftUI

struct SettingsView: View {
    @Environment(CalendarManager.self) var calendarManager
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            VStack(spacing: 30) {
                // Header
                Text("Settings")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                    .padding(.top, 20)
                
                // Scheduling Hours
                VStack(spacing: 20) {
                    Text("Scheduling Hours")
                        .font(.headline)
                        .foregroundColor(.white.opacity(0.8))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.leading, 40)
                    
                    // Start Time
                    HStack {
                        Text("Day Start")
                            .foregroundColor(.white.opacity(0.6))
                        Spacer()
                        Text(formatHour(calendarManager.dayStartHour))
                            .foregroundColor(.white)
                            .bold()
                        Stepper("", value: Bindable(calendarManager).dayStartHour, in: 0...23)
                            .labelsHidden()
                    }
                    .padding(.horizontal, 40)
                    
                    // End Time
                    HStack {
                        Text("Day End")
                            .foregroundColor(.white.opacity(0.6))
                        Spacer()
                        Text(formatHour(calendarManager.dayEndHour))
                            .foregroundColor(.white)
                            .bold()
                        Stepper("", value: Bindable(calendarManager).dayEndHour, in: 0...23)
                            .labelsHidden()
                    }
                    .padding(.horizontal, 40)
                }
                
                Spacer()
                
                // Sign Out Button
                Button(action: {
                    withAnimation {
                        calendarManager.signOut()
                        dismiss()
                    }
                }) {
                    Text("Log Out")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(Color.red.opacity(0.8))
                        .cornerRadius(12)
                }
                .padding(.horizontal, 40)
                
                Spacer()
            }
            .padding()
        }
        .preferredColorScheme(.dark)
    }
    
    func formatHour(_ hour: Int) -> String {
        let date = Calendar.current.date(bySettingHour: hour, minute: 0, second: 0, of: Date())!
        return date.formatted(date: .omitted, time: .shortened)
    }
}
