import Foundation

// MARK: - Envelope Specification

/// ADSR envelope parameters for an individual note
public struct EnvelopeSpec: Sendable, Equatable, Hashable {
    public let attackMs: Double
    public let decayMs: Double
    public let sustainLevel: Double
    public let releaseMs: Double
    public let isLinearDecay: Bool

    public init(
        attackMs: Double = 8.0,
        decayMs: Double = 40.0,
        sustainLevel: Double = 0.6,
        releaseMs: Double = 60.0,
        isLinearDecay: Bool = false
    ) {
        self.attackMs = attackMs
        self.decayMs = decayMs
        self.sustainLevel = sustainLevel
        self.releaseMs = releaseMs
        self.isLinearDecay = isLinearDecay
    }

    /// Global envelope default per AED-016 specification:
    /// Attack 8ms, Decay 40ms, Sustain 0.6, Release 60ms
    public static let `default` = EnvelopeSpec(
        attackMs: 8.0,
        decayMs: 40.0,
        sustainLevel: 0.6,
        releaseMs: 60.0,
        isLinearDecay: false
    )

    /// Slow attack envelope for `.agentThinking` (40ms attack)
    public static let slowAttack = EnvelopeSpec(
        attackMs: 40.0,
        decayMs: 40.0,
        sustainLevel: 0.6,
        releaseMs: 60.0,
        isLinearDecay: false
    )

    /// Linear decay envelope with zero sustain for `.criticalSystemError`
    public static let linearDecayNoSustain = EnvelopeSpec(
        attackMs: 8.0,
        decayMs: 40.0,
        sustainLevel: 0.0,
        releaseMs: 0.0,
        isLinearDecay: true
    )

    /// Ultra-short micro-feedback envelope for `.tabSwitch` (3ms attack)
    public static let microTick = EnvelopeSpec(
        attackMs: 3.0,
        decayMs: 15.0,
        sustainLevel: 0.3,
        releaseMs: 15.0,
        isLinearDecay: false
    )
}

// MARK: - Note Specification

/// Single musical note in an alert tone phrase
public struct NoteSpec: Sendable, Equatable, Hashable {
    /// Equal-tempered pitch in Hertz (A4 = 440.0 Hz)
    public let frequencyHz: Double
    /// Duration of the note in milliseconds
    public let durationMs: Double
    /// Custom envelope parameters if overriding global defaults
    public let envelope: EnvelopeSpec

    public init(
        frequencyHz: Double,
        durationMs: Double,
        envelope: EnvelopeSpec = .default
    ) {
        self.frequencyHz = frequencyHz
        self.durationMs = durationMs
        self.envelope = envelope
    }
}

// MARK: - Tone Specification

/// Full specification for a synthesized alert tone phrase
public struct ToneSpec: Sendable, Equatable, Hashable {
    /// Ordered sequence of notes constituting the melodic phrase
    public let notes: [NoteSpec]
    /// Inter-note silence gap in milliseconds (default 20ms; 15-30ms per spec)
    public let gapMs: Double

    public init(notes: [NoteSpec], gapMs: Double = 20.0) {
        self.notes = notes
        self.gapMs = gapMs
    }

    /// Total duration of the synthesized phrase including notes and inter-note gaps
    public var totalDurationMs: Double {
        guard !notes.isEmpty else { return 0 }
        let notesDuration = notes.reduce(0.0) { $0 + $1.durationMs }
        let gapsDuration = Double(max(0, notes.count - 1)) * gapMs
        return notesDuration + gapsDuration
    }
}

// MARK: - Semantic Alert Tone Enum

/// Complete 22-case canonical alert tone enumeration
public enum AlertTone: String, CaseIterable, Identifiable, Sendable {
    case buildSuccess        = "buildSuccess"
    case buildFailure        = "buildFailure"
    case taskComplete        = "taskComplete"
    case taskFailed          = "taskFailed"
    case warning             = "warning"
    case error               = "error"
    case mention             = "mention"
    case messageReceived     = "messageReceived"
    case fileSaved           = "fileSaved"
    case projectOpened       = "projectOpened"
    case projectClosed       = "projectClosed"
    case syncStarted         = "syncStarted"
    case syncComplete        = "syncComplete"
    case syncFailed          = "syncFailed"
    case gitCommit           = "gitCommit"
    case gitPushSuccess      = "gitPushSuccess"
    case gitPushFailed       = "gitPushFailed"
    case agentThinking       = "agentThinking"
    case agentResponseReady  = "agentResponseReady"
    case criticalSystemError = "criticalSystemError"
    case tabSwitch           = "tabSwitch"
    case deleteConfirm       = "deleteConfirm"

