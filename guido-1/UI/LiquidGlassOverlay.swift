//
//  LiquidGlassOverlay.swift
//  guido-1
//
//  Liquid glass overlay system for floating results and information
//

import SwiftUI
import UIKit

// MARK: - LiquidGlass Namespace

enum LiquidGlassOverlay {
    // Namespace for liquid glass components
}

// MARK: - Liquid Glass Components

struct LiquidGlassCard: View {
    let content: AnyView
    let intensity: Double
    let cornerRadius: CGFloat
    let shadowIntensity: Double
    
    let enableFloating: Bool
    
    @State private var floatAnimation: Double = 0.0
    
    init<Content: View>(
        intensity: Double = 0.8,
        cornerRadius: CGFloat = 24,
        shadowIntensity: Double = 0.3,
        enableFloating: Bool = false,
        @ViewBuilder content: () -> Content
    ) {
        self.content = AnyView(content())
        self.intensity = intensity
        self.cornerRadius = cornerRadius
        self.shadowIntensity = shadowIntensity
        self.enableFloating = enableFloating
    }
    
    var body: some View {
        content
            .background(
                LiquidGlassBackground(
                    intensity: intensity,
                    cornerRadius: cornerRadius
                )
            )
            .shadow(
                color: Color.black.opacity(shadowIntensity * 0.1),
                radius: 15,
                x: 0,
                y: 8 + (enableFloating ? sin(floatAnimation) * 2 : 0)
            )
            .shadow(
                color: Color.black.opacity(shadowIntensity * 0.05),
                radius: 30,
                x: 0,
                y: 15 + (enableFloating ? sin(floatAnimation) * 3 : 0)
            )
            .offset(y: enableFloating ? sin(floatAnimation) * 1.5 : 0)
            .onAppear {
                if enableFloating {
                    startFloatAnimation()
                }
            }
    }
    
    private func startFloatAnimation() {
        Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            withAnimation(.linear(duration: 0.1)) {
                floatAnimation += 0.05 // Much slower, less frequent updates
            }
        }
    }
}

struct LiquidGlassBackground: View {
    let intensity: Double
    let cornerRadius: CGFloat
    
    @State private var noiseOffset: CGPoint = .zero
    @State private var shimmerPhase: Double = 0.0
    
    var body: some View {
        ZStack {
            // Base glass effect
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.1 * intensity),
                            Color.white.opacity(0.05 * intensity),
                            Color.white.opacity(0.15 * intensity)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            
            // Frosted glass blur simulation
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(Color.white.opacity(0.08 * intensity))
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.clear,
                                    Color.white.opacity(0.1 * intensity),
                                    Color.clear
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .offset(x: cos(shimmerPhase) * 10, y: sin(shimmerPhase) * 10)
                )
            
            // Border highlight
            RoundedRectangle(cornerRadius: cornerRadius)
                .stroke(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.3 * intensity),
                            Color.white.opacity(0.1 * intensity),
                            Color.white.opacity(0.2 * intensity)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1.5
                )
            
            // Subtle inner highlight
            RoundedRectangle(cornerRadius: cornerRadius - 1)
                .stroke(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.15 * intensity),
                            Color.clear,
                            Color.white.opacity(0.1 * intensity)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
                .padding(1)
        }
        .onAppear {
            startShimmerAnimation()
        }
    }
    
    private func startShimmerAnimation() {
        Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { _ in
            withAnimation(.linear(duration: 0.2)) {
                shimmerPhase += 0.1 // Much slower shimmer
            }
        }
    }
}

// MARK: - Individual Result Card

struct IndividualResultCard: View {
    let result: LiquidGlassOverlay.ResultItem
    let index: Int
    let onDismiss: () -> Void
    
    @State private var appearOffset: CGFloat = 30
    @State private var appearOpacity: Double = 0
    @State private var cardHover: Bool = false
    
    var body: some View {
        LiquidGlassCard(intensity: 0.8, cornerRadius: 20, shadowIntensity: 0.25) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 16) {
                    // Icon with liquid glass backing
                    LiquidGlassCard(intensity: 0.5, cornerRadius: 12, shadowIntensity: 0.1) {
                        Image(systemName: result.iconName)
                            .font(.system(size: 20, weight: .medium))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [result.color, result.color.opacity(0.7)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 40, height: 40)
                    }
                    
                    VStack(alignment: .leading, spacing: 6) {
                        Text(result.title)
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                            .foregroundColor(.primary)
                        
                        if let subtitle = result.subtitle {
                            Text(subtitle)
                                .font(.system(size: 14, weight: .medium, design: .rounded))
                                .foregroundColor(.secondary)
                        }
                    }
                }
                
