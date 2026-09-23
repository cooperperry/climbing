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
            return "Point the phone at the climbing wall and walk along it. A scan of only the floor can't become a wall."
        case .writeFailed:
            return "The walls were scanned, but the model file couldn't be written. Try saving again."
        }
    }
}

struct GymScanMesh {
    var positions: [SIMD3<Float>]
    var indices: [UInt32]
}

/// Copies the live LiDAR mesh, drops the floor and ceiling, and writes a wall model.
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
        let cleaned = WallMeshMath.climbingWall(from: WallMesh(
            positions: mesh.positions.map { MeshPoint(x: Double($0.x), y: Double($0.y), z: Double($0.z)) },
            indices: mesh.indices.map { Int($0) }
        ))
        guard cleaned.positions.count >= 3, cleaned.indices.count >= 3 else { throw GymScanExportError.empty }
        let positions = cleaned.positions.map { SIMD3(Float($0.x), Float($0.y), Float($0.z)) }
        let indices = cleaned.indices.map { UInt32($0) }
        return try writeUSDZ(positions: positions, indices: indices)
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
        material.diffuse.contents = UIColor(red: 0.64, green: 0.62, blue: 0.58, alpha: 1)
        material.lightingModel = .lambert
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

    /// Rebuild an already-saved scan into the solid wall. Used once for older files.
    static func refine(_ data: Data) -> Data? {
        guard let mesh = mesh(fromUSDZ: data), mesh.isEmpty == false else { return nil }
        let cleaned = WallMeshMath.climbingWall(from: mesh)
        guard cleaned.isEmpty == false else { return nil }
        let positions = cleaned.positions.map { SIMD3(Float($0.x), Float($0.y), Float($0.z)) }
        let indices = cleaned.indices.map { UInt32($0) }
        return try? writeUSDZ(positions: positions, indices: indices)
    }

    private static func mesh(fromUSDZ data: Data) -> WallMesh? {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("gym-refine-\(UUID().uuidString).usdz")
        defer { try? FileManager.default.removeItem(at: url) }
        guard (try? data.write(to: url)) != nil,
              let scene = try? SCNScene(url: url, options: nil) else { return nil }
        var positions: [MeshPoint] = []
        var indices: [Int] = []
        var nodes = [scene.rootNode]
        scene.rootNode.enumerateChildNodes { node, _ in nodes.append(node) }
        for node in nodes {
            guard let geometry = node.geometry,
                  let source = geometry.sources(for: .vertex).first else { continue }
            let base = positions.count
            let stride = source.dataStride
            let offset = source.dataOffset
            let bytes = source.data
            for index in 0 ..< source.vectorCount {
                let start = offset + index * stride
                guard start + MemoryLayout<Float>.size * 3 <= bytes.count else { continue }
                let x = bytes.withUnsafeBytes { $0.load(fromByteOffset: start, as: Float.self) }
                let y = bytes.withUnsafeBytes { $0.load(fromByteOffset: start + 4, as: Float.self) }
                let z = bytes.withUnsafeBytes { $0.load(fromByteOffset: start + 8, as: Float.self) }
                let world = node.convertPosition(SCNVector3(x, y, z), to: nil)
                positions.append(MeshPoint(x: Double(world.x), y: Double(world.y), z: Double(world.z)))
            }
            for element in geometry.elements where element.primitiveType == .triangles {
                let bytesPerIndex = element.bytesPerIndex
                let raw = element.data
                let corners = element.primitiveCount * 3
                for corner in 0 ..< corners {
                    let start = corner * bytesPerIndex
                    guard start + bytesPerIndex <= raw.count else { continue }
                    let value: Int
                    if bytesPerIndex == MemoryLayout<UInt16>.size {
                        value = Int(raw.withUnsafeBytes { $0.load(fromByteOffset: start, as: UInt16.self) })
                    } else {
                        value = Int(raw.withUnsafeBytes { $0.load(fromByteOffset: start, as: UInt32.self) })
                    }
                    indices.append(base + value)
                }
            }
        }
        guard positions.count >= 3, indices.count >= 3 else { return nil }
        return WallMesh(positions: positions, indices: indices)
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
    var replacesExisting = false
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
                        Text(surfaceCount == 0 ? "Walk slowly along the wall" : "Scanning the wall shape")
                            .font(.subheadline.bold())
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(.ultraThinMaterial, in: Capsule())
                        if replacesExisting {
                            Text("Saving replaces this wall and the routes on it.")
                                .font(.caption)
                                .foregroundStyle(.white)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(.ultraThinMaterial, in: Capsule())
                        }
                        Button(isSaving ? "Cleaning up the wall…" : "Save wall") {
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

enum GymScanStore {
    static func fileURL(for gymID: UUID) -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let directory = base.appendingPathComponent("GymWalls", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("\(gymID.uuidString).usdz")
    }

    static func write(_ data: Data, gymID: UUID) throws {
        try data.write(to: fileURL(for: gymID), options: .atomic)
    }

    static func read(gymID: UUID) -> Data? {
        let url = fileURL(for: gymID)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try? Data(contentsOf: url)
    }

    static func hasModel(gymID: UUID) -> Bool {
        FileManager.default.fileExists(atPath: fileURL(for: gymID).path)
    }
}

struct GymWallEditor: View {
    var data: Data
    var routes: [WallRoutePin]
    var grades: [String]
    @Binding var grade: String?
    @Binding var color: HoldColor
    @Binding var discipline: ClimbDiscipline
    var onStroke: ([MeshPoint], MeshPoint) -> Void
    var onDelete: (UUID) -> Void

    @State private var placing = false
    @State private var selectedID: UUID?

    private var gradeChoices: [String] {
        grades.isEmpty ? GradeScaleTemplate.standardVScale().grades : grades
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            GymWallScene(
                data: data,
                routes: routes,
                selectedID: selectedID,
                placing: placing,
                color: color,
                onSelect: { selectedID = $0 },
                onStroke: onStroke
            )
            .ignoresSafeArea()
            controlBar
        }
        .background(Color.black)
        .navigationTitle("Climbing wall")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if grade == nil { grade = gradeChoices.first }
        }
    }

    private var controlBar: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(placing ? "Draw the route up the wall with your finger." : "Saved on this gym. Drag to look around.")
                .font(.caption)
                .foregroundStyle(.secondary)
            if placing {
                Picker("Type", selection: $discipline) {
                    ForEach(ClimbDiscipline.allCases) { item in
                        Text(item.shortName).tag(item)
                    }
                }
                .pickerStyle(.segmented)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(HoldColor.allCases) { item in
                            Button { color = item } label: {
                                Circle()
                                    .fill(Color(hold: item))
                                    .frame(width: 26, height: 26)
                                    .overlay {
                                        Circle().strokeBorder(color == item ? Color.primary : Color.clear, lineWidth: 2)
                                    }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(gradeChoices, id: \.self) { item in
                            Button(item) { grade = item }
                                .buttonStyle(.plain)
                                .font(.subheadline.bold())
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(grade == item ? AnyShapeStyle(.stravaOrange) : AnyShapeStyle(.quaternary), in: Capsule())
                                .foregroundStyle(grade == item ? Color.white : Color.primary)
                        }
                    }
                }
            }
            if routes.isEmpty == false {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(routes) { route in
                            let hold = HoldColor(rawValue: route.colorName) ?? .blue
                            Button {
                                selectedID = route.id
                            } label: {
                                HStack(spacing: 6) {
                                    Circle().fill(Color(hold: hold)).frame(width: 10, height: 10)
                                    Text(route.grade).font(.caption.bold())
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(selectedID == route.id ? AnyShapeStyle(.stravaOrange) : AnyShapeStyle(.quaternary), in: Capsule())
                                .foregroundStyle(selectedID == route.id ? Color.white : Color.primary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            HStack {
                Button(placing ? "Done drawing" : "Draw route") {
                    placing.toggle()
                }
                .buttonStyle(.borderedProminent)
                .tint(.stravaOrange)
                if let selectedID {
                    Button("Remove", role: .destructive) {
                        self.selectedID = nil
                        onDelete(selectedID)
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial)
    }
}

private struct GymWallScene: UIViewRepresentable {
    var data: Data
    var routes: [WallRoutePin]
    var selectedID: UUID?
    var placing: Bool
    var color: HoldColor
    var onSelect: (UUID?) -> Void
    var onStroke: ([MeshPoint], MeshPoint) -> Void

    func makeUIView(context: Context) -> SCNView {
        let view = SCNView()
        view.backgroundColor = .black
        view.autoenablesDefaultLighting = true
        view.allowsCameraControl = true
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.tapped))
        tap.cancelsTouchesInView = false
        view.addGestureRecognizer(tap)
        let pan = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.drew(_:)))
        pan.maximumNumberOfTouches = 1
        pan.isEnabled = false
        view.addGestureRecognizer(pan)
        context.coordinator.draw = pan
        return view
    }

    func updateUIView(_ uiView: SCNView, context: Context) {
        context.coordinator.placing = placing
        context.coordinator.color = color
        context.coordinator.onSelect = onSelect
        context.coordinator.onStroke = onStroke
        context.coordinator.draw?.isEnabled = placing
        uiView.allowsCameraControl = placing == false
        if placing == false {
            context.coordinator.draft.removeAll()
            uiView.scene?.rootNode.childNode(withName: "draft-stroke", recursively: false)?.removeFromParentNode()
        }
        if context.coordinator.loadedCount != data.count {
            let loaded = scene(from: data)
            uiView.scene = loaded
            frameCamera(on: loaded, in: uiView)
            context.coordinator.loadedCount = data.count
        }
        refreshRoutes(in: uiView.scene)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator: NSObject {
        var placing = false
        var loadedCount: Int?
        var color = HoldColor.blue
        var draft: [MeshPoint] = []
        var draw: UIPanGestureRecognizer?
        var onSelect: ((UUID?) -> Void)?
        var onStroke: (([MeshPoint], MeshPoint) -> Void)?

        @objc func tapped(_ gesture: UITapGestureRecognizer) {
            guard let view = gesture.view as? SCNView else { return }
            let hits = view.hitTest(gesture.location(in: view), options: [
                SCNHitTestOption.categoryBitMask: 2,
                SCNHitTestOption.searchMode: SCNHitTestSearchMode.closest.rawValue
            ])
            onSelect?(hits.first.flatMap { routeID(from: $0.node) })
        }

        @objc func drew(_ gesture: UIPanGestureRecognizer) {
            guard placing, let view = gesture.view as? SCNView else { return }
            switch gesture.state {
            case .began:
                draft.removeAll()
                if let hit = wallHit(in: view, at: gesture.location(in: view)) {
                    draft.append(hit)
                }
                showDraft(in: view)
            case .changed:
                guard let hit = wallHit(in: view, at: gesture.location(in: view)) else { return }
                if let last = draft.last {
                    let step = hypot(hit.x - last.x, hypot(hit.y - last.y, hit.z - last.z))
                    guard step >= 0.03 else { return }
                }
                draft.append(hit)
                showDraft(in: view)
            case .ended, .cancelled, .failed:
                let stroke = draft
                draft.removeAll()
                view.scene?.rootNode.childNode(withName: "draft-stroke", recursively: false)?.removeFromParentNode()
                guard gesture.state == .ended, stroke.count >= 2 else { return }
                let length = zip(stroke, stroke.dropFirst()).reduce(0.0) { total, pair in
                    total + hypot(pair.1.x - pair.0.x, hypot(pair.1.y - pair.0.y, pair.1.z - pair.0.z))
                }
                guard length >= 0.12 else { return }
                onStroke?(stroke, MeshPoint(x: 0, y: 0, z: 1))
            default:
                break
            }
        }

        private func wallHit(in view: SCNView, at point: CGPoint) -> MeshPoint? {
            let hits = view.hitTest(point, options: [
                SCNHitTestOption.categoryBitMask: 1,
                SCNHitTestOption.searchMode: SCNHitTestSearchMode.closest.rawValue
            ])
            guard let hit = hits.first else { return nil }
            let location = hit.worldCoordinates
            return MeshPoint(x: Double(location.x), y: Double(location.y), z: Double(location.z))
        }

        private func showDraft(in view: SCNView) {
            guard let scene = view.scene else { return }
            scene.rootNode.childNode(withName: "draft-stroke", recursively: false)?.removeFromParentNode()
            guard draft.count >= 2 else { return }
            let node = strokeNode(points: draft, color: color, selected: true)
            node.name = "draft-stroke"
            node.categoryBitMask = 2
            scene.rootNode.addChildNode(node)
        }

        private func routeID(from node: SCNNode?) -> UUID? {
            var current = node
            while let node = current {
                if let name = node.name, name.hasPrefix("route:"),
                   let id = UUID(uuidString: String(name.dropFirst("route:".count))) {
                    return id
                }
                current = node.parent
            }
            return nil
        }
    }

    private func refreshRoutes(in scene: SCNScene?) {
        guard let scene else { return }
        for child in scene.rootNode.childNodes where child.name?.hasPrefix("route:") == true {
            child.removeFromParentNode()
        }
        for route in routes {
            scene.rootNode.addChildNode(marker(for: route, selected: route.id == selectedID))
        }
    }

    private func marker(for route: WallRoutePin, selected: Bool) -> SCNNode {
        let hold = HoldColor(rawValue: route.colorName) ?? .blue
        if route.path.count >= 2 {
            let node = strokeNode(points: route.path, color: hold, selected: selected)
            node.name = "route:\(route.id.uuidString)"
            let top = route.path.max(by: { $0.y < $1.y }) ?? route.path[0]
            node.addChildNode(gradeLabel(route.grade, at: top))
            return node
        }
        let raw = SIMD3(Float(route.nx), Float(route.ny), Float(route.nz))
        let normal = simd_length(raw) > 0.001 ? simd_normalize(raw) : SIMD3<Float>(0, 0, 1)
        let lift: Float = 0.055
        let node = SCNNode()
        node.name = "route:\(route.id.uuidString)"
        node.categoryBitMask = 2
        node.position = SCNVector3(
            Float(route.x) + normal.x * lift,
            Float(route.y) + normal.y * lift,
            Float(route.z) + normal.z * lift
        )
        let sphere = SCNSphere(radius: selected ? 0.075 : 0.05)
        let material = SCNMaterial()
        material.diffuse.contents = UIColor(
            red: CGFloat(hold.red),
            green: CGFloat(hold.green),
            blue: CGFloat(hold.blue),
            alpha: 1
        )
        material.lightingModel = .constant
        sphere.materials = [material]
        node.geometry = sphere

        let text = SCNText(string: route.grade, extrusionDepth: 0.4)
        text.font = UIFont.systemFont(ofSize: 12, weight: .bold)
        text.flatness = 0.3
        let textMaterial = SCNMaterial()
        textMaterial.diffuse.contents = UIColor.white
        textMaterial.lightingModel = .constant
        text.materials = [textMaterial]
        let textNode = SCNNode(geometry: text)
        let (minBound, maxBound) = textNode.boundingBox
        let height = max(maxBound.y - minBound.y, 0.001)
        let scale = 0.07 / height
        textNode.scale = SCNVector3(scale, scale, scale)
        textNode.pivot = SCNMatrix4MakeTranslation((minBound.x + maxBound.x) / 2, minBound.y, 0)
        textNode.position = SCNVector3(0, 0.09, 0)
        textNode.constraints = [SCNBillboardConstraint()]
        node.addChildNode(textNode)
        return node
    }

    private func scene(from data: Data) -> SCNScene {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("gym-preview-\(UUID().uuidString).usdz")
        do {
            try data.write(to: url)
            let loaded = try SCNScene(url: url, options: nil)
            try? FileManager.default.removeItem(at: url)
            loaded.rootNode.enumerateChildNodes { node, _ in
                node.categoryBitMask = 1
                node.geometry?.materials.forEach { $0.isDoubleSided = true }
            }
            loaded.rootNode.categoryBitMask = 1
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
            guard node.geometry != nil, node.name?.hasPrefix("route:") != true else { continue }
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

private func strokeNode(points: [MeshPoint], color: HoldColor, selected: Bool) -> SCNNode {
    let node = SCNNode()
    node.categoryBitMask = 2
    let material = SCNMaterial()
    material.diffuse.contents = UIColor(red: CGFloat(color.red), green: CGFloat(color.green), blue: CGFloat(color.blue), alpha: 1)
    material.lightingModel = .constant
    let radius: CGFloat = selected ? 0.034 : 0.026
    for point in points {
        let sphere = SCNSphere(radius: radius)
        sphere.materials = [material]
        let dot = SCNNode(geometry: sphere)
        dot.categoryBitMask = 2
        dot.position = SCNVector3(Float(point.x), Float(point.y), Float(point.z) + 0.025)
        node.addChildNode(dot)
    }
    return node
}

private func gradeLabel(_ grade: String, at point: MeshPoint) -> SCNNode {
    let text = SCNText(string: grade, extrusionDepth: 0.4)
    text.font = UIFont.systemFont(ofSize: 12, weight: .bold)
    text.flatness = 0.3
    let material = SCNMaterial()
    material.diffuse.contents = UIColor.white
    material.lightingModel = .constant
    text.materials = [material]
    let node = SCNNode(geometry: text)
    let (minBound, maxBound) = node.boundingBox
    let height = max(maxBound.y - minBound.y, 0.001)
    let scale = 0.07 / height
    node.scale = SCNVector3(scale, scale, scale)
    node.pivot = SCNMatrix4MakeTranslation((minBound.x + maxBound.x) / 2, minBound.y, 0)
    node.position = SCNVector3(Float(point.x), Float(point.y) + 0.08, Float(point.z) + 0.03)
    node.constraints = [SCNBillboardConstraint()]
    node.categoryBitMask = 2
    return node
}
