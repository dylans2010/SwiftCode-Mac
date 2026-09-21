import SwiftUI
import AppKit

// MARK: - Animated Equalizer Wave Visualizer

@MainActor
private struct AudioEqualizerBars: View {
    @State private var animating = false

    var body: some View {
        HStack(alignment: .bottom, spacing: 2) {
            RoundedRectangle(cornerRadius: 1)
                .fill(Color.accentColor)
                .frame(width: 2.5, height: animating ? 13 : 4)
                .animation(.easeInOut(duration: 0.32).repeatForever(autoreverses: true), value: animating)
            RoundedRectangle(cornerRadius: 1)
                .fill(Color.accentColor)
                .frame(width: 2.5, height: animating ? 5 : 15)
                .animation(.easeInOut(duration: 0.24).repeatForever(autoreverses: true).delay(0.08), value: animating)
            RoundedRectangle(cornerRadius: 1)
                .fill(Color.accentColor)
                .frame(width: 2.5, height: animating ? 11 : 3)
                .animation(.easeInOut(duration: 0.36).repeatForever(autoreverses: true).delay(0.04), value: animating)
        }
        .frame(width: 14, height: 16)
        .onAppear { animating = true }
    }
}

// MARK: - Interactive Sound Picker with Modern UI & Hover-to-Play

@MainActor
public struct SoundPickerView: View {
    public let title: String
    public let category: AppSoundCategory
    @Binding public var selection: String

    @ObservedObject private var soundManager = SoundManager.shared
    @State private var isPopoverPresented = false
    @State private var searchText = ""
    @State private var hoveredSoundID: String? = nil

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
                    Circle()
                        .fill(Color(hex: sound.source.badgeColorHex).opacity(0.16))
                        .frame(width: 22, height: 22)
                        .overlay(
                            Image(systemName: sound.source == .system ? "apple.logo" : (sound.category?.iconName ?? "sparkles"))
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(Color(hex: sound.source.badgeColorHex))
                        )

                    VStack(alignment: .leading, spacing: 1) {
                        Text(sound.displayName)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.primary)
                            .lineLimit(1)

