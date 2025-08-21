# 🧪 MCP Mode Testing Instructions

## 🎯 **Quick Setup: Enable MCP Mode**

Add this button to your `RealtimeConversationView` or any convenient view:

```swift
// Add this to your SwiftUI view
VStack {
    // Your existing UI...
    
    // MCP Testing Controls
    HStack {
        Button("🧪 Enable MCP Mode") {
            Task { @MainActor in
                FeatureFlags.shared.migrationState = .hybrid
                FeatureFlags.shared.enableMCPForCategory(.location)
                FeatureFlags.shared.debugLoggingEnabled = true
                FeatureFlags.shared.isPerformanceMonitoringEnabled = true
                
                print("✅ TESTING: Enabled MCP for location tools")
                print("🔍 TESTING: Debug logging enabled")
                print("📊 TESTING: Performance monitoring enabled")
                print("🎯 TESTING: Migration state: \(FeatureFlags.shared.migrationState.displayName)")
            }
        }
        .padding()
        .background(Color.green)
        .foregroundColor(.white)
        .cornerRadius(8)
        
        Button("🔄 Back to Legacy") {
            Task { @MainActor in
                FeatureFlags.shared.migrationState = .legacy
                FeatureFlags.shared.debugLoggingEnabled = true
                
                print("🔙 TESTING: Reverted to Legacy mode")
                print("🎯 TESTING: Migration state: \(FeatureFlags.shared.migrationState.displayName)")
            }
        }
        .padding()
        .background(Color.orange)
        .foregroundColor(.white)
        .cornerRadius(8)
    }
    .padding()
}
```

## 🗣️ **Test Commands (Voice)**

### **Test 1: Basic Location (MCP)**
**Command**: "Where am I?"

**Expected MCP Logs**:
```
🔧 [MCPToolCoordinator] Executing 'get_user_location' via MCP
🗺️ [LocationMCPServer] Executing tool: get_user_location
✅ [LocationMCPServer] Found user location
```

**Expected Legacy Logs** (for comparison):
```
🔧 Executing tool: get_user_location with parameters: [:]
✅ Tool response sent for call ID: call_xxxxx
```

### **Test 2: Restaurant Search (MCP)**  
**Command**: "Find Italian restaurants nearby"

**Expected MCP Logs**:
```
🔧 [MCPToolCoordinator] Executing 'find_nearby_restaurants' via MCP
🗺️ [LocationMCPServer] Executing tool: find_nearby_restaurants
✅ [LocationMCPServer] Found 4 restaurants
```

### **Test 3: Transportation (MCP)**
**Command**: "Where's the nearest subway station?"

**Expected MCP Logs**:
```
🔧 [MCPToolCoordinator] Executing 'find_nearby_transport' via MCP
🗺️ [LocationMCPServer] Executing tool: find_nearby_transport  
✅ [LocationMCPServer] Found 2 transport options
```

### **Test 4: Services (MCP)**
**Command**: "Find hospitals nearby"

**Expected MCP Logs**:
```
🔧 [MCPToolCoordinator] Executing 'find_nearby_services' via MCP
🗺️ [LocationMCPServer] Executing tool: find_nearby_services
✅ [LocationMCPServer] Found 3 services
```

### **Test 5: Directions (MCP)**
**Command**: "How do I get to Central Park?"

**Expected MCP Logs**:
```
🔧 [MCPToolCoordinator] Executing 'get_directions' via MCP
🗺️ [LocationMCPServer] Executing tool: get_directions
✅ [LocationMCPServer] Generated directions to Central Park
```

## 🔍 **What to Look For**

### **✅ Success Indicators**:
1. **MCP Routing Logs**: Should see `🗺️ [LocationMCPServer]` instead of just `🔧 Executing tool`
2. **Same Response Quality**: AI responses should be identical to Legacy mode
3. **Same Voice Quality**: Audio should be unchanged
4. **Same Response Times**: Performance should be similar

### **❌ Failure Indicators**:
1. **No MCP Logs**: Still seeing legacy tool execution
2. **Different Responses**: AI giving different answers
3. **Voice Degradation**: Audio quality problems
4. **Slower Performance**: Noticeable delays

## 🚨 **Emergency Rollback**

If anything goes wrong:

```swift
Button("🚨 EMERGENCY ROLLBACK") {
    FeatureFlags.shared.emergencyRollbackToLegacy(reason: "MCP testing issues")
    print("🚨 ROLLED BACK TO LEGACY - ALL SAFE")
}
```

## 📊 **Performance Comparison**

1. **Test in Legacy Mode first** - note response times
2. **Switch to MCP Mode** - test same commands
3. **Compare logs and timing**

**Expected**: Nearly identical performance between modes.

## 🎯 **Test Sequence**

1. **Enable MCP Mode** (use button above)
2. **Test**: "Where am I?" → Check for MCP logs
3. **Test**: "Find restaurants nearby" → Check for MCP logs  
4. **Test**: "Find subway stations" → Check for MCP logs
5. **Switch back to Legacy** → Verify legacy logs return
6. **Compare**: Voice quality, response times, accuracy

---

## 🚀 **Ready to Test!**

1. Add the buttons to your UI
2. Tap "🧪 Enable MCP Mode"  
3. Test the voice commands above
4. Watch the logs for MCP routing
5. Report back with results!

**The key thing to watch for: `🗺️ [LocationMCPServer]` logs instead of just `🔧 Executing tool`**