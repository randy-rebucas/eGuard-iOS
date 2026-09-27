import SwiftUI

// MARK: - Icon tile

/// A rounded square with a tinted background and an SF Symbol, leading every list row.
struct IconTile: View {
    let symbolName: String
    var tint: Color = EGuardColors.primary
    var size: CGFloat = 36
    var filled = false

    var body: some View {
        Image(systemName: symbolName)
            .font(.system(size: size * 0.45, weight: .semibold))
            .foregroundStyle(filled ? .white : tint)
            .frame(width: size, height: size)
            .background(filled ? tint : tint.opacity(0.14), in: EGuardShapes.tile)
            .accessibilityHidden(true)
    }
}

// MARK: - Rows

/// Icon tile, title, subtitle, and an optional trailing view or chevron.
struct EGuardNavRow<Trailing: View>: View {
    let title: String
    var subtitle: String? = nil
    let symbolName: String
    var tint: Color = EGuardColors.primary
    var showsChevron = true
    var action: (() -> Void)? = nil
    @ViewBuilder var trailing: () -> Trailing

    init(
        title: String,
        subtitle: String? = nil,
        symbolName: String,
        tint: Color = EGuardColors.primary,
        showsChevron: Bool = true,
        action: (() -> Void)? = nil,
        @ViewBuilder trailing: @escaping () -> Trailing = { EmptyView() }
    ) {
        self.title = title
        self.subtitle = subtitle
        self.symbolName = symbolName
        self.tint = tint
        self.showsChevron = showsChevron
        self.action = action
        self.trailing = trailing
    }

    var body: some View {
        if let action {
            Button(action: action) { content }
                .buttonStyle(.plain)
        } else {
            content
        }
    }

    private var content: some View {
        HStack(spacing: EGuardSpacing.sm) {
            IconTile(symbolName: symbolName, tint: tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(EGuardTypography.label)
                    .foregroundStyle(EGuardColors.textPrimary)
                if let subtitle {
                    Text(subtitle)
                        .font(EGuardTypography.caption)
                        .foregroundStyle(EGuardColors.textSecondary)
                }
            }
            .multilineTextAlignment(.leading)
            Spacer(minLength: EGuardSpacing.xs)
            trailing()
            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(EGuardColors.neutral)
            }
        }
        .padding(.vertical, EGuardSpacing.xs)
        .contentShape(Rectangle())
    }
}

/// A checklist line with a status icon, used on Health and Complete screens.
struct ChecklistRow: View {
    let title: String
    var detail: String? = nil
    let status: HealthStatus

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: EGuardSpacing.sm) {
            Image(systemName: EGuardTheme.symbol(for: status))
                .foregroundStyle(EGuardTheme.color(for: status))
                .font(.title3)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(EGuardTypography.label)
                    .foregroundStyle(EGuardColors.textPrimary)
                if let detail {
                    Text(detail)
                        .font(EGuardTypography.caption)
                        .foregroundStyle(EGuardColors.textSecondary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, EGuardSpacing.xxs)
        .accessibilityElement(children: .combine)
        .accessibilityValue(status.title)
    }
}

/// Title on the left, optional "View All" on the right.
struct SectionHeader: View {
    let title: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(EGuardTypography.headline)
                .foregroundStyle(EGuardColors.textPrimary)
                .accessibilityAddTraits(.isHeader)
            Spacer()
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .font(EGuardTypography.label)
                    .foregroundStyle(EGuardColors.primary)
            }
        }
    }
}

// MARK: - Pills and badges

/// A small tinted capsule such as "Protected" or "Attention".
struct StatusPill: View {
    let text: String
    let tint: Color

    var body: some View {
        Text(text)
            .font(EGuardTypography.overline)
            .foregroundStyle(tint)
            .padding(.horizontal, EGuardSpacing.xs)
            .padding(.vertical, EGuardSpacing.xxs)
            .background(tint.opacity(0.14), in: Capsule())
    }
}

