import SwiftUI

// inputs {id, name, icon}, does {temporary demo widget proving the registry/render/reorder pipeline; replaced by real widgets in 0.3.0}, returns {NotchWidget}
final class PlaceholderWidget: NotchWidget {
    let id: String
    let displayName: String
    private let icon: String

    init(id: String, displayName: String, icon: String) {
        self.id = id
        self.displayName = displayName
        self.icon = icon
    }

    var expandedView: AnyView {
        AnyView(
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundStyle(.white.opacity(0.8))
                Text(displayName)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.6))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        )
    }
}
