//
//  AuthenticationView.swift
//  guido-1
//
//  Created by AI Assistant on 1/8/25.
//  Beautiful authentication view with liquid glass effects
//

import SwiftUI

struct AuthenticationView: View {
    @EnvironmentObject var authService: SupabaseAuthService
    @State private var isSignUp = false
    @State private var email = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var fullName = ""
    @State private var showingAlert = false
    @State private var alertMessage = ""
    @State private var isPasswordVisible = false
    @State private var isConfirmPasswordVisible = false
    
    var body: some View {
        GeometryReader { geometry in
                    ZStack {
            // Croatian Beach adaptive canvas background
            AdaptiveCanvas(
                userSpeaking: false,
                guidoSpeaking: false,
                conversationState: .idle,
                audioLevel: 0.0,
                testEnvironment: nil
            )
                
                // Main content
                VStack(spacing: 0) {
                    Spacer()
                    
                    // Logo and title section
                    logoSection
                        .padding(.bottom, 60)
                    
                    // Authentication form
                    authFormSection
                        .padding(.horizontal, 32)
                    
                    Spacer()
                    
                    // Footer
                    footerSection
                        .padding(.bottom, 50)
                }
            }
        }
        .ignoresSafeArea()
        .alert("Authentication", isPresented: $showingAlert) {
            Button("OK") { }
        } message: {
            Text(alertMessage)
        }
    }
    
    // MARK: - Logo Section
    
    private var logoSection: some View {
        VStack(spacing: CroatianBeachSpacing.medium) {
            // Croatian Beach app icon with sea glass effect
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [
                                CroatianBeachColors.seafoamMist.opacity(0.8),
                                CroatianBeachColors.crystalWater.opacity(0.3)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 120, height: 120)
                    .overlay(
                        Circle()
                            .stroke(
                                LinearGradient(
                                    colors: [
                                        CroatianBeachColors.crystalWater.opacity(0.6),
                                        CroatianBeachColors.seaFoam.opacity(0.3)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 2
                            )
                    )
                
                Image(systemName: "globe.americas.fill")
                    .font(.system(size: 50))
                    .foregroundColor(CroatianBeachColors.deepEmerald)
            }
            
            // App name with Croatian Beach typography
            Text("Guido")
                .font(CroatianBeachTypography.largeTitle)
                .foregroundColor(CroatianBeachColors.deepEmerald)
            
            Text("Your AI Travel Companion")
                .font(CroatianBeachTypography.body)
                .foregroundColor(CroatianBeachColors.emeraldShade)
        }
    }
    
    // MARK: - Auth Form Section
    
    private var authFormSection: some View {
        VStack(spacing: 24) {
            // Form container with liquid glass effect
            VStack(spacing: 20) {
                // Toggle between Sign In / Sign Up
                authToggleSection
                
                // Form fields
                authFieldsSection
                
                // Action buttons
                authButtonsSection
            }
            .padding(32)
            .background(
                LiquidGlassCard {
                    Color.clear
                }
            )
        }
    }
    
    private var authToggleSection: some View {
        HStack(spacing: 0) {
            Button(action: { withAnimation(.spring()) { isSignUp = false } }) {
                Text("Sign In")
                    .font(CroatianBeachTypography.body)
                    .foregroundColor(isSignUp ? CroatianBeachColors.emeraldShade.opacity(0.6) : CroatianBeachColors.deepEmerald)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(isSignUp ? Color.clear : CroatianBeachColors.seafoamMist.opacity(0.8))
                    )
            }
            
            Button(action: { withAnimation(.spring()) { isSignUp = true } }) {
                Text("Sign Up")
                    .font(CroatianBeachTypography.body)
                    .foregroundColor(isSignUp ? CroatianBeachColors.deepEmerald : CroatianBeachColors.emeraldShade.opacity(0.6))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(isSignUp ? CroatianBeachColors.seafoamMist.opacity(0.8) : Color.clear)
                    )
            }
        }
        .padding(4)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.black.opacity(0.2))
        )
    }
    
    private var authFieldsSection: some View {
        VStack(spacing: 16) {
            // Full name field (only for sign up)
            if isSignUp {
                LiquidGlassTextField(
                    text: $fullName,
                    placeholder: "Full Name",
                    icon: "person.fill"
                )
                .transition(.asymmetric(
                    insertion: .move(edge: .top).combined(with: .opacity),
                    removal: .move(edge: .top).combined(with: .opacity)
                ))
            }
            
            // Email field
            LiquidGlassTextField(
                text: $email,
                placeholder: "Email",
                icon: "envelope.fill",
                keyboardType: .emailAddress
            )
            
            // Password field
            LiquidGlassTextField(
                text: $password,
                placeholder: "Password",
                icon: "lock.fill",
                isSecure: !isPasswordVisible,
                trailingIcon: isPasswordVisible ? "eye.slash.fill" : "eye.fill",
                trailingAction: { isPasswordVisible.toggle() }
            )
            
            // Confirm password field (only for sign up)
            if isSignUp {
                LiquidGlassTextField(
                    text: $confirmPassword,
                    placeholder: "Confirm Password",
                    icon: "lock.fill",
                    isSecure: !isConfirmPasswordVisible,
                    trailingIcon: isConfirmPasswordVisible ? "eye.slash.fill" : "eye.fill",
                    trailingAction: { isConfirmPasswordVisible.toggle() }
                )
                .transition(.asymmetric(
                    insertion: .move(edge: .bottom).combined(with: .opacity),
                    removal: .move(edge: .bottom).combined(with: .opacity)
                ))
            }
        }
    }
    
    private var authButtonsSection: some View {
        VStack(spacing: 16) {
            // Primary action button
            Button(action: performPrimaryAction) {
                HStack {
                    if authService.isLoading {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .scaleEffect(0.8)
                    } else {
                        Text(isSignUp ? "Create Account" : "Sign In")
                            .font(.system(size: 16, weight: .semibold))
                    }
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(
                    LinearGradient(
                        colors: [Color.blue, Color.cyan],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.white.opacity(0.2), lineWidth: 1)
                )
            }
            .disabled(authService.isLoading || !isFormValid)
            .opacity(isFormValid ? 1.0 : 0.6)
            
            // Divider
            HStack {
                Rectangle()
                    .fill(Color.white.opacity(0.3))
                    .frame(height: 1)
                
                Text("or")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white.opacity(0.7))
                    .padding(.horizontal, 16)
                
                Rectangle()
                    .fill(Color.white.opacity(0.3))
                    .frame(height: 1)
            }
            
            // Google Sign In button
            Button(action: signInWithGoogle) {
                HStack(spacing: 12) {
                    Image(systemName: "globe")
                        .font(.system(size: 18, weight: .medium))
                    
                    Text("Continue with Google")
                        .font(.system(size: 16, weight: .medium))
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color.white.opacity(0.1))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(Color.white.opacity(0.3), lineWidth: 1)
                        )
                )
            }
            .disabled(authService.isLoading)
            
            // Forgot password (only for sign in)
            if !isSignUp {
                Button("Forgot Password?") {
                    // TODO: Implement forgot password
                }
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.white.opacity(0.8))
                .padding(.top, 8)
            }
        }
    }
    
    // MARK: - Footer Section
    
    private var footerSection: some View {
        VStack(spacing: 12) {
            Text("By continuing, you agree to our")
                .font(.system(size: 12))
                .foregroundColor(.white.opacity(0.6))
            
            HStack(spacing: 4) {
                Button("Terms of Service") {
                    // TODO: Show terms
                }
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.white.opacity(0.8))
                
                Text("and")
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.6))
                
                Button("Privacy Policy") {
                    // TODO: Show privacy policy
                }
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.white.opacity(0.8))
            }
        }
    }
    
    // MARK: - Computed Properties
    
    private var isFormValid: Bool {
        if isSignUp {
            return !email.isEmpty && 
                   !password.isEmpty && 
                   !confirmPassword.isEmpty &&
                   !fullName.isEmpty &&
                   password == confirmPassword &&
                   password.count >= 6 &&
                   email.contains("@")
        } else {
            return !email.isEmpty && 
                   !password.isEmpty &&
                   email.contains("@")
        }
    }
    
    // MARK: - Actions
    
    private func performPrimaryAction() {
        Task {
            do {
                if isSignUp {
                    _ = try await authService.signUp(
                        email: email,
                        password: password,
                        fullName: fullName.isEmpty ? nil : fullName
                    )
                } else {
                    _ = try await authService.signIn(
                        email: email,
                        password: password
                    )
                }
            } catch {
                alertMessage = error.localizedDescription
                showingAlert = true
            }
        }
    }
    
    private func signInWithGoogle() {
        Task {
            do {
                _ = try await authService.signInWithGoogle()
            } catch {
                alertMessage = error.localizedDescription
                showingAlert = true
            }
        }
    }
}

