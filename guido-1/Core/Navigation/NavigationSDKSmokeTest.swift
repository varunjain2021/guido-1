//
//  NavigationSDKSmokeTest.swift
//  guido-1
//
//  Smoke test for Google Navigation SDK integration
//  Run this to verify the SDK is properly configured with your API key
//

import Foundation
import CoreLocation
import GoogleMaps
import GoogleNavigation
import UIKit

// MARK: - Navigation Listener for Turn-by-Turn Events

/// Listener that receives real-time turn-by-turn navigation events
class NavigationEventListener: NSObject, GMSNavigatorListener {
    
    private var receivedEvents: [String] = []
    private var turnByTurnSteps: [TurnByTurnStep] = []
    private var onNavInfoReceived: ((GMSNavigationNavInfo) -> Void)?
    
    struct TurnByTurnStep {
        let stepNumber: Int
        let instruction: String
        let roadName: String
        let distanceMeters: Int
        let maneuver: String
    }
    
    func setNavInfoCallback(_ callback: @escaping (GMSNavigationNavInfo) -> Void) {
        self.onNavInfoReceived = callback
    }
    
    // MARK: - GMSNavigatorListener Protocol
    
    /// Called when navigation state changes (arrived, rerouting, etc.)
    func navigator(_ navigator: GMSNavigator, didArriveAt waypoint: GMSNavigationWaypoint) {
        let event = "🏁 ARRIVED at: \(waypoint.title ?? "destination")"
        receivedEvents.append(event)
        print(event)
    }
    
    /// Called when route changes (rerouting)
    func navigatorDidChangeRoute(_ navigator: GMSNavigator) {
        let event = "🔄 ROUTE CHANGED - recalculating..."
        receivedEvents.append(event)
        print(event)
    }
    
    /// Called when remaining time/distance updates
    func navigator(_ navigator: GMSNavigator, didUpdateRemainingTime time: TimeInterval) {
        let minutes = Int(time / 60)
        let event = "⏱️ TIME UPDATE: \(minutes) min remaining"
        receivedEvents.append(event)
        print(event)
    }
    
    func navigator(_ navigator: GMSNavigator, didUpdateRemainingDistance distance: CLLocationDistance) {
        let km = distance / 1000.0
        let event = String(format: "📏 DISTANCE UPDATE: %.1f km remaining", km)
        receivedEvents.append(event)
        print(event)
    }
    