                if let detail = result.detail {
                    Text(detail)
                        .font(.system(size: 12, weight: .regular, design: .rounded))
                        .foregroundColor(Color(.tertiaryLabel))
                        .lineLimit(3)
                }
                
                if let action = result.action {
                    Divider()
                        .opacity(0.2)
                    
                    Button(action: {
                        open(action: action)
                        onDismiss()
                    }) {
                        HStack {
                            Image(systemName: "arrow.up.right")
                                .font(.system(size: 14, weight: .semibold))
                            
                            Text(action.title)
                                .font(.system(size: 14, weight: .semibold, design: .rounded))
                            
                            Spacer()
                        }
                        .foregroundColor(result.color)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .frame(maxWidth: .infinity)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(result.color.opacity(0.12))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(result.color.opacity(0.35), lineWidth: 1)
                        )
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            .padding(16)
        }
        .scaleEffect(cardHover ? 1.02 : 1.0)
        .offset(y: appearOffset)
        .opacity(appearOpacity)
        .onAppear {
            withAnimation(
                .spring(dampingFraction: 0.7, blendDuration: 0.4)
                .delay(Double(index) * 0.1)
            ) {
                appearOffset = 0
                appearOpacity = 1
            }
        }
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.2)) {
                cardHover = hovering
            }
        }
    }

    private func open(action: LiquidGlassOverlay.ResultItem.Action) {
        let application = UIApplication.shared
        print("[Directions] 👆 Opening directions link: \(action.primaryURL.absoluteString)")
        application.open(action.primaryURL, options: [:]) { success in
            if !success, let fallback = action.fallbackURL {
                print("[Directions] ↩️ Primary URL failed, falling back to: \(fallback.absoluteString)")
                application.open(fallback, options: [:], completionHandler: nil)
            }
        }
    }
}

// MARK: - Result Item Display

struct LiquidGlassResultItem: View {
    let result: LiquidGlassOverlay.ResultItem
    let index: Int
    let isExpanded: Bool
    
    @State private var appearOffset: CGFloat = 50
    @State private var appearOpacity: Double = 0
    @State private var detailHeight: CGFloat = 0
    
    init(result: LiquidGlassOverlay.ResultItem, index: Int, isExpanded: Bool = false) {
        self.result = result
        self.index = index
        self.isExpanded = isExpanded
    }
    