    public var id: String { rawValue }

    // MARK: - Human-Readable Metadata

    public var displayName: String {
        switch self {
        case .buildSuccess:        return "Build Success"
        case .buildFailure:        return "Build Failure"
        case .taskComplete:        return "Task Complete"
        case .taskFailed:          return "Task Failed"
        case .warning:             return "Warning"
        case .error:               return "Error"
        case .mention:             return "Mention"
        case .messageReceived:     return "Message Received"
        case .fileSaved:           return "File Saved"
        case .projectOpened:       return "Project Opened"
        case .projectClosed:       return "Project Closed"
        case .syncStarted:         return "Sync Started"
        case .syncComplete:        return "Sync Complete"
        case .syncFailed:          return "Sync Failed"
        case .gitCommit:           return "Git Commit"
        case .gitPushSuccess:      return "Git Push Success"
        case .gitPushFailed:       return "Git Push Failed"
        case .agentThinking:       return "Agent Thinking"
        case .agentResponseReady:  return "Agent Response Ready"
        case .criticalSystemError: return "Critical System Error"
        case .tabSwitch:           return "Tab Switch"
        case .deleteConfirm:       return "Delete Confirmation"
        }
    }

    public var semanticUse: String {
        switch self {
        case .buildSuccess:        return "Build succeeded"
        case .buildFailure:        return "Build failed"
        case .taskComplete:        return "Agent task finished"
        case .taskFailed:          return "Agent task failed"
        case .warning:             return "Non-blocking warning"
        case .error:               return "Blocking error"
        case .mention:             return "Discord/mention-style ping"
        case .messageReceived:     return "New message"
        case .fileSaved:           return "File save confirmation"
        case .projectOpened:       return "Project load complete"
        case .projectClosed:       return "Project closed"
        case .syncStarted:         return "Cloud sync begins"
        case .syncComplete:        return "Cloud sync done"
        case .syncFailed:          return "Cloud sync error"
        case .gitCommit:           return "Commit created"
        case .gitPushSuccess:      return "Push succeeded"
        case .gitPushFailed:       return "Push rejected/failed"
        case .agentThinking:       return "Jules agent processing start"
        case .agentResponseReady:  return "Jules AED result ready"
        case .criticalSystemError: return "CAF-X / unrecoverable failure"
        case .tabSwitch:           return "Tab/panel switch"
        case .deleteConfirm:       return "Destructive action confirmed"
        }
    }

    public var characterDescription: String {
        switch self {
        case .buildSuccess:        return "Bright ascending major triad"
        case .buildFailure:        return "Descending minor 2nd, low register, resolves down"
        case .taskComplete:        return "Simple perfect 4th resolution, warm"
        case .taskFailed:          return "Low descending semitone, subdued"
        case .warning:             return "Two quick identical pips, mid-bright"
        case .error:               return "Three low repeated pulses, urgent but not harsh"
        case .mention:             return "Quick bright chirp, attention-grabbing"
        case .messageReceived:     return "Gentle major 3rd rise"
        case .fileSaved:           return "Single clean note, minimal"
        case .projectOpened:       return "Full ascending arpeggio, celebratory"
        case .projectClosed:       return "Descending arpeggio, mirror of Project Opened"
        case .syncStarted:         return "Rising major 3rd, light"
        case .syncComplete:        return "Resolves upward to dominant, satisfying"
        case .syncFailed:          return "Chromatic descent, unsettled"
        case .gitCommit:           return "Clean major 3rd, neutral-positive"
        case .gitPushSuccess:      return "Full major triad ascending"
        case .gitPushFailed:       return "Descending tritone-adjacent, dissonant-but-tasteful"
        case .agentThinking:       return "Single soft sustained pip, non-intrusive"
        case .agentResponseReady:  return "Bright ascending, highest priority tone in set"
        case .criticalSystemError: return "Low, grave, unambiguous severity"
        case .tabSwitch:           return "Ultra-short tick, near-inaudible confirmation"
        case .deleteConfirm:       return "Short descending minor 3rd, cautionary"
        }
    }

