import SwiftUI
import SceneKit

struct BuildingDetailSheet: View {
    let node: BuildingNode
    let dayRecord: DayRecord?
    var onRotate: (() -> Void)? = nil
    var onStore: (() -> Void)? = nil
    @Environment(\.dismiss) private var dismiss
    @State private var shown = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Rotating 3D preview of the actual building
                    SceneView(scene: previewScene, options: [])
                        .frame(height: 190)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius))
                        .scaleEffect(shown ? 1 : 0.6)
                        .opacity(shown ? 1 : 0)
                        .animation(.spring(response: 0.45, dampingFraction: 0.7), value: shown)
                        .padding(.top, 8)

                    VStack(spacing: 6) {
                        Text(node.type.displayName).font(.title2.bold())
                        if let record = dayRecord {
                            Text(record.date, format: Date.FormatStyle(date: .long))
                                .font(.subheadline).foregroundStyle(.secondary)
                        }
                        if !node.isComplete {
                            Label(L(S.map.underConstruction), systemImage: "hammer.fill")
                                .font(.caption).foregroundStyle(.orange)
                                .padding(.horizontal, 10).padding(.vertical, 4)
                                .background(Color.orange.opacity(0.12))
                                .clipShape(Capsule())
                        }
                    }

                    // Quick actions
                    HStack(spacing: 12) {
                        if node.canRotate {
                            Button {
                                (onRotate ?? node.toggleRotation)()
                            } label: {
                                Label(L(S.map.rotate), systemImage: "arrow.left.arrow.right")
                                    .font(.subheadline.bold())
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                                    .background(accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: Theme.rowRadius))
                                    .foregroundStyle(accentColor)
                            }
                            .buttonStyle(.plain)
                        }

                        // Put away rather than destroyed: it goes to the inventory and
                        // can come back any time, so no confirmation is needed.
                        if let onStore {
                            Button {
                                dismiss()
                                onStore()
                            } label: {
                                Label(L(S.town.storeAway), systemImage: "backpack.fill")
                                    .font(.subheadline.bold())
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.8)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                                    .background(accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: Theme.rowRadius))
                                    .foregroundStyle(accentColor)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 4)

                    Text(L(S.map.moveTip))
                        .font(.caption).foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)

                    Divider()

                    if let record = dayRecord, !record.pillars.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(L(S.calendar.dayPillars)).font(.headline)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            ForEach(record.pillars.sorted(by: { $0.order < $1.order })) { p in
                                HStack(spacing: 10) {
                                    Image(systemName: p.isCompleted ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(p.isCompleted ? Color.green : Color.secondary)
                                    Text(p.text)
                                        .foregroundStyle(p.isCompleted ? Color.primary : Color.secondary)
                                }
                            }
                        }
                        .padding(.horizontal)
                    }

                    Spacer(minLength: 32)
                }
                .padding(.horizontal)
            }
            .navigationTitle(node.type.displayName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(L(S.common.close)) { dismiss() }
                }
            }
        }
        .onAppear { shown = true }
    }

    /// Mini scene with a slowly rotating clone of the tapped building.
    private var previewScene: SCNScene {
        let scene = SCNScene()
        scene.background.contents = UIColor.secondarySystemBackground

        let model = BuildingFactory.node(for: node.type)
        // Center on the bounding box (wide models like the tavern stay mid-frame)
        let (minB, maxB) = model.boundingBox
        let h = CGFloat(maxB.y - minB.y)
        let w = CGFloat(maxB.x - minB.x)
        let cx: Float = (minB.x + maxB.x) / 2
        let cz: Float = (minB.z + maxB.z) / 2
        let cy: Float = Float(h) / 2
        model.position = SCNVector3(-cx, -cy, -cz)

        let spinner = SCNNode()
        spinner.addChildNode(model)
        spinner.runAction(.repeatForever(.rotateBy(x: 0, y: .pi * 2, z: 0, duration: 14)))
        scene.rootNode.addChildNode(spinner)

        // Pedestal
        let disc = SCNCylinder(radius: 0.7, height: 0.06)
        disc.firstMaterial?.diffuse.contents = UIColor(red: 0.55, green: 0.72, blue: 0.42, alpha: 1)
        disc.firstMaterial?.lightingModel = .lambert
        let pedestal = SCNNode(geometry: disc)
        pedestal.position = SCNVector3(0, Float(-h / 2) - 0.04, 0)
        spinner.addChildNode(pedestal)

        // Lights
        let sun = SCNLight()
        sun.type = .directional
        sun.intensity = 950
        sun.color = UIColor(red: 1.0, green: 0.96, blue: 0.88, alpha: 1)
        let sunNode = SCNNode()
        sunNode.light = sun
        sunNode.eulerAngles = SCNVector3(-0.9, -0.6, 0)
        scene.rootNode.addChildNode(sunNode)

        let amb = SCNLight()
        amb.type = .ambient
        amb.intensity = 600
        amb.color = UIColor(red: 0.85, green: 0.90, blue: 0.96, alpha: 1)
        let ambNode = SCNNode()
        ambNode.light = amb
        scene.rootNode.addChildNode(ambNode)

        // Camera framing the whole model, looking straight on
        // (slightly raised so the model sits a touch below center)
        let cam = SCNCamera()
        cam.usesOrthographicProjection = true
        cam.orthographicScale = Double(max(0.85, h * 0.68, w * 0.45))
        let camNode = SCNNode()
        camNode.camera = cam
        camNode.position = SCNVector3(0, 0.18, 10)
        scene.rootNode.addChildNode(camNode)

        return scene
    }

    private var accentColor: Color {
        let c = node.type.skColorRGB
        return Color(red: c.r, green: c.g, blue: c.b)
    }
}
