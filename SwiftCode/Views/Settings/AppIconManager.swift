import SwiftUI
#if os(macOS)
import AppKit
#elseif os(iOS)
import UIKit
#endif

// MARK: - AppIconCategory

public enum AppIconCategory: String, CaseIterable, Identifiable {
    case all = "All"
    case official = "Official"
    case nostalgia = "Nostalgia"
    case codeSymbols = "Code & Symbols"
    case themes = "Themes"
    case materials = "Materials"
    
    public var id: String { rawValue }
    
    public var iconName: String {
        switch self {
        case .all: return "square.grid.2x2.fill"
        case .official: return "sparkles"
        case .nostalgia: return "clock.arrow.circlepath"
        case .codeSymbols: return "curlybraces"
        case .themes: return "paintpalette.fill"
        case .materials: return "shield.fill"
        }
    }
}

// MARK: - AppIconVariant

public enum AppIconVariant: String, CaseIterable, Identifiable {
    // Official Liquid Glass Family
    case light = "Light"
    case dark = "Dark"
    case glass = "Glass"
    case tinted = "Tinted"
    
    // Nostalgia & Heritage
    case retroMac = "RetroMac"
    case aqua2001 = "Aqua2001"
    case nextstep = "NeXTSTEP"
    case crtGreen = "CRTGreen"
    case crtAmber = "CRTAmber"
    case synthwave = "Synthwave"
    case blueprint = "Blueprint"
    case floppyRetro = "FloppyRetro"
    
    // Developer & Coding Symbols
    case codeBraces = "CodeBraces"
    case terminalCli = "TerminalCli"
    case markupTag = "MarkupTag"
    case lambdaClosure = "LambdaClosure"
    case siliconChip = "SiliconChip"
    case bugHunter = "BugHunter"
    case gitBranch = "GitBranch"
    case compilerTurbo = "CompilerTurbo"
    
    // Syntax & Themes
    case cyberpunk = "Cyberpunk"
    case matrixRain = "MatrixRain"
    case dracula = "Dracula"
    case monokai = "Monokai"
    case solarized = "Solarized"
    case midnightPurple = "MidnightPurple"
    
    // Luxury Materials & Atmosphere
    case pureGold = "PureGold"
    case titanium = "Titanium"
    case emerald = "Emerald"
    case oceanAbyss = "OceanAbyss"
    
    public var id: String { rawValue }
    
    public var category: AppIconCategory {
        switch self {
        case .light, .dark, .glass, .tinted:
            return .official
        case .retroMac, .aqua2001, .nextstep, .crtGreen, .crtAmber, .synthwave, .blueprint, .floppyRetro:
            return .nostalgia
        case .codeBraces, .terminalCli, .markupTag, .lambdaClosure, .siliconChip, .bugHunter, .gitBranch, .compilerTurbo:
            return .codeSymbols
        case .cyberpunk, .matrixRain, .dracula, .monokai, .solarized, .midnightPurple:
            return .themes
        case .pureGold, .titanium, .emerald, .oceanAbyss:
            return .materials
        }
    }
    
    public var displayName: String {
        switch self {
        case .light: return "Liquid Light"
        case .dark: return "Obsidian Dark"
        case .glass: return "Pure Liquid Glass"
        case .tinted: return "Tinted Slate"
        case .retroMac: return "System 7 (1991)"
        case .aqua2001: return "Aqua Cheetah (2001)"
        case .nextstep: return "NeXTSTEP (1989)"
        case .crtGreen: return "Phosphor Green CRT"
        case .crtAmber: return "Amber VT220 Terminal"
        case .synthwave: return "Synthwave 80s"
        case .blueprint: return "Xcode Blueprint"
        case .floppyRetro: return "Floppy Disk 1.44MB"
        case .codeBraces: return "Curly Braces { }"
        case .terminalCli: return "Terminal >_"
        case .markupTag: return "Markup Tag </>"
        case .lambdaClosure: return "Lambda Closure λ"
        case .siliconChip: return "Silicon Processor"
        case .bugHunter: return "Bug Hunter"
        case .gitBranch: return "Git Branch Tree"
        case .compilerTurbo: return "Turbo Compiler ⚡️"
        case .cyberpunk: return "Cyberpunk Neon"
        case .matrixRain: return "Matrix Digital Rain"
        case .dracula: return "Dracula Vampire"
        case .monokai: return "Monokai Pro"
        case .solarized: return "Solarized Dark"
        case .midnightPurple: return "Midnight Violet"
        case .pureGold: return "24K Bullion Gold"
        case .titanium: return "Brushed Titanium"
        case .emerald: return "Emerald Gemstone"
        case .oceanAbyss: return "Ocean Abyss"
        }
    }
    
