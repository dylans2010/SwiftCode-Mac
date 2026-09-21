import SwiftUI
import AppKit

// MARK: - Interactive Sound Picker with Hover-to-Play

@MainActor
public struct SoundPickerView: View {
    public let title: String
    public let category: AppSoundCategory
    @Binding public var selection: String

    @ObservedObject private var soundManager = SoundManager.shared
    @State private var isPopoverPresented = false
    @State private var searchText = ""
    @State private var selectedFilter: FilterTab = .recommended
    @State private var hoveredSoundID: String? = nil

    private enum FilterTab: String, CaseIterable, Identifiable {
        case recommended = "Recommended"
        case cinematic   = "Cinematic"
        case system      = "System"
        case all         = "All"

        var id: String { rawValue }
    }

    public init(
        title: String,
        category: AppSoundCategory,
        selection: Binding<String>
    ) {
        self.title = title
        self.category = category
        self._selection = selection
    }

    private var currentSound: AppSound? {
        SoundCatalog.sound(for: selection)
    }

    public var body: some View {
        Button {
            isPopoverPresented.toggle()
        } label: {
            HStack(spacing: 8) {
                if let sound = currentSound {
                    Image(systemName: sound.source == .system ? "apple.logo" : (sound.source == .custom ? "sparkles" : "person.crop.circle"))
                        .font(.caption2.bold())
                        .foregroundStyle(Color(hex: sound.source.badgeColorHex))

                    Text(sound.displayName)
                        .font(.body)
                        .lineLimit(1)

                    Text(sound.source.rawValue)
                        .font(.system(size: 9, weight: .bold))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1.5)
                        .background(Capsule().fill(Color(hex: sound.source.badgeColorHex).opacity(0.15)))
                        .foregroundStyle(Color(hex: sound.source.badgeColorHex))
                } else if selection == SoundCatalog.noneSoundID {
                    Image(systemName: "speaker.slash.fill")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text("None (Silent)")
                        .font(.body)
                        .foregroundStyle(.secondary)
                } else {
                    Text(selection)
                        .font(.body)
                }

                Spacer()

                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .frame(minWidth: 200, maxWidth: 260)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color(NSColor.controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(Color(NSColor.separatorColor), lineWidth: 0.8)
            )
        }
        .buttonStyle(.plain)
        .popover(isPresented: $isPopoverPresented, arrowEdge: .bottom) {
            popoverContent
        }
    }

    // MARK: - Popover Content

    private var popoverContent: some View {
        VStack(spacing: 0) {
            // Header: Search & Filter Tabs
            VStack(spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                    TextField("Search sounds...", text: $searchText)
                        .textFieldStyle(.plain)
                        .font(.subheadline)
                    if !searchText.isEmpty {
                        Button {
                            searchText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                                .font(.caption)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(7)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color(NSColor.controlBackgroundColor))
                )

                // Filter Pills
                if searchText.isEmpty {
                    Picker("", selection: $selectedFilter) {
                        ForEach(FilterTab.allCases) { tab in
                            Text(tab.rawValue).tag(tab)
                        }
                    }
                    .pickerStyle(.segmented)
                    .controlSize(.small)
                }
            }
            .padding(10)
            .background(Color(NSColor.windowBackgroundColor))

            Divider()

            // Sound Items List
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    if !searchText.isEmpty {
                        let matching = SoundCatalog.filteredSounds(query: searchText)
                        if matching.isEmpty {
                            VStack(spacing: 6) {
                                Image(systemName: "speaker.slash")
                                    .font(.title2)
                                    .foregroundStyle(.secondary)
                                Text("No matching sounds")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 30)
                        } else {
                            ForEach(matching) { sound in
                                soundPopoverRow(sound)
                            }
                        }
                    } else {
                        switch selectedFilter {
                        case .recommended:
                            let recs = SoundCatalog.sounds(for: category)
                            if !recs.isEmpty {
                                sectionHeader("Recommended for \(category.rawValue)")
                                ForEach(recs) { sound in
                                    soundPopoverRow(sound)
                                }
                            }
                            let others = SoundCatalog.customSounds.filter { !recs.contains($0) }
                            if !others.isEmpty {
                                sectionHeader("Other Cinematic App Sounds")
                                ForEach(others) { sound in
                                    soundPopoverRow(sound)
                                }
                            }

                        case .cinematic:
                            sectionHeader("All 32 Cinematic App Sounds")
                            ForEach(SoundCatalog.customSounds) { sound in
                                soundPopoverRow(sound)
                            }

                        case .system:
                            sectionHeader("Native macOS System Sounds (\(SoundCatalog.systemSounds.count))")
                            ForEach(SoundCatalog.systemSounds) { sound in
                                soundPopoverRow(sound)
                            }

                        case .all:
                            let userSounds = SoundCatalog.discoverUserSounds()
                            sectionHeader("Cinematic App Sounds (\(SoundCatalog.customSounds.count))")
                            ForEach(SoundCatalog.customSounds) { sound in
                                soundPopoverRow(sound)
                            }
                            sectionHeader("Native System Sounds (\(SoundCatalog.systemSounds.count))")
                            ForEach(SoundCatalog.systemSounds) { sound in
                                soundPopoverRow(sound)
                            }
                            if !userSounds.isEmpty {
                                sectionHeader("User Installed Sounds (\(userSounds.count))")
                                ForEach(userSounds) { sound in
                                    soundPopoverRow(sound)
                                }
                            }
                        }
                    }

                    Divider()
                        .padding(.vertical, 4)

                    // Silent / None Option
                    noneOptionRow
                }
                .padding(6)
            }
            .frame(maxHeight: 320)