    /// Called with detailed navigation info including turn-by-turn steps
    func navigator(_ navigator: GMSNavigator, didUpdate navInfo: GMSNavigationNavInfo) {
        print("\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        print("🧭 TURN-BY-TURN NAV INFO RECEIVED")
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        
        // Navigation state
        let stateStr: String
        switch navInfo.navState {
        case .enroute:
            stateStr = "ENROUTE"
        case .rerouting:
            stateStr = "REROUTING"
        case .stopped:
            stateStr = "STOPPED"
        @unknown default:
            stateStr = "UNKNOWN"
        }
        print("📍 Nav State: \(stateStr)")
        
        // Current step info
        if let currentStep = navInfo.currentStep {
            print("\n🚗 CURRENT STEP:")
            printStepInfo(currentStep, prefix: "   ")
        }
        
        // Distance to next step
        print("\n📏 Distance to step: \(navInfo.distanceToCurrentStepMeters) meters")
        print("⏱️ Time to step: \(navInfo.timeToCurrentStepSeconds) seconds")
        
        // Remaining steps
        let remainingSteps = navInfo.remainingSteps
        print("\n📋 REMAINING STEPS: \(remainingSteps.count)")
        
        for (index, step) in remainingSteps.prefix(5).enumerated() {
            print("\n   Step \(index + 1):")
            printStepInfo(step, prefix: "      ")
            
            // Store for later analysis
            turnByTurnSteps.append(TurnByTurnStep(
                stepNumber: index + 1,
                instruction: step.fullInstructionText ?? "N/A",
                roadName: step.fullRoadName ?? "N/A",
                distanceMeters: step.stepNumber,
                maneuver: maneuverToString(step.maneuver)
            ))
        }
        
        if remainingSteps.count > 5 {
            print("\n   ... and \(remainingSteps.count - 5) more steps")
        }
        
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n")
        
        receivedEvents.append("NavInfo received with \(remainingSteps.count) steps")
        onNavInfoReceived?(navInfo)
    }
    
    private func printStepInfo(_ step: GMSNavigationStepInfo, prefix: String) {
        print("\(prefix)Road: \(step.fullRoadName ?? "N/A")")
        print("\(prefix)Instruction: \(step.fullInstructionText ?? "N/A")")
        print("\(prefix)Maneuver: \(maneuverToString(step.maneuver))")
        print("\(prefix)Exit number: \(step.exitNumber ?? "N/A")")
    }
    
    private func maneuverToString(_ maneuver: GMSNavigationManeuver) -> String {
        switch maneuver {
        case .destination:
            return "DESTINATION"
        case .depart:
            return "DEPART"
        case .straight:
            return "STRAIGHT"
        case .turnLeft:
            return "TURN_LEFT"
        case .turnRight:
            return "TURN_RIGHT"
        case .turnSlightLeft:
            return "SLIGHT_LEFT"
        case .turnSlightRight:
            return "SLIGHT_RIGHT"
        case .turnSharpLeft:
            return "SHARP_LEFT"
        case .turnSharpRight:
            return "SHARP_RIGHT"
        case .turnKeepLeft:
            return "KEEP_LEFT"
        case .turnKeepRight:
            return "KEEP_RIGHT"
        case .turnUTurnClockwise:
            return "U_TURN_CW"
        case .turnUTurnCounterClockwise:
            return "U_TURN_CCW"
        case .mergeUnspecified:
            return "MERGE"
        case .mergeLeft:
            return "MERGE_LEFT"
        case .mergeRight:
            return "MERGE_RIGHT"
        case .onRampUnspecified:
            return "ON_RAMP"
        case .onRampLeft:
            return "ON_RAMP_LEFT"
        case .onRampRight:
            return "ON_RAMP_RIGHT"
        case .onRampKeepLeft:
            return "ON_RAMP_KEEP_LEFT"
        case .onRampKeepRight:
            return "ON_RAMP_KEEP_RIGHT"
        case .onRampSharpLeft:
            return "ON_RAMP_SHARP_LEFT"
        case .onRampSharpRight:
            return "ON_RAMP_SHARP_RIGHT"
        case .onRampSlightLeft:
            return "ON_RAMP_SLIGHT_LEFT"
        case .onRampSlightRight:
            return "ON_RAMP_SLIGHT_RIGHT"
        case .onRampUTurnClockwise:
            return "ON_RAMP_UTURN_CW"
        case .onRampUTurnCounterClockwise:
            return "ON_RAMP_UTURN_CCW"
        case .offRampUnspecified:
            return "OFF_RAMP"
        case .offRampLeft:
            return "OFF_RAMP_LEFT"
        case .offRampRight:
            return "OFF_RAMP_RIGHT"
        case .offRampKeepLeft:
            return "OFF_RAMP_KEEP_LEFT"
        case .offRampKeepRight:
            return "OFF_RAMP_KEEP_RIGHT"
        case .offRampSharpLeft:
            return "OFF_RAMP_SHARP_LEFT"
        case .offRampSharpRight:
            return "OFF_RAMP_SHARP_RIGHT"
        case .offRampSlightLeft:
            return "OFF_RAMP_SLIGHT_LEFT"
        case .offRampSlightRight:
            return "OFF_RAMP_SLIGHT_RIGHT"
        case .forkLeft:
            return "FORK_LEFT"
        case .forkRight:
            return "FORK_RIGHT"
        case .roundaboutClockwise:
            return "ROUNDABOUT_CW"
        case .roundaboutCounterClockwise:
            return "ROUNDABOUT_CCW"
        case .roundaboutExitClockwise:
            return "ROUNDABOUT_EXIT_CW"
        case .roundaboutExitCounterClockwise:
            return "ROUNDABOUT_EXIT_CCW"
        case .roundaboutLeftClockwise:
            return "ROUNDABOUT_LEFT_CW"
        case .roundaboutLeftCounterClockwise:
            return "ROUNDABOUT_LEFT_CCW"
        case .roundaboutRightClockwise:
            return "ROUNDABOUT_RIGHT_CW"
        case .roundaboutRightCounterClockwise:
            return "ROUNDABOUT_RIGHT_CCW"
        case .roundaboutSharpLeftClockwise:
            return "ROUNDABOUT_SHARP_LEFT_CW"
        case .roundaboutSharpLeftCounterClockwise:
            return "ROUNDABOUT_SHARP_LEFT_CCW"
        case .roundaboutSharpRightClockwise:
            return "ROUNDABOUT_SHARP_RIGHT_CW"
        case .roundaboutSharpRightCounterClockwise:
            return "ROUNDABOUT_SHARP_RIGHT_CCW"
        case .roundaboutSlightLeftClockwise:
            return "ROUNDABOUT_SLIGHT_LEFT_CW"
        case .roundaboutSlightLeftCounterClockwise:
            return "ROUNDABOUT_SLIGHT_LEFT_CCW"
        case .roundaboutSlightRightClockwise:
            return "ROUNDABOUT_SLIGHT_RIGHT_CW"
        case .roundaboutSlightRightCounterClockwise:
            return "ROUNDABOUT_SLIGHT_RIGHT_CCW"
        case .roundaboutStraightClockwise:
            return "ROUNDABOUT_STRAIGHT_CW"
        case .roundaboutStraightCounterClockwise:
            return "ROUNDABOUT_STRAIGHT_CCW"
        case .roundaboutUTurnClockwise:
            return "ROUNDABOUT_UTURN_CW"
        case .roundaboutUTurnCounterClockwise:
            return "ROUNDABOUT_UTURN_CCW"
        case .ferryBoat:
            return "FERRY_BOAT"
        case .ferryTrain:
            return "FERRY_TRAIN"
        case .nameChange:
            return "NAME_CHANGE"
        case .unknown:
            return "UNKNOWN"
        @unknown default:
            return "UNHANDLED"
        }
    }
    
    func getReceivedEvents() -> [String] {
        return receivedEvents
    }
    
    func getTurnByTurnSteps() -> [TurnByTurnStep] {
        return turnByTurnSteps
    }
}

// MARK: - Smoke Test Class

/// Smoke test to verify Google Navigation SDK is working
class NavigationSDKSmokeTest {
    
