//
//  OCToolsUIView.swift
//  SwiftCode
//
//  Native tool-call activity from the OpenCode SDK runtime.
//
//  Visual language follows the Muse tool cards (MuseSDKToolCall):
//  12pt semibold rounded titles, 10–11pt secondary text, a collapsible
//  card per call with a rotating chevron, a tinted state badge, a
//  running progress indicator, and a scrollable monospaced result block.
//  The tint is orange, the OpenCode identity, against Muse's blue,
//  the native tools' green, and OpenRouter's purple.
//
//  Wiring (the parent owns this; this view renders only): the parent
//  observes `SDKToolEventStore` and passes a snapshot,
//  `OCToolsUIView(events: store.events(for: sessionId))`. The view takes
//  a plain array on purpose: rendering never touches a store, a client,
//  or any async work, so a streaming session cannot freeze the UI.
//  Rows are keyed by `toolCallId` (never by index or by `id`), so a
//  merge updates a row in place without duplicating it or losing its
//  expansion state.
//
//  Provider routing (integration correction to the original source
//  filter): the view renders every event whose serving provider is
//  "opencode", whatever its tool source. In an SDK run, a
//  SwiftCode-native call bridged through the OpenCode SDK still belongs
//  to that run's view — the native plan UI does not render SDK runs —
//  while `source` continues to drive execution routing and is shown
//  per row. Each event still renders in exactly one provider view,
//  never both. Tool names are displayed exactly as reported by the
//  server: no renaming and no prefix stripping. (Combined-mode
//  collisions are resolved by disabling the colliding built-in, not by
//  renaming it; see the OpenCode bridge.)

import SwiftUI
import AppKit

public struct OCToolsUIView: View {
    /// Snapshot of tool events for one session. May contain other
    /// providers' events; only this provider's rows are rendered.
    public let events: [SDKToolEvent]

    public init(events: [SDKToolEvent]) {
        self.events = events
    }

    /// This provider's rows only, in first-seen order (the store's order).
    private var toolEvents: [SDKToolEvent] {
        events.filter { $0.provider == "opencode" }
    }

    private var isRunning: Bool {
        toolEvents.contains { $0.state == .running }
    }

    public var body: some View {
        if toolEvents.isEmpty {
            Text("No OpenCode tool activity yet")
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "terminal")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Color.orange)

                    Text("OpenCode Tools")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.orange)

                    if isRunning {
                        ProgressView()
                            .scaleEffect(0.4)
                            .frame(width: 12, height: 12)
                    } else {
                        Text("· \(toolEvents.count) \(toolEvents.count == 1 ? "tool" : "tools")")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.secondary)
                    }

                    Spacer()
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))

                VStack(spacing: 6) {
                    ForEach(toolEvents, id: \.toolCallId) { event in
                        OCToolCallRow(event: event)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4)
        }
    }
}

// MARK: - One OpenCode tool call

private struct OCToolCallRow: View {
    let event: SDKToolEvent

    @State private var isOpen: Bool = false
    @State private var isCopied: Bool = false

    /// Parsed key/value rows from the (redacted) arguments, when the
    /// arguments are a JSON object. Nil for non-object arguments, which
    /// fall back to the plain redacted text block.
    private var argumentRows: [(key: String, value: String)]? {
        guard let data = event.safeArguments.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              !json.isEmpty else {
            return nil
        }
        return json.keys.sorted().map { key in
            (key: key, value: Self.displayValue(json[key]))
        }
    }

