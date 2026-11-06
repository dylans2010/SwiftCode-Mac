// STAGED PORT — SwiftCode-Legacy `SwiftCode/Views/AIAssistantPanelView.swift` (main ab03f681; Dylan's own code, direct port authorised under MIT).
// Staged by migration subagent A3 (Assist systems / tools / execution) — NOT yet landed in the repo.
// Target: swiftcode-ide (`swiftcode/Sources/swiftcode-ide/AIAssistantPanelView.swift`).
// Body is Legacy verbatim unless noted under ADAPTATIONS below. No Swift toolchain exists
// in this environment: static checks only — never claim a build passed.
// Audit gap this port closes (claimed-covered-audit):
//   - Insert suggestion action
//   - Replace suggestion action
// ADAPTATIONS:
//   - Added `import SwiftCodeAssistant` (views consume Assist models; module is a swiftcode-ide dependency).
// UNRESOLVED DEPENDENCIES (no definition in the destination yet; resolve as the owning ports land):
//   - AIAssistantViewModel — UNOWNED (no worklist) (`SwiftCode/ViewModels/AIAssistantViewModel.swift`)
//   - AIChatInputView — UNOWNED (no worklist) (`SwiftCode/Views/AIChatInputView.swift`)
//   - AIChatMessageListView — UNOWNED (no worklist) (`SwiftCode/Views/AIChatMessageListView.swift`)
//   - AIModelPickerView — UNOWNED (no worklist) (`SwiftCode/Views/AIModelPickerView.swift`)
//   - AISuggestionActionBar — other agent (views-native-ui) (`SwiftCode/Views/AISuggestionActionBar.swift`)
//   - EditorViewModel — other agent (editor-visual-artboards) (`SwiftCode/ViewModels/EditorViewModel.swift`)
//   - FileSystemService — other agent (services-networking-cloud) (`SwiftCode/Backend/FileSystem/FileSystemService.swift`)
//   - VisualEffectView — other agent (other) (`SwiftCode/UI/Styles/Styling/LiquidGlass.swift`)
// WIRING / REGISTRATION: Wire into the swiftcode-ide assistant UI (AssistantPane / AssistMainView) once the models it observes land.

import SwiftUI
import SwiftCodeAssistant

struct AIAssistantPanelView: View {
    @State var viewModel: AIAssistantViewModel
    @State var editorViewModel: EditorViewModel
    @State private var inputText = ""

    var body: some View {
        VStack(spacing: 0) {
            AIModelPickerView()
            AIChatMessageListView(messages: viewModel.conversation.messages)

            if let lastMsg = viewModel.conversation.messages.last, lastMsg.role == .assistant {
                AISuggestionActionBar { action in
                    handleAIAction(action, content: lastMsg.content)
                }
            }

            AIChatInputView(text: $inputText) {
                Task {
                    await viewModel.sendMessage(inputText, model: "openai/gpt-4o")
                    inputText = ""
                }
            }
        }
        .background(VisualEffectView(material: .sidebar, blendingMode: .withinWindow))
    }

    private func handleAIAction(_ action: AIAction, content: String) {
        switch action {
        case .insert:
            editorViewModel.activeDocument?.content += content
        case .replace:
            editorViewModel.activeDocument?.content = content
        case .apply:
            if let url = editorViewModel.activeDocument?.url {
                let newURL = url.deletingLastPathComponent().appendingPathComponent("Generated_" + url.lastPathComponent)
                Task {
                    try? await FileSystemService.shared.createFile(at: newURL, content: content)
                    await editorViewModel.openFile(url: newURL)
                }
            }
        }
    }
}

enum AIAction {
    case insert, replace, apply
}
