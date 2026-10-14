import SwiftUI

/// A vector orientation aid, paired with the text/state grid in ControllerTestView.
/// Stick caps describe the layout; only monitored buttons show live input.
struct ControllerDiagram: View {
    let style: ControllerButtonStyle
    let liveInputs: Set<String>
    let availableInputs: [String]

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            ZStack {
                ControllerOutline()
                    .fill(DesignTokens.surface)
                ControllerOutline()
                    .stroke(DesignTokens.border, lineWidth: 1.5)
                if style.isPlayStation {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(DesignTokens.border.opacity(0.35))
                        .frame(width: size.width * 0.24, height: size.height * 0.22)
                        .position(x: size.width * 0.5, y: size.height * 0.30)
                }
                stick(in: size, x: style == .xbox ? 0.24 : 0.37, y: style == .xbox ? 0.37 : 0.63)
                stick(in: size, x: 0.63, y: 0.63)
                let dpadX = style == .xbox ? 0.37 : 0.24
                let dpadY = style == .xbox ? 0.63 : 0.37
                indicator("dpadUp", symbol: "chevron.up", in: size, x: dpadX, y: dpadY - 0.095)
                indicator("dpadDown", symbol: "chevron.down", in: size, x: dpadX, y: dpadY + 0.095)
                indicator("dpadLeft", symbol: "chevron.left", in: size, x: dpadX - 0.055, y: dpadY)
                indicator("dpadRight", symbol: "chevron.right", in: size, x: dpadX + 0.055, y: dpadY)
                indicator("buttonA", in: size, x: 0.76, y: 0.48)
                indicator("buttonB", in: size, x: 0.82, y: 0.37)
                indicator("buttonX", in: size, x: 0.70, y: 0.37)
                indicator("buttonY", in: size, x: 0.76, y: 0.26)
                indicator("buttonOptions", symbol: style.isPlayStation ? "line.3.horizontal" : "rectangle.on.rectangle", in: size, x: 0.435, y: 0.47)
                indicator("buttonMenu", symbol: "line.3.horizontal", in: size, x: 0.565, y: 0.47)
                shoulder("leftShoulder", in: size, x: 0.24)
                shoulder("rightShoulder", in: size, x: 0.76)
            }
        }
        .aspectRatio(1.85, contentMode: .fit)
        .frame(maxWidth: 340)
        .frame(maxWidth: .infinity)
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }

    private func stick(in size: CGSize, x: CGFloat, y: CGFloat) -> some View {
        Circle()
            .fill(DesignTokens.border.opacity(0.45))
            .overlay(Circle().stroke(DesignTokens.textMuted, lineWidth: 1))
            .frame(width: size.width * 0.10, height: size.width * 0.10)
            .position(x: size.width * x, y: size.height * y)
    }

    @ViewBuilder
    private func indicator(_ input: String, symbol: String? = nil, in size: CGSize, x: CGFloat, y: CGFloat) -> some View {
        if availableInputs.contains(input) {
            let active = liveInputs.contains(input)
            ZStack {
                Circle().fill(active ? StatusToken.verified : DesignTokens.background)
                Circle().stroke(active ? Color.black : DesignTokens.textMuted, lineWidth: active ? 2 : 1)
                if let symbol {
                    Image(systemName: symbol).font(.caption2.weight(.semibold))
                } else {
                    Text(faceGlyph(for: input)).font(.psLabelEmphasized)
                }
            }
            .foregroundStyle(active ? Color.black : DesignTokens.textPrimary)
            .frame(width: size.width * 0.065, height: size.width * 0.065)
            .position(x: size.width * x, y: size.height * y)
        }
    }

    private func shoulder(_ input: String, in size: CGSize, x: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 4)
            .fill(liveInputs.contains(input) ? StatusToken.verified : DesignTokens.border)
            .frame(width: size.width * 0.16, height: size.height * 0.045)
            .position(x: size.width * x, y: size.height * 0.12)
    }

    private func faceGlyph(for input: String) -> String {
        if style.isPlayStation {
            switch input {
            case "buttonA": "×"
            case "buttonB": "○"
            case "buttonX": "□"
            case "buttonY": "△"
            default: ""
            }
        } else {
            switch input {
            case "buttonA": "A"
            case "buttonB": "B"
            case "buttonX": "X"
            case "buttonY": "Y"
            default: ""
            }
        }
    }
}

private struct ControllerOutline: Shape {
    func path(in rect: CGRect) -> Path {
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + rect.width * x, y: rect.minY + rect.height * y)
        }
        var path = Path()
        path.move(to: p(0.22, 0.16))
        path.addCurve(to: p(0.09, 0.82), control1: p(0.10, 0.20), control2: p(0.05, 0.68))
        path.addCurve(to: p(0.28, 0.82), control1: p(0.12, 1.00), control2: p(0.21, 0.99))
        path.addLine(to: p(0.39, 0.68))
        path.addQuadCurve(to: p(0.61, 0.68), control: p(0.50, 0.73))
        path.addLine(to: p(0.72, 0.82))
        path.addCurve(to: p(0.91, 0.82), control1: p(0.79, 0.99), control2: p(0.88, 1.00))
        path.addCurve(to: p(0.78, 0.16), control1: p(0.95, 0.68), control2: p(0.90, 0.20))
        path.addQuadCurve(to: p(0.22, 0.16), control: p(0.50, 0.10))
        path.closeSubpath()
        return path
    }
}