// MARK: - Liquid Glass Text Field

struct LiquidGlassTextField: View {
    @Binding var text: String
    let placeholder: String
    let icon: String
    var keyboardType: UIKeyboardType = .default
    var isSecure: Bool = false
    var trailingIcon: String?
    var trailingAction: (() -> Void)?
    
    @FocusState private var isFocused: Bool
    
    var body: some View {
        HStack(spacing: 12) {
            // Leading icon
            Image(systemName: icon)
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.white.opacity(0.7))
                .frame(width: 20)
            
            // Text field
            Group {
                if isSecure {
                    SecureField(placeholder, text: $text)
                } else {
                    TextField(placeholder, text: $text)
                }
            }
            .font(.system(size: 16, weight: .medium))
            .foregroundColor(.white)
            .keyboardType(keyboardType)
            .focused($isFocused)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            
            // Trailing icon
            if let trailingIcon = trailingIcon {
                Button(action: { trailingAction?() }) {
                    Image(systemName: trailingIcon)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.white.opacity(0.7))
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white.opacity(isFocused ? 0.15 : 0.1))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(
                            isFocused ? Color.white.opacity(0.4) : Color.white.opacity(0.2),
                            lineWidth: 1
                        )
                )
        )
        .animation(.easeInOut(duration: 0.2), value: isFocused)
    }
}



// MARK: - Animated Background

struct AnimatedBackgroundView: View {
    @State private var animateGradient = false
    
    var body: some View {
        LinearGradient(
            colors: [
                Color.blue.opacity(0.8),
                Color.purple.opacity(0.8),
                Color.pink.opacity(0.8),
                Color.orange.opacity(0.8)
            ],
            startPoint: animateGradient ? .topLeading : .bottomTrailing,
            endPoint: animateGradient ? .bottomTrailing : .topLeading
        )
        .ignoresSafeArea()
        .onAppear {
            withAnimation(.easeInOut(duration: 3).repeatForever(autoreverses: true)) {
                animateGradient.toggle()
            }
        }
    }
}

// MARK: - Preview

#Preview {
    AuthenticationView()
}
