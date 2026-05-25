// PoseDetector.swift — Camera + Vision body pose detection pipeline
// Compatible with iOS 14+ (uses VNDetectHumanBodyPoseRequest)
import Foundation
import AVFoundation
import Vision
import SwiftUI
import Combine

// MARK: - Body Pose Data

/// A recognised joint with its normalised position and confidence.
struct DetectedJoint: Equatable {
    let point: CGPoint       // Vision normalised coords (0-1, origin bottom-left)
    let confidence: Float
}

/// All joints detected in a single frame.
struct BodyPose: Equatable {
    let joints: [VNHumanBodyPoseObservation.JointName: DetectedJoint]
    let timestamp: Date

    func joint(_ name: VNHumanBodyPoseObservation.JointName) -> DetectedJoint? {
        guard let j = joints[name], j.confidence > 0.3 else { return nil }
        return j
    }

    /// Convert Vision normalised point (bottom-left origin) to a view coordinate.
    func viewPoint(_ name: VNHumanBodyPoseObservation.JointName,
                   in size: CGSize) -> CGPoint? {
        guard let j = joint(name) else { return nil }
        // Vision: origin bottom-left, Y up.  UIKit/SwiftUI: origin top-left, Y down.
        return CGPoint(x: j.point.x * size.width,
                       y: (1 - j.point.y) * size.height)
    }
}

// MARK: - Camera Manager

/// Manages AVCaptureSession for live camera feed.
final class CameraManager: NSObject, ObservableObject {
    let session = AVCaptureSession()
    @Published var permissionGranted = false
    @Published var cameraAvailable = false

    private let sessionQueue = DispatchQueue(label: "fitness.camera.session")
    var videoDataOutput = AVCaptureVideoDataOutput()

    var useFrontCamera = true

    override init() {
        super.init()
        checkPermission()
    }

    func checkPermission() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            permissionGranted = true
            setupSession()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    self?.permissionGranted = granted
                    if granted { self?.setupSession() }
                }
            }
        default:
            permissionGranted = false
        }
    }

    func setupSession() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            self.session.beginConfiguration()
            self.session.sessionPreset = .medium

            // Remove existing inputs
            for input in self.session.inputs {
                self.session.removeInput(input)
            }

            let position: AVCaptureDevice.Position = self.useFrontCamera ? .front : .back
            guard let device = AVCaptureDevice.default(
                .builtInWideAngleCamera, for: .video, position: position
            ) else {
                DispatchQueue.main.async { self.cameraAvailable = false }
                self.session.commitConfiguration()
                return
            }

            guard let input = try? AVCaptureDeviceInput(device: device) else {
                DispatchQueue.main.async { self.cameraAvailable = false }
                self.session.commitConfiguration()
                return
            }

            if self.session.canAddInput(input) {
                self.session.addInput(input)
            }

            self.videoDataOutput.alwaysDiscardsLateVideoFrames = true
            self.videoDataOutput.videoSettings = [
                kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_420YpCbCr8BiPlanarFullRange)
            ]

            if self.session.canAddOutput(self.videoDataOutput) {
                self.session.addOutput(self.videoDataOutput)
            }

            // Mirror front camera
            if let connection = self.videoDataOutput.connection(with: .video) {
                connection.videoOrientation = .portrait
                if self.useFrontCamera {
                    connection.isVideoMirrored = true
                }
            }

            self.session.commitConfiguration()
            DispatchQueue.main.async { self.cameraAvailable = true }
        }
    }

    func startSession() {
        sessionQueue.async { [weak self] in
            guard let self, !self.session.isRunning else { return }
            self.session.startRunning()
        }
    }

    func stopSession() {
        sessionQueue.async { [weak self] in
            guard let self, self.session.isRunning else { return }
            self.session.stopRunning()
        }
    }
}

// MARK: - Pose Detector

/// Processes camera frames with Vision to detect body pose.
final class PoseDetector: NSObject, ObservableObject {
    @Published var currentPose: BodyPose?
    @Published var isDetecting = false

    let cameraManager = CameraManager()
    private let visionQueue = DispatchQueue(label: "fitness.pose.vision", qos: .userInitiated)
    private var request: VNDetectHumanBodyPoseRequest?

    override init() {
        super.init()
        request = VNDetectHumanBodyPoseRequest()
        cameraManager.videoDataOutput.setSampleBufferDelegate(self, queue: visionQueue)
    }

    func start() {
        isDetecting = true
        cameraManager.startSession()
    }

    func stop() {
        isDetecting = false
        cameraManager.stopSession()
        DispatchQueue.main.async { self.currentPose = nil }
    }
}

extension PoseDetector: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        guard isDetecting,
              let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer),
              let request = request else { return }

        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer,
                                            orientation: .up,
                                            options: [:])
        do {
            try handler.perform([request])
            guard let observation = request.results?.first else {
                DispatchQueue.main.async { self.currentPose = nil }
                return
            }
            let pose = self.extractPose(from: observation)
            DispatchQueue.main.async { self.currentPose = pose }
        } catch {
            // Vision processing failed for this frame — skip
        }
    }

    private func extractPose(from observation: VNHumanBodyPoseObservation) -> BodyPose {
        let jointNames: [VNHumanBodyPoseObservation.JointName] = [
            .nose, .leftEye, .rightEye, .leftEar, .rightEar,
            .leftShoulder, .rightShoulder, .leftElbow, .rightElbow,
            .leftWrist, .rightWrist, .leftHip, .rightHip,
            .leftKnee, .rightKnee, .leftAnkle, .rightAnkle,
            .neck, .root
        ]

        var joints: [VNHumanBodyPoseObservation.JointName: DetectedJoint] = [:]
        for name in jointNames {
            if let point = try? observation.recognizedPoint(name) {
                joints[name] = DetectedJoint(
                    point: CGPoint(x: point.location.x, y: point.location.y),
                    confidence: point.confidence
                )
            }
        }
        return BodyPose(joints: joints, timestamp: Date())
    }
}

// MARK: - Camera Preview (UIViewRepresentable)

struct CameraPreviewView: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> UIView {
        let view = CameraPreviewUIView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {}
}

private class CameraPreviewUIView: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
    var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
}
