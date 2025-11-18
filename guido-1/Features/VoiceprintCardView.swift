//
//  VoiceprintCardView.swift
//  guido-1
//

import SwiftUI
import AVFoundation

@MainActor
final class VoiceprintEnrollmentViewModel: ObservableObject {
    enum QuietState: Equatable {
        case idle
        case recording
        case failed(db: Double)
        case passed(db: Double)
    }
    
    @Published var quietState: QuietState = .idle
    @Published var isRecordingPhrase = false
    @Published var recordProgress: Double = 0
    @Published var isSaving = false
    @Published var recordedCount = 0
    @Published var errorMessage: String?
    @Published var lastQualityHint: String?
    @Published var isCountdownActive = false
    @Published var countdownRemaining: Int = 0
    
    private let prompts = [
        "Hey Guido, where am I?",
        "What's the best dessert spot near me?"
    ]
    
    private let maxPhrases = 2
    private let service: VoiceprintService
    private let manager: VoiceprintManager
    private var phraseSnippets: [AudioSnippet] = []
    
    init(service: VoiceprintService = .shared, manager: VoiceprintManager = .shared) {
        self.service = service
        self.manager = manager
    }
    
    var totalPrompts: Int { maxPhrases }
    
    var currentPrompt: String {
        let index = min(recordedCount, prompts.count - 1)
        return prompts[index]
    }
    
    var quietCheckPassed: Bool {
        if case .passed = quietState {
            return true
        }
        return false
    }
    
    func startQuietCheck() {
        guard quietState != .recording else { return }
        quietState = .recording
        errorMessage = nil
        Task {
            let result = await service.performQuietCheck()
            await MainActor.run {
                quietState = result.isAcceptable ? .passed(db: result.decibels) : .failed(db: result.decibels)
            }
        }
    }
    
