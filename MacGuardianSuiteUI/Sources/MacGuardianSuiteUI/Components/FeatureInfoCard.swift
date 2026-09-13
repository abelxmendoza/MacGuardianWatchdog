import SwiftUI

/// A collapsible "what is this / why does it matter" explainer shown at the
/// top of a feature, dashboard, or tool. Every screen in MacGuardian should
/// answer three questions before the user acts: what does this do, why
/// should I care, and what exactly does it look at or change.
struct FeatureInfoCard: View {
    let icon: String
    let title: String
    let whatItDoes: String
    let whyItMatters: String
    /// Concrete things this feature reads, checks, or can modify - keeps
    /// "why it matters" from being vague marketing copy.
    var checks: [String] = []
    var checksLabel: String = "What it looks at"
    @State private var isExpanded = true

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.15)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: icon)
                        .foregroundColor(.themePurple)
                        .font(.title3)
                    Text("About \(title)")
                        .font(.subheadline.bold())
                        .foregroundColor(.themeText)
                    Spacer()
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption)
                        .foregroundColor(.themeTextSecondary)
                }
                .padding(12)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                VStack(alignment: .leading, spacing: 10) {
                    labeledText(label: "What it does", text: whatItDoes)
                    labeledText(label: "Why it matters", text: whyItMatters)

                    if !checks.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(checksLabel)
                                .font(.caption.bold())
                                .foregroundColor(.themePurple)
                            ForEach(checks, id: \.self) { item in
                                HStack(alignment: .top, spacing: 6) {
                                    Text("•")
                                        .foregroundColor(.themeTextSecondary)
                                    Text(item)
                                        .font(.caption)
                                        .foregroundColor(.themeTextSecondary)
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
            }
        }
        .background(Color.themePurple.opacity(0.08))
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.themePurpleDark.opacity(0.5), lineWidth: 1)
        )
    }

    private func labeledText(label: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption.bold())
                .foregroundColor(.themePurple)
            Text(text)
                .font(.caption)
                .foregroundColor(.themeTextSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
