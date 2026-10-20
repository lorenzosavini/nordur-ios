import SwiftUI
import AVFoundation
import CoreMotion

/// "Find the aurora with the camera": the camera on screen, and over it a
/// marker where the aurora should be (the direction and height worked out from
/// the OVATION oval or the Kp), with arrows to turn and tilt until it says
/// "look here". Like the apps that show the stars.
struct AuroraFinderView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var motion = PointingTracker()
    @State private var camera = CameraPreview.Session()
    @State private var onTarget = false

    /// Field of view of the main camera held upright (degrees).
    private let fovH = 56.0, fovV = 72.0

    var body: some View {
        let slot = model.auroraNow
        let overhead = slot?.geometry == .overhead
        // No direction from the model: towards the magnetic pole (north-west of Iceland), low on the horizon.
        let targetAz = slot?.lookAzimuth ?? ViewingGeometry.bearing(from: model.activePlace.coordinate,
                                                                    to: Coordinate(lat: Geomagnetic.poleLat, lon: Geomagnetic.poleLon))
        let targetEl = overhead ? 75 : max(8, min(70, slot?.lookElevation ?? 18))
        GeometryReader { geo in
            ZStack {
                CameraPreview(session: camera).ignoresSafeArea()
                if camera.denied {
                    Color.black.ignoresSafeArea()
                    Text("Consenti la fotocamera in Impostazioni › Norður per usare il mirino.")
                        .font(.app(.headline)).foregroundStyle(.white).multilineTextAlignment(.center).padding(30)
                }
                if let az = motion.azimuth, let el = motion.elevation {
                    let dAz = Self.delta(targetAz, az)
                    let dEl = targetEl - el
                    let x = geo.size.width / 2 + CGFloat(dAz / fovH) * geo.size.width
                    let y = geo.size.height / 2 - CGFloat(dEl / fovV) * geo.size.height
                    let inView = abs(dAz) < fovH / 2 - 4 && abs(dEl) < fovV / 2 - 4
                    let close = abs(dAz) < 9 && abs(dEl) < 9
                    // Horizon line (0° elevation) and compass marks.
                    horizon(geo.size, el: el, az: az)
                    if inView {
                        Target(close: close).position(x: x, y: y)
                    } else {
                        EdgeArrow(dAz: dAz, dEl: dEl, size: geo.size)
                    }
                    Crosshair(close: close).position(x: geo.size.width / 2, y: geo.size.height / 2)
                    Color.clear.onChange(of: close) { _, now in
                        if now && !onTarget { Haptics.result(true) }
                        onTarget = now
                    }
                    VStack {
                        instruction(dAz: dAz, dEl: dEl, close: close, overhead: overhead)
                        Spacer()
                    }
                    .padding(.top, 70)
                } else {
                    Text("Muovi il telefono in un otto per tarare la bussola…")
                        .font(.app(.headline)).foregroundStyle(.white)
                        .padding(14).background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 12))
                }
                VStack {
                    HStack {
                        Spacer()
                        Button { dismiss() } label: {
                            Image(systemName: "xmark").font(.system(size: 17, weight: .bold)).foregroundStyle(.white)
                                .frame(width: 44, height: 44).background(.black.opacity(0.5), in: Circle())
                        }
                        .accessibilityLabel(String(localized: "Chiudi"))
                    }
                    .padding(.horizontal, 16).padding(.top, 12)
                    Spacer()
                    info(slot: slot, az: targetAz, el: targetEl, overhead: overhead)
                }
            }
        }
        .background(Color.black)
        .preferredColorScheme(.dark)
        .onAppear { motion.start(); camera.start() }
        .onDisappear { motion.stop(); camera.stop() }
    }

    /// −180…180: how far to turn (positive: to the right).
    static func delta(_ target: Double, _ current: Double) -> Double {
        var d = (target - current).truncatingRemainder(dividingBy: 360)
        if d > 180 { d -= 360 }
        if d < -180 { d += 360 }
        return d
    }

    private func instruction(dAz: Double, dEl: Double, close: Bool, overhead: Bool) -> some View {
        let text: String
        if close {
            text = overhead ? String(localized: "Guarda qui: sopra di te") : String(localized: "Guarda qui!")
        } else if abs(dAz) >= 9 {
            text = dAz > 0 ? String(localized: "Gira a destra di \(Int(abs(dAz).rounded()))°") : String(localized: "Gira a sinistra di \(Int(abs(dAz).rounded()))°")
        } else {
            text = dEl > 0 ? String(localized: "Alza il telefono di \(Int(abs(dEl).rounded()))°") : String(localized: "Abbassa il telefono di \(Int(abs(dEl).rounded()))°")
        }
        return Text(text)
            .font(.app(.title3, .semibold)).foregroundStyle(close ? Color.black : .white)
            .padding(.horizontal, 18).padding(.vertical, 10)
            .background(close ? Theme.aurora : .black.opacity(0.55), in: Capsule())
            .animation(.snappy, value: close)
    }

    private func info(slot: AuroraSlot?, az: Double, el: Double, overhead: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(overhead ? String(localized: "Aurora sopra di te: guarda in alto") :
                    String(localized: "Direzione \(Fmt.compass(az)) \(String(format: "%03d", Int(az.rounded())))° · altezza \(Int(el.rounded()))°"))
                .font(.app(.headline)).foregroundStyle(.white)
            if let slot {
                Text(String(localized: "Adesso qui: \(slot.observability.label.lowercased())") + (slot.reasons.first.map { " · " + $0 } ?? ""))
                    .font(.app(.subheadline)).foregroundStyle(.white.opacity(0.85))
            }
            Text("La fotocamera vede l'aurora debole meglio dell'occhio: se non vedi niente, prova una foto in modalità Notte verso il mirino.")
                .font(.app(.caption)).foregroundStyle(.white.opacity(0.7))
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal, 12).padding(.bottom, 24)
    }

    /// The horizon and the cardinal points along it.
    private func horizon(_ size: CGSize, el: Double, az: Double) -> some View {
        let y = size.height / 2 + CGFloat(el / fovV) * size.height
        return ZStack {
            Rectangle().fill(.white.opacity(0.35)).frame(height: 1).position(x: size.width / 2, y: y)
            ForEach([0.0, 45, 90, 135, 180, 225, 270, 315], id: \.self) { mark in
                let d = Self.delta(mark, az)
                if abs(d) < fovH / 2 {
                    Text(Fmt.compass(mark)).font(.mono(13, .bold)).foregroundStyle(mark == 0 ? Theme.accent : .white.opacity(0.8))
                        .position(x: size.width / 2 + CGFloat(d / fovH) * size.width, y: y - 14)
                }
            }
        }
    }
}

