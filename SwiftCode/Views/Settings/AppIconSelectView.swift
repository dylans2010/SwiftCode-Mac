import SwiftUI
#if os(macOS)
import AppKit
#elseif os(iOS)
import UIKit
#endif

// MARK: - AppIconSelectView

public struct AppIconSelectView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var iconManager = AppIconManager.shared
    
    @State private var hoveredVariant: AppIconVariant?
    @State private var selectedCategory: AppIconCategory = .all
    @State private var searchText = ""
    @State private var previewTab: PreviewMode = .split
    @State private var selectedWallpaper: DockWallpaper = .sonoma
    
    public init() {}
    
    public enum PreviewMode: String, CaseIterable, Identifiable {
        case split = "Side-by-Side"
        case dock = "macOS Dock"
        case welcome = "Welcome View"
        
        public var id: String { rawValue }
        public var iconName: String {
            switch self {
            case .split: return "rectangle.split.2x1"
            case .dock: return "dock.rectangle"
            case .welcome: return "macwindow"
            }
        }
    }
    
    public enum DockWallpaper: String, CaseIterable, Identifiable {
        case sonoma = "Sonoma Sunset"
        case sequoia = "Sequoia Twilight"
        case cosmic = "Cosmic Deep"
        case silver = "Studio Silver"
        
        public var id: String { rawValue }
        
        public var gradientColors: [Color] {
            switch self {
            case .sonoma:
                return [Color(hex: 0xFD5E53), Color(hex: 0x9B51E0), Color(hex: 0x3B82F6)]
            case .sequoia:
                return [Color(hex: 0x1E1B4B), Color(hex: 0x312E81), Color(hex: 0x0F172A)]
            case .cosmic:
                return [Color(hex: 0x0A0A1A), Color(hex: 0x1A103C), Color(hex: 0x050510)]
            case .silver:
                return [Color(hex: 0xE2E8F0), Color(hex: 0xCBD5E1), Color(hex: 0x94A3B8)]
            }
        }
    }
    
    // Active variant to preview (hovered icon takes precedence for instant feedback)
    private var previewVariant: AppIconVariant {
        hoveredVariant ?? iconManager.currentVariant
    }
    
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
        VStack(spacing: 0) {
            // Header Bar
            headerBar
            
            Divider()
            
            ScrollView(.vertical, showsIndicators: true) {
                VStack(spacing: 24) {
                    // Live Previews Container (Dock & Welcome Window Replica)
                    livePreviewsSection
                    
                    // macOS 26+ Appearance Configuration (for Default icon)
                    appearanceAdaptationCard
                    
                    // Icon Gallery Section
                    iconGallerySection
                }
                .padding(24)
            }
        }
        .frame(minWidth: 880, idealWidth: 960, minHeight: 640, idealHeight: 740)
        .background(Color(NSColor.windowBackgroundColor))
    }
    
    // MARK: - Header Bar
    
    private var headerBar: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Image(systemName: "app.gift.fill")
                        .font(.title2)
                        .foregroundStyle(Color.orange)
                    Text("App Icon Customizer")
                        .font(.title2.bold())
                }
                Text("Choose from \(AppIconVariant.allCases.count) handcrafted icons with macOS Sequoia & 26+ appearance treatments")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            // Preview Mode Switcher
            Picker("Preview View", selection: $previewTab) {
                ForEach(PreviewMode.allCases) { mode in
                    Label(mode.rawValue, systemImage: mode.iconName).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 320)
            
            Button("Done") {
                dismiss()
            }
            .keyboardShortcut(.defaultAction)
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
        .background(.ultraThinMaterial)
    }
    
    // MARK: - Live Previews Section
    
    private var livePreviewsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Live Environment Previews", systemImage: "macwindow.and.cursorarrow")
                    .font(.headline)
                    .foregroundStyle(.primary)
                
                Spacer()
                
                // Wallpaper Picker for realistic Dock backdrop
                if previewTab == .split || previewTab == .dock {
                    HStack(spacing: 6) {
                        Text("Wallpaper:")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        
                        Picker("", selection: $selectedWallpaper) {
                            ForEach(DockWallpaper.allCases) { wp in
                                Text(wp.rawValue).tag(wp)
                            }
                        }
                        .pickerStyle(.menu)
                        .controlSize(.small)
                        .frame(width: 145)
                    }
                }
            }
            
            Group {
                switch previewTab {
                case .split:
                    HStack(spacing: 16) {
                        realisticDockPreviewCard
                            .frame(maxWidth: .infinity)
                        welcomeWindowPreviewCard
                            .frame(maxWidth: .infinity)
                    }
                case .dock:
                    realisticDockPreviewCard
                case .welcome:
                    welcomeWindowPreviewCard
                }
            }
        }
    }
    
    // MARK: - Realistic macOS Dock Preview Card
    
    private var realisticDockPreviewCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("macOS Dock Preview")
                    .font(.subheadline.bold())
                Spacer()
                Text("Simulated Dock Shelf")
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.primary.opacity(0.08)))
                    .foregroundStyle(.secondary)
            }
            
            // Dock Stage with selected wallpaper background
            ZStack(alignment: .bottom) {
                // Desktop Wallpaper Canvas
                LinearGradient(
                    colors: selectedWallpaper.gradientColors,
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .frame(height: 175)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.white.opacity(0.15), lineWidth: 1)
                )
                
                // Frosted Glass Dock Shelf
                HStack(spacing: 14) {
                    // Companion App: Finder
                    dockCompanionApp(name: "Finder", iconSystem: "face.smiling", bgGradient: [Color(hex: 0x38BDF8), Color(hex: 0x0284C7)])
                    
                    // Companion App: Safari
                    dockCompanionApp(name: "Safari", iconSystem: "safari.fill", bgGradient: [Color(hex: 0x60A5FA), Color(hex: 0x2563EB)])
                    
                    // SwiftCode Main App (Active/Hovered Icon)
                    VStack(spacing: 3) {
                        Group {
                            if let nsImg = NSImage(named: iconManager.resolvedPreviewImageName(for: previewVariant)) {
                                Image(nsImage: nsImg)
                                    .resizable()
                            } else {
                                Image(previewVariant.previewImageName)
                                    .resizable()
                            }
                        }
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 52, height: 52)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .shadow(color: Color.black.opacity(0.4), radius: 6, y: 4)
                        .scaleEffect(hoveredVariant != nil ? 1.15 : 1.05)
                        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: hoveredVariant)
                        
                        // Active Application Running White Dot Indicator
                        Circle()
                            .fill(Color.white.opacity(0.9))
                            .frame(width: 4, height: 4)
                            .shadow(color: .white.opacity(0.6), radius: 2)
                    }
                    .help("SwiftCode (\(previewVariant.displayName))")
                    
                    // Companion App: Xcode
                    dockCompanionApp(name: "Xcode", iconSystem: "hammer.fill", bgGradient: [Color(hex: 0x38BDF8), Color(hex: 0x1E40AF)])
                    
                    // Companion App: Terminal
                    dockCompanionApp(name: "Terminal", iconSystem: "terminal.fill", bgGradient: [Color(hex: 0x334155), Color(hex: 0x0F172A)])
                    
                    // Divider
                    Rectangle()
                        .fill(Color.white.opacity(0.2))
                        .frame(width: 1, height: 40)
                        .padding(.horizontal, 2)
                    
                    // Companion App: Trash
                    dockCompanionApp(name: "Trash", iconSystem: "trash.fill", bgGradient: [Color(hex: 0x94A3B8), Color(hex: 0x64748B)])
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(.ultraThinMaterial)
                        .shadow(color: Color.black.opacity(0.35), radius: 16, y: 8)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(Color.white.opacity(0.25), lineWidth: 1)
                )
                .padding(.bottom, 12)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.primary.opacity(0.03))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }
    
    private func dockCompanionApp(name: String, iconSystem: String, bgGradient: [Color]) -> some View {
        VStack(spacing: 3) {
            ZStack {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(LinearGradient(colors: bgGradient, startPoint: .top, endPoint: .bottom))
                    .frame(width: 46, height: 46)
                    .shadow(color: Color.black.opacity(0.25), radius: 4, y: 2)
                
                Image(systemName: iconSystem)
                    .font(.system(size: 24, weight: .medium))
                    .foregroundStyle(.white)
            }
            
            // Spacer to align with running indicator height
            Spacer().frame(height: 4)
        }
        .help(name)
    }
    
    // MARK: - Realistic Welcome Window Preview Card
    
    private var welcomeWindowPreviewCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Welcome View Replica")
                    .font(.subheadline.bold())
                Spacer()
                Text("Simulated App Launch Window")
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.primary.opacity(0.08)))
                    .foregroundStyle(.secondary)
            }
            
            // Miniature Authentic macOS Window
            VStack(spacing: 0) {
                // Window Title Bar
                HStack(spacing: 7) {
                    Circle().fill(Color(hex: 0xED6A5E)).frame(width: 10, height: 10)
                    Circle().fill(Color(hex: 0xF4BF4F)).frame(width: 10, height: 10)
                    Circle().fill(Color(hex: 0x61C554)).frame(width: 10, height: 10)
                    
                    Spacer()
                    Text("SwiftCode — Welcome")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                    Spacer()
                    
                    // Balance space for centering
                    Spacer().frame(width: 42)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.primary.opacity(0.05))
                
                Divider()
                
                // Window Content Split: Recent Projects Sidebar + Hero Welcome Section
                HStack(spacing: 0) {
                    // Mini Left Column: Recent Projects
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Recent Projects")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.secondary)
                            .padding(.bottom, 2)
                        
                        miniProjectRow(name: "SwiftCode.xcodeproj", time: "Just now", icon: "app.badge")
                        miniProjectRow(name: "WeatherKitApp", time: "Yesterday", icon: "cloud.sun.fill")
                        miniProjectRow(name: "SpatialVisionOS", time: "3 days ago", icon: "visionpro")
                        
                        Spacer()
                    }
                    .padding(10)
                    .frame(width: 135)
                    .background(Color.primary.opacity(0.02))
                    
                    Divider()
                    
                    // Mini Right Column: Welcome Hero Area with App Icon
                    VStack(spacing: 8) {
                        Spacer()
                        
                        // Mini Stylized App Icon
                        ZStack {
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(Color.orange.opacity(0.18))
                                .frame(width: 58, height: 58)
                                .blur(radius: 6)
                            
                            Group {
                                if let nsImg = NSImage(named: iconManager.resolvedPreviewImageName(for: previewVariant)) {
                                    Image(nsImage: nsImg)
                                        .resizable()
                                } else {
                                    Image(previewVariant.previewImageName)
                                        .resizable()
                                }
                            }
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 48, height: 48)
                            .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                            .shadow(color: Color.black.opacity(0.3), radius: 6, y: 3)
                        }
                        
                        Text("Welcome to SwiftCode")
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundStyle(Color.orange)
                        
                        Text("The desktop IDE for building and organizing cutting-edge Swift applications natively.")
                            .font(.system(size: 8))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 12)
                            .lineLimit(2)
                        
                        HStack(spacing: 6) {
                            Text("New Project")
                                .font(.system(size: 8, weight: .semibold))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Capsule().fill(Color.orange))
                                .foregroundStyle(.white)
                            
                            Text("Import Folder")
                                .font(.system(size: 8, weight: .semibold))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Capsule().fill(Color.primary.opacity(0.08)))
                                .foregroundStyle(.primary)
                        }
                        
                        Spacer()
                    }
                    .frame(maxWidth: .infinity)
                    .padding(8)
                }
            }
            .frame(height: 175)
            .background(Color(NSColor.controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.primary.opacity(0.12), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.18), radius: 10, y: 6)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.primary.opacity(0.03))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }
    
    private func miniProjectRow(name: String, time: String, icon: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 8))
                .foregroundStyle(Color.orange)
            VStack(alignment: .leading, spacing: 1) {
                Text(name)
                    .font(.system(size: 8, weight: .medium))
                    .lineLimit(1)
                Text(time)
                    .font(.system(size: 7))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 1)
    }
    
    // MARK: - macOS 26+ Appearance Adaptation Card
    
    private var appearanceAdaptationCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("macOS 26+ Dynamic Appearance Adaptation", systemImage: "sparkles")
                    .font(.headline)
                    .foregroundStyle(Color.orange)
                
                Spacer()
                
                Text("Apple HIG Compliant")
                    .font(.caption2.bold())
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Color.orange.opacity(0.12)))
                    .foregroundStyle(Color.orange)
            }
            
            Text("On macOS 26+ and modern macOS releases, Apple enables app icons to automatically adapt to Dark, Tinted, Light, or Clear appearances. Configure how the primary default icon responds to system appearance:")
                .font(.caption)
                .foregroundStyle(.secondary)
            
            HStack(spacing: 12) {
                ForEach(DefaultIconAppearance.allCases) { appearance in
                    let isSelected = iconManager.defaultAppearance == appearance
                    
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                            iconManager.setDefaultAppearance(appearance)
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: appearance.iconSymbol)
                                .font(.system(size: 13))
                            Text(appearance.rawValue)
                                .font(.system(size: 12, weight: isSelected ? .bold : .medium))
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(isSelected ? Color.orange : Color.primary.opacity(0.05))
                        )
                        .foregroundStyle(isSelected ? Color.white : Color.primary)
                    }
                    .buttonStyle(.plain)
                }
            }
            
            Text(iconManager.defaultAppearance.description)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .padding(.top, 2)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.primary.opacity(0.03))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }
    
    // MARK: - Icon Gallery Section
    
    private var iconGallerySection: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Search & Category Filter Bar
            HStack(spacing: 16) {
                // Search Field
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Search icons by name, style, nostalgia, terminal, or symbol...", text: $searchText)
                        .textFieldStyle(.plain)
                    if !searchText.isEmpty {
                        Button { searchText = "" } label: {
                            Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.05)))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.primary.opacity(0.08), lineWidth: 1))
                
                // Active count tag
                Text("\(filteredVariants.count) Icons Available")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
            }
            
            // Category Filter Pills
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
                            HStack(spacing: 6) {
                                Image(systemName: category.iconName)
                                    .font(.system(size: 11))
                                Text(category.rawValue)
                                    .font(.system(size: 12, weight: isSelected ? .bold : .medium))
                                Text("(\(count))")
                                    .font(.system(size: 10))
                                    .opacity(0.7)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(
                                Capsule().fill(isSelected ? Color.orange : Color.primary.opacity(0.06))
                            )
                            .foregroundStyle(isSelected ? Color.white : Color.primary)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            
            // Icon Grid
            if filteredVariants.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 36))
                        .foregroundStyle(.secondary)
                        .padding(.top, 24)
                    Text("No icons match \"\(searchText)\"")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                    Button("Clear Filter") {
                        searchText = ""
                        selectedCategory = .all
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 155, maximum: 185), spacing: 16)], spacing: 16) {
                    ForEach(filteredVariants) { variant in
                        AppIconGalleryCard(
                            variant: variant,
                            isSelected: iconManager.currentVariant == variant,
                            isHovered: hoveredVariant == variant,
                            onHover: { hovering in
                                withAnimation(.easeOut(duration: 0.15)) {
                                    hoveredVariant = hovering ? variant : (hoveredVariant == variant ? nil : hoveredVariant)
                                }
                            },
                            onSelect: {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                                    iconManager.setVariant(variant)
                                }
                            }
                        )
                    }
                }
            }
        }
    }
}

