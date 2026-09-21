import SwiftUI
import UIKit

/// Wall photo with today's route pins. Overlay sits on the fitted image so
/// 0...1 coordinates match the Watch map.
struct WallPinCanvas: View {
    var photoData: Data?
    var routes: [GymRoute]
    var selectedID: UUID?
    var onTapMap: (Double, Double) -> Void
    var onTapRoute: (GymRoute) -> Void

    var body: some View {
        Group {
            if let photoData, let image = UIImage(data: photoData) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .overlay { pinOverlay }
            } else {
                ZStack {
                    Color(.tertiarySystemFill)
                    Text("Add a wall photo, then tap to pin routes")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding()
                }
                .aspectRatio(3 / 4, contentMode: .fit)
                .overlay { pinOverlay }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private var pinOverlay: some View {
        GeometryReader { geo in
            ZStack {
                Color.clear
                    .contentShape(Rectangle())
                    .gesture(
                        SpatialTapGesture()
                            .onEnded { event in
                                let size = geo.size
                                guard size.width > 0, size.height > 0 else { return }
                                onTapMap(event.location.x / size.width, event.location.y / size.height)
                            }
                    )
                ForEach(routes, id: \.id) { route in
                    Button {
                        onTapRoute(route)
                    } label: {
                        Text(route.grade)
                            .font(.caption2.bold())
                            .foregroundStyle(route.holdColor.prefersDarkLabel ? Color.black : Color.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 4)
                            .background(Color(hold: route.holdColor), in: Capsule())
                            .overlay {
                                Capsule()
                                    .strokeBorder(
                                        selectedID == route.id ? Color.white : Color.clear,
                                        lineWidth: 2
                                    )
                            }
                    }
                    .buttonStyle(.plain)
                    .position(x: route.x * geo.size.width, y: route.y * geo.size.height)
                }
            }
        }
    }
}
