import SwiftUI

struct RootView: View {
    @StateObject private var engine = SpellEngine()
    @StateObject private var world = World()
    @State private var library: [Track] = Grimoire.library()
    @State private var dragOrigin: CGPoint?
    @State private var dragMode: DragMode = .none
    @State private var showTitle: Double = 0

    private enum DragMode { case none, spin, scrub, dismiss }

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let maxR = min(size.width, size.height) * 0.42

            TimelineView(.animation) { timeline in
                let now = timeline.date.timeIntervalSinceReferenceDate
                let _ = world.step(now: now)

                ZStack {
                    Veil(world: world, bands: engine.bands, dna: engine.current?.dna)
                        .ignoresSafeArea()

                    Canvas(rendersAsynchronously: false) { context, canvasSize in
                        draw(context: &context,
                             size: canvasSize,
                             center: center,
                             maxR: maxR,
                             time: world.drift)
                    }
                    .ignoresSafeArea()
                    .drawingGroup()

                    Chrome(engine: engine, world: world, library: library, maxR: maxR)
                }
            }
            .background(Color.black)
            .contentShape(Rectangle())
            .gesture(dragGesture(center: center, maxR: maxR))
            .onTapGesture { location in
                handleTap(at: location, center: center, maxR: maxR)
            }
        }
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
    }

    // MARK: - Layout

    /// Where a glyph sits right now. Pure function of index + world state, so
    /// the hit-test and the renderer can never disagree.
    private func placement(_ index: Int,
                           center: CGPoint,
                           maxR: CGFloat,
                           time: Double) -> (point: CGPoint, radius: CGFloat, presence: Double) {
        let track = library[index]
        let dna = track.dna

        // Three orbits, evenly peopled, each turning at its own rate — so the
        // rings shear against each other and the field never resolves into a
        // static wheel.
        let ringIndex = index % 3
        let perRing = Double((library.count + 2) / 3)
        let withinRing = Double(index / 3)

        let angle = withinRing / perRing * .pi * 2
            + Double(ringIndex) * 0.7
            + dna.orbitPhase * 0.10
            + world.rotation * (0.7 + 0.22 * Double(ringIndex))
            + time * 0.012 * dna.orbitSpeed

        // Orbits breathe slowly in and out of each other, so the field never
        // reads as a grid pretending to be a galaxy.
        let wobble = 1 + 0.05 * sin(time * 0.23 + dna.orbitPhase * 3)
        let orbit = maxR * (0.46 + 0.29 * Double(ringIndex)) * wobble

        let isFocus = world.focused?.id == track.id
        let pull = isFocus ? world.bloom : 0
        // Unfocused glyphs are pushed out and dimmed as the mandala opens.
        let push = isFocus ? 0 : world.bloom

        let r = orbit * (1 - pull) + orbit * push * 0.55
        var point = CGPoint(x: center.x + cos(angle) * r,
                            y: center.y + sin(angle) * r * 0.95)
        if isFocus {
            point.x += (center.x - point.x) * world.bloom
            point.y += (center.y - point.y) * world.bloom
        }

        let baseRadius = maxR * (0.070 + 0.038 * dna.spikiness)
        let radius = isFocus
            ? baseRadius + (maxR * 0.92 - baseRadius) * world.bloom
            : baseRadius * (1 - 0.45 * world.bloom)

        let presence = isFocus ? 1.0 : (1 - 0.72 * world.bloom)
        return (point, radius, presence)
    }

    // MARK: - Drawing

    private func draw(context: inout GraphicsContext,
                      size: CGSize,
                      center: CGPoint,
                      maxR: CGFloat,
                      time: Double) {

        let bands = engine.bands

        // Haloes first, through one shared blur.
        var glow = context
        glow.addFilter(.blur(radius: maxR * 0.10))
        for i in library.indices {
            let p = placement(i, center: center, maxR: maxR, time: time)
            guard p.presence > 0.02 else { continue }
            SigilRenderer.halo(&glow, dna: library[i].dna,
                               center: p.point, radius: p.radius,
                               bands: world.focused?.id == library[i].id ? bands : SIMD3(0.2, 0.2, 0.1),
                               alpha: p.presence)
        }

        // The thread: a light-line from the burning sigil to the next in the
        // queue. It is the only "list" in the app.
        if world.bloom > 0.05, let focused = world.focused,
           let fi = library.firstIndex(of: focused) {
            let from = placement(fi, center: center, maxR: maxR, time: time)
            let next = (fi + 1) % library.count
            let to = placement(next, center: center, maxR: maxR, time: time)
            var thread = Path()
            thread.move(to: from.point)
            let mid = CGPoint(x: (from.point.x + to.point.x) / 2 + sin(time * 0.7) * maxR * 0.12,
                              y: (from.point.y + to.point.y) / 2 + cos(time * 0.5) * maxR * 0.12)
            thread.addQuadCurve(to: to.point, control: mid)
            var tctx = context
            tctx.blendMode = .plusLighter
            tctx.stroke(thread,
                        with: .linearGradient(
                            Gradient(colors: [focused.dna.color(0.2, brightness: 0.9).opacity(0.55 * world.bloom),
                                              library[next].dna.color(0.6, brightness: 0.8).opacity(0.10 * world.bloom)]),
                            startPoint: from.point, endPoint: to.point),
                        style: StrokeStyle(lineWidth: 1.2, lineCap: .round,
                                           dash: [2, 9], dashPhase: -time * 26))
        }

        // Glyphs.
        for i in library.indices {
            let p = placement(i, center: center, maxR: maxR, time: time)
            guard p.presence > 0.02 else { continue }
            let isFocus = world.focused?.id == library[i].id
            SigilRenderer.draw(&context,
                               dna: library[i].dna,
                               center: p.point,
                               radius: p.radius,
                               time: time + Double(i) * 3.7,
                               bands: isFocus ? bands : SIMD3(0.15, 0.12, 0.05),
                               bloom: isFocus ? world.bloom : 0,
                               alpha: p.presence)
        }

        // The ring: transport, drawn as an arc of the mandala itself.
        if world.bloom > 0.02 {
            drawRing(&context, center: center, maxR: maxR, time: time)
        }
    }

    private func drawRing(_ context: inout GraphicsContext, center: CGPoint, maxR: CGFloat, time: Double) {
        guard let dna = world.focused?.dna else { return }
        let r = maxR * 1.02
        let fraction = world.scrubbing ? world.scrubFraction
                                       : min(1, engine.position / SpellEngine.trackLength)

        var ctx = context
        ctx.blendMode = .plusLighter

        let track = Path { p in
            p.addArc(center: center, radius: r,
                     startAngle: .radians(-.pi / 2), endAngle: .radians(3 * .pi / 2), clockwise: false)
        }
        ctx.stroke(track, with: .color(.white.opacity(0.06 * world.bloom)), lineWidth: 1)

        let played = Path { p in
            p.addArc(center: center, radius: r,
                     startAngle: .radians(-.pi / 2),
                     endAngle: .radians(-.pi / 2 + fraction * .pi * 2), clockwise: false)
        }
        ctx.stroke(played,
                   with: .color(dna.color(0.4, brightness: 1).opacity((0.42 + 0.5 * world.scrubGlow) * world.bloom)),
                   style: StrokeStyle(lineWidth: 1.5 + 2.5 * world.scrubGlow, lineCap: .round))

        // The head: a single mote of light you can take hold of.
        let a = -Double.pi / 2 + fraction * .pi * 2
        let head = CGPoint(x: center.x + cos(a) * r, y: center.y + sin(a) * r)
        let hr = (3.0 + 5.0 * world.scrubGlow) * world.bloom
        ctx.fill(Path(ellipseIn: CGRect(x: head.x - hr, y: head.y - hr, width: hr * 2, height: hr * 2)),
                 with: .color(.white.opacity(0.9 * world.bloom)))
        _ = time
    }

    // MARK: - Input

    private func dragGesture(center: CGPoint, maxR: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { value in
                if dragOrigin == nil {
                    dragOrigin = value.startLocation
                    dragMode = mode(for: value, center: center, maxR: maxR)
                }
                switch dragMode {
                case .spin:
                    world.spinVelocity = Double(-value.velocity.width) / 900
                    world.rotation += Double(value.translation.width - lastTranslation) / 900
                    lastTranslation = value.translation.width
                case .scrub:
                    world.scrubbing = true
                    world.scrubFraction = fraction(of: value.location, center: center)
                    engine.seek(toFraction: world.scrubFraction)
                case .dismiss:
                    let d = max(0, Double(value.translation.height)) / 260
                    world.bloomTarget = max(0, 1 - d)
                case .none:
                    break
                }
            }
            .onEnded { value in
                switch dragMode {
                case .spin:
                    world.spinVelocity = Double(-value.predictedEndTranslation.width - value.translation.width) / 3000
                case .scrub:
                    world.scrubbing = false
                case .dismiss:
                    if world.bloomTarget < 0.55 {
                        world.bloomTarget = 0
                        world.focused = nil
                        engine.dismiss()
                    } else {
                        world.bloomTarget = 1
                    }
                case .none:
                    break
                }
                dragOrigin = nil
                dragMode = .none
                lastTranslation = 0
            }
    }

    @State private var lastTranslation: CGFloat = 0

    private func mode(for value: DragGesture.Value, center: CGPoint, maxR: CGFloat) -> DragMode {
        guard world.bloom > 0.5 else { return .spin }
        let d = hypot(value.startLocation.x - center.x, value.startLocation.y - center.y)
        if d > maxR * 0.80 { return .scrub }
        if value.translation.height > abs(value.translation.width) { return .dismiss }
        return .spin
    }

    private func fraction(of point: CGPoint, center: CGPoint) -> Double {
        var a = atan2(point.y - center.y, point.x - center.x) + .pi / 2
        if a < 0 { a += .pi * 2 }
        return min(1, max(0, a / (.pi * 2)))
    }

    private func handleTap(at location: CGPoint, center: CGPoint, maxR: CGFloat) {
        if world.bloom > 0.6 {
            // Tapping the burning core holds the breath.
            let d = hypot(location.x - center.x, location.y - center.y)
            if d < maxR * 0.25 {
                engine.togglePlay()
                return
            }
        }

        var best: (index: Int, distance: CGFloat)?
        for i in library.indices {
            let p = placement(i, center: center, maxR: maxR, time: world.drift)
            guard p.presence > 0.15 else { continue }
            let d = hypot(location.x - p.point.x, location.y - p.point.y)
            if d < max(44, p.radius * 1.6), best == nil || d < best!.distance {
                best = (i, d)
            }
        }
        guard let hit = best else { return }
        summon(library[hit.index], index: hit.index)
    }

    private func summon(_ track: Track, index: Int) {
        world.focused = track
        world.focusIndex = index
        world.bloomTarget = 1
        engine.summon(track)
    }
}
