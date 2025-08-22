//
//  AdaptiveCanvas.swift
//  guido-1
//
//  Immersive adaptive canvas that responds to location, time, and conversation state
//

import SwiftUI
import CoreLocation

// MARK: - Canvas Theme System

enum CanvasEnvironment {
    case beach
    case park
    case urban
    case indoor
    case mountain
    case water
    case desert
    case unknown
    
    var primaryColors: [Color] {
        switch self {
        case .beach:
            return [
                Color(red: 0.02, green: 0.20, blue: 0.45), // Deep midnight ocean
                Color(red: 0.05, green: 0.55, blue: 0.75), // Vibrant deep turquoise
                Color(red: 0.15, green: 0.75, blue: 0.85), // Electric turquoise
                Color(red: 0.40, green: 0.88, blue: 0.92), // Brilliant aqua
                Color(red: 0.70, green: 0.95, blue: 0.88), // Luminous seafoam
                Color(red: 0.92, green: 0.88, blue: 0.65), // Golden sand
                Color(red: 0.98, green: 0.94, blue: 0.85)  // Warm ivory
            ]
        case .park:
            return [
                Color(red: 0.08, green: 0.15, blue: 0.08), // Deep forest night
                Color(red: 0.12, green: 0.40, blue: 0.18), // Rich emerald green
                Color(red: 0.25, green: 0.65, blue: 0.25), // Vivid forest green
                Color(red: 0.45, green: 0.82, blue: 0.30), // Electric lime green
                Color(red: 0.65, green: 0.88, blue: 0.45), // Bright spring green
                Color(red: 0.82, green: 0.94, blue: 0.68), // Luminous grass
                Color(red: 0.94, green: 0.98, blue: 0.88)  // Soft sunlight
            ]
        case .urban:
            return [
                Color(red: 0.05, green: 0.08, blue: 0.18), // Deep neon night
                Color(red: 0.15, green: 0.25, blue: 0.45), // Electric blue steel
                Color(red: 0.35, green: 0.45, blue: 0.65), // Vibrant concrete
                Color(red: 0.55, green: 0.65, blue: 0.78), // Bright steel
                Color(red: 0.75, green: 0.82, blue: 0.88), // Luminous concrete
                Color(red: 0.88, green: 0.92, blue: 0.96), // Brilliant modern
                Color(red: 0.96, green: 0.98, blue: 1.00)  // Pure urban light
            ]
        case .indoor:
            return [
                Color(red: 0.45, green: 0.35, blue: 0.25), // Rich wood
                Color(red: 0.65, green: 0.55, blue: 0.45), // Warm brown
                Color(red: 0.80, green: 0.72, blue: 0.60), // Natural beige
                Color(red: 0.88, green: 0.82, blue: 0.75), // Soft cream
                Color(red: 0.92, green: 0.88, blue: 0.82), // Light cream
                Color(red: 0.96, green: 0.93, blue: 0.88), // Warm white
                Color(red: 0.98, green: 0.96, blue: 0.93)  // Cozy white
            ]
        case .mountain:
            return [
                Color(red: 0.18, green: 0.22, blue: 0.35), // Deep mountain shadow
                Color(red: 0.35, green: 0.40, blue: 0.55), // Mountain blue
                Color(red: 0.50, green: 0.55, blue: 0.65), // Stone gray
                Color(red: 0.68, green: 0.72, blue: 0.78), // Light stone
                Color(red: 0.82, green: 0.85, blue: 0.88), // Misty gray
                Color(red: 0.90, green: 0.92, blue: 0.95), // Alpine mist
                Color(red: 0.95, green: 0.97, blue: 0.99)  // Snow white
            ]
        case .water:
            return [
                Color(red: 0.02, green: 0.12, blue: 0.35), // Abyssal deep blue
                Color(red: 0.08, green: 0.35, blue: 0.70), // Vivid ocean blue
                Color(red: 0.18, green: 0.55, blue: 0.85), // Electric water blue
                Color(red: 0.35, green: 0.72, blue: 0.92), // Brilliant aqua
                Color(red: 0.55, green: 0.85, blue: 0.96), // Luminous light blue
                Color(red: 0.75, green: 0.92, blue: 0.98), // Radiant pale blue
                Color(red: 0.92, green: 0.98, blue: 1.00)  // Pure crystal
            ]
        case .desert:
            return [
                Color(red: 0.45, green: 0.22, blue: 0.08), // Deep canyon earth
                Color(red: 0.68, green: 0.38, blue: 0.15), // Rich terracotta
                Color(red: 0.85, green: 0.55, blue: 0.25), // Vibrant desert gold
                Color(red: 0.92, green: 0.72, blue: 0.35), // Brilliant sand
                Color(red: 0.96, green: 0.82, blue: 0.55), // Luminous dune
                Color(red: 0.98, green: 0.90, blue: 0.75), // Radiant sand
                Color(red: 1.00, green: 0.96, blue: 0.88)  // Pure desert light
            ]
        case .unknown:
            return [
                Color(red: 0.30, green: 0.35, blue: 0.45), // Deep neutral
                Color(red: 0.45, green: 0.50, blue: 0.60), // Medium blue-gray
                Color(red: 0.60, green: 0.65, blue: 0.72), // Light gray
                Color(red: 0.72, green: 0.76, blue: 0.80), // Soft gray
                Color(red: 0.82, green: 0.85, blue: 0.88), // Very light gray
                Color(red: 0.90, green: 0.92, blue: 0.94), // Near white
                Color(red: 0.95, green: 0.96, blue: 0.97)  // Clean white
            ]
        }
    }
    
    var ripplePattern: RipplePattern {
        switch self {
        case .beach:
            return RipplePattern(
                style: .liquidPond,
                speed: 1.2,
                amplitude: 0.8,
                frequency: 2.0,
                decay: 0.9,
                depth: 0.8,
                viscosity: 0.3
            )
        case .park:
            return RipplePattern(
                style: .liquidPond,
                speed: 0.8,
                amplitude: 0.6,
                frequency: 1.5,
                decay: 0.85,
                depth: 0.6,
                viscosity: 0.5
            )
        case .urban:
            return RipplePattern(
                style: .liquidPond,
                speed: 1.4,
                amplitude: 0.5,
                frequency: 2.2,
                decay: 0.7,
                depth: 0.4,
                viscosity: 0.2
            )
        case .indoor:
            return RipplePattern(
                style: .liquidPond,
                speed: 0.6,
                amplitude: 0.4,
                frequency: 1.2,
                decay: 0.95,
                depth: 0.7,
                viscosity: 0.7
            )
        case .mountain:
            return RipplePattern(
                style: .liquidPond,
                speed: 1.0,
                amplitude: 0.7,
                frequency: 1.8,
                decay: 0.6,
                depth: 0.9,
                viscosity: 0.1
            )
        case .water:
            return RipplePattern(
                style: .liquidPond,
                speed: 1.5,
                amplitude: 0.9,
                frequency: 2.5,
                decay: 0.8,
                depth: 1.0,
                viscosity: 0.1
            )
        case .desert:
            return RipplePattern(
                style: .liquidPond,
                speed: 0.5,
                amplitude: 0.3,
                frequency: 1.0,
                decay: 0.9,
                depth: 0.3,
                viscosity: 0.8
            )
        case .unknown:
            return RipplePattern(
                style: .liquidPond,
                speed: 1.0,
                amplitude: 0.5,
                frequency: 1.5,
                decay: 0.8,
                depth: 0.5,
                viscosity: 0.4
            )
        }
    }
}

enum TimeOfDay {
    case dawn
    case morning
    case afternoon
    case evening
    case night
    case lateNight
    
    var lightingModifier: Color {
        switch self {
        case .dawn:
            return Color(red: 1.0, green: 0.7, blue: 0.4).opacity(0.3)  // Soft orange
        case .morning:
            return Color(red: 1.0, green: 0.9, blue: 0.7).opacity(0.2)  // Warm yellow
        case .afternoon:
            return Color.clear  // No modifier, full saturation
        case .evening:
            return Color(red: 1.0, green: 0.5, blue: 0.2).opacity(0.4)  // Golden hour
        case .night:
            return Color(red: 0.2, green: 0.3, blue: 0.6).opacity(0.5)  // Deep blue
        case .lateNight:
            return Color(red: 0.1, green: 0.1, blue: 0.3).opacity(0.7)  // Very dark blue
        }
    }
    
    var brightness: Double {
        switch self {
        case .dawn: return 0.7
        case .morning: return 1.0
        case .afternoon: return 1.0
        case .evening: return 0.8
        case .night: return 0.4
        case .lateNight: return 0.3
        }
    }
}

enum RippleStyle {
    case liquidPond  // New physics-based pond ripples
    case circular
    case organic
    case geometric
    case branching
    case angular
    case flowing
    case soft
}

struct RipplePattern {
    let style: RippleStyle
    let speed: Double
    let amplitude: Double
    let frequency: Double
    let decay: Double
    let depth: Double      // 3D depth effect (0-1)
    let viscosity: Double  // Liquid viscosity (0-1, higher = more viscous)
    
