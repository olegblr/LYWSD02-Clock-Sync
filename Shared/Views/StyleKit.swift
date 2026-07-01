//  StyleKit.swift
//  Shared styling utilities for LYWSD02 Clock Sync
//  Centralizes glass backgrounds, gradients, layout helpers.

import SwiftUI

struct AppDynamicBackground: View {
    @Environment(\.colorScheme) private var colorScheme
    var body: some View {
        LinearGradient(colors: gradientColors, startPoint: .topLeading, endPoint: .bottomTrailing)
            .overlay(Color.black.opacity(colorScheme == .dark ? 0.35 : 0.05))
            .ignoresSafeArea()
    }
    private var gradientColors: [Color] {
        if colorScheme == .dark {
            return [Color(red:0.10, green:0.12, blue:0.16), Color(red:0.05, green:0.06, blue:0.08)]
        } else {
            return [Color(red:0.94, green:0.96, blue:1.0), Color(red:0.88, green:0.92, blue:1.0)]
        }
    }
}

extension View {
    func glassBackground(cornerRadius: CGFloat = 36, strokeOpacity: Double = 0.15) -> some View {
        self
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).stroke(Color.white.opacity(strokeOpacity), lineWidth: 0.7))
            .shadow(color: Color.black.opacity(0.15), radius: 18, x: 0, y: 8)
    }
    func flexPriority() -> some View { self.layoutPriority(1) }
    func centeredInScroll() -> some View { self.frame(maxWidth: .infinity) }
}