/// Where the camera points: compass azimuth and height above the horizon, from
/// the device motion (true north when the location is known).
@Observable
final class PointingTracker {
    private(set) var azimuth: Double?
    private(set) var elevation: Double?
    @ObservationIgnored private let manager = CMMotionManager()

    func start() {
        guard manager.isDeviceMotionAvailable else { return }
        manager.deviceMotionUpdateInterval = 1 / 30
        let frames = CMMotionManager.availableAttitudeReferenceFrames()
        let frame: CMAttitudeReferenceFrame = frames.contains(.xTrueNorthZVertical) ? .xTrueNorthZVertical : .xMagneticNorthZVertical
        manager.startDeviceMotionUpdates(using: frame, to: .main) { [weak self] data, _ in
            guard let m = data?.attitude.rotationMatrix else { return }
            // The back camera looks along the device's −Z; in the reference frame
            // (X north, Y west, Z up) that is minus the third row of the matrix.
            let x = -m.m31, y = -m.m32, z = -m.m33
            var az = atan2(-y, x) * 180 / .pi
            if az < 0 { az += 360 }
            let el = asin(max(-1, min(1, z))) * 180 / .pi
            // A little smoothing, so the marker does not shake.
            if let prev = self?.azimuth {
                let d = AuroraFinderView.delta(az, prev)
                self?.azimuth = (prev + d * 0.25 + 360).truncatingRemainder(dividingBy: 360)
            } else {
                self?.azimuth = az
            }
            self?.elevation = (self?.elevation ?? el) * 0.75 + el * 0.25
        }
    }

