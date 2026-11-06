// STAGED PORT — SwiftCode-Legacy `SwiftCode/Views/Assist/ToolExecutionView.swift` (main ab03f681; Dylan's own code, direct port authorised under MIT).
// Staged by migration subagent A3 (Assist systems / tools / execution) — NOT yet landed in the repo.
// Target: swiftcode-ide (`swiftcode/Sources/swiftcode-ide/ToolExecutionView.swift`).
// Body is Legacy verbatim unless noted under ADAPTATIONS below. No Swift toolchain exists
// in this environment: static checks only — never claim a build passed.
// Audit gap this port closes (claimed-covered-audit):
//   - explicit Executing / Awaiting tool execution… state row
// ADAPTATIONS:
//   - Added `import SwiftCodeAssistant` (views consume Assist models; module is a swiftcode-ide dependency).
// UNRESOLVED DEPENDENCIES: none found by static scan (SwiftUI/Foundation/Apple-framework names excluded).
// WIRING / REGISTRATION: Wire into the swiftcode-ide assistant UI (AssistantPane / AssistMainView) once the models it observes land.

import SwiftUI
import SwiftCodeAssistant

@MainActor
public struct ToolExecutionView: View {
    let agentSession: AssistAgentSession

    public init(agentSession: AssistAgentSession) {
        self.agentSession = agentSession
    }

    public var body: some View {
        let status = agentSession.state.status
        if status == .executingTool || status == .inspectingResult {
            GroupBox {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 5) {
                        ProgressView()
                            .scaleEffect(0.4)
                            .tint(.secondary)
                        Text("Executing")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                        Spacer()
                    }

                    if let lastEvent = agentSession.state.events.last(where: { $0.state == .executingTool || $0.state == .inspectingResult }) {
                        Text(lastEvent.summary)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        Text("Awaiting tool execution...")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.tertiary)
                    }
                }
                .padding(4)
            }
            .groupBoxStyle(ModernGroupBoxStyle())
            .padding(.horizontal, 12)
        } else {
            EmptyView()
        }
    }
}