// MARK: - AppIconGalleryCard

private struct AppIconGalleryCard: View {
    let variant: AppIconVariant
    let isSelected: Bool
    let isHovered: Bool
    let onHover: (Bool) -> Void
    let onSelect: () -> Void
    
    var body: some View {
        Button(action: onSelect) {
            VStack(spacing: 8) {
                ZStack(alignment: .topTrailing) {
                    // Artwork Thumbnail
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
                    .frame(width: 86, height: 86)
                    .clipShape(RoundedRectangle(cornerRadius: 19, style: .continuous))
                    .shadow(
                        color: Color.black.opacity(isSelected ? 0.4 : (isHovered ? 0.3 : 0.15)),
                        radius: isHovered ? 10 : 5,
                        y: isHovered ? 6 : 3
                    )
                    
                    // Monospaced badge tag
                    if let symbol = variant.badgeSymbol {
                        Text(symbol)
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.black.opacity(0.8)))
                            .foregroundStyle(Color.white)
                            .offset(x: -4, y: 64)
                    }
                    
                    // Active selection checkmark badge
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.white, Color.orange)
                            .font(.system(size: 22, weight: .bold))
                            .offset(x: 6, y: -6)
                            .transition(.scale.combined(with: .opacity))
                    }
                }
                .padding(.top, 12)
                
                VStack(spacing: 2) {
                    Text(variant.displayName)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(isSelected ? Color.orange : Color.primary)
                        .multilineTextAlignment(.center)
                        .lineLimit(1)
                    
                    Text(variant.category.rawValue)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 6)
                .padding(.bottom, 12)
            }
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(isSelected ? Color.orange.opacity(0.12) : (isHovered ? Color.primary.opacity(0.06) : Color.primary.opacity(0.02)))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(isSelected ? Color.orange : (isHovered ? Color.primary.opacity(0.2) : Color.primary.opacity(0.06)), lineWidth: isSelected ? 2 : 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover(perform: onHover)
        .scaleEffect(isHovered ? 1.03 : 1.0)
        .animation(.easeOut(duration: 0.15), value: isHovered)
    }
}

// MARK: - Color Hex Initializer

private extension Color {
    init(hex: UInt32, alpha: Double = 1.0) {
        let r = Double((hex >> 16) & 0xFF) / 255.0
        let g = Double((hex >> 8) & 0xFF) / 255.0
        let b = Double(hex & 0xFF) / 255.0
        self.init(.sRGB, red: r, green: g, blue: b, opacity: alpha)
    }
}