    func stop() { manager.stopDeviceMotionUpdates() }
}

/// The marker on the aurora, a ring that fills when you are on it.
private struct Target: View {
    let close: Bool
    @State private var pulse = false

    var body: some View {
        ZStack {
            Circle().strokeBorder(Theme.aurora, lineWidth: 4).frame(width: 110, height: 110)
                .scaleEffect(pulse ? 1.15 : 0.95).opacity(pulse ? 0.5 : 1)
            Circle().fill(Theme.aurora.opacity(close ? 0.35 : 0.12)).frame(width: 96, height: 96)
            Label("AURORA", systemImage: "sparkles").font(.mono(12, .bold)).foregroundStyle(.white).offset(y: 74)
        }
        .onAppear { withAnimation(.easeInOut(duration: 0.9).repeatForever()) { pulse = true } }
    }
}

private struct Crosshair: View {
    let close: Bool
    var body: some View {
        ZStack {
            Rectangle().fill(.white.opacity(0.8)).frame(width: 28, height: 2)
            Rectangle().fill(.white.opacity(0.8)).frame(width: 2, height: 28)
            Circle().strokeBorder(close ? Theme.aurora : .white.opacity(0.8), lineWidth: 2).frame(width: 44, height: 44)
        }
    }
}

/// An arrow at the edge of the screen pointing to where the aurora is.
private struct EdgeArrow: View {
    let dAz: Double
    let dEl: Double
    let size: CGSize

    var body: some View {
        let angle = atan2(-dEl, dAz)
        let r = min(size.width, size.height) * 0.38
        Image(systemName: "arrow.right.circle.fill")
            .font(.system(size: 54, weight: .bold))
            .foregroundStyle(Theme.aurora, .black.opacity(0.4))
            .rotationEffect(.radians(angle))
            .position(x: size.width / 2 + r * CGFloat(cos(angle)), y: size.height / 2 + r * CGFloat(sin(angle)))
    }
}

/// The back camera, full screen.
struct CameraPreview: UIViewRepresentable {
    @Observable
    final class Session {
        let session = AVCaptureSession()
        private(set) var denied = false
        @ObservationIgnored private var configured = false

        func start() {
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async {
                    self.denied = !granted
                    guard granted else { return }
                    if !self.configured, let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
                       let input = try? AVCaptureDeviceInput(device: device), self.session.canAddInput(input) {
                        self.session.beginConfiguration()
                        self.session.sessionPreset = .high
                        self.session.addInput(input)
                        self.session.commitConfiguration()
                        self.configured = true
                    }
                    DispatchQueue.global(qos: .userInitiated).async { self.session.startRunning() }
                }
            }
        }

        func stop() { DispatchQueue.global(qos: .userInitiated).async { self.session.stopRunning() } }
    }

    let session: Session

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.preview.session = session.session
        view.preview.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ view: PreviewView, context: Context) {}

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var preview: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }
}

/// The button that opens it (Today, Aurora tab).
struct AuroraFinderButton: View {
    @State private var open = false

    var body: some View {
        Button { open = true } label: {
            Label("Trova l'aurora con la fotocamera", systemImage: "camera.viewfinder")
                .font(.mono(12, .bold)).tracking(0.4)
                .lineLimit(1).minimumScaleFactor(0.7)
                .frame(maxWidth: .infinity).frame(height: 46)
                .foregroundStyle(Theme.aurora)
                .overlay(Rectangle().strokeBorder(Theme.aurora, lineWidth: 1.5))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("aurora.finder")
        .fullScreenCover(isPresented: $open) { AuroraFinderView() }
    }
}
