import Foundation
import EventKit
import AppKit

class RemindersService: ObservableObject {
    private let eventStore = EKEventStore()
    
    func requestAccess() async -> Bool {
        do {
            let granted = try await eventStore.requestFullAccessToReminders()
            return granted
        } catch {
            print("Error requesting Reminders access: \(error)")
            return false
        }
    }
    
    func createReminder(title: String, dueDate: Date?) async -> String? {
        let reminder = EKReminder(eventStore: eventStore)
        reminder.title = title
        reminder.dueDateComponents = dueDate.flatMap { Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: $0) }
        reminder.calendar = eventStore.defaultCalendarForNewReminders()
        
        do {
            try eventStore.save(reminder, commit: true)
            return reminder.calendarItemIdentifier
        } catch {
            print("Error saving reminder: \(error)")
            return nil
        }
    }
}

class MickeyService: ObservableObject {
    func startRecording() {
        // Hypothèse: Mickey répond à un URL Scheme pour démarrer l'enregistrement
        if let url = URL(string: "mickey://start") {
            NSWorkspace.shared.open(url)
        }
        // Alternative: AppleScript
        /*
        let scriptSource = "tell application \"Mickey\" to start recording"
        if let script = NSAppleScript(source: scriptSource) {
            script.executeAndReturnError(nil)
        }
        */
    }
    
    func stopRecording() {
        if let url = URL(string: "mickey://stop") {
            NSWorkspace.shared.open(url)
        }
    }
}
