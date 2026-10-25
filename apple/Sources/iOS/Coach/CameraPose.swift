// Front camera → Apple Vision body pose, on a background queue. Frames are delivered upright and
// mirrored like the preview, so joint coordinates line up with what the rescuer sees on screen.
// The camera runs at its widest field of view (full 4:3 sensor, minimum zoom, Center Stage off) so
// a phone on the floor sees the whole upper body. A 3D body pose runs alongside the 2D one to
// measure the true elbow angle, which a flat image distorts when the arm isn't side-on.
import AVFoundation
import UIKit
import Vision

nonisolated struct PoseSample: Sendable {
    var t: Double
    var left: ArmJoints?
    var right: ArmJoints?
    /// Image size in pixels; joints are in this space with origin top-left.
    var imageSize: CGSize
    /// A second, lying-down body (the patient): shoulder and hip midpoints, when Vision finds one.
    var patientTorso: Torso? = nil
    /// True 3D elbow angles (degrees) from the 3D body pose, when recent; nil falls back to 2D.
    var elbow3DLeft: Double? = nil
    var elbow3DRight: Double? = nil
}

nonisolated final class CameraPose: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    enum Status: Sendable { case idle, denied, unavailable, running }

    let session = AVCaptureSession()
    let previewLayer: AVCaptureVideoPreviewLayer
    private let queue = DispatchQueue(label: "cpr.camera", qos: .userInteractive)
    private let output = AVCaptureVideoDataOutput()
    private var device: AVCaptureDevice?
    private var rotation: AVCaptureDevice.RotationCoordinator?
    private var observations: [NSKeyValueObservation] = []
    private let request = VNDetectHumanBodyPoseRequest()
    private let request3D = VNDetectHumanBodyPose3DRequest()
    private var frameIndex = 0
    private var last3D: (t: Double, left: Double?, right: Double?)?
    private let onPose: @Sendable (PoseSample) -> Void

    init(onPose: @escaping @Sendable (PoseSample) -> Void) {
        self.onPose = onPose
        previewLayer = AVCaptureVideoPreviewLayer(session: session)
        previewLayer.videoGravity = .resizeAspect // show the whole frame, never crop the body out
        super.init()
    }

    /// Asks for permission if needed, configures the front camera and starts it.
    func start(position: AVCaptureDevice.Position = .front) async -> Status {
        if AVCaptureDevice.authorizationStatus(for: .video) == .notDetermined {
            _ = await AVCaptureDevice.requestAccess(for: .video)
        }
        guard AVCaptureDevice.authorizationStatus(for: .video) == .authorized else { return .denied }
        return await withCheckedContinuation { cont in
            queue.async { [self] in
                if !session.isRunning {
                    guard configure(position: position) else { return cont.resume(returning: .unavailable) }
                    session.startRunning()
                }
                cont.resume(returning: .running)
            }
        }
    }

    func stop() {
        queue.async { [self] in if session.isRunning { session.stopRunning() } }
    }

    private func configure(position: AVCaptureDevice.Position) -> Bool {
        guard device == nil else { return true }
        // Center Stage crops in to follow faces; we need the whole upper body instead.
        if AVCaptureDevice.isCenterStageEnabled || AVCaptureDevice.centerStageControlMode != .app {
            AVCaptureDevice.centerStageControlMode = .app
            AVCaptureDevice.isCenterStageEnabled = false
        }
        guard let cam = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position),
              let input = try? AVCaptureDeviceInput(device: cam) else { return false }
        session.beginConfiguration()
        guard session.canAddInput(input), session.canAddOutput(output) else {
            session.commitConfiguration()
            return false
        }
        session.addInput(input)
        // Widest view: a 4:3 format (the full sensor, no 16:9 crop) of modest size, at 30 fps.
        let wide = cam.formats.filter { f in
            let d = CMVideoFormatDescriptionGetDimensions(f.formatDescription)
            return d.width <= 1920 && d.width >= 640 && abs(Double(d.width) / Double(d.height) - 4.0 / 3) < 0.02
                && f.videoSupportedFrameRateRanges.contains { $0.maxFrameRate >= 30 }
        }.max { a, b in
            if a.videoFieldOfView != b.videoFieldOfView { return a.videoFieldOfView < b.videoFieldOfView }
            return CMVideoFormatDescriptionGetDimensions(a.formatDescription).width
                > CMVideoFormatDescriptionGetDimensions(b.formatDescription).width // prefer the smaller one
        }
        if let wide, (try? cam.lockForConfiguration()) != nil {
            session.sessionPreset = .inputPriority
            cam.activeFormat = wide
            cam.activeVideoMinFrameDuration = CMTime(value: 1, timescale: 30)
            cam.activeVideoMaxFrameDuration = CMTime(value: 1, timescale: 30)
            cam.videoZoomFactor = cam.minAvailableVideoZoomFactor
            cam.unlockForConfiguration()
        } else {
            session.sessionPreset = .hd1280x720
        }
        output.alwaysDiscardsLateVideoFrames = true
        output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange]
        output.setSampleBufferDelegate(self, queue: queue)
        session.addOutput(output)
        if let conn = output.connection(with: .video), conn.isVideoMirroringSupported {
            conn.automaticallyAdjustsVideoMirroring = false
            conn.isVideoMirrored = position == .front
        }
        session.commitConfiguration()
        device = cam

        // Keep both the preview and the analysed frames upright as the phone rotates.
        let rc = AVCaptureDevice.RotationCoordinator(device: cam, previewLayer: previewLayer)
        rotation = rc
        applyRotation()
        let reapply: @Sendable (AVCaptureDevice.RotationCoordinator, NSKeyValueObservedChange<CGFloat>) -> Void = { [weak self] _, _ in
            guard let self else { return }
            self.queue.async { self.applyRotation() }
        }
        observations = [
            rc.observe(\.videoRotationAngleForHorizonLevelCapture, changeHandler: reapply),
            rc.observe(\.videoRotationAngleForHorizonLevelPreview, changeHandler: reapply),
        ]
        return true
    }

    private func applyRotation() {
        guard let rc = rotation else { return }
        let capture = rc.videoRotationAngleForHorizonLevelCapture
        let preview = rc.videoRotationAngleForHorizonLevelPreview
        if let conn = output.connection(with: .video), conn.isVideoRotationAngleSupported(capture) { conn.videoRotationAngle = capture }
        DispatchQueue.main.async { [previewLayer] in
            if let conn = previewLayer.connection, conn.isVideoRotationAngleSupported(preview) { conn.videoRotationAngle = preview }
        }
    }

    // MARK: AVCaptureVideoDataOutputSampleBufferDelegate

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let pixels = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let size = CGSize(width: CVPixelBufferGetWidth(pixels), height: CVPixelBufferGetHeight(pixels))
        let handler = VNImageRequestHandler(cvPixelBuffer: pixels, orientation: .up)
        let t = ProcessInfo.processInfo.systemUptime
        // The 3D pose is heavier; every third frame (~10 Hz) is plenty for an elbow angle.
        frameIndex += 1
        if frameIndex % 3 == 0 {
            try? handler.perform([request, request3D])
            if let body3D = request3D.results?.first {
                func angle(_ s: VNHumanBodyPose3DObservation.JointName, _ e: VNHumanBodyPose3DObservation.JointName,
                           _ w: VNHumanBodyPose3DObservation.JointName) -> Double? {
                    guard let ps = try? body3D.recognizedPoint(s), let pe = try? body3D.recognizedPoint(e),
                          let pw = try? body3D.recognizedPoint(w) else { return nil }
                    let a = ps.position.columns.3, b = pe.position.columns.3, c = pw.position.columns.3
                    let v1 = SIMD3<Double>(Double(a.x - b.x), Double(a.y - b.y), Double(a.z - b.z))
                    let v2 = SIMD3<Double>(Double(c.x - b.x), Double(c.y - b.y), Double(c.z - b.z))
                    let n = (v1 * v1).sum().squareRoot() * (v2 * v2).sum().squareRoot()
                    guard n > 0 else { return nil }
                    return acos(min(1, max(-1, (v1 * v2).sum() / n))) * 180 / .pi
                }
                last3D = (t, angle(.leftShoulder, .leftElbow, .leftWrist), angle(.rightShoulder, .rightElbow, .rightWrist))
            }
        } else {
            try? handler.perform([request])
        }
        let fresh3D = last3D.flatMap { t - $0.t < 0.5 ? $0 : nil }
        // Vision: normalized, origin bottom-left → pixels, origin top-left.
        func px(_ p: VNRecognizedPoint) -> CGPoint { CGPoint(x: p.x * size.width, y: (1 - p.y) * size.height) }
        func torso(_ b: VNHumanBodyPoseObservation) -> Torso? {
            func mid(_ a: VNHumanBodyPoseObservation.JointName, _ c: VNHumanBodyPoseObservation.JointName) -> CGPoint? {
                let pts = [a, c].compactMap { try? b.recognizedPoint($0) }.filter { $0.confidence >= 0.3 }
                guard !pts.isEmpty else { return nil }
                let ps = pts.map(px)
                return CGPoint(x: ps.map(\.x).reduce(0, +) / CGFloat(ps.count), y: ps.map(\.y).reduce(0, +) / CGFloat(ps.count))
            }
            guard let s = mid(.leftShoulder, .rightShoulder), let h = mid(.leftHip, .rightHip) else { return nil }
            return Torso(shoulder: s, hip: h)
        }
        let bodies = request.results ?? []
        // The rescuer kneels upright; the patient lies flat. Pick by torso angle when there are two.
        let ranked = bodies.map { (b: $0, torso: torso($0)) }
            .sorted { ($0.torso?.uprightness ?? 0.5) > ($1.torso?.uprightness ?? 0.5) }
        guard let body = ranked.first?.b else {
            onPose(PoseSample(t: t, imageSize: size))
            return
        }
        let patient = ranked.dropFirst().compactMap(\.torso).first { $0.uprightness < 0.5 }
        func arm(_ s: VNHumanBodyPoseObservation.JointName, _ e: VNHumanBodyPoseObservation.JointName,
                 _ w: VNHumanBodyPoseObservation.JointName) -> ArmJoints? {
            guard let ps = try? body.recognizedPoint(s), let pe = try? body.recognizedPoint(e),
                  let pw = try? body.recognizedPoint(w) else { return nil }
            return ArmJoints(shoulder: px(ps), elbow: px(pe), wrist: px(pw), confidence: min(ps.confidence, pe.confidence, pw.confidence))
        }
        onPose(PoseSample(t: t, left: arm(.leftShoulder, .leftElbow, .leftWrist),
                          right: arm(.rightShoulder, .rightElbow, .rightWrist), imageSize: size, patientTorso: patient,
                          elbow3DLeft: fresh3D?.left, elbow3DRight: fresh3D?.right))
    }
}
