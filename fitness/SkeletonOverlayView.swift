// SkeletonOverlayView.swift — Draws detected body joints and connections
import SwiftUI
import Vision

struct SkeletonOverlayView: View {
    let pose: BodyPose?
    let formQuality: FormQuality
    let size: CGSize

    // Joint connections for drawing skeleton lines
    private let connections: [(VNHumanBodyPoseObservation.JointName, VNHumanBodyPoseObservation.JointName)] = [
        // Torso
        (.neck, .root),
        (.leftShoulder, .neck),
        (.rightShoulder, .neck),
        (.leftShoulder, .leftElbow),
        (.rightShoulder, .rightElbow),
        (.leftElbow, .leftWrist),
        (.rightElbow, .rightWrist),
        // Lower body
        (.root, .leftHip),
        (.root, .rightHip),
        (.leftHip, .leftKnee),
        (.rightHip, .rightKnee),
        (.leftKnee, .leftAnkle),
        (.rightKnee, .rightAnkle),
        // Head
        (.neck, .nose),
        (.nose, .leftEye),
        (.nose, .rightEye),
        (.leftEye, .leftEar),
        (.rightEye, .rightEar),
    ]

    var lineColor: Color {
        switch formQuality {
        case .good: return .teal
        case .fair: return .amber
        case .poor: return .red
        }
    }

    var body: some View {
        Canvas { context, canvasSize in
            guard let pose else { return }

            // Draw connections
            for (from, to) in connections {
                guard let p1 = pose.viewPoint(from, in: canvasSize),
                      let p2 = pose.viewPoint(to, in: canvasSize) else { continue }

                var path = Path()
                path.move(to: p1)
                path.addLine(to: p2)
                context.stroke(path,
                    with: .color(lineColor.opacity(0.8)),
                    style: StrokeStyle(lineWidth: 3, lineCap: .round)
                )
            }

            // Draw joints
            let jointNames: [VNHumanBodyPoseObservation.JointName] = [
                .nose, .leftEye, .rightEye, .leftEar, .rightEar,
                .leftShoulder, .rightShoulder, .leftElbow, .rightElbow,
                .leftWrist, .rightWrist, .leftHip, .rightHip,
                .leftKnee, .rightKnee, .leftAnkle, .rightAnkle,
                .neck, .root
            ]

            for name in jointNames {
                guard let point = pose.viewPoint(name, in: canvasSize),
                      let joint = pose.joint(name) else { continue }

                let radius: CGFloat = isKeyJoint(name) ? 8 : 5
                let opacity = Double(joint.confidence)

                let rect = CGRect(
                    x: point.x - radius,
                    y: point.y - radius,
                    width: radius * 2,
                    height: radius * 2
                )

                // Outer glow
                context.fill(
                    Circle().path(in: rect.insetBy(dx: -2, dy: -2)),
                    with: .color(lineColor.opacity(opacity * 0.3))
                )
                // Inner dot
                context.fill(
                    Circle().path(in: rect),
                    with: .color(lineColor.opacity(opacity))
                )
                // White center
                let innerRect = rect.insetBy(dx: radius * 0.4, dy: radius * 0.4)
                context.fill(
                    Circle().path(in: innerRect),
                    with: .color(.white.opacity(opacity * 0.8))
                )
            }
        }
        .frame(width: size.width, height: size.height)
        .allowsHitTesting(false)
    }

    private func isKeyJoint(_ name: VNHumanBodyPoseObservation.JointName) -> Bool {
        [.leftShoulder, .rightShoulder, .leftElbow, .rightElbow,
         .leftWrist, .rightWrist, .leftHip, .rightHip,
         .leftKnee, .rightKnee, .leftAnkle, .rightAnkle].contains(name)
    }
}

// MARK: - Pulsing Dot (for rep animation)

struct PulsingDotView: View {
    @State private var scale: CGFloat = 1.0

    var body: some View {
        Circle()
            .fill(Color.teal)
            .frame(width: 12, height: 12)
            .scaleEffect(scale)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                    scale = 1.4
                }
            }
    }
}
