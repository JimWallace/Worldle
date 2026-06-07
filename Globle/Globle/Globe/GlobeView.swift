import SwiftUI
import SceneKit
import UIKit
import simd

/// A 3D globe the player can spin and pinch-zoom. Guessed countries are colored by
/// closeness, and the globe animates to face each new guess.
struct GlobeView: UIViewRepresentable {
    let countries: [Country]
    let fills: [(country: Country, color: UIColor)]
    let reveal: (country: Country, color: UIColor)?
    let focus: Country?
    let onFocusHandled: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(countries: countries) }

    func makeUIView(context: Context) -> SCNView {
        let view = SCNView()
        context.coordinator.setup(view)
        return view
    }

    func updateUIView(_ uiView: SCNView, context: Context) {
        context.coordinator.update(fills: fills, reveal: reveal,
                                   focus: focus, onFocusHandled: onFocusHandled)
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        private let renderer: GlobeTextureRenderer
        private let globeNode = SCNNode()
        private let cameraNode = SCNNode()
        private let material = SCNMaterial()

        private var yaw: Float = -0.17          // start over Africa/Europe
        private var pitch: Float = 0.30
        private var distance: Float = 3.8
        private let minDistance: Float = 1.8
        private let maxDistance: Float = 9.0
        private let dragSpeed: Float = 0.006

        private var panStart: CGPoint = .zero
        private var distanceAtPinchStart: Float = 3.8
        private var lastSignature: String?
        private var lastFocusId: String?

        init(countries: [Country]) {
            self.renderer = GlobeTextureRenderer(countries: countries)
            super.init()
        }

        func setup(_ view: SCNView) {
            let scene = SCNScene()

            material.lightingModel = .constant   // colors read true on every side
            material.isDoubleSided = true
            material.diffuse.contents = renderer.baseTexture()
            material.diffuse.wrapS = .clamp
            material.diffuse.wrapT = .clamp
            material.diffuse.magnificationFilter = .linear
            material.diffuse.minificationFilter = .linear

            globeNode.geometry = SphereMesh.make(radius: 1, stacks: 120, slices: 240)
            globeNode.geometry?.materials = [material]
            applyOrientation(animated: false)
            scene.rootNode.addChildNode(globeNode)

            let camera = SCNCamera()
            camera.fieldOfView = 30
            camera.zNear = 0.01
            camera.zFar = 100
            cameraNode.camera = camera
            cameraNode.position = SCNVector3(0, 0, distance)
            scene.rootNode.addChildNode(cameraNode)

            view.scene = scene
            view.pointOfView = cameraNode
            view.allowsCameraControl = false
            view.autoenablesDefaultLighting = false
            view.backgroundColor = UIColor(red: 0.04, green: 0.05, blue: 0.11, alpha: 1)
            view.antialiasingMode = .multisampling4X
            view.isUserInteractionEnabled = true

            let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
            let pinch = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
            pan.delegate = self
            pinch.delegate = self
            view.addGestureRecognizer(pan)
            view.addGestureRecognizer(pinch)
        }

        func update(fills: [(country: Country, color: UIColor)],
                    reveal: (country: Country, color: UIColor)?,
                    focus: Country?,
                    onFocusHandled: @escaping () -> Void) {
            let signature = fills.map(\.country.id).joined(separator: ",") + "|" + (reveal?.country.id ?? "")
            if signature != lastSignature {
                lastSignature = signature
                material.diffuse.contents = renderer.texture(fills: fills, reveal: reveal)
            }
            if let focus, focus.id != lastFocusId {
                lastFocusId = focus.id
                yaw = Float(Geo.radians(-focus.lon))
                pitch = max(-1.4, min(1.4, Float(Geo.radians(focus.lat))))
                applyOrientation(animated: true)
                DispatchQueue.main.async { onFocusHandled() }
            }
        }

        // MARK: - Orientation

        private func applyOrientation(animated: Bool) {
            let q = simd_quatf(angle: pitch, axis: SIMD3<Float>(1, 0, 0))
                  * simd_quatf(angle: yaw, axis: SIMD3<Float>(0, 1, 0))
            if animated {
                SCNTransaction.begin()
                SCNTransaction.animationDuration = 0.8
                SCNTransaction.animationTimingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                globeNode.simdOrientation = q
                SCNTransaction.commit()
            } else {
                globeNode.simdOrientation = q
            }
        }

        // MARK: - Gestures

        @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
            let t = gesture.translation(in: gesture.view)
            switch gesture.state {
            case .began:
                panStart = t
            case .changed:
                let dx = Float(t.x - panStart.x)
                let dy = Float(t.y - panStart.y)
                panStart = t
                yaw += dx * dragSpeed
                pitch += dy * dragSpeed
                pitch = max(-1.45, min(1.45, pitch))
                applyOrientation(animated: false)
            default:
                break
            }
        }

        @objc private func handlePinch(_ gesture: UIPinchGestureRecognizer) {
            switch gesture.state {
            case .began:
                distanceAtPinchStart = distance
            case .changed:
                distance = max(minDistance, min(maxDistance, distanceAtPinchStart / Float(gesture.scale)))
                cameraNode.position = SCNVector3(0, 0, distance)
            default:
                break
            }
        }

        func gestureRecognizer(_ g: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
            true
        }
    }
}