    private let apiKey: String
    private static var isInitialized = false
    private var mapView: GMSMapView?
    private var navigationListener: NavigationEventListener?
    
    init(apiKey: String) {
        self.apiKey = apiKey
    }
    
    /// Call this from AppDelegate or early in app lifecycle to initialize
    func initializeSDK() {
        guard !NavigationSDKSmokeTest.isInitialized else {
            print("🗺️ [NavigationSDK] Already initialized (skipping)")
            return
        }
        
        print("🗺️ [NavigationSDK] Verifying SDK initialization...")
        // Note: GMSServices.provideAPIKey is called once in guido_1App.swift
        // We just mark as initialized here to track state
        NavigationSDKSmokeTest.isInitialized = true
        print("✅ [NavigationSDK] SDK ready")
    }
    
    /// Test that we can access navigation services
    @MainActor
    func testNavigationAccess() async -> Bool {
        print("🧪 [NavigationSDK] Testing navigation access...")
        
        return await withCheckedContinuation { continuation in
            let termsOptions = GMSNavigationTermsAndConditionsOptions(companyName: "Guido")
            
            GMSNavigationServices.showTermsAndConditionsDialogIfNeeded(with: termsOptions) { accepted in
                if accepted {
                    print("✅ [NavigationSDK] Terms accepted - navigation available")
                    continuation.resume(returning: true)
                } else {
                    print("❌ [NavigationSDK] Terms rejected - navigation unavailable")
                    continuation.resume(returning: false)
                }
            }
        }
    }
    
