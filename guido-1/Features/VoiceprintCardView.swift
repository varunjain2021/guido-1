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
    @Published var isSaving = false
    @Published var recordedCount = 0
    @Published var errorMessage: String?
    
    private let prompts = [
        "Hey Guido, where am I?",
        "What's the best dessert spot near me?",
        "Are there any available e-bikes nearby?",
        "Can you read menus nearby and tell me about gluten-free options?"
    ]
    
    private let maxPhrases = 3
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
        isRecordingPhrase = true
        errorMessage = nil
        Task {
            let snippet = await service.recordPhrase()
            await MainActor.run {
                self.isRecordingPhrase = false
                if snippet.samples.isEmpty {
                    self.errorMessage = "Couldn't hear anything—try again."
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
        VStack(alignment: .leading, spacing: 18) {
            quietSection
            Divider().opacity(0.2)
            phraseSection
            Divider().opacity(0.2)
            privacySection
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
            Text("2. Record 3 sample requests")
                .font(.system(size: 15, weight: .bold, design: .rounded))
            Text("Say each phrase naturally. This stays private and only becomes a lightweight fingerprint.")
                .font(.system(size: 13, weight: .regular, design: .rounded))
                .foregroundColor(.secondary)
            ForEach(0..<viewModel.totalPrompts, id: \.self) { index in
                HStack(spacing: 8) {
                    Image(systemName: index < viewModel.recordedCount ? "checkmark.circle.fill" : "circle")
                        .foregroundColor(index < viewModel.recordedCount ? .green : Color(.tertiaryLabel))
                    Text(examplePrompt(at: index))
                        .font(.system(size: 13, weight: .regular, design: .rounded))
                        .foregroundColor(.secondary)
                }
            }
            if !voiceprintManager.hasVoiceprint {
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
                }
            } else {
                completionBadge
            }
            if let error = viewModel.errorMessage {
                Text(error)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundColor(.orange)
            }
        }
    }
    
    private var privacySection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Your voiceprint isn’t raw audio.")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
            Text("We store a short fingerprint (numbers only) with row-level security. You can regenerate it anytime.")
                .font(.system(size: 12, weight: .regular, design: .rounded))
                .foregroundColor(.secondary)
        }
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
        case 2:
            return "“Are there any available e-bikes nearby?”"
        default:
            return "“Can you check menus nearby for gluten-free options?”"
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

