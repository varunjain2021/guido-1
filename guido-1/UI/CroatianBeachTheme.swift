import SwiftUI

// MARK: - Croatian Beach Design System

/// Tool status for visual indicators
enum ToolStatus {
    case idle
    case listening
    case thinking
    case searching
    case lookingAround
    
    var iconName: String {
        switch self {
        case .idle:
            return "mic.fill"
        case .listening:
            return "waveform"
        case .thinking:
            return "brain.head.profile"
        case .searching:
            return "magnifyingglass"
        case .lookingAround:
            return "location.viewfinder"
        }
    }
    
    var color: Color {
        switch self {
        case .idle:
            return CroatianBeachColors.emeraldShade
        case .listening:
            return CroatianBeachColors.crystalWater
        case .thinking:
            return CroatianBeachColors.seaFoam
        case .searching:
            return CroatianBeachColors.deepWater
        case .lookingAround:
            return CroatianBeachColors.crystalWater
        }
    }
}

/// Croatian Beach Color Palette - Deep emerald waters and crystalline shores
struct CroatianBeachColors {
    // Primary Colors
    static let deepEmerald = Color(red: 0.05, green: 0.31, blue: 0.24)      // #0D4F3C - Primary text, deep forest green
    static let emeraldShade = Color(red: 0.11, green: 0.42, blue: 0.31)     // #1B6B4F - Secondary text, medium emerald
    static let seaFoam = Color(red: 0.18, green: 0.55, blue: 0.34)          // #2E8B57 - Accent elements, sea green
    static let crystalWater = Color(red: 0.25, green: 0.88, blue: 0.82)     // #40E0D0 - Discovery moments, turquoise
    static let beachSand = Color(red: 0.96, green: 0.97, blue: 0.94)        // #F5F7F0 - Background, warm off-white
    static let seafoamMist = Color(red: 0.91, green: 0.96, blue: 0.91)      // #E8F5E8 - Cards/surfaces, light green tint
    static let deepWater = Color(red: 0.07, green: 0.31, blue: 0.07)        // #134E13 - Headers, darkest green
}

/// Typography system for Croatian Beach theme
struct CroatianBeachTypography {
    static let largeTitle = Font.system(size: 28, weight: .bold, design: .rounded)
    static let title = Font.system(size: 22, weight: .semibold, design: .rounded)
    static let body = Font.system(size: 16, weight: .regular, design: .rounded)
    static let caption = Font.system(size: 14, weight: .regular, design: .rounded)
    static let voiceState = Font.system(size: 12, weight: .medium, design: .rounded)
}

/// Spacing system for consistent layout
struct CroatianBeachSpacing {
    static let micro: CGFloat = 4
    static let small: CGFloat = 8
    static let medium: CGFloat = 16
    static let large: CGFloat = 24
    static let xlarge: CGFloat = 32
    static let voiceHub: CGFloat = 120 // Large voice circle
}

/// Animations for discovery moments
struct CroatianBeachAnimations {
    /// Gentle breathing pulse for listening state
    static let breathingPulse = Animation.easeInOut(duration: 1.2).repeatForever(autoreverses: true)
    
    /// Discovery burst for finding places
    static let discoveryBurst = Animation.easeOut(duration: 0.6).repeatCount(3, autoreverses: true)
    
    /// Smooth transitions between states
    static let stateTransition = Animation.easeInOut(duration: 0.8)
    
    /// Card appearance animation
    static let cardAppear = Animation.spring(dampingFraction: 0.8, blendDuration: 0.5)
}

// MARK: - Custom Views with Croatian Beach Styling

/// Large voice interaction hub with Croatian beach styling
struct CroatianVoiceHub: View {
    let isListening: Bool
    let isActive: Bool
    let voiceState: String
    let action: () -> Void
    
