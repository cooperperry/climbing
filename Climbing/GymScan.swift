import ARKit
import RealityKit
import SceneKit
import SwiftUI
import UIKit

enum GymScanSupport {
    static var isAvailable: Bool {
        ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh)
    }
}

enum GymScanExportError: LocalizedError {
    case empty
    case writeFailed

    var errorDescription: String? {
        switch self {
        case .empty:
            return "The scan didn't have enough of the walls yet. Walk a bit closer and try again."
        case .writeFailed:
            return "The walls were scanned, but the model file couldn't be written. Try saving again."
        }
    }
}

struct GymScanMesh {
    var positions: [SIMD3<Float>]
    var indices: [UInt32]
}

/// Merges the live LiDAR mesh into a USDZ model of the room's surfaces.
enum GymScanExporter {
    /// Copy the mesh out of ARKit immediately. Those buffers are not safe to read later on another queue.
    static func snapshot(from anchors: [ARMeshAnchor]) -> GymScanMesh {
        var positions: [SIMD3<Float>] = []
        var indices: [UInt32] = []
        for anchor in anchors {
            let geometry = anchor.geometry
            let vertexCount = geometry.vertices.count
            guard vertexCount > 0 else { continue }
            let base = UInt32(positions.count)
            let transform = anchor.transform
            for index in 0 ..< vertexCount {
                let local = vertex(geometry.vertices, at: index)
                let world = transform * SIMD4<Float>(local.x, local.y, local.z, 1)
                positions.append(SIMD3(world.x, world.y, world.z))
            }
            appendFaces(geometry.faces, base: base, vertexCount: vertexCount, into: &indices)
        }
        return GymScanMesh(positions: positions, indices: indices)
    }

    static func usdzData(from mesh: GymScanMesh) throws -> Data {
        guard mesh.positions.count >= 3, mesh.indices.count >= 3 else { throw GymScanExportError.empty }
        return try writeUSDZ(positions: mesh.positions, indices: mesh.indices)
    }

    private static func vertex(_ source: ARGeometrySource, at index: Int) -> SIMD3<Float> {
        let pointer = source.buffer.contents().advanced(by: source.offset + (source.stride * index))
        let floats = pointer.assumingMemoryBound(to: Float.self)
        return SIMD3(floats[0], floats[1], floats[2])
    }

    private static func appendFaces(
        _ element: ARGeometryElement,
        base: UInt32,
        vertexCount: Int,
        into indices: inout [UInt32]
    ) {
        let perFace = element.indexCountPerPrimitive
        guard perFace == 3 else { return }
        let raw = element.buffer.contents()
        for face in 0 ..< element.count {
            var corners: [UInt32] = []
            corners.reserveCapacity(3)
            for corner in 0 ..< 3 {
                let offset = ((face * perFace) + corner) * element.bytesPerIndex
                let value: UInt32
                if element.bytesPerIndex == MemoryLayout<UInt16>.size {
                    value = UInt32(raw.load(fromByteOffset: offset, as: UInt16.self))
                } else {
                    value = raw.load(fromByteOffset: offset, as: UInt32.self)
                }
                corners.append(value)
            }
            guard corners.allSatisfy({ Int($0) < vertexCount }) else { continue }
            indices.append(contentsOf: corners.map { base + $0 })
        }
    }

    private static func writeUSDZ(positions: [SIMD3<Float>], indices: [UInt32]) throws -> Data {
        let vertices = positions.map { SCNVector3($0.x, $0.y, $0.z) }
        let normals = normals(positions: positions, indices: indices).map { SCNVector3($0.x, $0.y, $0.z) }
        let sources = [
            SCNGeometrySource(vertices: vertices),
            SCNGeometrySource(normals: normals)
        ]
        let used = (indices.count / 3) * 3
        let indexData = indices.prefix(used).withUnsafeBufferPointer { Data(buffer: $0) }
        let element = SCNGeometryElement(
            data: indexData,
            primitiveType: .triangles,
            primitiveCount: used / 3,
            bytesPerIndex: MemoryLayout<UInt32>.size
        )
        let geometry = SCNGeometry(sources: sources, elements: [element])
        let material = SCNMaterial()
        material.diffuse.contents = UIColor(white: 0.78, alpha: 1)
        material.isDoubleSided = true
        geometry.materials = [material]

        let scene = SCNScene()
        scene.rootNode.addChildNode(SCNNode(geometry: geometry))
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("gym-scan-\(UUID().uuidString).usdz")
        let wrote = scene.write(to: url, options: nil, delegate: nil, progressHandler: nil)
        defer { try? FileManager.default.removeItem(at: url) }
        guard wrote else { throw GymScanExportError.writeFailed }
        let data = try Data(contentsOf: url)
        guard data.isEmpty == false else { throw GymScanExportError.writeFailed }
        return data
    }