    func recordNextPhrase() {
        guard quietCheckPassed, recordedCount < maxPhrases, !isRecordingPhrase else { return }
        isCountdownActive = true
        countdownRemaining = 3
        isRecordingPhrase = false
        recordProgress = 0
        errorMessage = nil
        lastQualityHint = nil
        Task {
            for k in (1...3).reversed() {
                await MainActor.run { self.countdownRemaining = k }
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
            await MainActor.run {
                self.isCountdownActive = false
                self.isRecordingPhrase = true
            }
            // Start capture and progress concurrently so users speak during the actual recording window
            let uiDuration: TimeInterval = 3.0
            let startedAt = Date()
            async let snippetAsync: AudioSnippet = service.recordPhrase()
            // Drive a smooth progress bar while recording is in-flight
            while true {
                let elapsed = Date().timeIntervalSince(startedAt)
                await MainActor.run { self.recordProgress = min(1.0, elapsed / uiDuration) }
                if elapsed >= uiDuration { break }
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
            let snippet = await snippetAsync
            await MainActor.run {
                self.isRecordingPhrase = false
                self.recordProgress = 1
                if snippet.samples.isEmpty {
                    self.errorMessage = "Couldn't hear anything—try again."
                } else {
                    let quality = self.service.evaluateSpeechQuality(snippet: snippet)
                    if !quality.isAcceptable {
                        self.errorMessage = quality.reason ?? "Please try again."
                        self.lastQualityHint = "Spoken \(String(format: "%.0f%%", quality.voicedFraction * 100)), duration \(String(format: "%.1fs", quality.duration))"
                    } else {
                        self.phraseSnippets.append(snippet)
                        self.recordedCount = min(self.recordedCount + 1, self.maxPhrases)
                        if self.recordedCount == self.maxPhrases {
                            self.finalizeVoiceprint()
                        }
                    }
                }
            }
        }
    }
    
    private func finalizeVoiceprint() {
        guard !isSaving, let payload = service.buildVoiceprint(from: phraseSnippets) else {
            errorMessage = "Something went wrong while building your voiceprint."
            return
        }
        isSaving = true
        Task {
            await manager.saveVoiceprint(payload)
            await MainActor.run {
                self.isSaving = false
            }
        }
    }
    
    func reset() {
        quietState = .idle
        recordedCount = 0
        errorMessage = nil
        phraseSnippets.removeAll()
    }
}

struct VoiceprintCardView: View {
    let step: Int
    let totalSteps: Int
    @ObservedObject var viewModel: VoiceprintEnrollmentViewModel
    let allowRegenerate: Bool
    var onCompletion: () -> Void
    
    @EnvironmentObject private var voiceprintManager: VoiceprintManager
    
    var body: some View {
        LiquidGlassCard(intensity: 0.75, cornerRadius: 24, shadowIntensity: 0.28, enableFloating: false, enableShimmer: true) {
            VStack(alignment: .leading, spacing: 18) {
                OnboardingTitle(
                    iconName: "waveform",
                    iconTint: .blue,
                    title: "Teach Guido your voice",
                    subtitle: "Helps us ignore background chatter.",
                    step: step,
                    total: totalSteps
                )
                content
            }
            .padding(20)
            .frame(height: cardHeight)
            .onChange(of: voiceprintManager.hasVoiceprint) { hasVoiceprint in
                if hasVoiceprint {
                    onCompletion()
                }
            }
        }
        .padding(.horizontal, 6)
        .frame(maxWidth: 520)
    }
    
    private var content: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                quietSection
                Divider().opacity(0.2)
                phraseSection
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
    
    private var quietSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("1. Check your space")
                .font(.system(size: 15, weight: .bold, design: .rounded))
            Text("Find somewhere quiet so Guido can learn your voice.")
                .font(.system(size: 13, weight: .regular, design: .rounded))
                .foregroundColor(.secondary)
            switch viewModel.quietState {
            case .idle:
                primaryButton("Check background", action: viewModel.startQuietCheck)
            case .recording:
                ProgressView("Listening…").font(.system(size: 13, weight: .semibold))
            case .failed(let db):
                VStack(alignment: .leading, spacing: 6) {
                    Text("Too noisy (\(dbString(db)))")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.orange)
                    primaryButton("Try again", action: viewModel.startQuietCheck)
                }
            case .passed(let db):
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill").foregroundColor(.green)
                    Text("Sounds good (\(dbString(db)))")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.green)
                }
            }
        }
    }
    
    private var phraseSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("2. Record 2 sample requests")
                .font(.system(size: 15, weight: .bold, design: .rounded))
            // Dynamic status panel
            VStack(alignment: .leading, spacing: 8) {
                if viewModel.isCountdownActive {
                    HStack(spacing: 10) {
                        ZStack {
                            Circle()
                                .fill(Color.orange.opacity(0.15))
                                .frame(width: 30, height: 30)
                            Text("\(viewModel.countdownRemaining)")
                                .font(.system(size: 15, weight: .bold, design: .rounded))
                                .foregroundColor(.orange)
                        }
                        Text("Get ready…")
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundColor(.secondary)
                    }
                }
                HStack(spacing: 8) {
                    Image(systemName: viewModel.isRecordingPhrase ? "waveform.circle.fill" : "mic.circle")
                        .foregroundColor(viewModel.isRecordingPhrase ? .red : .blue)
                    Text(viewModel.isRecordingPhrase ? "Listening… say: \(examplePrompt(at: viewModel.recordedCount))" : "Next up: \(examplePrompt(at: viewModel.recordedCount))")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if viewModel.isRecordingPhrase {
                    ProgressView(value: viewModel.recordProgress)
                        .progressViewStyle(.linear)
                }
            }
            .padding(10)
            .background(Color.blue.opacity(0.08))
            .cornerRadius(10)
            
            // Checklist
            ForEach(0..<viewModel.totalPrompts, id: \.self) { index in
                HStack(spacing: 8) {
                    Image(systemName: index < viewModel.recordedCount ? "checkmark.circle.fill" : "circle")
                        .foregroundColor(index < viewModel.recordedCount ? .green : Color(.tertiaryLabel))
                    // Avoid duplicating the current prompt; show phrases only for completed items
                    if index < viewModel.recordedCount {
                        Text(examplePrompt(at: index))
                            .font(.system(size: 13, weight: .regular, design: .rounded))
                            .foregroundColor(.secondary)
                    } else if index != viewModel.recordedCount {
                        Text("Pending")
                            .font(.system(size: 13, weight: .regular, design: .rounded))
                            .foregroundColor(Color(.tertiaryLabel))
                    } else {
                        // Current prompt is already shown above as "Next up", keep this row minimal
                        Text("Now")
                            .font(.system(size: 13, weight: .regular, design: .rounded))
                            .foregroundColor(Color(.tertiaryLabel))
                    }
                }
            }
            // Compact two-line status (adapts on success/failure)
            VStack(alignment: .leading, spacing: 2) {
                Text(primaryStatusText)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundColor(primaryStatusColor)
                if let secondary = secondaryStatusText, !secondary.isEmpty {
                    Text(secondary)
                        .font(.system(size: 12, weight: .regular, design: .rounded))
                        .foregroundColor(.secondary)
                }
            }
            if !voiceprintManager.hasVoiceprint || allowRegenerate {
                if viewModel.isSaving {
                    ProgressView("Saving voiceprint…")
                        .font(.system(size: 13, weight: .semibold))
                } else if viewModel.isRecordingPhrase {
                    ProgressView("Recording…")
                        .font(.system(size: 13, weight: .semibold))
                } else if viewModel.recordedCount < viewModel.totalPrompts {
                    primaryButton("Record phrase \(viewModel.recordedCount + 1) of \(viewModel.totalPrompts)", action: viewModel.recordNextPhrase)
                        .disabled(!viewModel.quietCheckPassed)
                        .opacity(viewModel.quietCheckPassed ? 1 : 0.5)
                } else if allowRegenerate && viewModel.recordedCount >= viewModel.totalPrompts && !viewModel.isSaving {
                    // Offer to restart if user wants to regenerate again
                    primaryButton("Start over", action: viewModel.reset)
                }
                if allowRegenerate && voiceprintManager.hasVoiceprint {
                    Text("Regenerating will replace your existing voiceprint.")
                        .font(.system(size: 12, weight: .regular, design: .rounded))
                        .foregroundColor(.secondary)
                }
            } else {
                completionBadge
            }
            // Error details folded into compact status lines above
        }
    }
    
    // MARK: - Compact Status Helpers
    private var primaryStatusText: String {
        if let err = viewModel.errorMessage, !err.isEmpty {
            return "We didn’t catch enough—try again."
        }
        if viewModel.recordedCount == viewModel.totalPrompts && !voiceprintManager.hasVoiceprint {
            return "Captured \(viewModel.recordedCount)/\(viewModel.totalPrompts) — ready to save."
        }
        if viewModel.recordedCount > 0 {
            return "Captured \(viewModel.recordedCount)/\(viewModel.totalPrompts) — sounds good."
        }
        return ""
    }
    
    private var primaryStatusColor: Color {
        if viewModel.errorMessage != nil { return .orange }
        return Color(.secondaryLabel)
    }
    
    private var secondaryStatusText: String? {
        if viewModel.errorMessage != nil {
            return "Move closer, speak a bit louder and clearly, and finish the sentence."
        }
        if let hint = viewModel.lastQualityHint, !hint.isEmpty {
            return hint
        }
        return nil
    }
    
    private var completionBadge: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.shield.fill")
                .foregroundColor(.green)
            Text("Voiceprint saved—Guido will use it every time you connect.")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundColor(.green)
        }
        .padding(10)
        .background(Color.green.opacity(0.12))
        .cornerRadius(12)
    }
    
    private func examplePrompt(at index: Int) -> String {
        switch index {
        case 0:
            return "“Hey Guido, where am I?”"
        case 1:
            return "“What's the best dessert spot near me?”"
        default:
            return "“What's the best dessert spot near me?”"
        }
    }
    
    private func primaryButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Spacer()
                Text(title)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .padding(.vertical, 10)
                Spacer()
            }
        }
        .buttonStyle(.plain)
        .background(Color.blue.opacity(0.12))
        .cornerRadius(12)
    }
    
    private var cardHeight: CGFloat {
        let screenHeight = UIScreen.main.bounds.height
        if screenHeight < 700 { return 420 }
        if screenHeight > 850 { return 460 }
        return 440
    }
    
    private func dbString(_ db: Double) -> String {
        String(format: "%.1f dB", db)
    }
}