    private var circleGradient: LinearGradient {
        if isListening {
            return LinearGradient(
                colors: [CroatianBeachColors.crystalWater, CroatianBeachColors.seaFoam],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        } else {
            return LinearGradient(
                colors: [CroatianBeachColors.seafoamMist, CroatianBeachColors.beachSand],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }
    
    var body: some View {
        VStack(spacing: CroatianBeachSpacing.medium) {
            // Voice interaction circle
            Button(action: action) {
                ZStack {
                    // Outer breathing ring when listening
                    if isListening {
                        Circle()
                            .stroke(CroatianBeachColors.seaFoam.opacity(0.3), lineWidth: 8)
                            .frame(width: 140, height: 140)
                            .scaleEffect(isListening ? 1.1 : 1.0)
                            .opacity(isListening ? 0.7 : 1.0)
                            .animation(CroatianBeachAnimations.breathingPulse, value: isListening)
                    }
                    
                    // Main circle with gradient
                    Circle()
                        .fill(circleGradient)
                        .opacity(isListening ? 0.9 : 1.0)
                        .frame(width: CroatianBeachSpacing.voiceHub, height: CroatianBeachSpacing.voiceHub)
                        .overlay(
                            Image(systemName: isListening ? "waveform" : "mic.fill")
                                .font(.system(size: 40, weight: .medium))
                                .foregroundColor(isListening ? CroatianBeachColors.deepWater : CroatianBeachColors.emeraldShade)
                        )
                        .shadow(
                            color: isListening ? CroatianBeachColors.crystalWater.opacity(0.4) : CroatianBeachColors.seaFoam.opacity(0.2),
                            radius: isListening ? 20 : 8,
                            x: 0,
                            y: 4
                        )
                        .scaleEffect(isActive ? 1.05 : 1.0)
                        .animation(CroatianBeachAnimations.stateTransition, value: isListening)
                        .animation(CroatianBeachAnimations.stateTransition, value: isActive)
                }
            }
            .buttonStyle(PlainButtonStyle())
            
            // Voice state text
            Text(voiceState)
                .font(CroatianBeachTypography.voiceState)
                .foregroundColor(CroatianBeachColors.emeraldShade)
                .animation(.easeInOut(duration: 0.3), value: voiceState)
        }
    }
}

/// Conversation card with sea glass effect
struct CroatianConversationCard: View {
    let message: String
    let timestamp: String
    let isDiscovery: Bool
    
    var body: some View {
        HStack(alignment: .top, spacing: CroatianBeachSpacing.medium) {
            // Discovery indicator - crystal water dot
            Circle()
                .fill(isDiscovery ? CroatianBeachColors.crystalWater : CroatianBeachColors.seaFoam)
                .frame(width: 10, height: 10)
                .padding(.top, 6)
            
            VStack(alignment: .leading, spacing: CroatianBeachSpacing.small) {
                // Message text
                Text(message)
                    .font(CroatianBeachTypography.body)
                    .foregroundColor(CroatianBeachColors.deepEmerald)
                    .lineLimit(nil)
                
                // Timestamp
                Text(timestamp)
                    .font(CroatianBeachTypography.caption)
                    .foregroundColor(CroatianBeachColors.seaFoam)
            }
            
            Spacer()
        }
        .padding(CroatianBeachSpacing.large)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(CroatianBeachColors.seafoamMist)
                .shadow(
                    color: CroatianBeachColors.seaFoam.opacity(0.15),
                    radius: 12,
                    x: 0,
                    y: 4
                )
        )
        .transition(.asymmetric(
            insertion: .move(edge: .trailing).combined(with: .opacity),
            removal: .opacity
        ))
        .animation(CroatianBeachAnimations.cardAppear, value: message)
    }
}

/// Discovery notification with crystal water highlight
struct CroatianDiscoveryBanner: View {
    let text: String
    let isVisible: Bool
    
    var body: some View {
        if isVisible {
            HStack {
                Image(systemName: "location.fill")
                    .foregroundColor(CroatianBeachColors.crystalWater)
                    .font(.title3)
                
                Text(text)
                    .font(CroatianBeachTypography.body)
                    .foregroundColor(CroatianBeachColors.emeraldShade)
                    .fontWeight(.medium)
            }
            .padding(.horizontal, CroatianBeachSpacing.large)
            .padding(.vertical, CroatianBeachSpacing.medium)
            .background(
                Capsule()
                    .fill(CroatianBeachColors.crystalWater.opacity(0.1))
                    .overlay(
                        Capsule()
                            .stroke(CroatianBeachColors.crystalWater.opacity(0.3), lineWidth: 1)
                    )
            )
            .scaleEffect(isVisible ? 1.0 : 0.8)
            .opacity(isVisible ? 1.0 : 0.0)
            .animation(CroatianBeachAnimations.discoveryBurst, value: isVisible)
        }
    }
}

/// Clarification prompt with gentle inquiry styling
struct CroatianClarificationCard: View {
    let question: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: CroatianBeachSpacing.medium) {
            HStack {
                Image(systemName: "questionmark.circle.fill")
                    .foregroundColor(CroatianBeachColors.crystalWater)
                
                Text("Let me clarify...")
                    .font(CroatianBeachTypography.body)
                    .foregroundColor(CroatianBeachColors.seaFoam)
                    .fontWeight(.medium)
            }
            
            Text(question)
                .font(CroatianBeachTypography.body)
                .foregroundColor(CroatianBeachColors.deepEmerald)
                .lineLimit(nil)
        }
        .padding(CroatianBeachSpacing.large)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(CroatianBeachColors.crystalWater.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(
                            LinearGradient(
                                colors: [
                                    CroatianBeachColors.crystalWater.opacity(0.3),
                                    CroatianBeachColors.seaFoam.opacity(0.2)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1.5
                        )
                )
        )
    }
}

/// Enhanced voice hub with constant pulse and tool status indicators
struct EnhancedCroatianVoiceHub: View {
    let isListening: Bool
    let isActive: Bool
    let toolStatus: ToolStatus
    let action: () -> Void
    