            Divider()

            // Footer info
            HStack {
                Image(systemName: "cursorarrow.rays")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text("Hover over any sound to preview instantly")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color(NSColor.windowBackgroundColor))
        }
        .frame(width: 330)
        .onDisappear {
            hoveredSoundID = nil
        }
    }

    private func sectionHeader(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
            .padding(.horizontal, 8)
            .padding(.top, 6)
            .padding(.bottom, 2)
    }

    @ViewBuilder
    private func soundPopoverRow(_ sound: AppSound) -> some View {
        let isSelected = selection == sound.id
        let isPlaying = soundManager.currentlyPlayingSoundID == sound.id
        let isHovered = hoveredSoundID == sound.id

        Button {
            selection = sound.id
            isPopoverPresented = false
        } label: {
            HStack(spacing: 8) {
                // Source icon
                Image(systemName: sound.source == .system ? "apple.logo" : (sound.source == .custom ? "sparkles" : "person.crop.circle"))
                    .font(.caption2)
                    .foregroundStyle(Color(hex: sound.source.badgeColorHex))
                    .frame(width: 14)

                // Sound display name
                Text(sound.displayName)
                    .font(.subheadline)
                    .foregroundStyle(isSelected ? Color.accentColor : Color.primary)
                    .lineLimit(1)

                if let cat = sound.category {
                    Text(cat.rawValue)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                // Playing animation indicator
                if isPlaying {
                    HStack(spacing: 2) {
                        Image(systemName: "speaker.wave.2.fill")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    }
                }

                // Selected Checkmark
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.caption.bold())
                        .foregroundStyle(Color.accentColor)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(isHovered ? Color.accentColor.opacity(0.12) : (isSelected ? Color.accentColor.opacity(0.06) : Color.clear))
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            if hovering {
                hoveredSoundID = sound.id
                // Instant hover-to-play with 80ms debounce
                soundManager.previewOnHover(soundID: sound.id, delay: 0.08)
            } else if hoveredSoundID == sound.id {
                hoveredSoundID = nil
            }
        }
    }

    private var noneOptionRow: some View {
        let isSelected = selection == SoundCatalog.noneSoundID
        let isHovered = hoveredSoundID == SoundCatalog.noneSoundID

        return Button {
            selection = SoundCatalog.noneSoundID
            soundManager.stopAll()
            isPopoverPresented = false
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "speaker.slash.fill")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(width: 14)

                Text("None (Silent)")
                    .font(.subheadline)
                    .foregroundStyle(isSelected ? Color.accentColor : Color.primary)

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.caption.bold())
                        .foregroundStyle(Color.accentColor)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(isHovered ? Color.accentColor.opacity(0.12) : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            if hovering {
                hoveredSoundID = SoundCatalog.noneSoundID
                soundManager.stopAll()
            } else if hoveredSoundID == SoundCatalog.noneSoundID {
                hoveredSoundID = nil
            }
        }
    }
}