    public var subtitle: String {
        switch self {
        case .light:
            return "Frosted glass base with glowing warm amber Swift bird (Default)"
        case .dark:
            return "Deep space obsidian tile with molten electric orange luminescence"
        case .glass:
            return "Ultra-clear fluid glass with caustics, bubbles, and floating emblem"
        case .tinted:
            return "Monochrome liquid glass silhouette optimized for tinted appearance"
        case .retroMac:
            return "Classic 1-bit Macintosh with smiling Happy Mac face and floppy slot"
        case .aqua2001:
            return "Early Mac OS X candy gel pill button with brushed metal pinstripes"
        case .nextstep:
            return "Steve Jobs' iconic 1989 black cube with 4-quadrant color accents"
        case .crtGreen:
            return "1982 cathode ray monitor with green P1 phosphor scanlines & prompt"
        case .crtAmber:
            return "DEC VT220 amber monochrome terminal with warm scanlines & cursor"
        case .synthwave:
            return "Outrun 80s neon magenta sunset with perspective wireframe grid"
        case .blueprint:
            return "Architectural drafting blueprint grid with white chalk braces"
        case .floppyRetro:
            return "Classic 3.5\" HD diskette with aluminum shutter & handwritten label"
        case .codeBraces:
            return "Electric purple & neon cyan glowing curly braces with syntax dots"
        case .terminalCli:
            return "Dark developer terminal with macOS traffic lights & electric cyan prompt"
        case .markupTag:
            return "Polished software tag emblem with gradient magenta-to-purple brackets"
        case .lambdaClosure:
            return "Luminous turquoise Greek lambda celebrating Swift functional closures"
        case .siliconChip:
            return "Apple Silicon-style processor die with etched gold circuit bus traces"
        case .bugHunter:
            return "Tactical radar reticle with illuminated neon emerald debug beetle"
        case .gitBranch:
            return "Branch commit graph with illuminated nodes in cyan, green & orange"
        case .compilerTurbo:
            return "High-voltage lightning bolt with hazard chevrons for rapid compilation"
        case .cyberpunk:
            return "Matte carbon tile with dual neon cyan and hot magenta laser tubes"
        case .matrixRain:
            return "Pitch black canvas with cascading green digital rain streams"
        case .dracula:
            return "Vampire dark slate with soft lilac, hot pink and spring green tokens"
        case .monokai:
            return "Charcoal background with signature coral, sunny yellow & lime syntax"
        case .solarized:
            return "Ethan Schoonover's precision solarized base03 with cyan & orange"
        case .midnightPurple:
            return "Galactic violet nebula gradient with glowing ultraviolet Swift bird"
        case .pureGold:
            return "24K bullion gold plate with chamfered bevels & debossed Swift seal"
        case .titanium:
            return "Aerospace titanium with circular machining texture & laser engraving"
        case .emerald:
            return "Imperial Colombian emerald gemstone with faceted crystalline reflections"
        case .oceanAbyss:
            return "Deep midnight oceanic navy with bioluminescent turquoise caustics"
        }
    }
    
    public var badgeSymbol: String? {
        switch self {
        case .codeBraces: return "{ }"
        case .terminalCli, .crtGreen: return ">_"
        case .markupTag: return "</>"
        case .lambdaClosure: return "λ"
        case .crtAmber: return "$"
        case .compilerTurbo: return "⚡️"
        default: return nil
        }
    }
    
    public var previewImageName: String {
        "AppIcon-Preview-\(rawValue)"
    }
    
    public var assetCatalogName: String? {
        switch self {
        case .light:
            return nil // Default primary icon
        default:
            return "AppIcon-\(rawValue)"
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
            // Reverting to default bundle icon
            NSApplication.shared.applicationIconImage = nil
            // If Dock doesn't populate default image (e.g. running from build directory), fallback to explicit light icon image
            if NSApplication.shared.applicationIconImage == nil,
               let image = NSImage(named: variant.previewImageName) {
                NSApplication.shared.applicationIconImage = image
            }
        } else if let image = NSImage(named: variant.previewImageName) {
            NSApplication.shared.applicationIconImage = image
        }
        // Force the macOS Dock tile to immediately redraw
        NSApp.dockTile.display()
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
    @State private var selectedCategory: AppIconCategory = .all
    @State private var searchText = ""
    
    public init() {}
    
    private var filteredVariants: [AppIconVariant] {
        AppIconVariant.allCases.filter { variant in
            let matchesCategory = (selectedCategory == .all || variant.category == selectedCategory)
            if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return matchesCategory
            }
            let query = searchText.lowercased()
            let matchesText = variant.displayName.lowercased().contains(query) ||
                variant.subtitle.lowercased().contains(query) ||
                variant.category.rawValue.lowercased().contains(query)
            return matchesCategory && matchesText
        }
    }
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            // Active Hero Banner
            heroActiveBanner
            
            // Filter Bar & Search
            filterAndSearchBar
            