    init(style: RippleStyle, speed: Double, amplitude: Double, frequency: Double, decay: Double, depth: Double = 0.5, viscosity: Double = 0.3) {
        self.style = style
        self.speed = speed
        self.amplitude = amplitude
        self.frequency = frequency
        self.decay = decay
        self.depth = depth
        self.viscosity = viscosity
    }
}

// MARK: - Ripple State Management

enum RippleDirection {
    case inward  // User speaking
    case outward // Guido speaking
}

struct ActiveRipple: Identifiable {
    let id = UUID()
    let direction: RippleDirection
    let startTime: Date
    let intensity: Double
    let pattern: RipplePattern
    
    var age: TimeInterval {
        Date().timeIntervalSince(startTime)
    }
    
    var isExpired: Bool {
        age > (3.0 / pattern.speed) // Ripples last 3 seconds adjusted for speed
    }
}

// MARK: - Immersive Environment Context

struct EnvironmentContext {
    let environment: CanvasEnvironment
    let timeOfDay: TimeOfDay
    let colors: [Color]
    let isActive: Bool
    
    // Atmospheric foundation colors - deep environmental character
    var atmosphericColors: [Color] {
        switch environment {
        case .beach:
            return [
                colors.safeAccess(0).opacity(timeOfDay.brightness * 0.2),
                colors.safeAccess(1).opacity(timeOfDay.brightness * 0.4),
                colors.safeAccess(2).opacity(timeOfDay.brightness * 0.6),
                colors.safeAccess(3).opacity(timeOfDay.brightness * 0.8),
                colors.safeAccess(4).opacity(timeOfDay.brightness * 0.9),
                colors.safeAccess(5).opacity(timeOfDay.brightness * 0.95),
                colors.safeAccess(6).opacity(timeOfDay.brightness)
            ]
        case .park:
            return [
                colors.safeAccess(0).opacity(timeOfDay.brightness * 0.3),
                colors.safeAccess(1).opacity(timeOfDay.brightness * 0.5),
                colors.safeAccess(2).opacity(timeOfDay.brightness * 0.7),
                colors.safeAccess(3).opacity(timeOfDay.brightness * 0.8),
                colors.safeAccess(4).opacity(timeOfDay.brightness * 0.85),
                colors.safeAccess(5).opacity(timeOfDay.brightness * 0.9),
                colors.safeAccess(6).opacity(timeOfDay.brightness)
            ]
        case .urban:
            return [
                colors.safeAccess(0).opacity(timeOfDay.brightness * 0.4),
                colors.safeAccess(1).opacity(timeOfDay.brightness * 0.6),
                colors.safeAccess(2).opacity(timeOfDay.brightness * 0.75),
                colors.safeAccess(3).opacity(timeOfDay.brightness * 0.85),
                colors.safeAccess(4).opacity(timeOfDay.brightness * 0.9),
                colors.safeAccess(5).opacity(timeOfDay.brightness * 0.95),
                colors.safeAccess(6).opacity(timeOfDay.brightness)
            ]
        case .water:
            return [
                colors.safeAccess(0).opacity(timeOfDay.brightness * 0.1),
                colors.safeAccess(1).opacity(timeOfDay.brightness * 0.3),
                colors.safeAccess(2).opacity(timeOfDay.brightness * 0.5),
                colors.safeAccess(3).opacity(timeOfDay.brightness * 0.7),
                colors.safeAccess(4).opacity(timeOfDay.brightness * 0.85),
                colors.safeAccess(5).opacity(timeOfDay.brightness * 0.9),
                colors.safeAccess(6).opacity(timeOfDay.brightness)
            ]
        case .desert:
            return [
                colors.safeAccess(0).opacity(timeOfDay.brightness * 0.5),
                colors.safeAccess(1).opacity(timeOfDay.brightness * 0.7),
                colors.safeAccess(2).opacity(timeOfDay.brightness * 0.8),
                colors.safeAccess(3).opacity(timeOfDay.brightness * 0.85),
                colors.safeAccess(4).opacity(timeOfDay.brightness * 0.9),
                colors.safeAccess(5).opacity(timeOfDay.brightness * 0.95),
                colors.safeAccess(6).opacity(timeOfDay.brightness)
            ]
        case .mountain:
            return [
                colors.safeAccess(0).opacity(timeOfDay.brightness * 0.2),
                colors.safeAccess(1).opacity(timeOfDay.brightness * 0.4),
                colors.safeAccess(2).opacity(timeOfDay.brightness * 0.6),
                colors.safeAccess(3).opacity(timeOfDay.brightness * 0.75),
                colors.safeAccess(4).opacity(timeOfDay.brightness * 0.85),
                colors.safeAccess(5).opacity(timeOfDay.brightness * 0.9),
                colors.safeAccess(6).opacity(timeOfDay.brightness)
            ]
        case .indoor:
            return [
                colors.safeAccess(0).opacity(timeOfDay.brightness * 0.6),
                colors.safeAccess(1).opacity(timeOfDay.brightness * 0.75),
                colors.safeAccess(2).opacity(timeOfDay.brightness * 0.85),
                colors.safeAccess(3).opacity(timeOfDay.brightness * 0.9),
                colors.safeAccess(4).opacity(timeOfDay.brightness * 0.95),
                colors.safeAccess(5).opacity(timeOfDay.brightness * 0.98),
                colors.safeAccess(6).opacity(timeOfDay.brightness)
            ]
        case .unknown:
            return [
                colors.safeAccess(0).opacity(timeOfDay.brightness * 0.4),
                colors.safeAccess(1).opacity(timeOfDay.brightness * 0.6),
                colors.safeAccess(2).opacity(timeOfDay.brightness * 0.75),
                colors.safeAccess(3).opacity(timeOfDay.brightness * 0.85),
                colors.safeAccess(4).opacity(timeOfDay.brightness * 0.9),
                colors.safeAccess(5).opacity(timeOfDay.brightness * 0.95),
                colors.safeAccess(6).opacity(timeOfDay.brightness)
            ]
        }
    }
    
    // Depth colors for environmental character
    var depthColors: [Color] {
        [
            colors.safeAccess(1).opacity(timeOfDay.brightness * 0.3),
            colors.safeAccess(3).opacity(timeOfDay.brightness * 0.4),
            colors.safeAccess(5).opacity(timeOfDay.brightness * 0.2),
            Color.clear
        ]
    }
    
    // Ambient environmental mood colors
    var ambientColors: [Color] {
        switch environment {
        case .beach:
            return [colors.safeAccess(2).opacity(0.2), colors.safeAccess(4).opacity(0.3), colors.safeAccess(6).opacity(0.1)]
        case .park:
            return [colors.safeAccess(1).opacity(0.3), colors.safeAccess(3).opacity(0.2), colors.safeAccess(5).opacity(0.15)]
        case .urban:
            return [colors.safeAccess(0).opacity(0.4), colors.safeAccess(2).opacity(0.25), colors.safeAccess(4).opacity(0.1)]
        case .water:
            return [colors.safeAccess(1).opacity(0.2), colors.safeAccess(3).opacity(0.3), colors.safeAccess(5).opacity(0.2)]
        case .desert:
            return [colors.safeAccess(2).opacity(0.4), colors.safeAccess(4).opacity(0.3), colors.safeAccess(6).opacity(0.2)]
        case .mountain:
            return [colors.safeAccess(0).opacity(0.3), colors.safeAccess(2).opacity(0.2), colors.safeAccess(4).opacity(0.15)]
        case .indoor:
            return [colors.safeAccess(1).opacity(0.4), colors.safeAccess(3).opacity(0.3), colors.safeAccess(5).opacity(0.2)]
        case .unknown:
            return [colors.safeAccess(1).opacity(0.3), colors.safeAccess(3).opacity(0.2), colors.safeAccess(5).opacity(0.1)]
        }
    }
    
    // Atmospheric center points for different environments
    var atmosphericCenter: UnitPoint {
        switch environment {
        case .beach: return UnitPoint(x: 0.5, y: 0.6) // Horizon line
        case .park: return UnitPoint(x: 0.5, y: 0.4) // Canopy above
        case .urban: return UnitPoint(x: 0.5, y: 0.3) // City lights above
        case .water: return UnitPoint(x: 0.5, y: 0.5) // Deep center
        case .desert: return UnitPoint(x: 0.5, y: 0.7) // Sand below
        case .mountain: return UnitPoint(x: 0.5, y: 0.3) // Peak above
        case .indoor: return UnitPoint(x: 0.5, y: 0.5) // Centered
        case .unknown: return UnitPoint(x: 0.5, y: 0.5) // Centered
        }
    }
    
    var depthCenter: UnitPoint {
        switch environment {
        case .beach: return UnitPoint(x: 0.3, y: 0.7)
        case .park: return UnitPoint(x: 0.7, y: 0.3)
        case .urban: return UnitPoint(x: 0.4, y: 0.2)
        case .water: return UnitPoint(x: 0.6, y: 0.4)
        case .desert: return UnitPoint(x: 0.3, y: 0.8)
        case .mountain: return UnitPoint(x: 0.7, y: 0.2)
        case .indoor: return UnitPoint(x: 0.3, y: 0.3)
        case .unknown: return UnitPoint(x: 0.4, y: 0.4)
        }
    }
    