    private static func displayValue(_ value: Any?) -> String {
        guard let value else { return "" }
        if let string = value as? String { return string }
        if let bool = value as? Bool { return bool ? "true" : "false" }
        if let number = value as? NSNumber { return number.stringValue }
        if JSONSerialization.isValidJSONObject(value),
           let data = try? JSONSerialization.data(withJSONObject: value),
           let string = String(data: data, encoding: .utf8) {
            return string
        }
        return String(describing: value)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.18)) {
                    isOpen.toggle()
                }
            } label: {
                HStack(spacing: 8) {
                    statusIcon

                    Image(systemName: "wrench.and.screwdriver.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.orange)
                        .frame(width: 16, height: 16)

                    Text(event.toolName)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color.primary)
                        .lineLimit(1)

                    HStack(spacing: 3) {
                        Text(event.state.displayLabel)
                            .font(.system(size: 9, weight: .bold, design: .rounded))
                    }
                    .foregroundStyle(stateColor)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(stateColor.opacity(0.12), in: Capsule())

                    if let firstArgument = argumentRows?.first {
                        Text("\(firstArgument.key): \(firstArgument.value)")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 4))
                    }

                    Spacer(minLength: 4)

                    if let duration = event.duration {
                        Text(String(format: "%.1fs", duration))
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.tertiary)
                    }

                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(isOpen ? 90 : 0))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isOpen {
                VStack(alignment: .leading, spacing: 8) {
                    Divider()
                        .opacity(0.35)

                    if let description = event.toolDescription, !description.isEmpty {
                        Text(description)
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundStyle(Color.primary.opacity(0.85))
                            .padding(.horizontal, 4)
                    }

                    if let rows = argumentRows {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Arguments")
                                .font(.system(size: 10, weight: .semibold, design: .rounded))
                                .foregroundStyle(Color.orange)

                            ForEach(rows, id: \.key) { row in
                                HStack(alignment: .top, spacing: 6) {
                                    Text("\(row.key):")
                                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                        .frame(width: 80, alignment: .leading)

                                    Text(row.value)
                                        .font(.system(size: 10, design: .monospaced))
                                        .foregroundStyle(Color.primary.opacity(0.9))
                                        .textSelection(.enabled)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .padding(.vertical, 1)
                            }
                        }
                        .padding(8)
                        .background(Color.orange.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
                    }

                    if !event.safeArguments.isEmpty {
                        DisclosureGroup("Details") {
                            ScrollView([.horizontal, .vertical], showsIndicators: true) {
                                Text(event.safeArguments)
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundStyle(Color.secondary)
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(8)
                            }
                            .frame(maxHeight: 200)
                            .background(Color.black.opacity(0.22), in: RoundedRectangle(cornerRadius: 6))
                        }
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                    }

                    if event.state == .completed,
                       let result = event.safeResult, !result.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text("Result")
                                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                                    .foregroundStyle(Color.orange)

                                Spacer()

                                Button {
                                    NSPasteboard.general.clearContents()
                                    NSPasteboard.general.setString(result, forType: .string)
                                    isCopied = true
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
                                        isCopied = false
                                    }
                                } label: {
                                    HStack(spacing: 3) {
                                        Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
                                            .font(.system(size: 8))
                                        Text(isCopied ? "Copied" : "Copy")
                                            .font(.system(size: 9, weight: .medium))
                                    }
                                    .foregroundStyle(isCopied ? Color.green : Color.secondary)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 4))
                                }
                                .buttonStyle(.plain)
                            }

                            ScrollView([.horizontal, .vertical], showsIndicators: true) {
                                Text(result)
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundStyle(Color.secondary)
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(8)
                            }
                            .frame(maxHeight: 200)
                            .background(Color.black.opacity(0.22), in: RoundedRectangle(cornerRadius: 6))
                        }
                    }

                    if event.state == .failed || event.state == .cancelled {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Error")
                                .font(.system(size: 10, weight: .semibold, design: .rounded))
                                .foregroundStyle(Color.red)

                            Text(event.safeError ?? "Tool did not complete.")
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(Color.red.opacity(0.85))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(8)
                                .background(Color.red.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
                        }
                    }
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 8)
            }
        }
        .liquidGlass(style: .standard, cornerRadius: 8, tint: .orange)
    }

    private var stateColor: Color {
        switch event.state {
        case .requested: return .secondary
        case .running: return .orange
        case .completed: return .green
        case .failed, .cancelled: return .red
        }
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch event.state {
        case .running:
            ProgressView()
                .scaleEffect(0.35)
                .frame(width: 14, height: 14)
        case .completed:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Color.orange)
                .frame(width: 14, height: 14)
        case .failed, .cancelled:
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Color.red)
                .frame(width: 14, height: 14)
        case .requested:
            Circle()
                .fill(Color.secondary.opacity(0.3))
                .frame(width: 8, height: 8)
                .frame(width: 14, height: 14)
        }
    }
}
