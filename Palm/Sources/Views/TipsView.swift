import SwiftUI

/// The tips sheet. Opens on the section matching the lens you were looking at,
/// because a tip about panning is useless while you are drawing a hi-hat.
struct TipsView: View {
    let initial: Tip.Lens
    @State private var lens: Tip.Lens
    @Environment(\.dismiss) private var dismiss

    init(initial: Tip.Lens) {
        self.initial = initial
        _lens = State(initialValue: initial)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Tips").font(P.title(20)).foregroundStyle(P.ink)
                Spacer()
                Button("Done") { dismiss() }
                    .font(P.label(15))
                    .foregroundStyle(P.amber)
                    .frame(minWidth: P.touch, minHeight: P.touch)
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(Tip.Lens.allCases, id: \.rawValue) { option in
                        Button {
                            Haptic.select()
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                                lens = option
                            }
                        } label: {
                            Text(option.rawValue)
                                .font(P.label(13))
                                .padding(.horizontal, 15)
                                .frame(height: P.touch - 6)
                                .foregroundStyle(lens == option ? P.ground : P.dim)
                                .background(RoundedRectangle(cornerRadius: 11, style: .continuous)
                                    .fill(lens == option ? P.amber : P.raised))
                                .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous)
                                    .strokeBorder(lens == option ? .clear : P.line))
                        }
                        .buttonStyle(PressStyle())
                    }
                }
                .padding(.horizontal, 16)
            }
            .padding(.vertical, 10)

            ScrollView {
                VStack(spacing: P.gap) {
                    ForEach(Tips.forLens(lens)) { tip in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(tip.headline)
                                .font(P.title(16))
                                .foregroundStyle(P.ink)
                                .fixedSize(horizontal: false, vertical: true)
                            Text(tip.body)
                                .font(.system(size: 14, design: .rounded))
                                .foregroundStyle(P.dim)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(14)
                        .background(RoundedRectangle(cornerRadius: P.radius, style: .continuous)
                            .fill(P.raised))
                        .overlay(RoundedRectangle(cornerRadius: P.radius, style: .continuous)
                            .strokeBorder(P.line))
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
        }
        .background(P.surface)
    }
}