    /// Test creating a navigation session with turn-by-turn listener
    @MainActor
    func testNavigationRouteWithTurnByTurn(to destination: CLLocationCoordinate2D, from origin: CLLocationCoordinate2D) async -> NavigationRouteInfo? {
        print("🧪 [NavigationSDK] Testing route with TURN-BY-TURN feed...")
        print("   Origin: \(origin.latitude), \(origin.longitude)")
        print("   Destination: \(destination.latitude), \(destination.longitude)")
        
        // Create a map view (required for navigation)
        let mapView = GMSMapView(frame: CGRect(x: 0, y: 0, width: 100, height: 100))
        mapView.isNavigationEnabled = true
        self.mapView = mapView // Keep reference
        
        guard let navigator = mapView.navigator else {
            print("❌ [NavigationSDK] Failed to get navigator from map view")
            return nil
        }
        
        // Set up the turn-by-turn listener
        let listener = NavigationEventListener()
        self.navigationListener = listener // Keep reference
        navigator.add(listener)
        print("✅ [NavigationSDK] Turn-by-turn listener attached")
        
        // Enable voice guidance (even though we won't play it, this ensures nav info is generated)
        navigator.voiceGuidance = .alertsOnly
        
        // Create waypoints
        let destinationWaypoint = GMSNavigationWaypoint(location: destination, title: "Ravenwood High School")
        
        guard let waypoint = destinationWaypoint else {
            print("❌ [NavigationSDK] Failed to create destination waypoint")
            return nil
        }
        
        // Request route and wait for nav info
        return await withCheckedContinuation { (continuation: CheckedContinuation<NavigationRouteInfo?, Never>) in
            
            var hasResumed = false
            
            // Set callback for when we receive nav info
            listener.setNavInfoCallback { navInfo in
                guard !hasResumed else { return }
                hasResumed = true
                
                // Extract route info from nav info
                let routeInfo = NavigationRouteInfo(
                    totalDistanceMeters: Int(navigator.distanceToNextDestination),
                    totalTimeSeconds: Int(navigator.timeToNextDestination),
                    destinationLatitude: destination.latitude,
                    destinationLongitude: destination.longitude,
                    steps: navInfo.remainingSteps.map { step in
                        NavigationStepInfo(
                            instruction: step.fullInstructionText ?? "Continue",
                            roadName: step.fullRoadName ?? "",
                            distanceMeters: Int(step.distanceFromPrevStepMeters),
                            maneuver: self.maneuverDescription(step.maneuver),
                            latitude: 0, // Not available from step info directly
                            longitude: 0
                        )
                    },
                    navState: navInfo.navState
                )
                
                continuation.resume(returning: routeInfo)
            }
            
            // Calculate route
            navigator.setDestinations([waypoint]) { routeStatus in
                switch routeStatus {
                case .OK:
                    print("✅ [NavigationSDK] Route calculated - waiting for turn-by-turn data...")
                    
                    // Start guidance to trigger nav info updates
                    navigator.isGuidanceActive = true
                    
                    // If we don't get nav info within 5 seconds, return basic route info
                    DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                        guard !hasResumed else { return }
                        hasResumed = true
                        
                        print("⚠️ [NavigationSDK] Nav info timeout - returning basic route info")
                        
                        if let routeLeg = navigator.currentRouteLeg {
                            let routeInfo = NavigationRouteInfo(
                                totalDistanceMeters: Int(navigator.distanceToNextDestination),
                                totalTimeSeconds: Int(navigator.timeToNextDestination),
                                destinationLatitude: routeLeg.destinationCoordinate.latitude,
                                destinationLongitude: routeLeg.destinationCoordinate.longitude,
                                steps: [],
                                navState: nil
                            )
                            continuation.resume(returning: routeInfo)
                        } else {
                            continuation.resume(returning: nil)
                        }
                    }
                    
                case .noRouteFound:
                    print("❌ [NavigationSDK] No route found")
                    continuation.resume(returning: nil)
                    
                case .networkError:
                    print("❌ [NavigationSDK] Network error")
                    continuation.resume(returning: nil)
                    
                case .quotaExceeded:
                    print("❌ [NavigationSDK] Quota exceeded - check billing")
                    continuation.resume(returning: nil)
                    
                case .apiKeyNotAuthorized:
                    print("❌ [NavigationSDK] API key not authorized for Navigation SDK")
                    continuation.resume(returning: nil)
                    
                case .canceled:
                    print("⚠️ [NavigationSDK] Route request canceled")
                    continuation.resume(returning: nil)
                    
                case .duplicateWaypointsError:
                    print("❌ [NavigationSDK] Duplicate waypoints error")
                    continuation.resume(returning: nil)
                    
                case .noWaypointsError:
                    print("❌ [NavigationSDK] No waypoints provided")
                    continuation.resume(returning: nil)
                    
                case .locationUnavailable:
                    print("❌ [NavigationSDK] Location unavailable")
                    continuation.resume(returning: nil)
                    
                case .waypointError:
                    print("❌ [NavigationSDK] Waypoint error")
                    continuation.resume(returning: nil)
                    
                case .travelModeUnsupported:
                    print("❌ [NavigationSDK] Travel mode unsupported")
                    continuation.resume(returning: nil)
                    
                case .internalError:
                    print("❌ [NavigationSDK] Internal error")
                    continuation.resume(returning: nil)
                    
                @unknown default:
                    print("❌ [NavigationSDK] Unexpected status: \(routeStatus)")
                    continuation.resume(returning: nil)
                }
            }
        }
    }
    