    var body: some View {
        LiquidGlassCard(intensity: 0.7, cornerRadius: 20, shadowIntensity: 0.2) {
            VStack(spacing: 12) {
                HStack(spacing: 16) {
                    // Icon with liquid glass backing
                    LiquidGlassCard(intensity: 0.5, cornerRadius: 12, shadowIntensity: 0.1) {
                        Image(systemName: result.iconName)
                            .font(.system(size: 20, weight: .medium))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [result.color, result.color.opacity(0.7)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 40, height: 40)
                    }
                    
                    // Content
                    VStack(alignment: .leading, spacing: 4) {
                        Text(result.title)
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                            .foregroundColor(.primary)
                        
                        if let subtitle = result.subtitle {
                            Text(subtitle)
                                .font(.system(size: 14, weight: .medium, design: .rounded))
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    Spacer()
                }
                
                // Expanded detail section
                if isExpanded && result.detail != nil {
                    VStack(alignment: .leading, spacing: 8) {
                        Divider()
                            .opacity(0.3)
                        
                        Text(result.detail!)
                            .font(.system(size: 13, weight: .regular, design: .rounded))
                            .foregroundColor(Color(.tertiaryLabel))
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxHeight: isExpanded ? .infinity : 0, alignment: .top)
                    .clipped()
                    .transition(.asymmetric(
                        insertion: .move(edge: .top).combined(with: .opacity),
                        removal: .move(edge: .top).combined(with: .opacity)
                    ))
                }
            }
            .padding(16)
            .animation(.spring(response: 0.5, dampingFraction: 0.7), value: isExpanded)
        }
        .offset(y: appearOffset)
        .opacity(appearOpacity)
        .onAppear {
            withAnimation(
                .spring(dampingFraction: 0.7, blendDuration: 0.4)
                .delay(Double(index) * 0.08)
            ) {
                appearOffset = 0
                appearOpacity = 1
            }
        }
    }
}

// MARK: - Floating Results Panel

struct FloatingResultsPanel: View {
    let results: [LiquidGlassOverlay.ResultItem]
    let title: String
    let isVisible: Bool
    let onExpand: () -> Void
    let onDismiss: () -> Void
    
    @State private var cardsScale: CGFloat = 0.3
    @State private var cardsOpacity: Double = 0
    @State private var cardsRotation: Double = 5
    @State private var backgroundOpacity: Double = 0
    @State private var isExpanded: Bool = false
    
    var body: some View {
        GeometryReader { geometry in
            if isVisible && !results.isEmpty {
                ZStack {
                    // Background overlay
                    Color.black.opacity(backgroundOpacity * 0.15)
                        .ignoresSafeArea()
                        .allowsHitTesting(true)
                        .onTapGesture {
                            dismissWithBounce()
                        }
                    
                    // Smart centered layout for individual cards
                    VStack(spacing: 12) {
                        // Title header with dismiss button
                        HStack {
                            Text(title)
                                .font(.system(size: 18, weight: .semibold, design: .rounded))
                                .foregroundColor(.primary)
                            
                            Spacer()
                            
                            Button(action: { dismissWithBounce() }) {
                                LiquidGlassCard(intensity: 0.4, cornerRadius: 8, shadowIntensity: 0.1) {
                                    Image(systemName: "xmark")
                                        .font(.system(size: 14, weight: .medium))
                                        .foregroundColor(.secondary)
                                        .frame(width: 28, height: 28)
                                }
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                        .padding(.horizontal, 16)
                        
                        // Individual result cards in smart layout
                        let displayResults = isExpanded ? results : Array(results.prefix(3))
                        let useScrollView = displayResults.count > 4
                        
                        Group {
                            if useScrollView {
                                ScrollView {
                                    LazyVStack(spacing: 8) {
                                        ForEach(Array(displayResults.enumerated()), id: \.offset) { index, result in
                                            IndividualResultCard(
                                                result: result,
                                                index: index,
                                                onDismiss: { dismissWithBounce() }
                                            )
                                            .frame(maxWidth: .infinity)
                                        }
                                    }
                                    .padding(.horizontal, 8)
                                }
                                .frame(maxHeight: geometry.size.height * 0.5)
                            } else {
                                VStack(spacing: 8) {
                                    ForEach(Array(displayResults.enumerated()), id: \.offset) { index, result in
                                        IndividualResultCard(
                                            result: result,
                                            index: index,
                                            onDismiss: { dismissWithBounce() }
                                        )
                                        .frame(maxWidth: .infinity)
                                    }
                                }
                                .padding(.horizontal, 8)
                            }
                        }
                        
                        // Expand/Collapse button if needed
                        if results.count > 3 {
                            LiquidGlassCard(intensity: 0.5, cornerRadius: 12, shadowIntensity: 0.15) {
                                Button(action: { toggleExpansion() }) {
                                    HStack {
                                        Text(isExpanded ? "Show less" : "+ \(results.count - 3) more")
                                            .font(.system(size: 14, weight: .medium, design: .rounded))
                                            .foregroundColor(.secondary)
                                        
                                        Spacer()
                                        
                                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                                            .font(.system(size: 12, weight: .medium))
                                            .foregroundColor(.secondary)
                                    }
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 12)
                                }
                                .buttonStyle(PlainButtonStyle())
                            }
                        }
                    }
                    .frame(maxWidth: smartMaxWidth(for: results.count, screenWidth: geometry.size.width))
                    .position(
                        x: geometry.size.width / 2,
                        y: geometry.size.height / 2
                    )
                    .scaleEffect(cardsScale)
                    .opacity(cardsOpacity)
                    .rotationEffect(.degrees(cardsRotation))
                }
            }
        }
        .onChange(of: isVisible) { visible in
            if visible {
                popIn()
            }
        }
    }
    
    // Smart width calculation based on content
    private func smartMaxWidth(for itemCount: Int, screenWidth: CGFloat) -> CGFloat {
        switch itemCount {
        case 1:
            return min(screenWidth * 0.75, 350)  // Smaller for single item
        case 2...3:
            return min(screenWidth * 0.85, 400)  // Medium for few items
        default:
            return min(screenWidth * 0.9, 450)   // Larger for many items
        }
    }
    
    private func popIn() {
        // Reset initial state
        cardsScale = 0.3
        cardsOpacity = 0
        cardsRotation = 5
        backgroundOpacity = 0
        isExpanded = false
        
        // Animate in with pop effect
        withAnimation(.spring(response: 0.6, dampingFraction: 0.6, blendDuration: 0)) {
            cardsScale = 1.0
            cardsOpacity = 1.0
            cardsRotation = 0
            backgroundOpacity = 1.0
        }
    }
    
    private func dismissWithBounce() {
        // Bounce out animation
        withAnimation(.spring(response: 0.4, dampingFraction: 0.6, blendDuration: 0)) {
            cardsScale = 0.1
            cardsOpacity = 0
            cardsRotation = -3
            backgroundOpacity = 0
        }
        
        // Call dismiss after animation
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            onDismiss()
        }
    }
    
    private func toggleExpansion() {
        withAnimation(.spring(response: 0.5, dampingFraction: 0.7, blendDuration: 0)) {
            isExpanded.toggle()
        }
    }
}

// MARK: - Expanded Results View

struct ExpandedLiquidResults: View {
    let results: [LiquidGlassOverlay.ResultItem]
    let title: String
    let isVisible: Bool
    let onDismiss: () -> Void
    
    @State private var backgroundOpacity: Double = 0
    @State private var contentScale: Double = 0.9
    @State private var contentOpacity: Double = 0
    
    var body: some View {
        if isVisible {
            ZStack {
                // Backdrop
                Color.black.opacity(backgroundOpacity * 0.4)
                    .ignoresSafeArea()
                    .onTapGesture {
                        onDismiss()
                    }
                
                // Content
                VStack(spacing: 0) {
                    Spacer()
                    
                    LiquidGlassCard(intensity: 0.9, cornerRadius: 28, shadowIntensity: 0.4) {
                        VStack(spacing: 20) {
                            // Header
                            HStack {
                                Text(title)
                                    .font(.system(size: 24, weight: .bold, design: .rounded))
                                    .foregroundColor(.primary)
                                
                                Spacer()
                                
                                Button(action: onDismiss) {
                                    LiquidGlassCard(intensity: 0.4, cornerRadius: 12, shadowIntensity: 0.1) {
                                        Image(systemName: "xmark.circle.fill")
                                            .font(.system(size: 24, weight: .medium))
                                            .foregroundColor(.secondary)
                                            .frame(width: 40, height: 40)
                                    }
                                }
                                .buttonStyle(PlainButtonStyle())
                            }
                            
                            // Scrollable results
                            ScrollView {
                                LazyVStack(spacing: 12) {
                                    ForEach(Array(results.enumerated()), id: \.offset) { index, result in
                                        ExpandedLiquidResultItem(result: result, index: index)
                                    }
                                }
                                .padding(.vertical, 8)
                            }
                            .frame(maxHeight: UIScreen.main.bounds.height * 0.5)
                        }
                        .padding(24)
                    }
                    .frame(maxWidth: UIScreen.main.bounds.width * 0.9)
                    
                    Spacer()
                }
                .scaleEffect(contentScale)
                .opacity(contentOpacity)
            }
            .transition(.opacity)
            .onAppear {
                withAnimation(.spring(dampingFraction: 0.8, blendDuration: 0.6)) {
                    backgroundOpacity = 1
                    contentScale = 1.0
                    contentOpacity = 1
                }
            }
            .onDisappear {
                backgroundOpacity = 0
                contentScale = 0.9
                contentOpacity = 0
            }
        }
    }
}

struct ExpandedLiquidResultItem: View {
    let result: LiquidGlassOverlay.ResultItem
    let index: Int
    
    @State private var appearOffset: CGFloat = 50
    @State private var appearOpacity: Double = 0
    
    var body: some View {
        LiquidGlassCard(intensity: 0.6, cornerRadius: 20, shadowIntensity: 0.2) {
            HStack(spacing: 20) {
                // Enhanced icon
                LiquidGlassCard(intensity: 0.5, cornerRadius: 16, shadowIntensity: 0.15) {
                    Image(systemName: result.iconName)
                        .font(.system(size: 28, weight: .medium))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [result.color, result.color.opacity(0.7)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 56, height: 56)
                }
                
                // Enhanced content
                VStack(alignment: .leading, spacing: 8) {
                    Text(result.title)
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundColor(.primary)
                    
                    if let subtitle = result.subtitle {
                        Text(subtitle)
                            .font(.system(size: 16, weight: .medium, design: .rounded))
                            .foregroundColor(.secondary)
                    }
                    
                    if let detail = result.detail {
                        Text(detail)
                            .font(.system(size: 14, weight: .regular, design: .rounded))
                            .foregroundColor(Color(.tertiaryLabel))
                    }
                }
                
                Spacer()
            }
            .padding(20)
        }
        .offset(y: appearOffset)
        .opacity(appearOpacity)
        .onAppear {
            withAnimation(
                .spring(dampingFraction: 0.8, blendDuration: 0.5)
                .delay(Double(index) * 0.05)
            ) {
                appearOffset = 0
                appearOpacity = 1
            }
        }
    }
}

// MARK: - Result Item (Reusable)

extension LiquidGlassOverlay {
    struct ResultItem: Identifiable {
        let id = UUID()
        let title: String
        let subtitle: String?
        let detail: String?
        let iconName: String
        let color: Color
        let action: Action?
        
        struct Action {
            let title: String
            let primaryURL: URL
            let fallbackURL: URL?
        }
        
        init(
            title: String,
            subtitle: String? = nil,
            detail: String? = nil,
            iconName: String = "location.fill",
            color: Color = .blue,
            action: Action? = nil
        ) {
            self.title = title
            self.subtitle = subtitle
            self.detail = detail
            self.iconName = iconName
            self.color = color
            self.action = action
        }
    }
}