    public var notesDescription: String {
        switch self {
        case .buildSuccess:        return "C5 (523Hz) → E5 (659Hz) → G5 (784Hz)"
        case .buildFailure:        return "F4 (349Hz) → D#4 (311Hz)"
        case .taskComplete:        return "G4 (392Hz) → C5 (523Hz)"
        case .taskFailed:          return "A3 (220Hz) → G#3 (208Hz)"
        case .warning:             return "E5 (659Hz) → E5 (659Hz)"
        case .error:               return "C4 (262Hz) → C4 (262Hz) → C4 (262Hz)"
        case .mention:             return "B5 (988Hz) → D6 (1175Hz)"
        case .messageReceived:     return "A4 (440Hz) → C#5 (554Hz)"
        case .fileSaved:           return "E5 (659Hz)"
        case .projectOpened:       return "C4 (262Hz) → E4 (330Hz) → G4 (392Hz) → C5 (523Hz)"
        case .projectClosed:       return "C5 (523Hz) → G4 (392Hz) → E4 (330Hz) → C4 (262Hz)"
        case .syncStarted:         return "D5 (587Hz) → F#5 (740Hz)"
        case .syncComplete:        return "F#5 (740Hz) → D5 (587Hz) → A5 (880Hz)"
        case .syncFailed:          return "D5 (587Hz) → C#5 (554Hz) → C5 (523Hz)"
        case .gitCommit:           return "G4 (392Hz) → B4 (494Hz)"
        case .gitPushSuccess:      return "G4 (392Hz) → B4 (494Hz) → D5 (587Hz)"
        case .gitPushFailed:       return "D5 (587Hz) → A#4 (466Hz)"
        case .agentThinking:       return "A4 (440Hz)"
        case .agentResponseReady:  return "E5 (659Hz) → G5 (784Hz) → C6 (1047Hz)"
        case .criticalSystemError: return "C4 (262Hz) → G3 (196Hz) → C4 (262Hz)"
        case .tabSwitch:           return "C6 (1047Hz)"
        case .deleteConfirm:       return "E4 (330Hz) → C4 (262Hz)"
        }
    }

    public var systemImageName: String {
        switch self {
        case .buildSuccess:        return "hammer.fill"
        case .buildFailure:        return "hammer.slash"
        case .taskComplete:        return "checkmark.circle.fill"
        case .taskFailed:          return "xmark.circle.fill"
        case .warning:             return "exclamationmark.triangle.fill"
        case .error:               return "exclamationmark.octagon.fill"
        case .mention:             return "at"
        case .messageReceived:     return "bubble.left.fill"
        case .fileSaved:           return "square.and.arrow.down.fill"
        case .projectOpened:       return "folder.badge.plus"
        case .projectClosed:       return "folder.badge.minus"
        case .syncStarted:         return "arrow.triangle.2.circlepath"
        case .syncComplete:        return "checkmark.icloud.fill"
        case .syncFailed:          return "exclamationmark.icloud.fill"
        case .gitCommit:           return "point.topleft.down.curvedto.point.bottomright.up"
        case .gitPushSuccess:      return "arrow.up.circle.fill"
        case .gitPushFailed:       return "exclamationmark.arrow.triangle.2.circlepath"
        case .agentThinking:       return "brain.head.profile"
        case .agentResponseReady:  return "sparkles"
        case .criticalSystemError: return "bolt.trianglebadge.exclamationmark.fill"
        case .tabSwitch:           return "rectangle.split.2x1"
        case .deleteConfirm:       return "trash.fill"
        }
    }

    // MARK: - Exact AED-016 Specification Mapping