    // Ambient gradient directions
    var ambientDirection: (start: UnitPoint, end: UnitPoint) {
        switch environment {
        case .beach: return (.bottom, .top) // Water to sky
        case .park: return (.topLeading, .bottomTrailing) // Sunlight through leaves
        case .urban: return (.top, .bottom) // City glow downward
        case .water: return (.topTrailing, .bottomLeading) // Current flow
        case .desert: return (.bottomTrailing, .topLeading) // Heat rising
        case .mountain: return (.top, .bottom) // Mountain air descent
        case .indoor: return (.topLeading, .bottomTrailing) // Warm lighting
        case .unknown: return (.topLeading, .bottomTrailing) // Default
        }
    }
    
    // Environmental characteristics count and properties
    var characteristicCount: Int {
        switch environment {
        case .beach: return 3 // Waves, depth, shimmer
        case .park: return 4 // Canopy layers, sunbeams, depth
        case .urban: return 2 // Glow, reflections
        case .water: return 4 // Currents, depth layers
        case .desert: return 2 // Heat shimmer, depth
        case .mountain: return 3 // Mist layers, peaks
        case .indoor: return 2 // Warm spots, ambiance
        case .unknown: return 2 // Basic depth
        }
    }
    
    func characteristicColors(for index: Int) -> [Color] {
        switch environment {
        case .beach:
            switch index {
            case 0: return [colors.safeAccess(2).opacity(0.2), Color.clear] // Wave shimmer
            case 1: return [colors.safeAccess(0).opacity(0.3), colors.safeAccess(1).opacity(0.1)] // Deep water
            case 2: return [colors.safeAccess(4).opacity(0.15), Color.clear] // Surface light
            default: return [Color.clear]
            }
        case .park:
            switch index {
            case 0: return [colors.safeAccess(1).opacity(0.25), Color.clear] // Deep canopy
            case 1: return [colors.safeAccess(3).opacity(0.2), colors.safeAccess(5).opacity(0.1)] // Sunbeam
            case 2: return [colors.safeAccess(2).opacity(0.15), Color.clear] // Mid canopy
            case 3: return [colors.safeAccess(6).opacity(0.1), Color.clear] // Light filtering
            default: return [Color.clear]
            }
        case .urban:
            switch index {
            case 0: return [colors.safeAccess(1).opacity(0.3), colors.safeAccess(3).opacity(0.1)] // City glow
            case 1: return [colors.safeAccess(5).opacity(0.2), Color.clear] // Reflections
            default: return [Color.clear]
            }
        case .water:
            switch index {
            case 0: return [colors.safeAccess(0).opacity(0.4), colors.safeAccess(1).opacity(0.2)] // Deep current
            case 1: return [colors.safeAccess(2).opacity(0.25), Color.clear] // Mid current
            case 2: return [colors.safeAccess(4).opacity(0.2), colors.safeAccess(5).opacity(0.1)] // Surface flow
            case 3: return [colors.safeAccess(6).opacity(0.15), Color.clear] // Light refraction
            default: return [Color.clear]
            }
        case .desert:
            switch index {
            case 0: return [colors.safeAccess(2).opacity(0.3), colors.safeAccess(4).opacity(0.15)] // Heat shimmer
            case 1: return [colors.safeAccess(0).opacity(0.2), Color.clear] // Deep sand
            default: return [Color.clear]
            }
        case .mountain:
            switch index {
            case 0: return [colors.safeAccess(3).opacity(0.25), Color.clear] // Lower mist
            case 1: return [colors.safeAccess(5).opacity(0.2), colors.safeAccess(6).opacity(0.1)] // High mist
            case 2: return [colors.safeAccess(1).opacity(0.15), Color.clear] // Shadow valleys
            default: return [Color.clear]
            }
        case .indoor:
            switch index {
            case 0: return [colors.safeAccess(3).opacity(0.3), colors.safeAccess(5).opacity(0.2)] // Warm glow
            case 1: return [colors.safeAccess(6).opacity(0.15), Color.clear] // Soft ambiance
            default: return [Color.clear]
            }
        case .unknown:
            switch index {
            case 0: return [colors.safeAccess(2).opacity(0.2), Color.clear]
            case 1: return [colors.safeAccess(4).opacity(0.15), Color.clear]
            default: return [Color.clear]
            }
        }
    }
    
    func characteristicCenter(for index: Int) -> UnitPoint {
        let baseOffsets: [UnitPoint] = [
            UnitPoint(x: 0.3, y: 0.3),
            UnitPoint(x: 0.7, y: 0.6),
            UnitPoint(x: 0.2, y: 0.8),
            UnitPoint(x: 0.8, y: 0.2)
        ]
        guard baseOffsets.count > 0 else { return UnitPoint(x: 0.5, y: 0.5) }
        return baseOffsets[index % baseOffsets.count]
    }
    
    func characteristicRadius(for index: Int) -> Double {
        let baseRadii: [Double] = [0.6, 0.4, 0.8, 0.3]
        guard baseRadii.count > 0 else { return 0.5 }
        return baseRadii[index % baseRadii.count]
    }
    
    func characteristicBlendMode(for index: Int) -> BlendMode {
        let modes: [BlendMode] = [.overlay, .multiply, .screen, .softLight]
        guard modes.count > 0 else { return .overlay }
        return modes[index % modes.count]
    }
    
    func characteristicOpacity(for index: Int) -> Double {
        let opacities: [Double] = [0.4, 0.3, 0.5, 0.25]
        guard opacities.count > 0 else { return 0.3 }
        return opacities[index % opacities.count]
    }
    
    func characteristicSpeed(for index: Int) -> Double {
        let speeds: [Double] = [0.2, 0.15, 0.25, 0.3]
        guard speeds.count > 0 else { return 0.2 }
        return speeds[index % speeds.count]
    }
    
    // Refraction colors for glassy effects
    var refractionColors: [Color] {
        [
            colors.safeAccess(3).opacity(0.1),
            colors.safeAccess(5).opacity(0.05),
            Color.clear
        ]
    }
    
    // Enhanced particle system for richer depth
    var particleCount: Int {
        switch environment {
        case .beach: return 12 // More floating debris, bubbles, sea foam
        case .park: return 16 // More pollen, leaves, light specks
        case .urban: return 10 // More dust, light particles, city sparkles  
        case .water: return 14 // More bubbles, organisms, light rays
        case .desert: return 8 // More sand particles, heat shimmer
        case .mountain: return 11 // More mist particles, snow specks
        case .indoor: return 7 // More dust motes, light specks
        case .unknown: return 8 // More generic particles
        }
    }
    
    func particleColors(for index: Int) -> [Color] {
        guard colors.count > 0 else {
            return [Color.gray.opacity(0.15), Color.gray.opacity(0.08), Color.clear]
        }
        return [
            colors.safeAccess(index).opacity(0.15),
            colors.safeAccess(index + 2).opacity(0.08),
            Color.clear
        ]
    }
    
    func particleSize(for index: Int) -> CGFloat {
        let baseSizes: [CGFloat] = [8, 12, 6, 10, 14, 5, 9, 11]
        guard baseSizes.count > 0 else { return 8.0 }
        return baseSizes[index % baseSizes.count]
    }
    
    func particlePosition(for index: Int, size: CGSize, animation: Double, inConversation: Bool = false) -> CGPoint {
        if inConversation {
            // Ultra-simple positioning during conversation for maximum smoothness
            let seed = Double(index) * 2.5
            let slowSpeed = 0.05  // Very slow movement
            let simpleAnim = animation * slowSpeed + seed
            
            return CGPoint(
                x: size.width * (0.2 + 0.6 * (0.5 + sin(simpleAnim) * 0.3)),
                y: size.height * (0.2 + 0.6 * (0.5 + cos(simpleAnim) * 0.3))
            )
        } else {
            // Full movement when idle
            let seed = Double(index) * 2.7
            let speed = 0.08 + Double(index % 3) * 0.03
            let animSpeed = animation * speed + seed
            
            return CGPoint(
                x: size.width * (0.15 + 0.7 * (0.5 + sin(animSpeed) * 0.4)),
                y: size.height * (0.15 + 0.7 * (0.5 + cos(animSpeed * 0.8) * 0.4))
            )
        }
    }
    
    func particleOpacity(for index: Int, animation: Double) -> Double {
        // Simplified opacity calculation
        let seed = Double(index) * 1.6
        return 0.35 + sin(animation * 0.3 + seed) * 0.15  // Reduced variation, smoother animation
    }
    
    func particleBlur(for index: Int) -> CGFloat {
        let blurs: [CGFloat] = [1.0, 1.5, 0.5, 2.0, 1.2, 0.8]
        guard blurs.count > 0 else { return 1.0 }
        return blurs[index % blurs.count]
    }
    
    // Lighting properties
    var lightingColors: [Color] {
        [
            timeOfDay.lightingModifier.opacity(0.3),
            timeOfDay.lightingModifier.opacity(0.1),
            Color.clear
        ]
    }
    
