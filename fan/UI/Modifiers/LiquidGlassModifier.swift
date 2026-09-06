//
//  LiquidGlassModifier.swift
//  ffan
//
//  Native Liquid Glass (macOS 26+) with material fallback styling for
//  macOS 13–15. The glass path is additionally gated behind
//  `#if compiler(>=6.2)` because the glassEffect symbols only exist in
//  the macOS 26 SDK (Xcode 26); older Xcode builds compile the fallback.
//

import SwiftUI

// MARK: - Shared glass surface (native glass on 26, material below)

struct GlassSurfaceModifier: ViewModifier {
    var cornerRadius: CGFloat = 16
    var prominent: Bool = false

    private var fallbackShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
    }

    func body(content: Content) -> some View {
        #if compiler(>=6.2)
        if #available(macOS 26.0, *) {
            content
                .glassEffect(
                    prominent
                        ? .regular.tint(.white.opacity(0.08)).interactive()
                        : .regular.interactive(),
                    in: .rect(cornerRadius: cornerRadius)
                )
        } else {
            content
                .materialSurface(shape: fallbackShape, prominent: prominent)
        }
        #else
        content
            .materialSurface(shape: fallbackShape, prominent: prominent)
        #endif
    }
}

// MARK: - Adaptive button styles (glass on 26, bordered below)

extension View {
    /// `.glass` / `.glassProminent` on macOS 26+, bordered equivalents below.
    @ViewBuilder
    func adaptiveGlassButtonStyle(prominent: Bool = false) -> some View {
        #if compiler(>=6.2)
        if #available(macOS 26.0, *) {
            if prominent {
                self.buttonStyle(.glassProminent)
            } else {
                self.buttonStyle(.glass)
            }
        } else if prominent {
            self.buttonStyle(.borderedProminent)
        } else {
            self.buttonStyle(.bordered)
        }
        #else
        if prominent {
            self.buttonStyle(.borderedProminent)
        } else {
            self.buttonStyle(.bordered)
        }
        #endif
    }
}

extension View {
    /// Material-based stand-in for Liquid Glass on macOS 13–15.
    @ViewBuilder
    func materialSurface(shape: RoundedRectangle, prominent: Bool) -> some View {
        self
            .background(prominent ? .thickMaterial : .ultraThinMaterial, in: shape)
            .overlay {
                shape
                    .strokeBorder(.white.opacity(prominent ? 0.18 : 0.10), lineWidth: 0.5)
            }
            .shadow(color: .black.opacity(0.10), radius: 8, y: 2)
    }
}

// MARK: - Ambient backdrop (gives glass something to refract)

/// Full-bleed animated mesh used behind Liquid Glass panels (showcase pattern).
/// Falls back to an animated gradient below macOS 15 (no MeshGradient).
struct LiquidGlassAmbientBackground: View {
    @State private var phase: CGFloat = 0

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            Group {
                #if compiler(>=6.2)
                if #available(macOS 15.0, *) {
                    MeshGradient(
                        width: 3,
                        height: 3,
                        points: [
                            .init(0, 0), .init(0.5, 0), .init(1, 0),
                            .init(0, 0.5), .init(0.5, 0.5), .init(1, 0.5),
                            .init(0, 1), .init(0.5, 1), .init(1, 1)
                        ],
                        colors: meshColors(time: t)
                    )
                } else {
                    fallbackMesh(time: t)
                }
                #else
                fallbackMesh(time: t)
                #endif
            }
            .ignoresSafeArea()
            .overlay {
                LinearGradient(
                    colors: [
                        Color.black.opacity(0.12),
                        Color.clear,
                        Color.black.opacity(0.18)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()
            }
        }
    }

    private func fallbackMesh(time: TimeInterval) -> some View {
        let colors = meshColors(time: time)
        return ZStack {
            LinearGradient(
                colors: Array(colors.prefix(4)),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            RadialGradient(
                colors: [colors[6].opacity(0.65), Color.clear],
                center: .bottomTrailing,
                startRadius: 10,
                endRadius: 420
            )
        }
    }

    private func meshColors(time: TimeInterval) -> [Color] {
        let s = sin(time * 0.35)
        let c = cos(time * 0.28)
        return [
            Color(hue: 0.58 + s * 0.04, saturation: 0.55, brightness: 0.92),
            Color(hue: 0.62 + c * 0.03, saturation: 0.48, brightness: 0.88),
            Color(hue: 0.72 + s * 0.05, saturation: 0.52, brightness: 0.90),
            Color(hue: 0.55 + c * 0.04, saturation: 0.45, brightness: 0.85),
            Color(hue: 0.60, saturation: 0.38, brightness: 0.78),
            Color(hue: 0.68 + s * 0.03, saturation: 0.50, brightness: 0.86),
            Color(hue: 0.52 + c * 0.02, saturation: 0.42, brightness: 0.82),
            Color(hue: 0.64 + s * 0.04, saturation: 0.46, brightness: 0.84),
            Color(hue: 0.70 + c * 0.03, saturation: 0.44, brightness: 0.80)
        ]
    }
}

// MARK: - Panel wrapper

struct LiquidGlassPanel<Content: View>: View {
    var cornerRadius: CGFloat = 20
    var prominent: Bool = false
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .modifier(GlassSurfaceModifier(cornerRadius: cornerRadius, prominent: prominent))
    }
}

// MARK: - Legacy modifier (routes to native glass on macOS 26)

struct LiquidGlassModifier: ViewModifier {
    var cornerRadius: CGFloat = 16
    var prominent: Bool = false

    func body(content: Content) -> some View {
        content
            .modifier(GlassSurfaceModifier(cornerRadius: cornerRadius, prominent: prominent))
    }
}

extension View {
    /// Applies Apple's Liquid Glass material in a rounded rect (material fallback below macOS 26).
    func liquidGlass(cornerRadius: CGFloat = 16, prominent: Bool = false) -> some View {
        modifier(LiquidGlassModifier(cornerRadius: cornerRadius, prominent: prominent))
    }
}
