import SwiftUI
import UIKit

/// The app's visual language: quiet infrastructure surfaces with provider color
/// reserved for identity and state, rather than decorative gradients.
///
/// This file is intentionally small so a widget extension can share the same
/// tokens without compiling `ProviderVisuals.swift`.
enum AppTheme {
    private static func adaptive(light: UIColor, dark: UIColor) -> Color {
        Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark ? dark : light
        })
    }

    static let canvas = adaptive(
        light: UIColor(red: 0.955, green: 0.966, blue: 0.982, alpha: 1),
        dark: UIColor(red: 0.018, green: 0.022, blue: 0.030, alpha: 1)
    )
    static let surface = adaptive(
        light: UIColor(red: 0.995, green: 0.998, blue: 1.0, alpha: 1),
        dark: UIColor(red: 0.060, green: 0.070, blue: 0.090, alpha: 1)
    )
    static let surfaceRaised = adaptive(
        light: UIColor(red: 0.918, green: 0.935, blue: 0.961, alpha: 1),
        dark: UIColor(red: 0.082, green: 0.092, blue: 0.115, alpha: 1)
    )
    static let textPrimary = adaptive(
        light: UIColor(red: 0.070, green: 0.090, blue: 0.125, alpha: 1),
        dark: UIColor(red: 0.94, green: 0.95, blue: 0.97, alpha: 1)
    )
    static let textSecondary = adaptive(
        light: UIColor(red: 0.33, green: 0.37, blue: 0.44, alpha: 1),
        dark: UIColor(red: 0.64, green: 0.67, blue: 0.73, alpha: 1)
    )
    static let textTertiary = adaptive(
        light: UIColor(red: 0.49, green: 0.53, blue: 0.60, alpha: 1),
        dark: UIColor(red: 0.44, green: 0.47, blue: 0.53, alpha: 1)
    )
    static let stroke = adaptive(
        light: UIColor.black.withAlphaComponent(0.095),
        dark: UIColor.white.withAlphaComponent(0.10)
    )
    static let strokeStrong = adaptive(
        light: UIColor.black.withAlphaComponent(0.15),
        dark: UIColor.white.withAlphaComponent(0.14)
    )
    static let strokeSoft = adaptive(
        light: UIColor.black.withAlphaComponent(0.060),
        dark: UIColor.white.withAlphaComponent(0.055)
    )
    static let divider = adaptive(
        light: UIColor.black.withAlphaComponent(0.075),
        dark: UIColor.white.withAlphaComponent(0.065)
    )
    static let signal = adaptive(
        light: UIColor(red: 0.075, green: 0.37, blue: 0.79, alpha: 1),
        dark: UIColor(red: 0.31, green: 0.63, blue: 1.0, alpha: 1)
    )
    static let success = adaptive(
        light: UIColor(red: 0.08, green: 0.49, blue: 0.27, alpha: 1),
        dark: UIColor(red: 0.30, green: 0.79, blue: 0.52, alpha: 1)
    )
    static let warning = adaptive(
        light: UIColor(red: 0.65, green: 0.36, blue: 0.02, alpha: 1),
        dark: UIColor(red: 0.96, green: 0.65, blue: 0.24, alpha: 1)
    )
    static let danger = adaptive(
        light: UIColor(red: 0.73, green: 0.12, blue: 0.17, alpha: 1),
        dark: UIColor(red: 0.96, green: 0.35, blue: 0.38, alpha: 1)
    )
    static let shadow = adaptive(
        light: UIColor.black.withAlphaComponent(0.10),
        dark: UIColor.black.withAlphaComponent(0.24)
    )
    static let shadowSoft = adaptive(
        light: UIColor.black.withAlphaComponent(0.065),
        dark: UIColor.black.withAlphaComponent(0.14)
    )
    static let glassTint = adaptive(
        light: UIColor.white.withAlphaComponent(0.16),
        dark: UIColor.black.withAlphaComponent(0.58)
    )
    static let skeleton = adaptive(
        light: UIColor.black.withAlphaComponent(0.045),
        dark: UIColor.white.withAlphaComponent(0.045)
    )
    static let skeletonStrong = adaptive(
        light: UIColor.black.withAlphaComponent(0.070),
        dark: UIColor.white.withAlphaComponent(0.075)
    )

    static let panelRadius: CGFloat = 16
    static let controlRadius: CGFloat = 13
    static let iconRadius: CGFloat = 10
}