            // Grid of Icons
            if filteredVariants.isEmpty {
                emptySearchResultsView
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 145, maximum: 175), spacing: 16)], spacing: 16) {
                    ForEach(filteredVariants) { variant in
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
    
    // MARK: - Hero Active Banner
    
    private var heroActiveBanner: some View {
        HStack(spacing: 16) {
            // Icon thumbnail
            Group {
                #if os(macOS)
                if let nsImg = NSImage(named: iconManager.currentVariant.previewImageName) {
                    Image(nsImage: nsImg)
                        .resizable()
                } else {
                    Image(iconManager.currentVariant.previewImageName)
                        .resizable()
                }
                #else
                Image(iconManager.currentVariant.previewImageName)
                    .resizable()
                #endif
            }
            .aspectRatio(contentMode: .fit)
            .frame(width: 76, height: 76)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .shadow(color: Color.black.opacity(0.25), radius: 10, y: 5)
            
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(iconManager.currentVariant.displayName)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(Color.primary)
                    
                    Text(iconManager.currentVariant.category.rawValue)
                        .font(.system(size: 11, weight: .semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Color.orange.opacity(0.15)))
                        .foregroundStyle(Color.orange)
                }
                
                Text(iconManager.currentVariant.subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(Color.secondary)
                    .lineLimit(2)
                
                HStack(spacing: 6) {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 7, height: 7)
                    Text("Currently Active on macOS Dock")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color.secondary)
                }
                .padding(.top, 2)
            }
            
            Spacer()
            
            if iconManager.currentVariant != .light {
                Button("Reset to Default") {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                        iconManager.setVariant(.light)
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.primary.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }
    
    // MARK: - Filter and Search Bar
    
    private var filterAndSearchBar: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Search field
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                    .font(.system(size: 13))
                
                TextField("Search icons by name, theme, or symbol...", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                            .font(.system(size: 13))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.primary.opacity(0.05)))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(Color.primary.opacity(0.08), lineWidth: 1))
            
            // Category filter pills
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(AppIconCategory.allCases) { category in
                        let count = category == .all ? AppIconVariant.allCases.count : AppIconVariant.allCases.filter { $0.category == category }.count
                        let isSelected = selectedCategory == category
                        
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                selectedCategory = category
                            }
                        } label: {
                            HStack(spacing: 5) {
                                Image(systemName: category.iconName)
                                    .font(.system(size: 11))
                                Text(category.rawValue)
                                    .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                                Text("(\(count))")
                                    .font(.system(size: 10))
                                    .opacity(0.7)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(
                                Capsule()
                                    .fill(isSelected ? Color.orange : Color.primary.opacity(0.06))
                            )
                            .foregroundStyle(isSelected ? Color.white : Color.primary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }
    
    // MARK: - Empty State
    
    private var emptySearchResultsView: some View {
        VStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 32))
                .foregroundStyle(Color.secondary)
                .padding(.top, 20)
            
            Text("No icons match \"\(searchText)\"")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.secondary)
            
            Button("Clear Search Filter") {
                searchText = ""
                selectedCategory = .all
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .padding(.bottom, 20)
        }
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.primary.opacity(0.02))
        )
    }
}

// MARK: - AppIconCard

private struct AppIconCard: View {
    let variant: AppIconVariant
    let isSelected: Bool
    let onSelect: () -> Void
    
    @State private var isHovering = false
    
    var body: some View {
        Button(action: onSelect) {
            VStack(spacing: 8) {
                ZStack(alignment: .topTrailing) {
                    Group {
                        #if os(macOS)
                        if let nsImg = NSImage(named: variant.previewImageName) {
                            Image(nsImage: nsImg)
                                .resizable()
                        } else {
                            Image(variant.previewImageName)
                                .resizable()
                        }
                        #else
                        Image(variant.previewImageName)
                            .resizable()
                        #endif
                    }
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 80, height: 80)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .shadow(
                        color: Color.black.opacity(isSelected ? 0.35 : (isHovering ? 0.25 : 0.15)),
                        radius: isHovering ? 8 : 4,
                        y: isHovering ? 5 : 2
                    )
                    
                    if let symbol = variant.badgeSymbol {
                        Text(symbol)
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.black.opacity(0.75)))
                            .foregroundStyle(Color.white)
                            .offset(x: -4, y: 58)
                    }
                    
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.white, Color.orange)
                            .font(.system(size: 20, weight: .bold))
                            .offset(x: 6, y: -6)
                            .transition(.scale.combined(with: .opacity))
                    }
                }
                .padding(.top, 10)
                
                VStack(spacing: 2) {
                    Text(variant.displayName)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(isSelected ? Color.orange : Color.primary)
                        .multilineTextAlignment(.center)
                        .lineLimit(1)
                    
                    Text(variant.category.rawValue)
                        .font(.system(size: 10))
                        .foregroundStyle(Color.secondary)
                }
                .padding(.horizontal, 6)
                .padding(.bottom, 10)
            }
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(isSelected ? Color.orange.opacity(0.12) : (isHovering ? Color.primary.opacity(0.05) : Color.primary.opacity(0.02)))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(isSelected ? Color.orange : (isHovering ? Color.primary.opacity(0.18) : Color.primary.opacity(0.06)), lineWidth: isSelected ? 2 : 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .scaleEffect(isHovering ? 1.025 : 1.0)
        .animation(.easeOut(duration: 0.15), value: isHovering)
    }
}
