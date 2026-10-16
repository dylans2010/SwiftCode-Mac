//
//  AssistSpeechUI.swift
//  SwiftCode
//
//  Native speech recognition modal/sheet view for Assist.
//  Uses Apple's native SFSpeechRecognizer and AVAudioEngine to record audio,
//  provide real-time streaming transcription, and send transcribed prompts
//  directly to Assist.
//

import SwiftUI
import Speech
import AVFoundation

public struct AssistSpeechUI: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var manager = AssistManager.shared

    public var onSend: ((String) -> Void)?
    public var onInsert: ((String) -> Void)?

    @State private var transcribedText: String = ""
    @State private var isRecording: Bool = false
    @State private var isAuthorized: Bool = false
    @State private var errorMessage: String? = nil
    @State private var waveAnimation: Double = 1.0

    @State private var speechRecognizer = SFSpeechRecognizer(locale: Locale.current)
    @State private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    @State private var recognitionTask: SFSpeechRecognitionTask?
    @State private var audioEngine = AVAudioEngine()

    public init(onSend: ((String) -> Void)? = nil, onInsert: ((String) -> Void)? = nil) {
        self.onSend = onSend
        self.onInsert = onInsert
    }

    public var body: some View {
        VStack(spacing: 16) {
            // Top Header Bar
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "mic.fill")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Color.accentColor)

                    Text("Voice Assistant Prompt")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                }

                Spacer()

                Button {
                    stopRecording()
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            Divider()

            // Main Transcription Display Area
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    if transcribedText.isEmpty {
                        Text(isRecording ? "Listening... Speak your prompt clearly." : "Tap the microphone to start recording your prompt.")
                            .font(.system(size: 13, weight: .regular))
                            .foregroundStyle(.secondary)
                            .italic()
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, 12)
                    } else {
                        Text(transcribedText)
                            .font(.system(size: 14, weight: .medium, design: .rounded))
                            .foregroundStyle(.primary)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(12)
            }
            .frame(height: 140)
            .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isRecording ? Color.accentColor.opacity(0.5) : Color.clear, lineWidth: 1.5)
            )

            if let error = errorMessage {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.red)
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            // Audio Visualizer Waveform / Pulsating Mic Trigger
            ZStack {
                Circle()
                    .fill(isRecording ? Color.red.opacity(0.15) : Color.accentColor.opacity(0.12))
                    .frame(width: 80, height: 80)
                    .scaleEffect(isRecording ? waveAnimation : 1.0)
                    .animation(isRecording ? .easeInOut(duration: 0.8).repeatForever(autoreverses: true) : .default, value: waveAnimation)

                Button {
                    if isRecording {
                        stopRecording()
                    } else {
                        startRecording()
                    }
                } label: {
                    ZStack {
                        Circle()
                            .fill(isRecording ? Color.red : Color.accentColor)
                            .frame(width: 56, height: 56)
                            .shadow(color: isRecording ? .red.opacity(0.4) : .accentColor.opacity(0.4), radius: 6, y: 3)

                        Image(systemName: isRecording ? "square.fill" : "mic.fill")
                            .font(.system(size: 22, weight: .bold))
                            .foregroundStyle(.white)
                    }
                }
                .buttonStyle(.plain)
            }
            .padding(.vertical, 8)

            // Action Buttons Footer
            HStack(spacing: 12) {
                Button {
                    let text = transcribedText.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !text.isEmpty else { return }
                    stopRecording()
                    if let onInsert {
                        onInsert(text)
                    }
                    dismiss()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "square.and.pencil")
                            .font(.system(size: 11))
                        Text("Insert in Prompt")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 7)
                    .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                .disabled(transcribedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                Button {
                    let text = transcribedText.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !text.isEmpty else { return }
                    stopRecording()
                    if let onSend {
                        onSend(text)
                    } else {
                        Task {
                            await manager.sendMessage(text)
                        }
                    }
                    dismiss()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "paperplane.fill")
                            .font(.system(size: 11))
                        Text("Send to Assist")
                            .font(.system(size: 12, weight: .bold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 7)
                    .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 8))
                    .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
                .disabled(transcribedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(18)
        .frame(width: 420, height: 380)
        .onAppear {
            requestPermissions()
        }
        .onDisappear {
            stopRecording()
        }
    }

    // MARK: - Speech Recognition Engine Lifecycle

    private func requestPermissions() {
        SFSpeechRecognizer.requestAuthorization { status in
            DispatchQueue.main.async {
                switch status {
                case .authorized:
                    self.isAuthorized = true
                    self.errorMessage = nil
                case .denied:
                    self.isAuthorized = false
                    self.errorMessage = "Speech recognition permission was denied. Enable it in macOS System Settings."
                case .restricted:
                    self.isAuthorized = false
                    self.errorMessage = "Speech recognition is restricted on this device."
                case .notDetermined:
                    self.isAuthorized = false
                    self.errorMessage = "Speech recognition permission not determined."
                @unknown default:
                    self.isAuthorized = false
                }
            }
        }

        #if os(macOS)
        AVCaptureDevice.requestAccess(for: .audio) { granted in
            if !granted {
                DispatchQueue.main.async {
                    self.errorMessage = "Microphone permission was denied. Enable it in macOS System Settings."
                }
            }
        }
        #endif
    }

    private func startRecording() {
        guard isAuthorized else {
            requestPermissions()
            return
        }

        if audioEngine.isRunning {
            audioEngine.stop()
            recognitionRequest?.endAudio()
        }

        recognitionTask?.cancel()
        recognitionTask = nil

        #if os(iOS)
        let audioSession = AVAudioSession.sharedInstance()
        try? audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
        try? audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        #endif

        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest = recognitionRequest else { return }

        recognitionRequest.shouldReportPartialResults = true

        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)

        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
            self.recognitionRequest?.append(buffer)
        }

        audioEngine.prepare()
        do {
            try audioEngine.start()
            isRecording = true
            errorMessage = nil
            waveAnimation = 1.35

            recognitionTask = speechRecognizer?.recognitionTask(with: recognitionRequest) { result, error in
                if let result = result {
                    DispatchQueue.main.async {
                        self.transcribedText = result.bestTranscription.formattedString
                    }
                }

                if error != nil || (result?.isFinal ?? false) {
                    DispatchQueue.main.async {
                        self.stopRecording()
                    }
                }
            }
        } catch {
            errorMessage = "Could not start audio engine: \(error.localizedDescription)"
            stopRecording()
        }
    }

    private func stopRecording() {
        guard isRecording else { return }
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()

        recognitionRequest = nil
        recognitionTask = nil
        isRecording = false
        waveAnimation = 1.0
    }
}
