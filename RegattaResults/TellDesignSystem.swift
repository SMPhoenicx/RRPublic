//
//  AtmosphereBackground.swift
//  RegattaResults
//
//  Created by Suman Muppavarapu on 5/12/26.
//
import SwiftUI

// MARK: - Color Tokens

extension Color {
    // Accent
    static let tellAccent   = Color(red: 0.902, green: 0.298, blue: 0.271) // #E64C45
    static let tellAmber    = Color(red: 0.910, green: 0.659, blue: 0.278) // #E8A847
    static let tellCool     = Color(red: 0.612, green: 0.765, blue: 0.910) // #9CC3E8
    static let tellGreen    = Color(red: 0.357, green: 0.843, blue: 0.604) // #5BD79A

    // Text
    static let tellText     = Color(red: 0.949, green: 0.961, blue: 0.980) // #F2F5FA
    static let tellTextDim  = Color(red: 0.949, green: 0.961, blue: 0.980).opacity(0.74)
    static let tellTextMute = Color(red: 0.949, green: 0.961, blue: 0.980).opacity(0.46)

    // Glass
    static let glassTint    = Color.white.opacity(0.05)
    static let glassBorder  = Color.white.opacity(0.11)
    static let glassHL      = Color.white.opacity(0.22)  // top highlight

    // Background
    static let atmBase      = Color(red: 0.043, green: 0.094, blue: 0.157) // #0B1828
    static let atmDeep      = Color(red: 0.020, green: 0.043, blue: 0.082) // #050B15
}

// MARK: - Rail Color Helper

func tellRailColor(for status: String?) -> Color {
    switch status {
    case "live":     return .tellAccent
    case "upcoming": return .tellAmber
    default:         return .tellCool
    }
}

// MARK: - Atmosphere Background

struct AtmosphereBackground: View {
    var body: some View {
        ZStack {
            // Base gradient
            LinearGradient(
                colors: [.atmBase, .atmDeep],
                startPoint: .top,
                endPoint: .bottom
            )

            // Light blobs
            GeometryReader { geo in
                let w = geo.size.width
                // Top-right blue
                RadialGradient(
                    colors: [Color(red: 0.306, green: 0.482, blue: 0.714).opacity(0.2), .clear],
                    center: .init(x: 0.9, y: 0.11),
                    startRadius: 0,
                    endRadius: w * 0.4
                )

                // Mid-left blue
                RadialGradient(
                    colors: [Color(red: 0.184, green: 0.329, blue: 0.541).opacity(0.3), .clear],
                    center: .init(x: 0.17, y: 0.6),
                    startRadius: 0,
                    endRadius: w * 0.75
                )

                // Bottom-right red blob
                RadialGradient(
                    colors: [Color.tellAccent.opacity(0.10), .clear],
                    center: .init(x: 0.90, y: 0.89),
                    startRadius: 0,
                    endRadius: w * 0.6
                )
            }
        }
        .ignoresSafeArea()
    }
}

// MARK: - Glass Card Modifier

struct GlassCardModifier: ViewModifier {
    var radius: CGFloat    = 14
    var tint: Color        = .glassTint
    var borderColor: Color = .glassBorder
    var railColor: Color?  = nil
    var railWidth: CGFloat = 24
    var gradOn: Bool = true

    func body(content: Content) -> some View {
        content
            .background(
                ZStack(alignment: .leading) {
                    // Blur + tint
                    RoundedRectangle(cornerRadius: radius)
                        .fill(.ultraThinMaterial)
                    RoundedRectangle(cornerRadius: radius)
                        .fill(tint)
                    if let rail = railColor {
                        Rectangle()
                            .fill( LinearGradient(colors: [rail.opacity(0.75), gradOn ? .clear:rail], startPoint: .leading, endPoint: .trailing))
                            .frame(width: railWidth)
                            .shadow(color: rail.opacity(0.5), radius: 6, x: 0, y: 0)
                    }
                }
            )
            // Top inner highlight + border
            .overlay(
                RoundedRectangle(cornerRadius: radius)
                    .strokeBorder(
                        LinearGradient(
                            colors: [.glassHL, borderColor, borderColor],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 1
                    )
            )
            .clipShape(RoundedRectangle(cornerRadius: radius))
            .shadow(color: .black.opacity(0.45), radius: 18, x: 0, y: 8)
    }
}

extension View {
    func glassCard(
        radius: CGFloat = 14,
        tint: Color = .glassTint,
        borderColor: Color = .glassBorder,
        railColor: Color? = nil,
        railWidth: CGFloat = 24,
        gradOn: Bool = true
    ) -> some View {
        modifier(GlassCardModifier(radius: radius, tint: tint, borderColor: borderColor, railColor: railColor, railWidth: railWidth, gradOn: gradOn))
    }
}

// MARK: - Glass Strip (top/bottom bars)

struct GlassStrip<Content: View>: View {
    let content: Content
    var dark: Bool = false

