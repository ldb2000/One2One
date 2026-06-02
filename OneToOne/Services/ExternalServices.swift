import Foundation
import EventKit
import AppKit

class RemindersService: ObservableObject {
    private let eventStore = EKEventStore()

    /// Demande l'autorisation d'accès complet aux Rappels (requise par EventKit
    /// avant toute lecture/écriture). Retourne `false` si refusée ou en erreur.
    func requestAccess() async -> Bool {
        do {
            let granted = try await eventStore.requestFullAccessToReminders()
            return granted
        } catch {
            print("Error requesting Reminders access: \(error)")
            return false
        }
    }
    
    /// Crée un rappel dans le calendrier par défaut des Rappels.
    /// Retourne l'identifiant de l'item créé, ou `nil` si la sauvegarde échoue.
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
    /// Démarre l'enregistrement Mickey via son URL Scheme (`mickey://start`).
    /// Aucune alternative de repli : si l'app Mickey n'est pas installée ou
    /// n'enregistre pas ce scheme, l'ouverture est silencieusement ignorée.
    func startRecording() {
        // Hypothèse: Mickey répond à un URL Scheme pour démarrer l'enregistrement
        if let url = URL(string: "mickey://start") {
            NSWorkspace.shared.open(url)
        }
    }
    
    func stopRecording() {
        if let url = URL(string: "mickey://stop") {
            NSWorkspace.shared.open(url)
        }
    }
}
