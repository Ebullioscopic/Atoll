import SwiftUI

struct CompanionMascotView: View {
    let source: String
    let status: CompanionStatus
    var size: CGFloat = 27

    var body: some View {
        SharedMascotView(source: source, status: MascotAgentStatus(status.rawValue), size: size)
    }
}