    var lightingCenter: UnitPoint {
        switch timeOfDay {
        case .dawn: return UnitPoint(x: 0.2, y: 0.3)
        case .morning: return UnitPoint(x: 0.3, y: 0.2)
        case .afternoon: return UnitPoint(x: 0.5, y: 0.1)
        case .evening: return UnitPoint(x: 0.7, y: 0.3)
        case .night: return UnitPoint(x: 0.5, y: 0.8)
        case .lateNight: return UnitPoint(x: 0.5, y: 0.9)
        }
    }
    
    var lightingIntensity: Double {
        switch timeOfDay {
        case .dawn: return 0.4
        case .morning: return 0.3
        case .afternoon: return 0.2
        case .evening: return 0.5
        case .night: return 0.6
        case .lateNight: return 0.7
        }
    }
}

// Safe array access extension
extension Array where Element == Color {
    func safeAccess(_ index: Int) -> Color {
        guard !isEmpty && count > 0 else { return Color.gray }
        let safeIndex = index >= 0 ? index % count : 0
        return self[safeIndex]
    }
}

// MARK: - Adaptive Canvas View

struct AdaptiveCanvas: View {
    // Environment and context
    @StateObject private var locationManager = LocationManager()
    
    // Canvas state
    @State private var currentEnvironment: CanvasEnvironment = .unknown
    @State private var currentTimeOfDay: TimeOfDay = .morning
    @State private var activeRipples: [ActiveRipple] = []
    @State private var canvasColors: [Color] = []
    @State private var baseAnimation: Double = 0.0
    
    // Ripple triggers
    let userSpeaking: Bool
    let guidoSpeaking: Bool
    let conversationState: ConversationState
    let audioLevel: Float
    let testEnvironment: CanvasEnvironment?
    
    // Animation timing
    @State private var animationTimer: Timer?
    @State private var rippleCleanupTimer: Timer?
    @State private var continuousRippleTimer: Timer?
    
    // Performance monitoring
    @State private var performanceMode: PerformanceMode = .auto
    @State private var lastFrameTime: Date = Date()
    @State private var frameTimeHistory: [TimeInterval] = []
    
    enum PerformanceMode {
        case auto    // Automatically adjust based on performance
        case high    // Full quality always
        case low     // Simplified always
    }
    
    init(userSpeaking: Bool = false, 
         guidoSpeaking: Bool = false, 
         conversationState: ConversationState = .idle,
         audioLevel: Float = 0.0,
         testEnvironment: CanvasEnvironment? = nil) {
        self.userSpeaking = userSpeaking
        self.guidoSpeaking = guidoSpeaking
        self.conversationState = conversationState
        self.audioLevel = audioLevel
        self.testEnvironment = testEnvironment
    }
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Deep radial background orb - always present
                backgroundOrb(size: geometry.size)
                
                // Ambient liquid textures (performance aware)
                ambientLiquidTextures(size: geometry.size)
                
                // Properly sized ripple layers
                ForEach(activeRipples.prefix(shouldUseHighQuality ? 3 : 1)) { ripple in
                    RippleLayer(
                        ripple: ripple,
                        environment: currentEnvironment,
                        canvasSize: geometry.size,
                        colors: canvasColors
                    )
                }
                
