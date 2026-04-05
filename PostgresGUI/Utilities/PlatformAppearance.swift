//
//  PlatformAppearance.swift
//  PostgresGUI
//
//  Compatibility helpers for newer macOS visual styles.
//

import SwiftUI

struct PlatformGlassProminentButtonStyleModifier: ViewModifier {
    func body(content: Content) -> some View {
        content.buttonStyle(.borderedProminent)
    }
}

struct PlatformGlassEffectModifier<ClipShape: Shape>: ViewModifier {
    let clipShape: ClipShape

    func body(content: Content) -> some View {
        content
            .background(.regularMaterial, in: clipShape)
            .clipShape(clipShape)
            .overlay(
                clipShape.stroke(Color.secondary.opacity(0.18), lineWidth: 0.5)
            )
    }
}

extension View {
    func platformGlassProminentButtonStyle() -> some View {
        modifier(PlatformGlassProminentButtonStyleModifier())
    }

    func platformGlassEffect<ClipShape: Shape>(_ clipShape: ClipShape) -> some View {
        modifier(PlatformGlassEffectModifier(clipShape: clipShape))
    }
}
