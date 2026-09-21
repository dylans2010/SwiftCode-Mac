import SwiftUI

/// macOS-native SwiftUI view allowing developers to audition and test all 22 synthesized alert tones
public struct SoundPreviewView: View {
    @State private var player = AlertSoundPlayer.shared
    @State private var searchText: String = ""
    @State private var selectedGroup: ToneGroupFilter = .all

    private enum ToneGroupFilter: String, CaseIterable, Identifiable {
        case all = "All (22)"
        case buildAndAgent = "Build & Agent"
        case systemAlerts = "Alerts & Errors"
        case gitAndSync = "Git & Cloud"
        case editorActions = "Editor & Project"

        var id: String { rawValue }
    }

    public init() {}

    private var filteredTones: [AlertTone] {
        AlertTone.allCases.filter { tone in
            let matchesGroup: Bool
            switch selectedGroup {
            case .all:
                matchesGroup = true
            case .buildAndAgent:
                matchesGroup = [
                    .buildSuccess, .buildFailure, .taskComplete, .taskFailed,
                    .agentThinking, .agentResponseReady
                ].contains(tone)
            case .systemAlerts:
                matchesGroup = [
                    .warning, .error, .criticalSystemError, .mention, .messageReceived
                ].contains(tone)
            case .gitAndSync:
                matchesGroup = [
                    .gitCommit, .gitPushSuccess, .gitPushFailed,
                    .syncStarted, .syncComplete, .syncFailed
                ].contains(tone)
            case .editorActions:
                matchesGroup = [
                    .fileSaved, .projectOpened, .projectClosed, .tabSwitch, .deleteConfirm
                ].contains(tone)
            }

            guard matchesGroup else { return false }

            if searchText.isEmpty { return true }
            return tone.displayName.localizedCaseInsensitiveContains(searchText)
                || tone.semanticUse.localizedCaseInsensitiveContains(searchText)
                || tone.characterDescription.localizedCaseInsensitiveContains(searchText)
                || tone.notesDescription.localizedCaseInsensitiveContains(searchText)
        }
    }

    public var body: some View {
        VStack(spacing: 0) {
            headerControls
            Divider()
            toneList
            Divider()
            footerBar
        }
        .frame(minWidth: 540, minHeight: 480)
    }

    // MARK: - Header Controls

    private var headerControls: some View {
        VStack(spacing: 12) {
            HStack(spacing: 16) {
                // Title and Hero Icon
                HStack(spacing: 10) {
                    Image(systemName: "waveform.circle.fill")
                        .font(.title2)
                        .foregroundStyle(Color.orange)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Synthesized Alert Sounds")
                            .font(.headline)
                        Text("22 melodic tones synthesized in code via AVAudioEngine (Zero audio assets)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                // Master Mute Toggle
                Toggle(isOn: $player.isMuted) {
                    Label(
                        player.isMuted ? "Muted" : "Sound Enabled",
                        systemImage: player.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill"
                    )
                    .font(.subheadline)
                }
                .toggleStyle(.button)
                .tint(player.isMuted ? .red : .accentColor)
            }

            HStack(spacing: 16) {
                // Volume Slider
                HStack(spacing: 8) {
                    Image(systemName: "speaker.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Slider(value: $player.volume, in: 0.0...1.0)
                        .frame(width: 140)
                        .disabled(player.isMuted)

                    Image(systemName: "speaker.wave.3.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text("\(Int(player.volume * 100))%")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 36, alignment: .trailing)
                }

                Spacer()

                // Search Bar
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    TextField("Search tones...", text: $searchText)
                        .textFieldStyle(.plain)
                        .font(.subheadline)

                    if !searchText.isEmpty {
                        Button {
                            searchText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(6)
                .background(Color(NSColor.controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .frame(maxWidth: 200)
            }

            // Category Filter Picker
            Picker("", selection: $selectedGroup) {
                ForEach(ToneGroupFilter.allCases) { filter in
                    Text(filter.rawValue).tag(filter)
                }
            }
            .pickerStyle(.segmented)
            .controlSize(.small)
        }
        .padding(14)
        .background(Color(NSColor.windowBackgroundColor))
    }

    // MARK: - Tone List

    private var toneList: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                ForEach(filteredTones) { tone in
                    toneRow(tone)
                }
            }
            .padding(14)
        }
    }

    private func toneRow(_ tone: AlertTone) -> some View {
        let isPlaying = player.currentlyPlayingTone == tone

        return HStack(spacing: 12) {
            // Icon
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(isPlaying ? Color.orange.opacity(0.2) : Color.primary.opacity(0.04))
                    .frame(width: 38, height: 38)

                Image(systemName: tone.systemImageName)
                    .font(.body)
                    .foregroundStyle(isPlaying ? Color.orange : Color.primary)
            }

            // Tone Information
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(tone.displayName)
                        .font(.subheadline.bold())

                    Text(tone.semanticUse)
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.primary.opacity(0.06)))
                        .foregroundStyle(.secondary)
                }

                Text(tone.notesDescription)
                    .font(.caption.monospaced())
                    .foregroundStyle(Color.accentColor)

                Text(tone.characterDescription)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Play / Audition Button
            Button {
                if isPlaying {
                    player.stop()
                } else {
                    player.play(tone)
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: isPlaying ? "stop.fill" : "play.fill")
                        .font(.caption)
                    Text(isPlaying ? "Playing" : "Audition")
                        .font(.caption.bold())
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(isPlaying ? Color.orange : Color(NSColor.controlBackgroundColor))
                .foregroundStyle(isPlaying ? Color.white : Color.primary)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(isPlaying ? Color.orange : Color.primary.opacity(0.1), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            .disabled(player.isMuted)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(isPlaying ? Color.orange.opacity(0.08) : Color(NSColor.controlBackgroundColor).opacity(0.5))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(isPlaying ? Color.orange.opacity(0.4) : Color.primary.opacity(0.06), lineWidth: 1)
        )
    }

    // MARK: - Footer

    private var footerBar: some View {
        HStack {
            Image(systemName: "checkmark.shield.fill")
                .font(.caption)
                .foregroundStyle(.green)
            Text("Additive harmonic synthesis (70% Sine + 30% Triangle overtone, ADSR envelope)")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Spacer()
            Text("\(filteredTones.count) of 22 tones")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Color(NSColor.windowBackgroundColor))
    }
}