/// A capsule segmented control with a filled selected segment, as in the mockup.
struct PillSegmentedControl<Option: Hashable>: View {
    let options: [Option]
    @Binding var selection: Option
    let title: (Option) -> String
    @Namespace private var namespace

    var body: some View {
        HStack(spacing: EGuardSpacing.xxs) {
            ForEach(options, id: \.self) { option in
                Button {
                    withAnimation(.snappy(duration: 0.25)) { selection = option }
                } label: {
                    Text(title(option))
                        .font(EGuardTypography.label)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .foregroundStyle(selection == option ? .white : EGuardColors.textPrimary)
                        .padding(.horizontal, EGuardSpacing.xs)
                        .padding(.vertical, EGuardSpacing.xs)
                        .frame(maxWidth: .infinity)
                        .background {
                            if selection == option {
                                Capsule()
                                    .fill(EGuardColors.primary)
                                    .matchedGeometryEffect(id: "pill", in: namespace)
                            }
                        }
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selection == option ? [.isSelected] : [])
            }
        }
        .padding(EGuardSpacing.xxs)
        .background(EGuardColors.surface, in: Capsule())
    }
}

// MARK: - Ring gauge

/// A circular progress ring with the value centered inside.
struct RingGauge<Label: View>: View {
    let progress: Double
    var tint: Color = EGuardColors.primary
    var lineWidth: CGFloat = 14
    var size: CGFloat = 140
    @ViewBuilder var label: () -> Label

    var body: some View {
        ZStack {
            Circle()
                .stroke(tint.opacity(0.15), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: min(max(progress, 0), 1))
                .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeOut(duration: 0.6), value: progress)
            label()
        }
        .frame(width: size, height: size)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Avatar

/// A circular photo or initials, optionally with a small status dot.
struct AvatarView: View {
    let name: String
    var imageData: Data? = nil
    var size: CGFloat = 56
    var tint: Color = EGuardColors.primary

    var body: some View {
        ZStack {
            if let imageData, let image = UIImage(data: imageData) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Circle().fill(tint.opacity(0.15))
                Text(initials)
                    .font(.system(size: size * 0.38, weight: .bold, design: .rounded))
                    .foregroundStyle(tint)
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .accessibilityLabel(name.isEmpty ? "No photo" : "\(name)'s photo")
    }

    private var initials: String {
        let parts = name.split(separator: " ").prefix(2)
        let letters = parts.compactMap { $0.first }.map(String.init)
        return letters.isEmpty ? "?" : letters.joined().uppercased()
    }
}

// MARK: - Text field

/// A bordered field with a leading icon and small floating label, as on Create Account.
struct EGuardTextField: View {
    let label: String
    let placeholder: String
    @Binding var text: String
    var symbolName: String
    var isSecure = false
    var contentType: UITextContentType? = nil
    var keyboard: UIKeyboardType = .default
    var autocapitalization: TextInputAutocapitalization = .never
    /// Applied to the inner field so UI tests can find it.
    var identifier: String? = nil

    @State private var isRevealed = false
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: EGuardSpacing.sm) {
            Image(systemName: symbolName)
                .foregroundStyle(isFocused ? EGuardColors.primary : EGuardColors.neutral)
                .frame(width: 22)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(EGuardTypography.caption)
                    .foregroundStyle(EGuardColors.textSecondary)
                field
                    .font(EGuardTypography.body)
                    .textContentType(contentType)
                    .keyboardType(keyboard)
                    .textInputAutocapitalization(autocapitalization)
                    .autocorrectionDisabled(isSecure || keyboard == .emailAddress)
                    .focused($isFocused)
                    .submitLabel(.done)
                    .accessibilityIdentifier(identifier ?? "")
            }
            if isSecure {
                Button {
                    isRevealed.toggle()
                } label: {
                    Image(systemName: isRevealed ? "eye.slash" : "eye")
                        .foregroundStyle(EGuardColors.neutral)
                }
                .accessibilityLabel(isRevealed ? "Hide password" : "Show password")
            }
        }
        .padding(.horizontal, EGuardSpacing.sm)
        .padding(.vertical, EGuardSpacing.xs)
        .background(EGuardColors.surface, in: EGuardShapes.button)
        .overlay(
            EGuardShapes.button.strokeBorder(isFocused ? EGuardColors.primary : EGuardColors.divider, lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture { isFocused = true }
    }

    @ViewBuilder
    private var field: some View {
        if isSecure && !isRevealed {
            SecureField(placeholder, text: $text)
        } else {
            TextField(placeholder, text: $text)
        }
    }
}

// MARK: - Confetti

/// Lightweight celebratory confetti drawn with Canvas; no assets required.
struct ConfettiView: View {
    private struct Piece {
        let x: Double
        let y: Double
        let size: Double
        let rotation: Double
        let color: Color
        let isRound: Bool
    }

