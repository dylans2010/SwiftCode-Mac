import SwiftUI

struct AssistantTheme {
    static let canvas = LinearGradient(
        colors: [Color(red: 0.07, green: 0.09, blue: 0.16), Color(red: 0.14, green: 0.10, blue: 0.24), Color(red: 0.07, green: 0.22, blue: 0.30)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let glassFill = LinearGradient(
        colors: [Color.white.opacity(0.18), Color.white.opacity(0.08)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let accent = LinearGradient(
        colors: [Color.blue, Color.purple, Color.cyan],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let assistantBubble = LinearGradient(
        colors: [Color.white.opacity(0.18), Color.white.opacity(0.10)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let userBubble = LinearGradient(
        colors: [Color.blue, Color.purple],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

struct AssistantGlassCardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(AssistantTheme.glassFill)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(Color.white.opacity(0.14), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.18), radius: 20, y: 10)
    }
}

extension View {
    func assistantGlassCard() -> some View {
        modifier(AssistantGlassCardModifier())
    }
}

struct AssistantSectionHeader: View {
    let eyebrow: String
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(eyebrow.uppercased())
                .font(.caption.weight(.bold))
                .tracking(1.2)
                .foregroundStyle(Color.white.opacity(0.72))
            Text(title)
                .font(.system(.title2, design: .rounded).weight(.bold))
                .foregroundStyle(.white)
            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(Color.white.opacity(0.72))
        }
    }
}

struct ChatMessageBubble: View {
    let message: ChatMessage

    var body: some View {
        HStack(alignment: .bottom, spacing: 10) {
            if message.role == .assistant {
                bubble
                Spacer(minLength: 56)
            } else {
                Spacer(minLength: 56)
                bubble
            }
        }
    }

    private var bubble: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(message.role == .assistant ? "Assistant" : "You")
                .font(.caption.weight(.semibold))
                .foregroundStyle(message.role == .assistant ? Color.white.opacity(0.70) : Color.white.opacity(0.82))

            Text(message.content)
                .font(.body)
                .foregroundStyle(.white)
                .textSelection(.enabled)

            Text(Self.timestampFormatter.string(from: message.timestamp))
                .font(.caption2)
                .foregroundStyle(Color.white.opacity(0.64))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(message.role == .assistant ? AssistantTheme.assistantBubble : AssistantTheme.userBubble)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.white.opacity(message.role == .assistant ? 0.12 : 0.18), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.18), radius: 16, y: 8)
    }

    private static let timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }()
}

struct TypingIndicatorBubble: View {
    var body: some View {
        HStack {
            HStack(spacing: 10) {
                ProgressView()
                    .tint(.white)
                    .scaleEffect(0.85)
                Text("Assistant is composing…")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Color.white.opacity(0.72))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(AssistantTheme.assistantBubble)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            Spacer(minLength: 56)
        }
    }
}

struct SlashCommandList: View {
    let commands: [String]
    let onSelect: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(commands, id: \.self) { command in
                Button {
                    onSelect(command)
                } label: {
                    HStack {
                        Image(systemName: "sparkles")
                            .foregroundStyle(.white.opacity(0.8))
                        Text(command)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.white)
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .background(Color.white.opacity(0.04))
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
        }
        .padding(10)
        .assistantGlassCard()
    }
}

struct AssistantPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(.white)
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity)
            .background(AssistantTheme.accent)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .shadow(color: Color.blue.opacity(configuration.isPressed ? 0.12 : 0.28), radius: configuration.isPressed ? 6 : 16, y: configuration.isPressed ? 3 : 8)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.spring(response: 0.22, dampingFraction: 0.72), value: configuration.isPressed)
    }
}

struct AssistantSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity)
            .background(Color.white.opacity(configuration.isPressed ? 0.14 : 0.09))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.white.opacity(0.12), lineWidth: 1)
            )
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(.spring(response: 0.22, dampingFraction: 0.78), value: configuration.isPressed)
    }
}
