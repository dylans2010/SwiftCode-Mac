import Foundation
import SwiftUI
import SwiftCodeIDECore
import SwiftCodeIDEShell

struct DebugArea: View {
    @Bindable var model: WorkspaceShellModel
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let c = ShellColors(scheme)
        HStack(spacing: 0) {
            if model.debug.showsVariables {
                VariablesPane(model: model).frame(minWidth: 150, maxWidth: .infinity)
                if model.debug.showsConsole { Hairline(color: c.separator, vertical: true) }
            }
            if model.debug.showsConsole {
                VStack(spacing: 0) {
                    if showsRunOutput {
                        ConsoleRowsView(model: model, colors: c)
                    } else {
                        LogView(lines: shownLines, colors: c)
                    }
                    if model.debug.isDebugging { ConsolePrompt(model: model) }
                    bar(c) {
                        ConsoleFilterMenu(model: model)
                        Spacer(minLength: 0)
                        Button { model.clearConsole() } label: {
                            Image(systemName: "trash").font(.system(size: 12)).foregroundStyle(c.secondaryLabel)
                        }
                        .buttonStyle(.plain)
                        .help("Clear Console")
                        .accessibilityLabel("Clear Console")
                        .shellTarget("clear console")
                        DebugHalvesToggles(model: model)
                    }
                }
                .frame(minWidth: 150, maxWidth: .infinity)
                .shellTarget("debug pane")
            }
        }
        .background(c.content)
        .shellTarget("debug area")
    }

    var showsRunOutput: Bool {
        let console = model.debug.consoleFilter == .all ? model.console : model.debug.consoleText
        return !console.isEmpty && (model.debugPane == .console || model.buildLog.isEmpty)
    }

    var shownLines: [String] {
        let console = (model.debug.consoleFilter == .all ? model.console : model.debug.consoleText).replacingOccurrences(of: "\r", with: "")
        if model.debugPane == .console && !console.isEmpty || model.buildLog.isEmpty {
            return console.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        }
        return model.buildLog
    }

    func bar<C: View>(_ c: ShellColors, @ViewBuilder _ content: () -> C) -> some View {
        HStack(spacing: 10) { content() }
            .padding(.horizontal, CGFloat(WorkspaceChrome.bottomBarSideInset))
            .frame(height: CGFloat(WorkspaceChrome.bottomBarHeight))
    }

}

struct LogView: View {
    let lines: [String]
    let colors: ShellColors

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(lines.enumerated()), id: \.offset) { pair in
                        Text(verbatim: pair.element.isEmpty ? " " : pair.element)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(colors.label)
                            .lineLimit(6)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .id(pair.offset)
                    }
                }
                .padding(6)
            }
            .scrollIndicators(.hidden)
            .onChange(of: lines.count) { _, n in
                if n > 0 { proxy.scrollTo(n - 1, anchor: .bottom) }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