    init(dark: Bool = false, @ViewBuilder content: () -> Content) {
        self.dark = dark
        self.content = content()
    }

    var body: some View {
        content
            .background(
                ZStack {
                    Rectangle().fill(.ultraThinMaterial)
                    Rectangle().fill(dark
                        ? Color(red: 0.024, green: 0.047, blue: 0.086).opacity(0.55)
                        : Color.white.opacity(0.08)
                    )
                }
                .overlay(alignment: .top) {
                    Rectangle()
                        .fill(Color.white.opacity(0.10))
                        .frame(height: 0.5)
                }
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(Color.black.opacity(0.25))
                        .frame(height: 0.5)
                }
            )
    }
}

// MARK: - Status Pill

enum StatusTone { case red, amber, cyan, green, ghost }

struct StatusPill: View {
    let text: String
    var tone: StatusTone = .amber
    var showPulse: Bool  = false

    private var colors: (bg: Color, fg: Color) {
        switch tone {
        case .red:   return (.tellAccent.opacity(0.18),    .tellAccent.opacity(0.90))
        case .amber: return (.tellAmber.opacity(0.18),     .tellAmber)
        case .cyan:  return (.tellCool.opacity(0.18),      .tellCool)
        case .green: return (.tellGreen.opacity(0.16),     .tellGreen)
        case .ghost: return (.white.opacity(0.10),         .white.opacity(0.85))
        }
    }

    var body: some View {
        HStack(spacing: 5) {
            if showPulse {
                Circle()
                    .fill(colors.fg)
                    .frame(width: 5, height: 5)
                    .shadow(color: colors.fg.opacity(0.8), radius: 3)
            }
            Text(text)
                .font(.system(size: 9.5, weight: .black))
                .tracking(1.0)
                .textCase(.uppercase)
        }
        .foregroundColor(colors.fg)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(colors.bg)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(colors.bg, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

// MARK: - Filter Chip

struct FilterChip: View {
    let label: String
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 13, weight: isOn ? .regular : .medium))
                .foregroundColor(isOn ? .white : .tellTextDim)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(
                    Group {
                        if isOn {
                            RoundedRectangle(cornerRadius: 20)
                                .fill(Color.tellAccent.opacity(0.22))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 20)
                                        .stroke(Color.tellAccent.opacity(0.55), lineWidth: 1)
                                )
                        } else {
                            RoundedRectangle(cornerRadius: 20)
                                .fill(Color.white.opacity(0.07))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 20)
                                        .stroke(Color.glassBorder, lineWidth: 1)
                                )
                        }
                    }
                )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Event Row

struct TellEventRow: View {
    let event: DBEvent

    private var statusLabel: String {
        switch event.status {
        case "live":     return "LIVE"
        case "upcoming": return dateLabel
        default:         return "UPCOMING"
        }
    }

    private var statusTone: StatusTone {
        switch event.status {
        case "live":     return .red
        case "upcoming": return .amber
        default:         return .cyan
        }
    }

    private var dateLabel: String {
        guard let start = event.startDate else { return "TBD" }
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return f.string(from: start)
    }

    private var dateRange: String {
        guard let start = event.startDate else { return "TBD" }
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        if let end = event.endDate, !Calendar.current.isDate(start, inSameDayAs: end) {
            return "\(f.string(from: start))–\(DateFormatter().apply { $0.dateFormat = "MMM d" }.string(from: end))"
        }
        return f.string(from: start)
    }

