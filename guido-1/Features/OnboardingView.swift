//
//  OnboardingView.swift
//  guido-1
//

import SwiftUI

struct OnboardingView: View {
    @EnvironmentObject var appState: AppState
    @State private var email: String = ""
    @State private var password: String = ""
    @State private var isRegistering: Bool = false
    @State private var isBusy: Bool = false
    @State private var errorMessage: String?
    
    var body: some View {
        ZStack {
            VStack(spacing: 20) {
                // Header card
                LiquidGlassCard(intensity: 0.85, cornerRadius: 28, shadowIntensity: 0.35, enableFloating: true) {
                    VStack(spacing: 8) {
                        Text("Welcome to Guido")
                            .font(.system(size: 24, weight: .bold, design: .rounded))
                            .foregroundColor(.primary)
                        Text("Sign in to continue")
                            .font(.system(size: 14, weight: .medium, design: .rounded))
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 18)
                }
                .padding(.horizontal, 24)
                
                // Google sign-in
                LiquidGlassCard(intensity: 0.7, cornerRadius: 20, shadowIntensity: 0.25) {
                    Button(action: { Task { await signInWithGoogle() } }) {
                        HStack(spacing: 12) {
                            Image(systemName: "g.circle.fill")
                                .font(.system(size: 22, weight: .semibold))
                                .foregroundColor(.primary)
                            Text("Continue with Google")
                                .font(.system(size: 16, weight: .semibold, design: .rounded))
                                .foregroundColor(.primary)
                            Spacer()
                        }
                        .padding(.horizontal, 18)
                        .padding(.vertical, 14)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
                .padding(.horizontal, 24)
                
                // Email/password card
                LiquidGlassCard(intensity: 0.7, cornerRadius: 20, shadowIntensity: 0.25) {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            SegmentedToggle(isRegistering: $isRegistering)
                        }
                        .padding(.bottom, 4)
                        
                        TextField("Email", text: $email)
                            .textContentType(.emailAddress)
                            .keyboardType(.emailAddress)
                            .autocapitalization(.none)
                            .disableAutocorrection(true)
                            .padding(12)
                            .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.05)))
                        
                        SecureField("Password", text: $password)
                            .textContentType(.password)
                            .padding(12)
                            .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.05)))
                        
                        if let errorMessage {
                            Text(errorMessage)
                                .font(.system(size: 12, weight: .medium, design: .rounded))
                                .foregroundColor(.red)
                        }
                        
                        Button(action: { Task { await submitEmailPassword() } }) {
                            HStack {
                                if isBusy {
                                    ProgressView()
                                        .progressViewStyle(CircularProgressViewStyle())
                                }
                                Text(isRegistering ? "Create account" : "Sign in")
                                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                                Spacer()
                                Image(systemName: "arrow.right")
                            }
                            .foregroundColor(.primary)
                            .padding(.horizontal, 18)
                            .padding(.vertical, 12)
                        }
                        .disabled(isBusy || email.isEmpty || password.count < 6)
                        .buttonStyle(PlainButtonStyle())
                    }
                    .padding(16)
                }
                .padding(.horizontal, 24)
                
                Spacer()
            }
            .padding(.top, 60)
            .padding(.bottom, 40)
        }
    }
    
    private func signInWithGoogle() async {
        isBusy = true
        errorMessage = nil
        let result = await appState.signInWithGoogle()
        isBusy = false
        if case .failure(let error) = result {
            errorMessage = error.localizedDescription
        }
    }
    
    private func submitEmailPassword() async {
        isBusy = true
        errorMessage = nil
        let result: Result<Void, Error>
        if isRegistering {
            result = await appState.signUp(email: email, password: password)
        } else {
            result = await appState.signIn(email: email, password: password)
        }
        isBusy = false
        if case .failure(let error) = result {
            errorMessage = error.localizedDescription
        }
    }
}

private struct SegmentedToggle: View {
    @Binding var isRegistering: Bool
    
    var body: some View {
        HStack(spacing: 6) {
            segment(title: "Sign in", active: !isRegistering) {
                withAnimation(.easeInOut(duration: 0.2)) { isRegistering = false }
            }
            segment(title: "Create account", active: isRegistering) {
                withAnimation(.easeInOut(duration: 0.2)) { isRegistering = true }
            }
        }
    }
    
    private func segment(title: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundColor(active ? .white : .primary)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(active ? Color.blue : Color.clear)
                )
        }
        .buttonStyle(PlainButtonStyle())
    }
}


