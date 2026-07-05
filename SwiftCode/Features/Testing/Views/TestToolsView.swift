import SwiftUI

public struct TestToolsView: View {
    let project: Project
    @StateObject private var testManager = TestToolsManager.shared
    @StateObject private var coverageManager = TestCoverageManager()
    @State private var selectedCategory: TestCategory? = nil
    @State private var searchText = ""

    public init(project: Project) {
        self.project = project
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                Color(red: 0.05, green: 0.05, blue: 0.07).ignoresSafeArea()

                VStack(spacing: 0) {
                    summaryDashboard

                    categoryPicker

                    List {
                        if testManager.isRunning {
                            HStack {
                                ProgressView().padding(.trailing, 8)
                                Text("Running Tests...")
                            }
                        }

                        ForEach(filteredTests) { result in
                            TestResultRow(result: result)
                        }
                    }
                    .listStyle(.insetGrouped)
                    .scrollContentBackground(.hidden)
                }
            }
            .navigationTitle("Test Center")
            .searchable(text: $searchText, prompt: "Search tests...")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        Task { await testManager.runParallelTests(forProject: project) }
                        coverageManager.calculateCoverage(for: project)
                    } label: {
                        Label("Run All", systemImage: "play.fill")
                    }
                    .disabled(testManager.isRunning)
                }
            }
        }
    }

    private var summaryDashboard: some View {
        HStack(spacing: 20) {
            VStack {
                Text("\(testManager.results.filter { $0.status == .success }.count)")
                    .font(.title2.bold()).foregroundStyle(.green)
                Text("Passed").font(.caption).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)

            VStack {
                Text("\(testManager.results.filter { $0.status == .failed }.count)")
                    .font(.title2.bold()).foregroundStyle(.red)
                Text("Failed").font(.caption).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)

            VStack {
                Text(String(format: "%.1f%%", coverageManager.projectCoverage * 100))
                    .font(.title2.bold()).foregroundStyle(.blue)
                Text("Coverage").font(.caption).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
        }
        .padding()
        .background(Color.white.opacity(0.05))
    }

    private var categoryPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack {
                Button("All") { selectedCategory = nil }
                    .buttonStyle(.bordered).tint(selectedCategory == nil ? .blue : .secondary)

                ForEach(TestCategory.allCases, id: \.self) { cat in
                    Button(cat.rawValue) { selectedCategory = cat }
                        .buttonStyle(.bordered).tint(selectedCategory == cat ? .blue : .secondary)
                }
            }
            .padding()
        }
    }

    private var filteredTests: [TestResult] {
        testManager.results.filter { result in
            let catMatch = selectedCategory == nil || result.category == selectedCategory
            let textMatch = searchText.isEmpty || result.name.localizedCaseInsensitiveContains(searchText)
            return catMatch && textMatch
        }
    }
}

struct TestResultRow: View {
    let result: TestResult

    var body: some View {
        HStack {
            Image(systemName: result.status == .success ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(result.status == .success ? .green : .red)

            VStack(alignment: .leading) {
                Text(result.name).font(.headline)
                HStack {
                    Text(result.category.rawValue).font(.caption).foregroundStyle(.blue)
                    Text("•").foregroundStyle(.secondary)
                    Text(String(format: "%.2fs", result.executionTime)).font(.caption).foregroundStyle(.secondary)
                }
            }

            Spacer()

            if let error = result.errorMessage {
                Image(systemName: "info.circle").foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}