    @State private var constantPulseScale: CGFloat = 1.0
    
    var body: some View {
        VStack(spacing: CroatianBeachSpacing.medium) {
            // Voice interaction circle with enhanced animations
            Button(action: action) {
                ZStack {
                    // Constant pulse rings
                    ForEach(0..<3, id: \.self) { index in
                        Circle()
                            .stroke(toolStatus.color.opacity(0.2), lineWidth: 2)
                            .frame(width: 160 + CGFloat(index * 20), height: 160 + CGFloat(index * 20))
                            .scaleEffect(constantPulseScale)
                            .opacity(0.6 - Double(index) * 0.2)
                            .animation(
                                Animation.easeInOut(duration: 2.0 + Double(index) * 0.5)
                                    .repeatForever(autoreverses: true)
                                    .delay(Double(index) * 0.3),
                                value: constantPulseScale
                            )
                    }
                    
                    // Listening breathing ring
                    if isListening {
                        Circle()
                            .stroke(CroatianBeachColors.crystalWater.opacity(0.4), lineWidth: 8)
                            .frame(width: 140, height: 140)
                            .scaleEffect(isListening ? 1.2 : 1.0)
                            .opacity(isListening ? 0.8 : 1.0)
                            .animation(CroatianBeachAnimations.breathingPulse, value: isListening)
                    }
                    
                    // Main circle with dynamic gradient
                    Circle()
                        .fill(mainCircleGradient)
                        .frame(width: CroatianBeachSpacing.voiceHub, height: CroatianBeachSpacing.voiceHub)
                        .overlay(
                            Image(systemName: toolStatus.iconName)
                                .font(.system(size: 40, weight: .medium))
                                .foregroundColor(iconColor)
                                .animation(.easeInOut(duration: 0.4), value: toolStatus.iconName)
                        )
                        .shadow(
                            color: toolStatus.color.opacity(0.4),
                            radius: isListening ? 25 : 12,
                            x: 0,
                            y: 6
                        )
                        .scaleEffect(isActive ? 1.05 : 1.0)
                        .animation(.easeInOut(duration: 0.3), value: isActive)
                        .animation(.easeInOut(duration: 0.5), value: toolStatus)
                }
            }
            .buttonStyle(PlainButtonStyle())
        }
        .onAppear {
            constantPulseScale = 1.1
        }
    }
    
    private var mainCircleGradient: LinearGradient {
        switch toolStatus {
        case .listening:
            return LinearGradient(
                colors: [CroatianBeachColors.crystalWater, CroatianBeachColors.seaFoam],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .thinking:
            return LinearGradient(
                colors: [CroatianBeachColors.seaFoam, CroatianBeachColors.emeraldShade],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .searching:
            return LinearGradient(
                colors: [CroatianBeachColors.deepWater, CroatianBeachColors.seaFoam],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .lookingAround:
            return LinearGradient(
                colors: [CroatianBeachColors.crystalWater, CroatianBeachColors.deepWater],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .idle:
            return LinearGradient(
                colors: [CroatianBeachColors.seafoamMist, CroatianBeachColors.beachSand],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }
    
    private var iconColor: Color {
        switch toolStatus {
        case .idle:
            return CroatianBeachColors.emeraldShade
        case .listening:
            return CroatianBeachColors.deepWater
        case .thinking, .searching, .lookingAround:
            return .white
        }
    }
}

/// Simple control buttons with Croatian beach styling
struct CroatianControlButton: View {
    let icon: String
    let action: () -> Void
    let isActive: Bool
    
    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(isActive ? CroatianBeachColors.crystalWater : CroatianBeachColors.emeraldShade)
        }
        .buttonStyle(PlainButtonStyle())
        .scaleEffect(isActive ? 1.1 : 1.0)
        .animation(CroatianBeachAnimations.stateTransition, value: isActive)
    }
}