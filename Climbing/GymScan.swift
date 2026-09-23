import ARKit
import MetalKit
import ModelIO
import RealityKit
import SceneKit
import SwiftUI

enum GymScanSupport {
    static var isAvailable: Bool {
        ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh)
    }
}

enum GymScanExportError: Error {
    case empty
    case noDevice
}

/// Merges the live LiDAR mesh into a USDZ model of the room's surfaces.
enum GymScanExporter {
    static func usdzData(from anchors: [ARMeshAnchor]) throws -> Data {
        var positions: [SIMD3<Float>] = []
        var indices: [UInt32] = []
        for anchor in anchors {
            let geometry = anchor.geometry
            let base = UInt32(positions.count)
            for index in 0 ..< geometry.vertices.count {
                let local = vertex(geometry.vertices, at: index)
                let world = anchor.transform * SIMD4<Float>(local.x, local.y, local.z, 1)
                positions.append(SIMD3(world.x, world.y, world.z))
            }
            appendFaces(geometry.faces, base: base, into: &indices)
        }
        guard positions.count >= 3, indices.count >= 3 else { throw GymScanExportError.empty }
        return try writeUSDZ(positions: positions, indices: indices)
    }

    private static func vertex(_ source: ARGeometrySource, at index: Int) -> SIMD3<Float> {
        let pointer = source.buffer.contents().advanced(by: source.offset + (source.stride * index))
        let floats = pointer.assumingMemoryBound(to: Float.self)
        return SIMD3(floats[0], floats[1], floats[2])
    }

    private static func appendFaces(_ element: ARGeometryElement, base: UInt32, into indices: inout [UInt32]) {
        let perFace = element.indexCountPerPrimitive
        let total = element.count * perFace
        let raw = element.buffer.contents()
        for index in 0 ..< total {
            let offset = index * element.bytesPerIndex
            let value: UInt32
            if element.bytesPerIndex == MemoryLayout<UInt16>.size {
                value = UInt32(raw.load(fromByteOffset: offset, as: UInt16.self))
            } else {
                value = raw.load(fromByteOffset: offset, as: UInt32.self)
            }
            indices.append(base + value)
        }
    }

    private static func writeUSDZ(positions: [SIMD3<Float>], indices: [UInt32]) throws -> Data {
        guard let device = MTLCreateSystemDefaultDevice() else { throw GymScanExportError.noDevice }
        let allocator = MTKMeshBufferAllocator(device: device)
        let vertexData = positions.withUnsafeBytes { Data($0) }
        let indexData = indices.withUnsafeBytes { Data($0) }
        let vertexBuffer = allocator.newBuffer(with: vertexData, type: .vertex)
        let indexBuffer = allocator.newBuffer(with: indexData, type: .index)

        let material = MDLMaterial(name: "wall", scatteringFunction: MDLPhysicallyPlausibleScatteringFunction())
        material.setProperty(MDLMaterialProperty(name: "baseColor", semantic: .baseColor, float3: SIMD3<Float>(0.72, 0.74, 0.78)))
        let submesh = MDLSubmesh(
            indexBuffer: indexBuffer,
            indexCount: indices.count,
            indexType: .uInt32,
            geometryType: .triangles,
            material: material
        )

        let descriptor = MDLVertexDescriptor()
        descriptor.attributes[0] = MDLVertexAttribute(
            name: MDLVertexAttributePosition,
            format: .float3,
            offset: 0,
            bufferIndex: 0
        )
        descriptor.layouts[0] = MDLVertexBufferLayout(stride: MemoryLayout<SIMD3<Float>>.stride)
        let mesh = MDLMesh(
            vertexBuffer: vertexBuffer,
            vertexCount: positions.count,
            descriptor: descriptor,
            submeshes: [submesh]
        )
        let asset = MDLAsset(bufferAllocator: allocator)
        asset.add(mesh)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("gym-scan-\(UUID().uuidString).usdz")
        try asset.export(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        return try Data(contentsOf: url)
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
        let anchors = GymScanSessionStore.shared.anchors
        DispatchQueue.global(qos: .userInitiated).async {
            let result = Result { try GymScanExporter.usdzData(from: anchors) }
            DispatchQueue.main.async {
                isSaving = false
                switch result {
                case .success(let data):
                    onSave(data)
                    dismiss()
                case .failure:
                    saveError = "The scan didn't have enough of the walls yet. Walk a bit closer and try again."
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
        view.scene = scene(from: data)
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
}