    public var spec: ToneSpec {
        switch self {
        // 1. Build Success: C5 (523.25) -> E5 (659.25) -> G5 (783.99) | 90, 90, 160 ms
        case .buildSuccess:
            return ToneSpec(notes: [
                NoteSpec(frequencyHz: 523.25, durationMs: 90),
                NoteSpec(frequencyHz: 659.25, durationMs: 90),
                NoteSpec(frequencyHz: 783.99, durationMs: 160)
            ], gapMs: 20)

        // 2. Build Failure: F4 (349.23) -> D#4 (311.13) | 140, 220 ms
        case .buildFailure:
            return ToneSpec(notes: [
                NoteSpec(frequencyHz: 349.23, durationMs: 140),
                NoteSpec(frequencyHz: 311.13, durationMs: 220)
            ], gapMs: 20)

        // 3. Task Complete: G4 (392.00) -> C5 (523.25) | 100, 200 ms
        case .taskComplete:
            return ToneSpec(notes: [
                NoteSpec(frequencyHz: 392.00, durationMs: 100),
                NoteSpec(frequencyHz: 523.25, durationMs: 200)
            ], gapMs: 20)

        // 4. Task Failed: A3 (220.00) -> G#3 (207.65) | 160, 240 ms
        case .taskFailed:
            return ToneSpec(notes: [
                NoteSpec(frequencyHz: 220.00, durationMs: 160),
                NoteSpec(frequencyHz: 207.65, durationMs: 240)
            ], gapMs: 20)

        // 5. Warning: E5 (659.25) -> E5 (659.25) | 80, 80 ms (30ms gap)
        case .warning:
            return ToneSpec(notes: [
                NoteSpec(frequencyHz: 659.25, durationMs: 80),
                NoteSpec(frequencyHz: 659.25, durationMs: 80)
            ], gapMs: 30)

        // 6. Error: C4 (261.63) -> C4 (261.63) -> C4 (261.63) | 70, 70, 140 ms
        case .error:
            return ToneSpec(notes: [
                NoteSpec(frequencyHz: 261.63, durationMs: 70),
                NoteSpec(frequencyHz: 261.63, durationMs: 70),
                NoteSpec(frequencyHz: 261.63, durationMs: 140)
            ], gapMs: 20)

        // 7. Mention: B5 (987.77) -> D6 (1174.66) | 60, 140 ms
        case .mention:
            return ToneSpec(notes: [
                NoteSpec(frequencyHz: 987.77, durationMs: 60),
                NoteSpec(frequencyHz: 1174.66, durationMs: 140)
            ], gapMs: 20)

        // 8. Message Received: A4 (440.00) -> C#5 (554.37) | 90, 150 ms
        case .messageReceived:
            return ToneSpec(notes: [
                NoteSpec(frequencyHz: 440.00, durationMs: 90),
                NoteSpec(frequencyHz: 554.37, durationMs: 150)
            ], gapMs: 20)

        // 9. File Saved: E5 (659.25) | 100 ms
        case .fileSaved:
            return ToneSpec(notes: [
                NoteSpec(frequencyHz: 659.25, durationMs: 100)
            ], gapMs: 0)

        // 10. Project Opened: C4 (261.63) -> E4 (329.63) -> G4 (392.00) -> C5 (523.25) | 70, 70, 70, 180 ms
        case .projectOpened:
            return ToneSpec(notes: [
                NoteSpec(frequencyHz: 261.63, durationMs: 70),
                NoteSpec(frequencyHz: 329.63, durationMs: 70),
                NoteSpec(frequencyHz: 392.00, durationMs: 70),
                NoteSpec(frequencyHz: 523.25, durationMs: 180)
            ], gapMs: 20)

        // 11. Project Closed: C5 (523.25) -> G4 (392.00) -> E4 (329.63) -> C4 (261.63) | 70, 70, 70, 180 ms
        case .projectClosed:
            return ToneSpec(notes: [
                NoteSpec(frequencyHz: 523.25, durationMs: 70),
                NoteSpec(frequencyHz: 392.00, durationMs: 70),
                NoteSpec(frequencyHz: 329.63, durationMs: 70),
                NoteSpec(frequencyHz: 261.63, durationMs: 180)
            ], gapMs: 20)

        // 12. Sync Started: D5 (587.33) -> F#5 (739.99) | 80, 120 ms
        case .syncStarted:
            return ToneSpec(notes: [
                NoteSpec(frequencyHz: 587.33, durationMs: 80),
                NoteSpec(frequencyHz: 739.99, durationMs: 120)
            ], gapMs: 20)

        // 13. Sync Complete: F#5 (739.99) -> D5 (587.33) -> A5 (880.00) | 70, 70, 160 ms
        case .syncComplete:
            return ToneSpec(notes: [
                NoteSpec(frequencyHz: 739.99, durationMs: 70),
                NoteSpec(frequencyHz: 587.33, durationMs: 70),
                NoteSpec(frequencyHz: 880.00, durationMs: 160)
            ], gapMs: 20)

        // 14. Sync Failed: D5 (587.33) -> C#5 (554.37) -> C5 (523.25) | 90, 90, 200 ms
        case .syncFailed:
            return ToneSpec(notes: [
                NoteSpec(frequencyHz: 587.33, durationMs: 90),
                NoteSpec(frequencyHz: 554.37, durationMs: 90),
                NoteSpec(frequencyHz: 523.25, durationMs: 200)
            ], gapMs: 20)

        // 15. Git Commit: G4 (392.00) -> B4 (493.88) | 90, 130 ms
        case .gitCommit:
            return ToneSpec(notes: [
                NoteSpec(frequencyHz: 392.00, durationMs: 90),
                NoteSpec(frequencyHz: 493.88, durationMs: 130)
            ], gapMs: 20)

        // 16. Git Push Success: G4 (392.00) -> B4 (493.88) -> D5 (587.33) | 70, 70, 170 ms
        case .gitPushSuccess:
            return ToneSpec(notes: [
                NoteSpec(frequencyHz: 392.00, durationMs: 70),
                NoteSpec(frequencyHz: 493.88, durationMs: 70),
                NoteSpec(frequencyHz: 587.33, durationMs: 170)
            ], gapMs: 20)

        // 17. Git Push Failed: D5 (587.33) -> A#4 (466.16) | 130, 220 ms
        case .gitPushFailed:
            return ToneSpec(notes: [
                NoteSpec(frequencyHz: 587.33, durationMs: 130),
                NoteSpec(frequencyHz: 466.16, durationMs: 220)
            ], gapMs: 20)

        // 18. Agent Thinking: A4 (440.00) | 250 ms (slow attack 40ms)
        case .agentThinking:
            return ToneSpec(notes: [
                NoteSpec(frequencyHz: 440.00, durationMs: 250, envelope: .slowAttack)
            ], gapMs: 0)

        // 19. Agent Response Ready: E5 (659.25) -> G5 (783.99) -> C6 (1046.50) | 70, 70, 190 ms
        case .agentResponseReady:
            return ToneSpec(notes: [
                NoteSpec(frequencyHz: 659.25, durationMs: 70),
                NoteSpec(frequencyHz: 783.99, durationMs: 70),
                NoteSpec(frequencyHz: 1046.50, durationMs: 190)
            ], gapMs: 20)

        // 20. Critical System Error: C4 (261.63) -> G3 (196.00) -> C4 (261.63) | 120, 120, 220 ms (linear decay, no sustain)
        case .criticalSystemError:
            return ToneSpec(notes: [
                NoteSpec(frequencyHz: 261.63, durationMs: 120, envelope: .linearDecayNoSustain),
                NoteSpec(frequencyHz: 196.00, durationMs: 120, envelope: .linearDecayNoSustain),
                NoteSpec(frequencyHz: 261.63, durationMs: 220, envelope: .linearDecayNoSustain)
            ], gapMs: 20)

        // 21. Tab Switch (Bonus micro-feedback): C6 (1046.50) | 40 ms (attack 3ms)
        case .tabSwitch:
            return ToneSpec(notes: [
                NoteSpec(frequencyHz: 1046.50, durationMs: 40, envelope: .microTick)
            ], gapMs: 0)

        // 22. Delete Confirm (Bonus): E4 (329.63) -> C4 (261.63) | 90, 150 ms
        case .deleteConfirm:
            return ToneSpec(notes: [
                NoteSpec(frequencyHz: 329.63, durationMs: 90),
                NoteSpec(frequencyHz: 261.63, durationMs: 150)
            ], gapMs: 20)
        }
    }
}