                // No overlay needed - the beautiful orb speaks for itself
            }
            .clipped()
            .drawingGroup() // GPU optimization for complex layering
        }
        .onAppear {
            setupCanvas()
            startAnimations()
        }
        .onDisappear {
            stopAnimations()
        }
        .onChange(of: userSpeaking) { speaking in
            // No ripples when user speaks - keep the experience peaceful and clean
            if !speaking {
                stopContinuousRipples()
            }
        }
        .onChange(of: guidoSpeaking) { speaking in
            // No ripples when AI speaks - just the beautiful background responds
            if !speaking {
                stopContinuousRipples()
            }
        }
        .onChange(of: conversationState) { state in
            updateCanvasForState(state)
        }
        .onReceive(locationManager.$nearbyPlaces) { places in
            if testEnvironment == nil {
                updateEnvironment(from: places)
            }
        }
        .onChange(of: testEnvironment) { testEnv in
            if let testEnv = testEnv {
                withAnimation(.easeInOut(duration: 1.5)) {
                    currentEnvironment = testEnv
                    updateCanvasColors()
                }
            }
        }
    }
    
    // MARK: - Background Orb System
    
    private func backgroundOrb(size: CGSize) -> some View {
        let colors = canvasColors
        let envContext = environmentContext
        
        return ZStack {
            // Deep atmospheric base layer
            atmosphericBase(size: size, colors: colors, context: envContext)
            
            // Mid-layer environmental storytelling
            environmentalMidLayer(size: size, colors: colors, context: envContext)
            
            // Glassy refraction surface layer
            glassyRefractionLayer(size: size, colors: colors, context: envContext)
            
            // Organic depth particles
            organicDepthParticles(size: size, colors: colors, context: envContext)
            
            // Time-of-day atmospheric lighting
            atmosphericLighting(size: size, context: envContext)
        }
        .animation(.easeInOut(duration: 4.0), value: canvasColors)
        .animation(.easeInOut(duration: 3.0), value: currentTimeOfDay)
    }
    
    // Rich environmental context for immersive experiences
    private var environmentContext: EnvironmentContext {
        EnvironmentContext(
            environment: currentEnvironment,
            timeOfDay: currentTimeOfDay,
            colors: canvasColors,
            isActive: isInActiveConversation
        )
    }
    
    // Enhanced atmospheric foundation with smooth anti-aliased gradients
    private func atmosphericBase(size: CGSize, colors: [Color], context: EnvironmentContext) -> some View {
        let maxRadius = min(size.width, size.height) * 0.95
        
        return ZStack {
            // Enhanced primary atmospheric gradient with more color steps
            RadialGradient(
                colors: context.atmosphericColors,
                center: context.atmosphericCenter,
                startRadius: 0,
                endRadius: maxRadius
            )
            .drawingGroup() // GPU acceleration for smoother gradients
            
            // Enhanced secondary depth gradient with softer transitions
            RadialGradient(
                colors: [
                    context.depthColors[0],
                    context.depthColors[0].opacity(0.7),
                    context.depthColors[1],
                    context.depthColors[1].opacity(0.5),
                    context.depthColors[2],
                    Color.clear
                ],
                center: context.depthCenter,
                startRadius: maxRadius * 0.15,
                endRadius: maxRadius * 0.85
            )
            .blendMode(.multiply)
            .drawingGroup()
            
            // Enhanced ambient layer with more color steps
            LinearGradient(
                colors: [
                    context.ambientColors[0],
                    context.ambientColors[0].opacity(0.7),
                    context.ambientColors[1],
                    context.ambientColors[1].opacity(0.5),
                    context.ambientColors[2],
                    Color.clear
                ],
                startPoint: context.ambientDirection.start,
                endPoint: context.ambientDirection.end
            )
            .blendMode(.overlay)
            .opacity(0.5)
            .drawingGroup()
        }
        .drawingGroup()
    }
    
    // Performance-optimized environmental layer
    private func environmentalMidLayer(size: CGSize, colors: [Color], context: EnvironmentContext) -> some View {
        let maxRadius = min(size.width, size.height) * 0.75
        
        return ZStack {
            if isInActiveConversation {
                // Simplified version during conversation for performance
                ForEach(0..<min(context.characteristicCount, 3), id: \.self) { index in
                    RadialGradient(
                        colors: [
                            context.characteristicColors(for: index)[0],
                            context.characteristicColors(for: index)[1].opacity(0.4),
                            Color.clear
                        ],
                        center: context.characteristicCenter(for: index),
                        startRadius: maxRadius * 0.2,
                        endRadius: maxRadius * context.characteristicRadius(for: index)
                    )
                    .blendMode(context.characteristicBlendMode(for: index))
                    .opacity(context.characteristicOpacity(for: index) * 0.8)
                }
            } else {
                // Full detail when idle
                ForEach(0..<context.characteristicCount, id: \.self) { index in
                    RadialGradient(
                        colors: [
                            context.characteristicColors(for: index)[0],
                            context.characteristicColors(for: index)[0].opacity(0.6),
                            context.characteristicColors(for: index)[1],
                            context.characteristicColors(for: index)[1].opacity(0.3),
                            Color.clear
                        ],
                        center: context.characteristicCenter(for: index),
                        startRadius: maxRadius * 0.1,
                        endRadius: maxRadius * context.characteristicRadius(for: index)
                    )
                    .blendMode(context.characteristicBlendMode(for: index))
                    .opacity(context.characteristicOpacity(for: index))
                    .scaleEffect(1.0 + sin(baseAnimation * context.characteristicSpeed(for: index) + Double(index)) * 0.06)
                    .rotationEffect(.degrees(sin(baseAnimation * context.characteristicSpeed(for: index) * 0.5) * 2))
                }
                
                // Environmental veil only when idle
                RadialGradient(
                    colors: [
                        colors.safeAccess(0).opacity(0.05),
                        colors.safeAccess(2).opacity(0.03),
                        Color.clear
                    ],
                    center: UnitPoint(
                        x: 0.5 + sin(baseAnimation * 0.06) * 0.08,
                        y: 0.5 + cos(baseAnimation * 0.04) * 0.1
                    ),
                    startRadius: 0,
                    endRadius: maxRadius * 1.1
                )
                .blendMode(.multiply)
                .opacity(0.6)
            }
        }
        .drawingGroup()
    }
    
    // Environmental refraction layer (no white center elements)
    private func glassyRefractionLayer(size: CGSize, colors: [Color], context: EnvironmentContext) -> some View {
        let maxRadius = min(size.width, size.height) * 0.7
        
        return ZStack {
            // Environmental color refraction only
            RadialGradient(
                colors: [
                    context.refractionColors[0].opacity(0.08),
                    context.refractionColors[0].opacity(0.05),
                    context.refractionColors[1].opacity(0.06),
                    context.refractionColors[1].opacity(0.03),
                    Color.clear
                ],
                center: UnitPoint(
                    x: 0.5 + sin(baseAnimation * 0.35 + 1.2) * 0.025,
                    y: 0.5 + cos(baseAnimation * 0.28 + 1.2) * 0.018
                ),
                startRadius: maxRadius * 0.3,
                endRadius: maxRadius * 0.9
            )
            .blendMode(.screen)
            .opacity(0.5)
            
            // Subtle environmental glow (no center start)
            RadialGradient(
                colors: [
                    context.refractionColors[1].opacity(0.04),
                    Color.clear
                ],
                center: UnitPoint(
                    x: 0.5 + sin(baseAnimation * 0.15 + 2.1) * 0.02,
                    y: 0.5 + cos(baseAnimation * 0.12 + 2.1) * 0.025
                ),
                startRadius: maxRadius * 0.4,
                endRadius: maxRadius * 1.2
            )
            .blendMode(.softLight)
            .opacity(0.4)
        }
        .drawingGroup()
    }
    
    // Ultra-smooth particle system optimized for conversation
    private func organicDepthParticles(size: CGSize, colors: [Color], context: EnvironmentContext) -> some View {
        ZStack {
            if isInActiveConversation {
                // Minimal particles during conversation for maximum smoothness
                ForEach(0..<min(context.particleCount / 3, 4), id: \.self) { index in
                    Circle()
                        .fill(
                            // Ultra-simple fill for smooth conversation
                            context.particleColors(for: index)[0].opacity(0.4)
                        )
                        .frame(width: context.particleSize(for: index) * 0.8, height: context.particleSize(for: index) * 0.8)
                        .position(context.particlePosition(for: index, size: size, animation: baseAnimation, inConversation: true))
                        .opacity(0.6) // Static opacity for performance
                        .blur(radius: 1.0) // Fixed blur for performance
                }
            } else {
                // Full particles when idle
                ForEach(0..<context.particleCount, id: \.self) { index in
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [
                                    context.particleColors(for: index)[0],
                                    context.particleColors(for: index)[1].opacity(0.5),
                                    Color.clear
                                ],
                                center: .center,
                                startRadius: 0,
                                endRadius: 20
                            )
                        )
                        .frame(width: context.particleSize(for: index), height: context.particleSize(for: index))
                        .position(context.particlePosition(for: index, size: size, animation: baseAnimation, inConversation: false))
                        .opacity(context.particleOpacity(for: index, animation: baseAnimation))
                        .blur(radius: context.particleBlur(for: index))
                }
            }
        }
        .drawingGroup()
    }
    
    // Performance-optimized atmospheric lighting
    private func atmosphericLighting(size: CGSize, context: EnvironmentContext) -> some View {
        let maxRadius = min(size.width, size.height) * 0.6
        
        return ZStack {
            if isInActiveConversation {
                // Simplified lighting during conversation
                RadialGradient(
                    colors: [
                        context.lightingColors[0].opacity(0.12),
                        context.lightingColors[1].opacity(0.06),
                        Color.clear
                    ],
                    center: context.lightingCenter,
                    startRadius: 0,
                    endRadius: maxRadius
                )
                .blendMode(.overlay)
                .opacity(context.lightingIntensity * 0.8)
            } else {
                // Full lighting when idle
                RadialGradient(
                    colors: [
                        context.lightingColors[0].opacity(0.15),
                        context.lightingColors[0].opacity(0.08),
                        context.lightingColors[1].opacity(0.12),
                        context.lightingColors[1].opacity(0.05),
                        Color.clear
                    ],
                    center: context.lightingCenter,
                    startRadius: 0,
                    endRadius: maxRadius
                )
                .blendMode(.overlay)
                .opacity(context.lightingIntensity)
                
                // Breathing glow only when idle
                RadialGradient(
                    colors: [
                        context.lightingColors[0].opacity(0.06),
                        context.lightingColors[1].opacity(0.03),
                        Color.clear
                    ],
                    center: UnitPoint(
                        x: 0.5 + sin(baseAnimation * 0.08) * 0.06,
                        y: 0.5 + cos(baseAnimation * 0.06) * 0.08
                    ),
                    startRadius: maxRadius * 0.3,
                    endRadius: maxRadius * 1.3
                )
                .blendMode(.screen)
                .opacity(0.5)
            }
        }
        .drawingGroup()
    }
    
    private func backgroundGradient(size: CGSize) -> some View {
        ZStack {
            // Ensure we have enough colors for safe access
            let colors = canvasColors
            guard colors.count >= 7 else {
                // Fallback for insufficient colors
                return AnyView(
                    RadialGradient(
                        colors: colors.map { $0.opacity(currentTimeOfDay.brightness) },
                        center: UnitPoint(x: 0.5, y: 0.5),
                        startRadius: size.width * 0.1,
                        endRadius: size.width * 0.8
                    )
                )
            }
            
            return AnyView(ZStack {
                if isInActiveConversation || !shouldUseHighQuality {
                    // Ultra-simplified gradient during conversations or poor performance
                    RadialGradient(
                        colors: [
                            colors[2].opacity(currentTimeOfDay.brightness * 0.4),
                            colors[4].opacity(currentTimeOfDay.brightness * 0.7),
                            colors[6].opacity(currentTimeOfDay.brightness)
                        ],
                        center: UnitPoint(x: 0.5, y: 0.5),
                        startRadius: size.width * 0.1,
                        endRadius: size.width * 0.8
                    )
                } else {
                    // Full quality gradient when idle
                    // Deep base layer for depth
                    LinearGradient(
                        colors: [
                            colors[0].opacity(currentTimeOfDay.brightness * 0.8),
                            colors[1].opacity(currentTimeOfDay.brightness * 0.6),
                            colors[2].opacity(currentTimeOfDay.brightness * 0.4)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    
                    // Main radial gradient - perfectly centered
                    RadialGradient(
                        colors: [
                            colors[2].opacity(currentTimeOfDay.brightness * 0.3),
                            colors[3].opacity(currentTimeOfDay.brightness * 0.6),
                            colors[4].opacity(currentTimeOfDay.brightness * 0.8),
                            colors[5].opacity(currentTimeOfDay.brightness * 0.9),
                            colors[6].opacity(currentTimeOfDay.brightness)
                        ],
                        center: UnitPoint(x: 0.5, y: 0.5), // Perfect center
                        startRadius: size.width * 0.05,
                        endRadius: size.width * 0.85
                    )
                    .blendMode(.multiply)
                    
                    // Secondary radial for variety and depth
                    RadialGradient(
                        colors: [
                            colors[1].opacity(currentTimeOfDay.brightness * 0.2),
                            colors[3].opacity(currentTimeOfDay.brightness * 0.4),
                            colors[5].opacity(currentTimeOfDay.brightness * 0.3),
                            Color.clear
                        ],
                        center: UnitPoint(x: 0.3, y: 0.7), // Off-center for variety
                        startRadius: size.width * 0.1,
                        endRadius: size.width * 0.6
                    )
                    .blendMode(.overlay)
                    
                    // Subtle highlight gradient
                    RadialGradient(
                        colors: [
                            colors[4].opacity(currentTimeOfDay.brightness * 0.15),
                            colors[6].opacity(currentTimeOfDay.brightness * 0.1),
                            Color.clear
                        ],
                        center: UnitPoint(x: 0.7, y: 0.3), // Another off-center for depth
                        startRadius: size.width * 0.05,
                        endRadius: size.width * 0.5
                    )
                    .blendMode(.softLight)
                    
                    // Time of day lighting overlay
                    RadialGradient(
                        colors: [
                            currentTimeOfDay.lightingModifier.opacity(0.3),
                            currentTimeOfDay.lightingModifier.opacity(0.15),
                            Color.clear
                        ],
                        center: UnitPoint(x: 0.5, y: 0.5), // Centered lighting
                        startRadius: size.width * 0.1,
                        endRadius: size.width * 0.7
                    )
                    .blendMode(.overlay)
                }
            })
        }
        .animation(.easeInOut(duration: 2.5), value: canvasColors)
        .animation(.easeInOut(duration: 2.0), value: currentTimeOfDay)
    }
    
    // MARK: - Ambient Liquid Textures
    
    private func ambientLiquidTextures(size: CGSize) -> some View {
        ZStack {
            // Smart performance scaling based on activity and device performance
            if isInActiveConversation || !shouldUseHighQuality {
                // Simplified during conversations or poor performance
                ForEach(0..<1, id: \.self) { layer in
                    simpleLiquidTexture(size: size, layer: layer)
                }
                
                // Minimal floating elements during speech
                ForEach(0..<2, id: \.self) { index in
                    simplifiedFloatingTexture(size: size, index: index)
                }
            } else {
                // Full beauty when idle and performance is good
                ForEach(0..<2, id: \.self) { layer in // Reduced from 3 for performance
                    liquidDropTexture(size: size, layer: layer)
                }
                
                // Floating discs for visual depth
                ForEach(0..<4, id: \.self) { index in // Reduced from 6 for performance
                    randomFloatingTexture(size: size, index: index)
                }
                
                // Large floating elements for depth
                ForEach(0..<2, id: \.self) { index in // Reduced from 3 for performance
                    largeFloatingDisc(size: size, index: index)
                }
            }
        }
        .drawingGroup() // GPU optimization for texture rendering
    }
    
    // Ultra-simplified floating texture for performance during speech
    private func simplifiedFloatingTexture(size: CGSize, index: Int) -> some View {
        let colors = currentEnvironment.primaryColors
        let safeColor = colors.first ?? Color.gray.opacity(0.1)
        let randomSeed = Double(index) * 2.0
        let speed = 0.1
        let scale = 0.04 + Double(index % 2) * 0.02
        
        return Circle()
            .fill(safeColor.opacity(0.15))
            .frame(width: size.width * scale, height: size.width * scale)
            .position(
                x: size.width * (0.2 + 0.6 * (0.5 + sin(baseAnimation * speed + randomSeed) * 0.5)),
                y: size.height * (0.2 + 0.6 * (0.5 + cos(baseAnimation * speed * 0.8 + randomSeed) * 0.5))
            )
            .opacity(0.4)
    }
    
    // Ultra-simple texture for performance during conversations
    private func simpleLiquidTexture(size: CGSize, layer: Int) -> some View {
        let colors = currentEnvironment.primaryColors
        let safeColors: [Color] = colors.count >= 3 ? colors : [Color.gray.opacity(0.05), Color.clear]
        
        return Circle()
            .fill(
                RadialGradient(
                    colors: [
                        safeColors[0].opacity(0.1),
                        Color.clear
                    ],
                    center: UnitPoint(x: 0.5, y: 0.5),
                    startRadius: 0,
                    endRadius: size.width * 0.3
                )
            )
            .scaleEffect(0.8 + sin(baseAnimation * 0.1) * 0.1)
            .opacity(0.3)
    }
    
    private func liquidDropTexture(size: CGSize, layer: Int) -> some View {
        let colors = currentEnvironment.primaryColors
        let layerDelay = Double(layer) * 0.6
        let layerScale = 0.25 + Double(layer) * 0.15
        let randomOffset = Double(layer) * 0.3
        
        // Safe color access with bounds checking
        let safeColors: [Color]
        if colors.count >= 3 {
            safeColors = colors
        } else {
            // Fallback colors if insufficient
            safeColors = [Color.gray.opacity(0.1), Color.gray.opacity(0.05), Color.clear]
        }
        
        let colorStartIndex = layer % max(1, safeColors.count - 2)
        let color1Index = min(colorStartIndex, safeColors.count - 1)
        let color2Index = min(colorStartIndex + 1, safeColors.count - 1)
        let color3Index = min(colorStartIndex + 2, safeColors.count - 1)
        
        return Circle()
            .fill(
                RadialGradient(
                    colors: [
                        safeColors[color1Index].opacity(0.18 + Double(layer) * 0.03),
                        safeColors[color2Index].opacity(0.12),
                        safeColors[color3Index].opacity(0.06),
                        Color.clear
                    ],
                    center: UnitPoint(
                        x: 0.5 + sin(baseAnimation * 0.35 + layerDelay + randomOffset) * 0.25,
                        y: 0.5 + cos(baseAnimation * 0.25 + layerDelay + randomOffset) * 0.2
                    ),
                    startRadius: 0,
                    endRadius: size.width * (0.25 + Double(layer) * 0.12)
                )
            )
            .scaleEffect(layerScale + sin(baseAnimation * 0.2 + layerDelay) * 0.08)
            .opacity(0.5 + sin(baseAnimation * 0.35 + layerDelay) * 0.25)
            .blur(radius: 0.5 + Double(layer) * 0.4)
    }
    
    private func randomFloatingTexture(size: CGSize, index: Int) -> some View {
        let colors = currentEnvironment.primaryColors
        let randomSeed = Double(index) * 2.14159 // Use pi-based offset for randomness
        let speed = 0.12 + Double(index % 3) * 0.08
        let scale = 0.06 + Double(index % 4) * 0.025
        
        // Safe color access with bounds checking
        let safeColors: [Color]
        if colors.count >= 3 {
            safeColors = colors
        } else {
            // Fallback colors if insufficient
            safeColors = [Color.gray.opacity(0.08), Color.gray.opacity(0.04), Color.clear]
        }
        
        // Use varied color combinations across the spectrum with safe indexing
        let colorIndex1 = index % safeColors.count
        let colorIndex2 = (index + 2) % safeColors.count
        let colorIndex3 = (index + 4) % safeColors.count
        
        return Ellipse()
            .fill(
                RadialGradient(
                    colors: [
                        safeColors[colorIndex1].opacity(0.22),
                        safeColors[colorIndex2].opacity(0.14),
                        safeColors[colorIndex3].opacity(0.08),
                        Color.clear
                    ],
                    center: UnitPoint(
                        x: 0.3 + sin(baseAnimation * 0.4 + randomSeed) * 0.4,
                        y: 0.3 + cos(baseAnimation * 0.3 + randomSeed) * 0.4
                    ),
                    startRadius: 0,
                    endRadius: 40
                )
            )
            .frame(
                width: size.width * scale,
                height: size.width * scale * (0.6 + sin(baseAnimation + randomSeed) * 0.4)
            )
            .position(
                x: size.width * (0.15 + 0.7 * (0.5 + sin(baseAnimation * speed + randomSeed) * 0.5)),
                y: size.height * (0.15 + 0.7 * (0.5 + cos(baseAnimation * speed * 0.7 + randomSeed) * 0.5))
            )
            .rotationEffect(.degrees(baseAnimation * 8 + randomSeed * 45))
            .opacity(0.35 + sin(baseAnimation * 0.5 + randomSeed) * 0.25)
    }
    
    // Large floating discs for enhanced depth and visual richness
    private func largeFloatingDisc(size: CGSize, index: Int) -> some View {
        let colors = currentEnvironment.primaryColors
        let safeColors: [Color] = colors.count >= 6 ? colors : [Color.blue.opacity(0.1), Color.cyan.opacity(0.08), Color.white.opacity(0.04)]
        
        let randomSeed = Double(index) * 3.14159 + 1.5 // Different seed for variety
        let speed = 0.08 + Double(index % 2) * 0.05 // Slower, more majestic movement
        let baseScale = 0.12 + Double(index % 3) * 0.04 // Larger base size
        
        // Use complementary colors for more vibrancy
        let colorIndex1 = (index * 2) % safeColors.count
        let colorIndex2 = (index * 2 + 3) % safeColors.count
        let colorIndex3 = (index * 2 + 5) % safeColors.count
        
        return Circle()
            .fill(
                RadialGradient(
                    colors: [
                        safeColors[colorIndex1].opacity(0.28),
                        safeColors[colorIndex2].opacity(0.18),
                        safeColors[colorIndex3].opacity(0.10),
                        Color.clear
                    ],
                    center: UnitPoint(
                        x: 0.2 + sin(baseAnimation * 0.3 + randomSeed) * 0.6,
                        y: 0.2 + cos(baseAnimation * 0.2 + randomSeed) * 0.6
                    ),
                    startRadius: 0,
                    endRadius: 60
                )
            )
            .frame(
                width: size.width * baseScale,
                height: size.width * baseScale * (0.8 + sin(baseAnimation * 0.4 + randomSeed) * 0.2)
            )
            .position(
                x: size.width * (0.1 + 0.8 * (0.5 + sin(baseAnimation * speed + randomSeed) * 0.5)),
                y: size.height * (0.1 + 0.8 * (0.5 + cos(baseAnimation * speed * 0.6 + randomSeed) * 0.5))
            )
            .rotationEffect(.degrees(baseAnimation * 5 + randomSeed * 30))
            .opacity(0.45 + sin(baseAnimation * 0.4 + randomSeed) * 0.25)
            .blur(radius: 0.5)
    }
    
    // MARK: - Setup and Animation Management
    
    private func setupCanvas() {
        updateTimeOfDay()
        updateEnvironment(from: locationManager.nearbyPlaces)
        updateCanvasColors()
    }
    
    private func startAnimations() {
        // Balanced timing for smooth particles and conversation
        let baseInterval: TimeInterval
        if isInActiveConversation {
            baseInterval = 0.1   // 10fps during speech - smooth particles, efficient conversation
        } else if shouldUseHighQuality {
            baseInterval = 0.066 // 15fps when idle - smooth and responsive
        } else {
            baseInterval = 0.1   // 10fps when performance is poor
        }
        
        animationTimer = Timer.scheduledTimer(withTimeInterval: baseInterval, repeats: true) { _ in
            // Update performance metrics
            self.updatePerformanceMetrics()
            
            // Remove animation wrapper during any speech activity for better performance
            if self.isInActiveConversation || self.userSpeaking || self.guidoSpeaking {
                self.baseAnimation += baseInterval
            } else {
                withAnimation(.linear(duration: baseInterval)) {
                    self.baseAnimation += baseInterval
                }
            }
        }
        
        // Less frequent ripple cleanup during conversations
        let cleanupInterval = isInActiveConversation ? 1.0 : 0.5
        rippleCleanupTimer = Timer.scheduledTimer(withTimeInterval: cleanupInterval, repeats: true) { _ in
            self.cleanupExpiredRipples()
        }
        
        // Time of day updates
        Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { _ in
            self.updateTimeOfDay()
        }
    }
    
    // Helper to determine conversation state for performance scaling
    private var isInActiveConversation: Bool {
        return userSpeaking || guidoSpeaking || conversationState == .listening || conversationState == .thinking
    }
    
    // Performance-aware quality determination
    private var shouldUseHighQuality: Bool {
        switch performanceMode {
        case .high:
            return true
        case .low:
            return false
        case .auto:
            // Use simplified graphics during conversations or if performance is poor
            return !isInActiveConversation && averageFrameTime < 0.05 // 20fps threshold
        }
    }
    
    private var averageFrameTime: TimeInterval {
        guard !frameTimeHistory.isEmpty else { return 0.016 } // 60fps default
        return frameTimeHistory.reduce(0, +) / Double(frameTimeHistory.count)
    }
    
    private func updatePerformanceMetrics() {
        let now = Date()
        let frameTime = now.timeIntervalSince(lastFrameTime)
        lastFrameTime = now
        
        frameTimeHistory.append(frameTime)
        if frameTimeHistory.count > 10 { // Keep last 10 frames
            frameTimeHistory.removeFirst()
        }
    }
    
    private func stopAnimations() {
        animationTimer?.invalidate()
        rippleCleanupTimer?.invalidate()
        continuousRippleTimer?.invalidate()
        animationTimer = nil
        rippleCleanupTimer = nil
        continuousRippleTimer = nil
    }
    
    private func startContinuousRipples(direction: RippleDirection) {
        stopContinuousRipples() // Stop any existing continuous ripples
        
        // Realistic pond ripple timing - like dropping pebbles
        let rippleInterval: TimeInterval = 3.0 // Slow, natural timing
        continuousRippleTimer = Timer.scheduledTimer(withTimeInterval: rippleInterval, repeats: true) { _ in
            // Create ripples based on actual speaking state
            let shouldCreateRipple: Bool
            if direction == .inward {
                shouldCreateRipple = self.userSpeaking || self.currentConversationState == .listening
            } else {
                shouldCreateRipple = self.guidoSpeaking || self.currentConversationState == .speaking
            }
            
            guard shouldCreateRipple && self.activeRipples.count < 3 else { return }
            
            let ripple = ActiveRipple(
                direction: direction,
                startTime: Date(),
                intensity: direction == .inward ? max(0.5, Double(self.audioLevel) * 0.8) : 0.8,
                pattern: self.currentEnvironment.ripplePattern
            )
            
            // Smooth, organic appearance like real water
            withAnimation(.easeOut(duration: 0.5)) {
                self.activeRipples.append(ripple)
            }
        }
    }
    
    private func stopContinuousRipples() {
        continuousRippleTimer?.invalidate()
        continuousRippleTimer = nil
    }
    
    private func updateTimeOfDay() {
        let hour = Calendar.current.component(.hour, from: Date())
        let newTimeOfDay: TimeOfDay
        
        switch hour {
        case 5..<7:
            newTimeOfDay = .dawn
        case 7..<12:
            newTimeOfDay = .morning
        case 12..<17:
            newTimeOfDay = .afternoon
        case 17..<19:
            newTimeOfDay = .evening
        case 19..<23:
            newTimeOfDay = .night
        default:
            newTimeOfDay = .lateNight
        }
        
        if newTimeOfDay != currentTimeOfDay {
            withAnimation(.easeInOut(duration: 2.0)) {
                currentTimeOfDay = newTimeOfDay
            }
        }
    }
    
    private func updateEnvironment(from places: [NearbyPlace]) {
        let newEnvironment = determineEnvironment(from: places)
        
        if newEnvironment != currentEnvironment {
            withAnimation(.easeInOut(duration: 3.0)) {
                currentEnvironment = newEnvironment
                updateCanvasColors()
            }
        }
    }
    
    private func determineEnvironment(from places: [NearbyPlace]) -> CanvasEnvironment {
        let categories = places.map { $0.category.lowercased() }
        
        // Beach indicators
        if categories.contains(where: { $0.contains("beach") || $0.contains("coast") || $0.contains("shore") }) {
            return .beach
        }
        
        // Park indicators
        if categories.contains(where: { $0.contains("park") || $0.contains("garden") || $0.contains("nature") || $0.contains("forest") }) {
            return .park
        }
        
        // Water indicators
        if categories.contains(where: { $0.contains("lake") || $0.contains("river") || $0.contains("harbor") || $0.contains("marina") }) {
            return .water
        }
        
        // Mountain indicators
        if categories.contains(where: { $0.contains("mountain") || $0.contains("hill") || $0.contains("peak") }) {
            return .mountain
        }
        
        // Urban indicators
        if categories.contains(where: { $0.contains("building") || $0.contains("office") || $0.contains("shop") || $0.contains("restaurant") }) {
            return .urban
        }
        
        // Indoor indicators
        if categories.contains(where: { $0.contains("museum") || $0.contains("mall") || $0.contains("hotel") || $0.contains("hospital") }) {
            return .indoor
        }
        
        return .unknown
    }
    
    private func updateCanvasColors() {
        canvasColors = currentEnvironment.primaryColors
    }
    
    private func updateCanvasForState(_ state: ConversationState) {
        // Subtle, creative visual feedback - no overwhelming brightness
        switch state {
        case .listening:
            // User speaking: Subtle warm undertone (breath rising from bottom)
            currentConversationState = .listening
        case .thinking, .processing:
            // AI thinking: Gentle center pulse (neural activity)
            currentConversationState = .thinking
        case .speaking:
            // AI speaking: Cool crystalline flow (knowledge from top)
            currentConversationState = .speaking
        case .idle:
            // Peaceful natural state
            currentConversationState = .idle
        }
    }
    
    // Conversation state for visual effects
    @State private var currentConversationState: ConversationState = .idle
    

    
    // MARK: - Ripple Management
    
    private func triggerUserRipple() {
        // Clear, strong initial ripple for user speaking
        let intensity = min(1.0, max(0.6, Double(audioLevel) * 2.0))
        let ripple = ActiveRipple(
            direction: .inward,
            startTime: Date(),
            intensity: intensity,
            pattern: currentEnvironment.ripplePattern
        )
        
        withAnimation(.easeOut(duration: 0.3)) {
            activeRipples.append(ripple)
        }
    }
    
    private func triggerGuidoRipple() {
        // Clear, strong initial ripple for AI speaking
        let ripple = ActiveRipple(
            direction: .outward,
            startTime: Date(),
            intensity: 0.9, // Strong but not overwhelming
            pattern: currentEnvironment.ripplePattern
        )
        
        withAnimation(.easeOut(duration: 0.3)) {
            activeRipples.append(ripple)
        }
    }
    
    private func cleanupExpiredRipples() {
        activeRipples.removeAll { $0.isExpired }
    }
}

// MARK: - Ripple Layer Component

struct RippleLayer: View {
    let ripple: ActiveRipple
    let environment: CanvasEnvironment
    let canvasSize: CGSize
    let colors: [Color]
    
    @State private var animationProgress: Double = 0.0
    
    var body: some View {
        GeometryReader { geometry in
            switch ripple.pattern.style {
            case .liquidPond:
                liquidPondRipple
            case .circular:
                circularRipple
            case .organic:
                organicRipple
            case .geometric:
                geometricRipple
            case .branching:
                branchingRipple
            case .angular:
                angularRipple
            case .flowing:
                flowingRipple
            case .soft:
                softRipple
            }
        }
        .onAppear {
            startRippleAnimation()
        }
    }
    
    // MARK: - Liquid Pond Ripples (Physics-based)
    
    private var liquidPondRipple: some View {
        ZStack {
            // More rings for realistic pond effect
            let ringCount = isInActiveConversation ? 4 : 6  // More rings for better pond effect
            ForEach(0..<ringCount, id: \.self) { rippleIndex in
                liquidRippleRing(index: rippleIndex)
            }
        }
        .frame(width: canvasSize.width, height: canvasSize.height)
        .position(x: canvasSize.width * 0.5, y: canvasSize.height * 0.5)
    }
    
    // Helper to check conversation state for performance scaling
    private var isInActiveConversation: Bool {
        // Simplified check based on ripple age (active ripples suggest conversation)
        return ripple.age < 2.0
    }
    
    private func liquidRippleRing(index: Int) -> some View {
        // Organic pond timing - each ring follows the previous naturally
        let ringDelay = Double(index) * 0.3 * ripple.pattern.viscosity
        let ringProgress = max(0, min(1.0, animationProgress - ringDelay))
        
        // Realistic pond physics - slow, organic expansion
        let baseScale: Double
        if ripple.direction == .inward {
            // User speaking: Ripples start from edge, contract inward (like reverse pond)
            baseScale = (1.0 - ringProgress) * 2.0
        } else {
            // AI speaking: Classic pond ripples - start small, expand naturally
            baseScale = ringProgress * 1.5
        }
        
        // Natural ring spacing and timing
        let ringScale = baseScale * (0.3 + Double(index) * 0.2)
        
        // Organic opacity decay - like real water ripples
        let ringOpacity = (1.0 - pow(ringProgress, 1.5)) * ripple.intensity * 0.6
        
        // Realistic physics-based decay
        let distanceDecay = exp(-Double(index) * 0.15)
        let timeDecay = exp(-ringProgress * 0.8) // Much slower, more organic
        let totalDecay = distanceDecay * timeDecay
        
        // Pond-like line thickness - thin like real water ripples
        let lineThickness = max(0.5, 2.0 * totalDecay * (1.0 - Double(index) * 0.2))
        
        return Circle()
            .stroke(
                // Glassy water gradient - like looking through water
                RadialGradient(
                    colors: [
                        rippleColor.opacity(ringOpacity * 0.9),
                        rippleColor.opacity(ringOpacity * 0.6),
                        rippleColor.opacity(ringOpacity * 0.3),
                        rippleColor.opacity(ringOpacity * 0.1),
                        Color.clear
                    ],
                    center: .center,
                    startRadius: 0,
                    endRadius: 30
                ),
                lineWidth: lineThickness
            )
            .scaleEffect(ringScale * 40) // Much smaller, more realistic scale
            .opacity(totalDecay * 0.8)
            // Realistic water refraction effect
            .overlay(
                Circle()
                    .stroke(
                        rippleColor.opacity(ringOpacity * 0.15),
                        lineWidth: lineThickness * 0.5
                    )
                    .scaleEffect(ringScale * 40 * 1.02) // Slightly larger for refraction
                    .blur(radius: 0.5)
            )
            // Removed white highlight overlay to eliminate center white dot
    }
    
    private var circularRipple: some View {
        ZStack {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .stroke(
                        rippleColor.opacity(rippleOpacity(for: index)),
                        lineWidth: rippleWidth(for: index)
                    )
                    .scaleEffect(rippleScale(for: index))
            }
        }
        .frame(width: canvasSize.width, height: canvasSize.height)
        .position(x: canvasSize.width * 0.5, y: canvasSize.height * 0.5)
    }
    
    private var organicRipple: some View {
        ZStack {
            ForEach(0..<5, id: \.self) { index in
                RoundedRectangle(cornerRadius: 20)
                    .fill(
                        RadialGradient(
                            colors: [
                                rippleColor.opacity(rippleOpacity(for: index) * 0.3),
                                rippleColor.opacity(rippleOpacity(for: index) * 0.1),
                                Color.clear
                            ],
                            center: .center,
                            startRadius: 0,
                            endRadius: 100
                        )
                    )
                    .scaleEffect(
                        x: rippleScale(for: index) * (1.0 + sin(animationProgress * 3 + Double(index)) * 0.2),
                        y: rippleScale(for: index) * (1.0 + cos(animationProgress * 2.5 + Double(index)) * 0.15)
                    )
                    .rotationEffect(.degrees(animationProgress * 10 + Double(index * 45)))
            }
        }
        .frame(width: canvasSize.width, height: canvasSize.height)
        .position(x: canvasSize.width * 0.5, y: canvasSize.height * 0.5)
    }
    
    private var geometricRipple: some View {
        ZStack {
            ForEach(0..<4, id: \.self) { index in
                Rectangle()
                    .stroke(
                        rippleColor.opacity(rippleOpacity(for: index)),
                        lineWidth: rippleWidth(for: index)
                    )
                    .scaleEffect(rippleScale(for: index))
                    .rotationEffect(.degrees(45 + animationProgress * 20))
            }
        }
        .frame(width: canvasSize.width * 0.8, height: canvasSize.width * 0.8)
        .position(x: canvasSize.width * 0.5, y: canvasSize.height * 0.5)
    }
    
    private var branchingRipple: some View {
        ZStack {
            ForEach(0..<8, id: \.self) { index in
                RoundedRectangle(cornerRadius: 2)
                    .fill(rippleColor.opacity(rippleOpacity(for: index)))
                    .frame(
                        width: 4,
                        height: rippleScale(for: index) * 150
                    )
                    .offset(y: -rippleScale(for: index) * 75)
                    .rotationEffect(.degrees(Double(index) * 45))
            }
        }
        .frame(width: canvasSize.width, height: canvasSize.height)
        .position(x: canvasSize.width * 0.5, y: canvasSize.height * 0.5)
    }
    
    private var angularRipple: some View {
        ZStack {
            ForEach(0..<6, id: \.self) { index in
                Path { path in
                    let center = CGPoint(x: canvasSize.width * 0.5, y: canvasSize.height * 0.5)
                    let radius = rippleScale(for: index) * 150
                    
                    for i in 0..<6 {
                        let angle = Double(i) * .pi / 3
                        let point = CGPoint(
                            x: center.x + cos(angle) * radius,
                            y: center.y + sin(angle) * radius
                        )
                        
                        if i == 0 {
                            path.move(to: point)
                        } else {
                            path.addLine(to: point)
                        }
                    }
                    path.closeSubpath()
                }
                .stroke(
                    rippleColor.opacity(rippleOpacity(for: index)),
                    lineWidth: rippleWidth(for: index)
                )
            }
        }
    }
    
    private var flowingRipple: some View {
        ZStack {
            ForEach(0..<4, id: \.self) { index in
                Wave(
                    frequency: ripple.pattern.frequency,
                    amplitude: ripple.pattern.amplitude * rippleScale(for: index),
                    phase: animationProgress * 2 + Double(index)
                )
                .stroke(
                    rippleColor.opacity(rippleOpacity(for: index)),
                    lineWidth: rippleWidth(for: index)
                )
            }
        }
        .frame(width: canvasSize.width, height: canvasSize.height)
    }
    
    private var softRipple: some View {
        ZStack {
            ForEach(0..<3, id: \.self) { index in
                Ellipse()
                    .fill(
                        RadialGradient(
                            colors: [
                                rippleColor.opacity(rippleOpacity(for: index) * 0.2),
                                Color.clear
                            ],
                            center: .center,
                            startRadius: 0,
                            endRadius: 100
                        )
                    )
                    .scaleEffect(rippleScale(for: index))
                    .blur(radius: 5)
            }
        }
        .frame(width: canvasSize.width, height: canvasSize.height)
        .position(x: canvasSize.width * 0.5, y: canvasSize.height * 0.5)
    }
    
    // MARK: - Ripple Calculations
    
    private var rippleColor: Color {
        if colors.isEmpty {
            return Color.blue
        }
        
        let colorIndex = Int(ripple.age * 2) % colors.count
        return colors[colorIndex]
    }
    
    private func rippleScale(for index: Int) -> Double {
        let baseScale = ripple.direction == .inward 
            ? (1.0 - animationProgress) 
            : animationProgress
        
        let layerOffset = Double(index) * 0.2
        let adjustedProgress = max(0, animationProgress - layerOffset)
        
        return baseScale * adjustedProgress * ripple.intensity
    }
    
    private func rippleOpacity(for index: Int) -> Double {
        let baseOpacity = 1.0 - (ripple.age / 3.0) // Fade over 3 seconds
        let layerOpacity = 1.0 - (Double(index) * 0.3)
        
        return max(0, baseOpacity * layerOpacity * ripple.intensity)
    }
    
    private func rippleWidth(for index: Int) -> CGFloat {
        let baseWidth: CGFloat = 2.0
        let intensityMultiplier = CGFloat(ripple.intensity)
        
        return baseWidth * intensityMultiplier * (1.0 - CGFloat(index) * 0.2)
    }
    
    private func startRippleAnimation() {
        withAnimation(.linear(duration: 3.0 / ripple.pattern.speed)) {
            animationProgress = 1.0
        }
    }
}

// MARK: - Wave Shape

struct Wave: Shape {
    let frequency: Double
    let amplitude: Double
    let phase: Double
    
    func path(in rect: CGRect) -> Path {
        var path = Path()
        
        let stepX = rect.width / 100
        
        for i in 0...100 {
            let x = Double(i) * stepX
            let normalizedX = x / rect.width
            let y = rect.midY + sin(normalizedX * frequency * 2 * .pi + phase) * amplitude * rect.height * 0.1
            
            let point = CGPoint(x: x, y: y)
            
            if i == 0 {
                path.move(to: point)
            } else {
                path.addLine(to: point)
            }
        }
        
        return path
    }
}

// MARK: - Conversation State for Canvas

enum ConversationState {
    case idle
    case listening
    case processing
    case speaking
    case thinking
}

// MARK: - Extensions for Testing

extension CanvasEnvironment: CaseIterable {
    var displayName: String {
        switch self {
        case .beach: return "🏖️"
        case .park: return "🌳"
        case .urban: return "🏙️"
        case .indoor: return "🏠"
        case .mountain: return "⛰️"
        case .water: return "💧"
        case .desert: return "🏜️"
        case .unknown: return "❓"
        }
    }
}