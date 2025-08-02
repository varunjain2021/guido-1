# Guido AI Assistant - Modern Voice Activity Detection

A SwiftUI iOS app that demonstrates advanced Voice Activity Detection (VAD) for natural conversation with AI.

## 🎯 What's New - Modern VAD System

This app now implements a **state-of-the-art Voice Activity Detection system** that solves common turn detection problems:

### ✅ **Problems Solved**
- **Accurate turn detection** - knows when you're actually done speaking
- **Noise robustness** - works in real-world environments with background noise
- **No manual stopping** - automatically detects speech end points
- **Multiple VAD options** - choose the best solution for your needs

### 🏆 **VAD Technologies Available**

| Technology | Accuracy | Latency | Best For |
|------------|----------|---------|----------|
| **🥇 Silero VAD** | 95%+ | ~30ms | Production apps, highest accuracy |
| **🥈 WebRTC VAD** | 85-90% | ~10ms | Real-time apps, lightweight |
| **🥉 Cobra VAD** | 90%+ | <10ms | Commercial apps (requires API key) |
| **📱 Fallback VAD** | 70-80% | ~5ms | When external libraries unavailable |

## 🚀 Quick Setup

### 1. Clone the Repository
```bash
git clone <your-repo-url>
cd guido-1
```

### 2. Choose Your VAD Solution

**Option A: Silero VAD (Recommended)**
```ruby
# In your Podfile, uncomment:
pod 'Silero-VAD-for-iOS'
```

**Option B: WebRTC VAD (Lightweight)**
```ruby
# In your Podfile, uncomment:
pod 'VoiceActivityDetector'
```

**Option C: Picovoice Cobra (Commercial)**
```ruby
# In your Podfile, uncomment:
pod 'Cobra-iOS'
```

### 3. Install Dependencies
```bash
# Copy the template Podfile
cp Podfile.template Podfile

# Edit Podfile to uncomment your chosen VAD library
# Then install
pod install
```

### 4. Configure VAD in Code
```swift
// In AudioManager.swift, uncomment the imports for your chosen VAD:
import SileroVAD          // For Silero VAD
// import VoiceActivityDetector  // For WebRTC VAD
// import Cobra              // For Picovoice Cobra
```

### 5. Configure API Keys
```bash
# Copy the template configuration file
cp Config.template.plist Config.plist

# Edit Config.plist with your actual API keys:
# - OpenAI_API_Key: Your OpenAI API key
# - ElevenLabs_API_Key: Your ElevenLabs API key
```

**⚠️ Security Note:** Never commit `Config.plist` with real API keys to version control!

### 6. Build and Run! 🎉

## 🔧 Technical Architecture

### Modern VAD Pipeline
```
Audio Input → Resampling → VAD Processing → Confidence Score → Turn Detection
     ↓              ↓            ↓              ↓              ↓
   48kHz          16kHz      AI/Algorithm    0.0-1.0      Auto-stop
```

### VAD Configuration
```swift
struct ModernVADConfig {
    let type: VADType = .hybrid              // Use multiple VADs
    let silenceDuration: TimeInterval = 1.5  // Wait time after silence
    let minSpeechDuration: TimeInterval = 0.3 // Minimum valid speech
    let vadSampleRate: Int = 16000           // Optimal for VAD
    
    // Silero-specific settings
    let sileroThreshold: Float = 0.5         // AI confidence threshold
    let sileroWindowSize: Int = 1536         // 96ms windows
    
    // WebRTC-specific settings  
    let webrtcAggressiveness: Int = 2        // Noise tolerance (0-3)
    let webrtcFrameLength: Int = 320         // 20ms frames
}
```

## 📱 App Features

### Real-time VAD Feedback
- **🗣️ Speech Detection** - Visual confidence meter
- **🤐 Silence Detection** - Countdown timer
- **✅ Turn Complete** - Automatic processing
- **📊 Audio Visualization** - Live waveform display

### Intelligent Conversation Flow
1. **Tap to start** listening
2. **Speak naturally** - no need to hold button
3. **Visual feedback** shows VAD confidence
4. **Automatic stop** when you finish talking
5. **AI response** with speech synthesis
6. **Continue conversation** seamlessly

## 🎛️ VAD Tuning Guide

