import SwiftUI
#if os(macOS)
import AppKit
#elseif os(iOS)
import UIKit
#endif

// MARK: - AppIconVariant

public enum AppIconVariant: String, CaseIterable, Identifiable {
    case light = "Light"
    case dark = "Dark"
    case tinted = "Tinted"
    case glass = "Glass"
    
    public var id: String { rawValue }
    
    public var displayName: String {
        switch self {
        case .light:
            return "Liquid Light"
        case .dark:
            return "Obsidian Dark"
        case .tinted:
            return "Tinted Slate"
        case .glass:
            return "Liquid Glass"
        }
    }
    
    public var subtitle: String {
        switch self {
        case .light:
            return "Frosted glass base with glowing warm amber Swift bird"
        case .dark:
            return "Deep obsidian tile with molten electric orange luminescence"
        case .tinted:
            return "Monochrome liquid glass silhouette optimized for tinted appearance"
        case .glass:
            return "Ultra-clear fluid glass with caustics, bubbles, and floating emblem"
        }
    }
    
    public var previewImageName: String {
        "AppIcon-Preview-\(rawValue)"
    }
    
    public var assetCatalogName: String? {
        switch self {
        case .light:
            return nil // Default primary icon
        case .dark:
            return "AppIcon-Dark"
        case .tinted:
            return "AppIcon-Tinted"
        case .glass:
            return "AppIcon-Glass"
        }
    }
}

// MARK: - AppIconManager

@MainActor
public final class AppIconManager: ObservableObject {
    public static let shared = AppIconManager()
    
    private let userDefaultsKey = "selectedAppIconVariant"
    
    @Published public private(set) var currentVariant: AppIconVariant
    
    private init() {
        if let saved = UserDefaults.standard.string(forKey: userDefaultsKey),
           let variant = AppIconVariant(rawValue: saved) {
            self.currentVariant = variant
        } else {
            self.currentVariant = .light
        }
        
        // Apply on launch
        applyIcon(variant: self.currentVariant)
    }
    
    public func setVariant(_ variant: AppIconVariant) {
        currentVariant = variant
        UserDefaults.standard.set(variant.rawValue, forKey: userDefaultsKey)
        applyIcon(variant: variant)
    }
    
    private func applyIcon(variant: AppIconVariant) {
        #if os(macOS)
        if variant == .light {
            // Setting nil restores the default bundle icon
            NSApplication.shared.applicationIconImage = nil
        } else if let image = NSImage(named: variant.previewImageName) {
            NSApplication.shared.applicationIconImage = image
        }
        #elseif os(iOS)
        guard UIApplication.shared.supportsAlternateIcons else { return }
        UIApplication.shared.setAlternateIconName(variant.assetCatalogName) { error in
            if let error = error {
                print("Failed to set alternate icon: \(error.localizedDescription)")
            }
        }
        #endif
    }
}

// MARK: - AppIconPickerView

public struct AppIconPickerView: View {
    @ObservedObject private var iconManager = AppIconManager.shared
    
    public init() {}
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 140, maximum: 180), spacing: 16)], spacing: 16) {
                ForEach(AppIconVariant.allCases) { variant in
                    AppIconCard(
                        variant: variant,
                        isSelected: iconManager.currentVariant == variant
                    ) {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                            iconManager.setVariant(variant)
                        }
                    }
                }
            }
        }
    }
}

private struct AppIconCard: View {
    let variant: AppIconVariant
    let isSelected: Bool
    let onSelect: () -> Void
    
    @State private var isHovering = false
    
    var body: some View {
        Button(action: onSelect) {
            VStack(spacing: 10) {
                ZStack(alignment: .topTrailing) {
                    Image(variant.previewImageName)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 80, height: 80)
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .shadow(color: Color.black.opacity(isHovering ? 0.25 : 0.15), radius: isHovering ? 8 : 4, y: isHovering ? 5 : 2)
                    
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.white, Color.orange)
                            .font(.system(size: 20, weight: .bold))
                            .offset(x: 6, y: -6)
                            .transition(.scale.combined(with: .opacity))
                    }
                }
                .padding(.top, 8)
                
                VStack(spacing: 2) {
                    Text(variant.displayName)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(isSelected ? Color.orange : Color.primary)
                    
                    Text(variant.rawValue)
                        .font(.system(size: 11))
                        .foregroundStyle(Color.secondary)
                }
                .padding(.bottom, 8)
            }
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(isSelected ? Color.orange.opacity(0.1) : (isHovering ? Color.primary.opacity(0.04) : Color.clear))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(isSelected ? Color.orange : (isHovering ? Color.primary.opacity(0.12) : Color.clear), lineWidth: 1.5)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .scaleEffect(isHovering ? 1.02 : 1.0)
        .animation(.easeOut(duration: 0.15), value: isHovering)
    }
}