                        HStack(spacing: 4) {
                            Text(sound.source.rawValue)
                                .font(.system(size: 9.5, weight: .semibold))
                                .foregroundStyle(.secondary)
                            if let cat = sound.category {
                                Text("·")
                                    .font(.system(size: 9))
                                    .foregroundStyle(.tertiary)
                                Text(cat.rawValue)
                                    .font(.system(size: 9.5))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                } else if selection == SoundCatalog.noneSoundID {
                    Circle()
                        .fill(Color.secondary.opacity(0.12))
                        .frame(width: 22, height: 22)
                        .overlay(
                            Image(systemName: "speaker.slash.fill")
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                        )

                    Text("None (Silent)")
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(.secondary)
                } else {
                    Text(SoundCatalog.displayName(for: selection))
                        .font(.system(size: 13, weight: .medium))
                }

                Spacer(minLength: 8)

                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary.opacity(0.7))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .frame(minWidth: 210, maxWidth: 260)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color(NSColor.controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color(NSColor.separatorColor).opacity(0.6), lineWidth: 0.8)
            )
        }
        .buttonStyle(.plain)
        .popover(isPresented: $isPopoverPresented, arrowEdge: .bottom) {
            popoverContent
        }
    }

    // MARK: - Popover Content (Modern Unified Non-Tabbed Layout)

    private var popoverContent: some View {
        VStack(spacing: 0) {
            // Header: Modern Glassmorphic Search Bar
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)

                TextField("Search sounds...", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))

                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color(NSColor.controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color(NSColor.separatorColor).opacity(0.4), lineWidth: 0.8)
            )
            .padding(10)
            .background(Color(NSColor.windowBackgroundColor))

            Divider()

            // Sound Items ScrollView
            ScrollView {
                VStack(alignment: .leading, spacing: 3) {
                    if !searchText.isEmpty {
                        let matching = SoundCatalog.filteredSounds(query: searchText)
                        if matching.isEmpty {
                            VStack(spacing: 8) {
                                Image(systemName: "speaker.slash")
                                    .font(.system(size: 26))
                                    .foregroundStyle(.tertiary)
                                Text("No matching sounds found")
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundStyle(.secondary)
                                Text("Try searching with a different term")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 36)
                        } else {
                            sectionHeader("Matching Sounds (\(matching.count))")
                            ForEach(matching) { sound in
                                soundPopoverRow(sound)
                            }
                        }
                    } else {
                        // Section 1: Recommended for this event category
                        let recs = SoundCatalog.sounds(for: category)
                        if !recs.isEmpty {
                            sectionHeader("Recommended for \(category.rawValue)")
                            ForEach(recs) { sound in
                                soundPopoverRow(sound)
                            }
                        }

                        // Section 2: Other Cinematic App Micro-Sounds
                        let others = SoundCatalog.customSounds.filter { !recs.contains($0) }
                        if !others.isEmpty {
                            sectionHeader("Cinematic App Sounds (\(others.count))")
                            ForEach(others) { sound in
                                soundPopoverRow(sound)
                            }
                        }

                        // Section 3: Native macOS System Sounds
                        let systemSounds = SoundCatalog.systemSounds
                        if !systemSounds.isEmpty {
                            sectionHeader("Native System Sounds (\(systemSounds.count))")
                            ForEach(systemSounds) { sound in
                                soundPopoverRow(sound)
                            }
                        }

                        // Section 4: User-Installed Sounds
                        let userSounds = SoundCatalog.discoverUserSounds()
                        if !userSounds.isEmpty {
                            sectionHeader("User Sounds (\(userSounds.count))")
                            ForEach(userSounds) { sound in
                                soundPopoverRow(sound)
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
            .frame(maxHeight: 340)

            Divider()

            // Footer hint
            HStack(spacing: 6) {
                Image(systemName: "cursorarrow.rays")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                Text("Hover over any sound to preview instantly")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(NSColor.windowBackgroundColor))
        }
        .frame(width: 340)
        .onDisappear {
            hoveredSoundID = nil
        }
    }

    private func sectionHeader(_ text: String) -> some View {
        HStack {
            Text(text)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            Spacer()
        }
        .padding(.horizontal, 8)
        .padding(.top, 8)
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
                // Source / Category badge icon
                Circle()
                    .fill(Color(hex: sound.source.badgeColorHex).opacity(isPlaying ? 0.25 : 0.12))
                    .frame(width: 20, height: 20)
                    .overlay(
                        Image(systemName: sound.source == .system ? "apple.logo" : (sound.category?.iconName ?? "sparkles"))
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Color(hex: sound.source.badgeColorHex))
                    )

                // Sound display name
                Text(sound.displayName)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .medium))
                    .foregroundStyle(isSelected ? Color.accentColor : Color.primary)
                    .lineLimit(1)

                if let cat = sound.category {
                    Text(cat.rawValue)
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                // Playing wave animation indicator
                if isPlaying {
                    AudioEqualizerBars()
                        .padding(.trailing, 2)
                }

                // Selected checkmark
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Color.accentColor)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5.5)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isHovered ? Color.accentColor.opacity(0.12) : (isSelected ? Color.accentColor.opacity(0.06) : Color.clear))
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            if hovering {
                hoveredSoundID = sound.id
                soundManager.previewOnHover(soundID: sound.id, delay: 0.05)
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
                Circle()
                    .fill(Color.secondary.opacity(0.12))
                    .frame(width: 20, height: 20)
                    .overlay(
                        Image(systemName: "speaker.slash.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    )

                Text("None (Silent)")
                    .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? Color.accentColor : Color.primary)

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Color.accentColor)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5.5)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
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