### For Noisy Environments
```swift
// Increase thresholds
let sileroThreshold: Float = 0.7        // Higher confidence required
let webrtcAggressiveness: Int = 3       // Maximum noise filtering
let silenceDuration: TimeInterval = 2.0 // Longer silence wait
```

### For Quiet Environments  
```swift
// Lower thresholds for sensitivity
let sileroThreshold: Float = 0.3        // More sensitive
let webrtcAggressiveness: Int = 1       // Light filtering
let silenceDuration: TimeInterval = 1.0 // Faster response
```

### For Multiple Speakers
```swift
// Use hybrid mode with strict requirements
let hybridRequiresBoth: Bool = true     // Both VADs must agree
let minSpeechDuration: TimeInterval = 0.5 // Longer minimum speech
```

## 🔍 Debugging VAD Issues

### Check VAD Status
The app shows real-time VAD information:
- **Status message** - Current VAD state
- **Confidence meter** - AI confidence (0-100%)
- **Source indicator** - Which VAD is active (Silero/WebRTC/Hybrid/Fallback)

### Common Issues

**"VAD not stopping"**
- Check `silenceThreshold` - may be too low
- Verify `silenceDuration` - may need to increase
- Look for background noise in environment

**"VAD too sensitive"**  
- Increase `minSpeechDuration` 
- Raise confidence thresholds
- Switch to less aggressive WebRTC mode

**"Poor accuracy"**
- Ensure Silero VAD is properly installed
- Check microphone permissions
- Verify audio sample rate (16kHz optimal)

### Debug Logs
Enable detailed logging:
```swift
// In AudioManager.swift, logs show:
print("🔍 VAD: SPEECH/SILENCE - confidence - source")
// Example: "🔍 VAD: SPEECH - 0.85 - Silero"
```

## 📚 Advanced Usage

### Custom VAD Implementation
```swift
// Extend with your own VAD algorithm
private func runCustomVAD(samples: [Float]) -> VADResult {
    // Your custom VAD logic here
    return VADResult(isSpeech: detected, confidence: confidence, source: "Custom")
}
```

### VAD Event Handling
```swift
// Listen for VAD events
audioManager.enableVAD { [weak self] in
    // Called when silence detected after speech
    self?.handleTurnComplete()
}
```

### Performance Monitoring
```swift
// Track VAD performance
let vadLatency = Date().timeIntervalSince(vadStartTime)
let accuracy = correctDetections / totalDetections
```

## 🏗️ Project Structure

```
guido-1/
├── Core/
│   ├── AudioManager.swift      # Modern VAD implementation
│   ├── OpenAIChatService.swift # AI conversation
│   └── ElevenLabsService.swift # Speech synthesis
├── Features/
│   ├── ListeningView.swift     # Main conversation UI
│   └── ProactiveGuideView.swift # Proactive mode
└── UI/
    └── Supporting views
```

## 📖 References & Research

- **Silero VAD**: [GitHub Repository](https://github.com/snakers4/silero-vad)
- **WebRTC VAD**: [Google WebRTC Project](https://webrtc.org/)
- **Apple Speech**: [SpeechAnalyzer (iOS 26+)](https://developer.apple.com/documentation/speech)
- **Picovoice Cobra**: [Official Documentation](https://picovoice.ai/docs/quick-start/cobra-ios/)

## 🛠️ Troubleshooting

### Build Issues
```bash
# Clean and rebuild
pod deintegrate
pod install
# Clean build folder in Xcode
```

### Runtime Issues
- Check microphone permissions in Settings
- Verify API keys are valid
- Ensure iOS 16+ target deployment
- **Test on physical device (not simulator)**

### ⚠️ Simulator Support
**This app requires a physical iOS device to run properly.**

- ✅ **Device builds**: Full functionality with real-time voice and WebRTC features
- ❌ **Simulator builds**: Limited functionality - WebRTC features disabled due to framework limitations

The GoogleWebRTC framework used for real-time communication does not support iOS Simulator. While the app includes conditional compilation to handle this gracefully, full functionality requires a physical device.

## 🤝 Contributing

We welcome contributions! Areas for improvement:
- Additional VAD algorithms
- Better confidence calibration  
- Multi-language support
- Real-time visualization enhancements

## 📄 License

This project is licensed under the MIT License - see the LICENSE file for details.

---

**Made with ❤️ for the future of voice interfaces** 