    private static func normals(positions: [SIMD3<Float>], indices: [UInt32]) -> [SIMD3<Float>] {
        var accumulated = Array(repeating: SIMD3<Float>.zero, count: positions.count)
        var index = 0
        while index + 2 < indices.count {
            let a = Int(indices[index])
            let b = Int(indices[index + 1])
            let c = Int(indices[index + 2])
            index += 3
            guard a < positions.count, b < positions.count, c < positions.count else { continue }
            let face = simd_cross(positions[b] - positions[a], positions[c] - positions[a])
            accumulated[a] += face
            accumulated[b] += face
            accumulated[c] += face
        }
        return accumulated.map { value in
            let length = simd_length(value)
            return length > 0.00001 ? value / length : SIMD3<Float>(0, 1, 0)
        }
    }
}

struct GymScanCaptureView: View {
    var onSave: (Data) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var surfaceCount = 0
    @State private var saveError: String?
    @State private var isSaving = false

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                if GymScanSupport.isAvailable {
                    GymScanARRepresentable(surfaceCount: $surfaceCount)
                        .ignoresSafeArea()
                    VStack(spacing: 10) {
                        Text(surfaceCount == 0 ? "Walk slowly along the walls" : "Scanning the wall shape")
                            .font(.subheadline.bold())
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(.ultraThinMaterial, in: Capsule())
                        Button(isSaving ? "Saving…" : "Save scan") {
                            save()
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.stravaOrange)
                        .disabled(surfaceCount == 0 || isSaving)
                    }
                    .padding(.bottom, 24)
                } else {
                    ContentUnavailableView(
                        "LiDAR needed to scan",
                        systemImage: "viewfinder",
                        description: Text("A Pro iPhone can capture the curve of the walls. This phone can still use the flat map.")
                    )
                }
            }
            .navigationTitle("Scan gym")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .alert("Couldn't save the scan", isPresented: Binding(
                get: { saveError != nil },
                set: { if $0 == false { saveError = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(saveError ?? "")
            }
        }
    }

    private func save() {
        isSaving = true
        let mesh = GymScanExporter.snapshot(from: GymScanSessionStore.shared.anchors)
        DispatchQueue.global(qos: .userInitiated).async {
            let result = Result { try GymScanExporter.usdzData(from: mesh) }
            DispatchQueue.main.async {
                isSaving = false
                switch result {
                case .success(let data):
                    onSave(data)
                    dismiss()
                case .failure(let error):
                    saveError = error.localizedDescription
                }
            }
        }
    }
}

/// Shares the latest mesh with the Save button. The AR view writes it; the button reads it.
final class GymScanSessionStore {
    static let shared = GymScanSessionStore()
    var anchors: [ARMeshAnchor] = []
}

struct GymScanARRepresentable: UIViewRepresentable {
    @Binding var surfaceCount: Int

    func makeUIView(context: Context) -> ARView {
        let view = ARView(frame: .zero)
        view.session.delegate = context.coordinator
        let coaching = ARCoachingOverlayView()
        coaching.session = view.session
        coaching.goal = .tracking
        coaching.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(coaching)
        let config = ARWorldTrackingConfiguration()
        config.sceneReconstruction = .mesh
        config.planeDetection = [.horizontal, .vertical]
        config.environmentTexturing = .none
        view.session.run(config)
        view.debugOptions.insert(.showSceneUnderstanding)
        return view
    }

    func updateUIView(_ uiView: ARView, context: Context) {}

