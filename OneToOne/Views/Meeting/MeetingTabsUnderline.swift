import SwiftUI

struct MeetingTabsUnderline: View {
    @Binding var selection: MeetingView.MeetingSection
    let attachmentsCount: Int
    let hasReport: Bool

    @Namespace private var underlineNS

    var body: some View {
        HStack(spacing: 28) {
            ForEach(MeetingView.MeetingSection.allCases) { section in
                tab(section)
            }
            Spacer()
        }
        .padding(.horizontal, 28)
        .padding(.top, 6)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(MeetingTheme.hairline)
                .frame(height: 0.5)
        }
    }

    @ViewBuilder
    private func tab(_ section: MeetingView.MeetingSection) -> some View {
        let isActive = selection == section
        Button {
            withAnimation(.easeInOut(duration: 0.2)) { selection = section }
        } label: {
            VStack(spacing: 6) {
                HStack(spacing: 4) {
                    Text(section.rawValue)
                        .font(isActive ? .body.weight(.semibold) : .body)
                        .foregroundColor(isActive ? .primary : .secondary)
                    badge(for: section)
                }
                if isActive {
                    Rectangle()
                        .fill(MeetingTheme.accentOrange)
                        .frame(height: 2)
                        .matchedGeometryEffect(id: "underline", in: underlineNS)
                } else {
                    Color.clear.frame(height: 2)
                }
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func badge(for section: MeetingView.MeetingSection) -> some View {
        switch section {
        case .documents where attachmentsCount > 0:
            Text("\(attachmentsCount)")
                .font(.caption2.bold())
                .foregroundColor(.white)
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .background(Capsule().fill(Color.secondary))
        case .report where hasReport:
            Image(systemName: "checkmark")
                .font(.caption2.bold())
                .foregroundColor(MeetingTheme.accentOrange)
        default:
            EmptyView()
        }
    }
}
