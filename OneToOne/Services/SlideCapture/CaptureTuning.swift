import Foundation

/// Les réglages que l'utilisateur a modifiés **à la main**.
///
/// Copié de `SessionController.TunedField` du dépôt Teams-Capture
/// (programme §2.5). Sans ce garde-fou, changer le type de la réunion
/// détruirait silencieusement un réglage fin : on choisit « Atelier » pour la
/// périodicité et on perd la sensibilité qu'on venait de baisser.
///
/// Type valeur et fonction pure : la règle se teste sans écran ni base.
struct CaptureTuning: Equatable, Sendable {

    enum Field: Hashable, Sendable {
        case sensitivity
        case automaticDetection
        case periodicCapture
    }

    private(set) var touched: Set<Field> = []

    init(touched: Set<Field> = []) {
        self.touched = touched
    }

    mutating func markTouched(_ field: Field) {
        touched.insert(field)
    }

    func contains(_ field: Field) -> Bool { touched.contains(field) }

    /// Applique le profil d'un type de réunion à des réglages existants, en
    /// **épargnant** les champs déjà touchés à la main.
    func apply(_ profile: CaptureProfile, to settings: SlideCaptureSettings) -> SlideCaptureSettings {
        var resultat = settings
        if !contains(.sensitivity) { resultat.sensitivity = profile.sensitivity }
        if !contains(.automaticDetection) { resultat.detectsAutomatically = profile.detectsAutomatically }
        if !contains(.periodicCapture) { resultat.periodicCapture = profile.periodicCapture }
        return resultat
    }
}