    static func dismantleUIView(_ uiView: ARView, coordinator: Coordinator) {
        uiView.session.pause()
        GymScanSessionStore.shared.anchors = []
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(surfaceCount: $surfaceCount)
    }

    final class Coordinator: NSObject, ARSessionDelegate {
        var surfaceCount: Binding<Int>

        init(surfaceCount: Binding<Int>) {
            self.surfaceCount = surfaceCount
        }

        func session(_ session: ARSession, didAdd anchors: [ARAnchor]) {
            refresh(session)
        }

        func session(_ session: ARSession, didUpdate anchors: [ARAnchor]) {
            refresh(session)
        }

        private func refresh(_ session: ARSession) {
            let meshes = session.currentFrame?.anchors.compactMap { $0 as? ARMeshAnchor } ?? []
            let count = meshes.count
            DispatchQueue.main.async {
                GymScanSessionStore.shared.anchors = meshes
                self.surfaceCount.wrappedValue = count
            }
        }
    }
}

struct GymScanPreview: View {
    var data: Data

    var body: some View {
        GymScanSceneView(data: data)
            .ignoresSafeArea()
            .background(Color.black)
            .navigationTitle("Gym model")
            .navigationBarTitleDisplayMode(.inline)
    }
}

private struct GymScanSceneView: UIViewRepresentable {
    var data: Data

    func makeUIView(context: Context) -> SCNView {
        let view = SCNView()
        view.backgroundColor = .black
        view.autoenablesDefaultLighting = true
        view.allowsCameraControl = true
        let loaded = scene(from: data)
        view.scene = loaded
        frameCamera(on: loaded, in: view)
        return view
    }

    func updateUIView(_ uiView: SCNView, context: Context) {}

    private func scene(from data: Data) -> SCNScene {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("gym-preview-\(UUID().uuidString).usdz")
        do {
            try data.write(to: url)
            let loaded = try SCNScene(url: url, options: nil)
            try? FileManager.default.removeItem(at: url)
            return loaded
        } catch {
            try? FileManager.default.removeItem(at: url)
            return SCNScene()
        }
    }

    private func frameCamera(on scene: SCNScene, in view: SCNView) {
        var minP = SIMD3<Float>(repeating: .greatestFiniteMagnitude)
        var maxP = SIMD3<Float>(repeating: -.greatestFiniteMagnitude)
        var found = false
        var nodes = [scene.rootNode]
        scene.rootNode.enumerateChildNodes { node, _ in
            nodes.append(node)
        }
        for node in nodes {
            guard node.geometry != nil else { continue }
            let (localMin, localMax) = node.boundingBox
            let corners = [
                SCNVector3(localMin.x, localMin.y, localMin.z),
                SCNVector3(localMax.x, localMin.y, localMin.z),
                SCNVector3(localMin.x, localMax.y, localMin.z),
                SCNVector3(localMax.x, localMax.y, localMin.z),
                SCNVector3(localMin.x, localMin.y, localMax.z),
                SCNVector3(localMax.x, localMin.y, localMax.z),
                SCNVector3(localMin.x, localMax.y, localMax.z),
                SCNVector3(localMax.x, localMax.y, localMax.z)
            ]
            for corner in corners {
                let world = node.convertPosition(corner, to: nil)
                found = true
                minP = simd_min(minP, SIMD3(world.x, world.y, world.z))
                maxP = simd_max(maxP, SIMD3(world.x, world.y, world.z))
            }
        }
        guard found else { return }
        let center = (minP + maxP) * 0.5
        let span = max(maxP.x - minP.x, max(maxP.y - minP.y, maxP.z - minP.z))
        let distance = max(span * 1.4, 0.5)
        let cameraNode = SCNNode()
        let camera = SCNCamera()
        camera.zNear = 0.01
        camera.zFar = Double(distance) * 20
        cameraNode.camera = camera
        cameraNode.position = SCNVector3(center.x, center.y + span * 0.35, center.z + distance)
        cameraNode.look(at: SCNVector3(center.x, center.y, center.z))
        scene.rootNode.addChildNode(cameraNode)
        view.pointOfView = cameraNode
    }
}
