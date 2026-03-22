import SwiftUI

struct StatusBadgeView: View {
    let statusName: String
    let category: JiraStatusCategory

    private var badgeColor: Color {
        switch category {
        case .new:
            return .blue
        case .indeterminate:
            return .orange
        case .done:
            return .green
        case .unknown:
            return .gray
        }
    }

    var body: some View {
        Text(statusName)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(badgeColor)
            .clipShape(Capsule())
    }
}
