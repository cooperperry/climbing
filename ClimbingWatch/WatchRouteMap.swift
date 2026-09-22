import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// Current wall photo plus today's pins. Tap a pin to log the armed outcome.
struct WatchRouteMap: View {
    var photoData: Data?
    var routes: [WatchRoutePin]
    var onSelect: (WatchRoutePin) -> Void

    var body: some View {
        Group {
            if let photoData, let image = UIImage(data: photoData) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .overlay { pinOverlay }
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.white.opacity(0.08))
                    if routes.isEmpty {
                    Text("No routes on this wall yet")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(6)
                    }
                }
                .aspectRatio(3 / 4, contentMode: .fit)
                .overlay { pinOverlay }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var pinOverlay: some View {
        GeometryReader { geo in
            ZStack {
                ForEach(routes) { route in
                    Button {
                        onSelect(route)
                    } label: {
                        Text(route.grade)
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(route.holdColor.prefersDarkLabel ? Color.black : Color.white)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 2)
                            .background(Color(hold: route.holdColor), in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .position(x: route.x * geo.size.width, y: route.y * geo.size.height)
                }
            }
        }
    }
}