    var body: some View {
        HStack(alignment: .center, spacing: 0) {
            // Thumbnail
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color(
                        hue: Double((event.sourceEventId.unicodeScalars.first?.value ?? 200) % 360) / 360.0,
                        saturation: 0.35,
                        brightness: 0.38
                    ))
                    .frame(width: 60, height: 60)

                Text(event.displayName.prefix(2).uppercased())
                    .font(.system(size: 18, weight: .black, design: .rounded))
                    .foregroundColor(.white.opacity(0.85))
            }
            .padding(.leading, 6)
            .padding(.vertical, 8)

            // Info
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    if let club = event.clubName {
                        Text(club)
                            .font(.system(size: 10.5, weight: .semibold))
                            .foregroundColor(.tellTextMute)
                            .lineLimit(1)
                    }
                }

                Text(event.displayName)
                    .font(.system(size: 15.5, weight: .black))
                    .foregroundColor(.tellText)
                    .lineLimit(1)
                    .tracking(-0.2)

                HStack(spacing: 10) {
                    Label(dateRange, systemImage: "calendar")
                    if let loc = event.location {
                        Label(loc, systemImage: "location")
                            .lineLimit(1)
                    }
                }
                .font(.system(size: 11.5))
                .foregroundColor(.tellTextDim)
                .labelStyle(CompactLabelStyle())
            }
            .padding(.leading, 12)
            .padding(.trailing, 14)
            .padding(.vertical, 10)

            Spacer()
        }
        .glassCard(railColor: tellRailColor(for: event.status))
        .padding(.horizontal, 16)
    }
}

// MARK: - Compact Label Style

struct CompactLabelStyle: LabelStyle {

    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 4) {
            configuration.icon.imageScale(.small)
            configuration.title
        }
    }
}

// MARK: - Section Header

struct TellSectionHeader: View {
    let title: String
    var subtitle: String? = nil
    var action: String? = nil
    var onAction: (() -> Void)? = nil

    var body: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.tellText)
                if let sub = subtitle {
                    Text(sub)
                        .font(.system(size: 12))
                        .foregroundColor(.tellTextMute)
                }
            }
            Spacer()
            if let action, let handler = onAction {
                Button(action: handler) {
                    Text(action)
                        .font(.system(size: 11.5, weight: .bold))
                        .tracking(0.5)
                        .textCase(.uppercase)
                        .foregroundColor(.tellAccent)
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
    }
}

// MARK: - Top Bar

struct TellTopBar: View {
    var subtitle: String = ""
    var title: String
    var transparent: Bool = false

    var body: some View {
        GlassStrip(dark: true) {
            VStack(spacing: 0) {
                Spacer().frame(height: 56) // status bar clearance
                HStack {
                    VStack(alignment: .leading, spacing: 1) {
                        if !subtitle.isEmpty {
                            Text(subtitle.uppercased())
                                .font(.system(size: 10, weight: .black))
                                .tracking(1.2)
                                .foregroundColor(.tellTextMute)
                        }
                        Text(title)
                            .font(.system(size: 24, weight: .black))
                            .tracking(-0.5)
                            .foregroundColor(.tellText)
                    }
                    Spacer()
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 12)
            }
        }
    }
}

// MARK: - DateFormatter helper

extension DateFormatter {
    func apply(_ config: (DateFormatter) -> Void) -> DateFormatter {
        config(self)
        return self
    }
}

#Preview {
    VStack {
        Text("Hello")
            .foregroundStyle(Color(.black))
            .padding()
    }
    .glassCard(radius: 12, tint: .glassTint, railColor: .tellCool, railWidth: 26, gradOn: true)
}
//
//func glassCard(
//    radius: CGFloat = 14,
//    tint: Color = .glassTint,
//    borderColor: Color = .glassBorder,
//    railColor: Color? = nil
//) -> some View {
//    modifier(GlassCardModifier(radius: radius, tint: tint, borderColor: borderColor, railColor: railColor))
//}