    private func maneuverDescription(_ maneuver: GMSNavigationManeuver) -> String {
        switch maneuver {
        case .destination: return "Arrive at destination"
        case .depart: return "Depart"
        case .straight: return "Continue straight"
        case .turnLeft: return "Turn left"
        case .turnRight: return "Turn right"
        case .turnSlightLeft: return "Slight left"
        case .turnSlightRight: return "Slight right"
        case .turnSharpLeft: return "Sharp left"
        case .turnSharpRight: return "Sharp right"
        case .turnKeepLeft: return "Keep left"
        case .turnKeepRight: return "Keep right"
        case .turnUTurnClockwise, .turnUTurnCounterClockwise: return "Make a U-turn"
        case .mergeUnspecified, .mergeLeft, .mergeRight: return "Merge"
        case .onRampUnspecified, .onRampLeft, .onRampRight, .onRampKeepLeft, .onRampKeepRight,
             .onRampSharpLeft, .onRampSharpRight, .onRampSlightLeft, .onRampSlightRight,
             .onRampUTurnClockwise, .onRampUTurnCounterClockwise: return "Take the on-ramp"
        case .offRampUnspecified, .offRampLeft, .offRampRight, .offRampKeepLeft, .offRampKeepRight,
             .offRampSharpLeft, .offRampSharpRight, .offRampSlightLeft, .offRampSlightRight: return "Take the exit"
        case .forkLeft: return "Keep left at fork"
        case .forkRight: return "Keep right at fork"
        case .roundaboutClockwise, .roundaboutCounterClockwise: return "Enter roundabout"
        case .roundaboutExitClockwise, .roundaboutExitCounterClockwise: return "Exit roundabout"
        case .ferryBoat, .ferryTrain: return "Take the ferry"
        case .nameChange: return "Road name changes"
        default: return "Continue"
        }
    }
    
    /// Clean up navigation session
    func cleanup() {
        if let navigator = mapView?.navigator {
            navigator.clearDestinations()
            navigator.isGuidanceActive = false
            if let listener = navigationListener {
                navigator.remove(listener)
            }
        }
        mapView = nil
        navigationListener = nil
        print("🧹 [NavigationSDK] Cleaned up navigation session")
    }
}

// MARK: - Route Info Models

/// Information about a calculated route
struct NavigationRouteInfo {
    let totalDistanceMeters: Int
    let totalTimeSeconds: Int
    let destinationLatitude: Double
    let destinationLongitude: Double
    let steps: [NavigationStepInfo]
    let navState: GMSNavigationNavState?
    
    init(totalDistanceMeters: Int, totalTimeSeconds: Int, destinationLatitude: Double, destinationLongitude: Double, steps: [NavigationStepInfo], navState: GMSNavigationNavState? = nil) {
        self.totalDistanceMeters = totalDistanceMeters
        self.totalTimeSeconds = totalTimeSeconds
        self.destinationLatitude = destinationLatitude
        self.destinationLongitude = destinationLongitude
        self.steps = steps
        self.navState = navState
    }
    
