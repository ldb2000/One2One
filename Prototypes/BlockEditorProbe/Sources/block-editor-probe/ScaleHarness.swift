import AppKit
import ProbeCore

/// Mesure la tenue à l'échelle : montage initial, fluidité au défilement,
/// latence de frappe. Les trois chiffres partent tels quels dans l'ADR de
/// verdict — c'est leur seule raison d'être.
@MainActor
enum ScaleHarness {

    static func run(blockCount: Int) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 620),
            styleMask: [.titled, .resizable],
            backing: .buffered,
            defer: false)

        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 720, height: 620))
        scroll.hasVerticalScroller = true
        window.contentView = scroll
        window.makeKeyAndOrderFront(nil)

        let coordinator = SelectionCoordinator(
            document: ProbeDocument(texts: SampleText.blocks(count: blockCount)))
        let stack = BlockStackView(coordinator: coordinator)
        stack.setFrameSize(NSSize(width: scroll.contentSize.width, height: 400))
        scroll.documentView = stack

        let mount = measureMount(coordinator: coordinator, stack: stack, scroll: scroll)
        let scrolling = measureScrolling(scroll: scroll, stack: stack)
        let typing = measureTyping(coordinator: coordinator, stack: stack, blockCount: blockCount)

        report(blockCount: blockCount, mount: mount, scrolling: scrolling, typing: typing)
        window.orderOut(nil)
    }

    // MARK: - Les trois mesures

    /// Montage initial : de la pose du document à la première disposition
    /// complète, affichage compris.
    private static func measureMount(coordinator: SelectionCoordinator,
                                     stack: BlockStackView,
                                     scroll: NSScrollView) -> Double {
        let start = CFAbsoluteTimeGetCurrent()
        coordinator.attach(stack: stack)
        stack.layoutSubtreeIfNeeded()
        scroll.displayIfNeeded()
        return (CFAbsoluteTimeGetCurrent() - start) * 1000
    }

    /// Défilement : quarante pas du haut vers le bas, chacun forcé à
    /// s'afficher. On rapporte le pire pas, celui qui se verrait à l'œil.
    private static func measureScrolling(scroll: NSScrollView, stack: BlockStackView) -> [Double] {
        let steps = 40
        let travel = max(stack.frame.height - scroll.contentSize.height, 1)
        var samples: [Double] = []

        for step in 0...steps {
            let y = travel * CGFloat(step) / CGFloat(steps)
            let start = CFAbsoluteTimeGetCurrent()
            scroll.contentView.scroll(to: NSPoint(x: 0, y: y))
            scroll.reflectScrolledClipView(scroll.contentView)
            scroll.displayIfNeeded()
            samples.append((CFAbsoluteTimeGetCurrent() - start) * 1000)
        }
        return samples
    }

    /// Latence de frappe : deux cents caractères insérés par le vrai chemin,
    /// dans un bloc au milieu du document, disposition et affichage compris.
    private static func measureTyping(coordinator: SelectionCoordinator,
                                      stack: BlockStackView,
                                      blockCount: Int) -> [Double] {
        let target = blockCount / 2
        guard let view = stack.view(at: target) else { return [] }
        view.window?.makeFirstResponder(view)
        coordinator.setSelection(ProbeSelection(
            caret: ProbePosition(blockIndex: target, offset: coordinator.document.blocks[target].length)))

        var samples: [Double] = []
        for index in 0..<200 {
            let start = CFAbsoluteTimeGetCurrent()
            view.insertText("x", replacementRange: view.selectedRange())
            stack.layoutSubtreeIfNeeded()
            view.displayIfNeeded()
            samples.append((CFAbsoluteTimeGetCurrent() - start) * 1000)
            if index % 40 == 39 {
                // Une frappe sur cinq déclenche un retour à la ligne : c'est
                // le cas coûteux, on veut qu'il soit dans l'échantillon.
                stack.needsLayout = true
            }
        }
        return samples
    }

    // MARK: - Rapport

    private static func report(blockCount: Int,
                               mount: Double,
                               scrolling: [Double],
                               typing: [Double]) {
        print("")
        print("Tenue à l'échelle — \(blockCount) blocs, \(ProcessInfo.processInfo.operatingSystemVersionString)")
        print("---------------------------------------------------------------")
        print(String(format: "Montage initial            %8.1f ms", mount))
        print(String(format: "Défilement, pas médian     %8.2f ms", percentile(scrolling, 0.50)))
        print(String(format: "Défilement, pire pas       %8.2f ms", scrolling.max() ?? 0))
        print(String(format: "Frappe, médiane            %8.2f ms", percentile(typing, 0.50)))
        print(String(format: "Frappe, 95e centile        %8.2f ms", percentile(typing, 0.95)))
        print(String(format: "Frappe, pire cas           %8.2f ms", typing.max() ?? 0))
        print("---------------------------------------------------------------")
        print("Repère : un pas de défilement au-delà de 16,7 ms saute une image.")
        print("Repère : une frappe au-delà de 16,7 ms se sent au doigt.")
        print("")
    }

    private static func percentile(_ samples: [Double], _ fraction: Double) -> Double {
        guard !samples.isEmpty else { return 0 }
        let sorted = samples.sorted()
        let index = Int((Double(sorted.count - 1) * fraction).rounded())
        return sorted[index]
    }
}
