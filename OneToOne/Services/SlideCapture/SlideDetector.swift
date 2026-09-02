/// Décide, à partir d'une suite d'empreintes, quand un nouveau slide doit être enregistré.
///
/// On n'écrit jamais une image en mouvement. Tout écart au-dessus du seuil de mouvement
/// « arme » l'attente ; l'écriture n'a lieu qu'une fois l'image stable pendant
/// `stableTicksRequired` ticks. Le détecteur se réarme aussi quand l'écran s'est éloigné
/// du dernier slide **acquitté**, même si aucun tick isolé n'a franchi le seuil : sans
/// cela, une dérive lente (fondu, Morph, défilement lent d'un PDF) ne produirait jamais
/// rien.
///
/// Ce type ne fait aucune I/O : déterministe et testable par séquences de décisions.
struct SlideDetector: Sendable {

    enum Decision: Equatable, Sendable {
        /// Le contenu bouge, ou il n'y a pas encore de référence : on attend.
        case settling
        /// Contenu stable déjà traité : rien à faire.
        case ignore
        /// Un nouveau slide vient de se stabiliser : l'appelant doit l'écrire.
        case newSlide
        /// Slide déjà enregistré dans cette session : ne pas réécrire.
        case duplicate
    }

    private let movementThreshold: Double
    private let identityThreshold: Double
    private let stableTicksRequired: Int

    private var previous: SlideFingerprint?
    private var stableTicks = 0
    /// Armé dès la construction : sinon le slide déjà affiché au démarrage ne serait
    /// jamais écrit, et le slide de titre serait systématiquement perdu.
    private var armed = true
    private var recorded: [SlideFingerprint] = []
    /// Dernier slide acquitté (écrit **ou** reconnu doublon) : ce qui est réellement à
    /// l'écran, contrairement à `recorded.last` qui, après un doublon, ne l'est plus.
    private var acknowledged: SlideFingerprint?

    init(settings: SlideCaptureSettings) {
        self.movementThreshold = settings.movementThreshold
        self.identityThreshold = settings.identityThreshold
        self.stableTicksRequired = max(1, settings.stableTicksRequired)
    }

    /// Nombre de slides retenus (ceux consommés et ceux réamorcés par `seed`).
    var recordedCount: Int { recorded.count }

    /// Ajoute des empreintes déjà connues à l'historique anti-doublon, sans toucher à
    /// l'état de stabilisation. Sert à reprendre un lot existant.
    mutating func seed(_ known: [SlideFingerprint]) {
        recorded.append(contentsOf: known)
    }

    mutating func consume(_ fingerprint: SlideFingerprint) -> Decision {
        defer { previous = fingerprint }

        guard let previous else { return .settling }

        if fingerprint.distance(to: previous) >= movementThreshold {
            armed = true
            stableTicks = 0
            return .settling
        }

        // Dérive lente : aucun tick n'a franchi le seuil, mais l'écran s'est éloigné du
        // slide acquitté.
        if !armed, let acknowledged, fingerprint.distance(to: acknowledged) >= movementThreshold {
            armed = true
            stableTicks = 0
        }

        stableTicks += 1
        guard armed, stableTicks >= stableTicksRequired else { return .ignore }

        armed = false
        stableTicks = 0

        if recorded.contains(where: { $0.distance(to: fingerprint) < identityThreshold }) {
            acknowledged = fingerprint
            return .duplicate
        }
        recorded.append(fingerprint)
        acknowledged = fingerprint
        return .newSlide
    }
}
