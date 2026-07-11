import SwiftUI

/// The central view container that handles zooming, scaling, and placing the interactive preview frames.
public struct PreviewCanvasView: View {
    @Environment(PreviewManager.self) private var previewManager

    public var body: some View {
        GeometryReader { proxy in
            VStack {
                if previewManager.isCompiling {
                    VStack(spacing: 12) {
                        ProgressView()
                            .scaleEffect(1.2)
                        Text("Compiling SwiftUI View...")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let session = previewManager.activeSession, session.status == .failed, let error = session.error {
                    // Compilation error panel
                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.red)
                                .font(.title)
                            Text("Preview Compilation Failed")
                                .font(.headline)
                        }

                        Text(error.localizedDescription)
                            .font(.system(.body, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .padding()
                            .background(Color.black.opacity(0.2))
                            .clipShape(RoundedRectangle(cornerRadius: 6))

                        Button(action: {
                            Task {
                                await previewManager.triggerReload()
                            }
                        }) {
                            Label("Try Again", systemImage: "arrow.clockwise")
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .padding(24)
                    .frame(maxWidth: 450)
                    .background(Color(NSColor.controlBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .shadow(radius: 10)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    // Render Active Preview Device Frame
                    let config = previewManager.configuration
                    let baseDimensions = PreviewRenderer.shared.resolveDeviceDimensions(
                        name: config.deviceName,
                        orientation: config.orientation
                    )

                    let layout = PreviewRenderer.shared.calculateScaledFrame(
                        deviceWidth: baseDimensions.width,
                        deviceHeight: baseDimensions.height,
                        containerWidth: proxy.size.width - 60,
                        containerHeight: proxy.size.height - 60,
                        zoomScale: config.zoomScale
                    )

                    PreviewDeviceFrameView(
                        deviceName: config.deviceName,
                        orientation: config.orientation,
                        style: config.interfaceStyle,
                        showSafeArea: config.showSafeArea,
                        viewSize: CGSize(width: baseDimensions.width, height: baseDimensions.height)
                    ) {
                        // Render target preview content
                        VStack {
                            Spacer()
                            Image(systemName: "sparkles")
                                .font(.system(size: 32))
                                .foregroundStyle(.orange)

                            Text(previewManager.selectedPreview?.previewName ?? "SwiftUI Preview")
                                .font(.title3.bold())
                                .padding(.top, 4)

                            Text("Active Canvas Session Running")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            Spacer()
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(config.interfaceStyle == .dark ? Color(red: 0.1, green: 0.1, blue: 0.12) : Color.white)
                        .foregroundStyle(config.interfaceStyle == .dark ? .white : .black)
                    }
                    .frame(width: layout.width, height: layout.height)
                    .scaleEffect(layout.scale)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
    }
}
