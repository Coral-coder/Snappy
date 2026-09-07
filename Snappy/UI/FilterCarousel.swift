import SwiftUI

/// Horizontal strip of lenses. Swiping the viewfinder moves the same selection,
/// so the carousel is a shortcut rather than the only way to change filters.
struct FilterCarousel: View {
    let effects: [LensEffect]
    @Binding var selectedIndex: Int

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(Array(effects.enumerated()), id: \.offset) { index, effect in
                        Button {
                            withAnimation(.snappy(duration: 0.2)) { selectedIndex = index }
                        } label: {
                            LensChip(effect: effect, isSelected: index == selectedIndex)
                        }
                        .buttonStyle(.plain)
                        .id(index)
                    }
                }
                .padding(.horizontal, 4)
            }
            .frame(height: 74)
            .onChange(of: selectedIndex) { _, index in
                withAnimation(.snappy(duration: 0.25)) {
                    proxy.scrollTo(index, anchor: .center)
                }
            }
        }
    }
}

private struct LensChip: View {
    let effect: LensEffect
    let isSelected: Bool

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: effect.symbol)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(isSelected ? .black : .white)
                .frame(width: 46, height: 46)
                .background(isSelected ? Color.white : Color.black.opacity(0.35), in: Circle())
                .overlay(
                    Circle().stroke(.white.opacity(isSelected ? 0 : 0.35), lineWidth: 1)
                )
            Text(effect.name)
                .font(.system(size: 10, weight: isSelected ? .semibold : .regular))
                .foregroundStyle(.white.opacity(isSelected ? 1 : 0.7))
                .lineLimit(1)
                .frame(width: 62)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(effect.name)
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
    }
}
