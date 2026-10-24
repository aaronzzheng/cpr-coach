// Front camera → Apple Vision body pose, on a background queue. Frames are delivered upright and
// mirrored like the preview, so joint coordinates line up with what the rescuer sees on screen.
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
    private let onPose: @Sendable (PoseSample) -> Void

    init(onPose: @escaping @Sendable (PoseSample) -> Void) {
        self.onPose = onPose
        previewLayer = AVCaptureVideoPreviewLayer(session: session)
        previewLayer.videoGravity = .resizeAspectFill
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
        guard let cam = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position),
              let input = try? AVCaptureDeviceInput(device: cam) else { return false }
        session.beginConfiguration()
        session.sessionPreset = .hd1280x720
        guard session.canAddInput(input), session.canAddOutput(output) else {
            session.commitConfiguration()
            return false
        }
        session.addInput(input)
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
        try? handler.perform([request])
        let t = ProcessInfo.processInfo.systemUptime
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
                          right: arm(.rightShoulder, .rightElbow, .rightWrist), imageSize: size, patientTorso: patient))
    }
}