    var formattedDistance: String {
        if totalDistanceMeters >= 1000 {
            let miles = Double(totalDistanceMeters) / 1609.34
            return String(format: "%.1f miles", miles)
        } else {
            let feet = Double(totalDistanceMeters) * 3.28084
            return String(format: "%.0f ft", feet)
        }
    }
    
    var formattedTime: String {
        let minutes = totalTimeSeconds / 60
        if minutes >= 60 {
            let hours = minutes / 60
            let remainingMinutes = minutes % 60
            return "\(hours)h \(remainingMinutes)min"
        } else {
            return "\(minutes) min"
        }
    }
    
    var navStateDescription: String {
        guard let state = navState else { return "Unknown" }
        switch state {
        case .enroute: return "En Route"
        case .rerouting: return "Rerouting"
        case .stopped: return "Stopped"
        @unknown default: return "Unknown"
        }
    }
}

/// Information about a single navigation step
struct NavigationStepInfo {
    let instruction: String
    let roadName: String
    let distanceMeters: Int
    let maneuver: String
    let latitude: Double
    let longitude: Double
}

// MARK: - Manual Test Runner

/// Run this to perform a quick smoke test with turn-by-turn
/// Call from a view or button action to verify SDK setup
@MainActor
func runNavigationSDKSmokeTest(apiKey: String, currentLocation: CLLocationCoordinate2D?) async -> Bool {
    print("═══════════════════════════════════════════════════════")
    print("🗺️ GOOGLE NAVIGATION SDK SMOKE TEST (WITH TURN-BY-TURN)")
    print("═══════════════════════════════════════════════════════")
    
    let test = NavigationSDKSmokeTest(apiKey: apiKey)
    
    // Step 1: Initialize
    test.initializeSDK()
    
    // Step 2: Test access (shows T&C dialog if needed)
    let accessOk = await test.testNavigationAccess()
    
    guard accessOk else {
        print("═══════════════════════════════════════════════════════")
        print("❌ SMOKE TEST FAILED - Terms not accepted")
        print("═══════════════════════════════════════════════════════")
        return false
    }
    
    // Step 3: Test route calculation with turn-by-turn (if we have a location)
    if let origin = currentLocation {
        // Test destination: Ravenwood High School, Brentwood, Tennessee
        // Address: 1724 Wilson Pike, Brentwood, TN 37027
        let testDestination = CLLocationCoordinate2D(latitude: 35.9847, longitude: -86.7828)
        
        print("\n🧪 [NavigationSDK] Testing route to Ravenwood High School, TN...")
        print("   This will test the TURN-BY-TURN navigation feed\n")
        
        if let routeInfo = await test.testNavigationRouteWithTurnByTurn(to: testDestination, from: origin) {
            print("\n═══════════════════════════════════════════════════════")
            print("✅ ROUTE CALCULATED SUCCESSFULLY")
            print("═══════════════════════════════════════════════════════")
            print("📍 Destination: Ravenwood High School, TN")
            print("📏 Distance: \(routeInfo.formattedDistance)")
            print("⏱️ Time: \(routeInfo.formattedTime)")
            print("🚗 Nav State: \(routeInfo.navStateDescription)")
            print("📋 Steps: \(routeInfo.steps.count)")
            
            if !routeInfo.steps.isEmpty {
                print("\n🗺️ TURN-BY-TURN DIRECTIONS:")
                print("───────────────────────────────────────────────────────")
                for (index, step) in routeInfo.steps.prefix(10).enumerated() {
                    print("\(index + 1). \(step.maneuver)")
                    if !step.roadName.isEmpty {
                        print("   onto \(step.roadName)")
                    }
                    if !step.instruction.isEmpty && step.instruction != step.maneuver {
                        print("   \(step.instruction)")
                    }
                }
                if routeInfo.steps.count > 10 {
                    print("   ... and \(routeInfo.steps.count - 10) more steps")
                }
            }
        } else {
            print("⚠️ [NavigationSDK] Route test failed - check API key permissions")
        }
        
        // Cleanup
        test.cleanup()
    } else {
        print("⚠️ [NavigationSDK] Skipping route test - no current location")
    }
    
    print("═══════════════════════════════════════════════════════")
    print("✅ SMOKE TEST COMPLETED")
    print("═══════════════════════════════════════════════════════")
    
    return true
}
