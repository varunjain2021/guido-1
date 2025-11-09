# Uncomment the next line to define a global platform for your project
platform :ios, '16.0'

target 'guido-1' do
  # Use static libraries to avoid framework embedding issues
  use_frameworks! :linkage => :static

  # Pods for guido-1
  
  # ==== VOICE ACTIVITY DETECTION (VAD) ====
  # Using working libraries available on CocoaPods:
  
  # 🎤 Audio Processing Foundation
  pod 'AudioKit', '~> 5.0'  # Powerful audio processing toolkit
  
  # 🌐 WebRTC for Realtime API
  pod 'GoogleWebRTC', '~> 1.1'
  
  # 🔍 Alternative VAD approaches we can implement:
  # AudioKit provides excellent real-time audio analysis capabilities
  # We'll use it to enhance our custom VAD implementation

  target 'guido-1Tests' do
    inherit! :search_paths
    # Pods for testing
  end

  target 'guido-1UITests' do
    # Pods for testing
  end

end

# Post-install script to ensure proper deployment targets
post_install do |installer|
  installer.pods_project.targets.each do |target|
    target.build_configurations.each do |config|
      config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '16.0'
      config.build_settings['CODE_SIGN_IDENTITY'] = ''
      # Fix Xcode 15+ user script sandboxing breaking CocoaPods resource scripts
      config.build_settings['ENABLE_USER_SCRIPT_SANDBOXING'] = 'NO'
    end
  end
end 