    private let pieces: [Piece]

    init(count: Int = 36) {
        let palette = [EGuardColors.primary, EGuardColors.success, EGuardColors.tileYellow, EGuardColors.tilePink, EGuardColors.tileOrange, EGuardColors.tileTeal]
        var generator = SystemRandomNumberGenerator()
        pieces = (0..<count).map { index in
            Piece(
                x: Double.random(in: 0.02...0.98, using: &generator),
                y: Double.random(in: 0.02...0.95, using: &generator),
                size: Double.random(in: 5...11, using: &generator),
                rotation: Double.random(in: 0...360, using: &generator),
                color: palette[index % palette.count],
                isRound: index % 3 == 0
            )
        }
    }

    var body: some View {
        Canvas { context, size in
            for piece in pieces {
                let rect = CGRect(
                    x: piece.x * size.width,
                    y: piece.y * size.height,
                    width: piece.size,
                    height: piece.isRound ? piece.size : piece.size * 0.55
                )
                var transform = CGAffineTransform(translationX: rect.midX, y: rect.midY)
                transform = transform.rotated(by: piece.rotation * .pi / 180)
                transform = transform.translatedBy(x: -rect.midX, y: -rect.midY)
                let path = piece.isRound
                    ? Path(ellipseIn: rect).applying(transform)
                    : Path(roundedRect: rect, cornerRadius: 1.5).applying(transform)
                context.fill(path, with: .color(piece.color))
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// MARK: - Empty state

/// Centered illustration and message used when a screen has no data yet.
struct EmptyStateView: View {
    let symbolName: String
    let title: String
    let message: String
    var tint: Color = EGuardColors.primary

    var body: some View {
        VStack(spacing: EGuardSpacing.sm) {
            EGuardIllustration(symbolName: symbolName, tint: tint, size: 80)
            Text(title)
                .font(EGuardTypography.headline)
                .foregroundStyle(EGuardColors.textPrimary)
            Text(message)
                .font(EGuardTypography.callout)
                .foregroundStyle(EGuardColors.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(EGuardSpacing.lg)
    }
}

#Preview {
    ScrollView {
        VStack(spacing: 24) {
            RingGauge(progress: 0.8, tint: EGuardColors.success) {
                VStack {
                    Text("8 / 10").font(EGuardTypography.metric)
                    Text("Good Protection").font(EGuardTypography.caption).foregroundStyle(EGuardColors.success)
                }
            }
            EGuardCard {
                EGuardNavRow(title: "Daily screen time", subtitle: "3 hours/day", symbolName: "clock.fill")
                Divider()
                EGuardNavRow(title: "Bedtime", subtitle: "9:30 PM – 6:00 AM", symbolName: "moon.fill", tint: EGuardColors.tilePurple)
            }
            PillSegmentedControl(options: ["Today", "7 Days", "30 Days"], selection: .constant("Today")) { $0 }
            EGuardTextField(label: "Email address", placeholder: "you@example.com", text: .constant(""), symbolName: "envelope")
            HStack { AvatarView(name: "Mia Cruz"); AvatarView(name: "Lucas", tint: EGuardColors.tileOrange) }
            ChecklistRow(title: "Screen time configured", status: .pass)
            ChecklistRow(title: "Bedtime", status: .notConfigured)
        }
        .padding()
    }
    .background(EGuardColors.background)
}
