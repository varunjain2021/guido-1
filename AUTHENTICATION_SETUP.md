# Authentication Setup Guide

This guide will help you set up authentication for Guido using Supabase and Google OAuth.

## 🚀 Quick Start

### 1. Install Dependencies

First, install CocoaPods dependencies:

```bash
cd /path/to/guido-1
pod install
```

Then, add Supabase via Swift Package Manager in Xcode:
- See `SUPABASE_SPM_SETUP.md` for detailed instructions
- Add `https://github.com/supabase/supabase-swift` as a package dependency

### 2. Set up Supabase

1. **Create a Supabase project**
   - Go to [supabase.com](https://supabase.com)
   - Click "New Project"
   - Choose your organization and fill in project details
   - Wait for the project to be created

2. **Get your project credentials**
   - Go to Settings > API in your Supabase dashboard
   - Copy your **Project URL** and **anon/public key**

3. **Configure the app**
   - Copy `SupabaseConfig.template.swift` to `SupabaseConfig.swift`
   - Replace the placeholder values with your actual Supabase credentials:

```swift
struct SupabaseConfig {
    static let supabaseURL = "https://your-actual-project-id.supabase.co"
    static let supabaseAnonKey = "your-actual-anon-key-here"
    static let googleClientID = "your-google-client-id.apps.googleusercontent.com"
}
```

4. **Set up the database**
   - Go to the SQL Editor in your Supabase dashboard
   - Copy and run the SQL commands from `SupabaseConfig.template.swift` (see the comments at the bottom)
   - This will create the necessary tables and Row Level Security policies

### 3. Set up Google OAuth (Optional but Recommended)

1. **Create Google Cloud Project**
   - Go to [Google Cloud Console](https://console.cloud.google.com)
   - Create a new project or select an existing one
   - Enable the Google+ API

2. **Create OAuth credentials**
   - Go to Credentials > Create Credentials > OAuth 2.0 Client ID
   - Choose "iOS" as the application type
   - Enter your bundle identifier (e.g., `com.yourname.guido-1`)
   - Download the `GoogleService-Info.plist` file

3. **Add to Xcode**
   - Drag `GoogleService-Info.plist` into your Xcode project
   - Make sure it's added to the target

4. **Configure Supabase for Google OAuth**
   - In your Supabase dashboard, go to Authentication > Providers
   - Enable Google provider
   - Add your Google OAuth client ID and secret

### 4. Update Info.plist

Add the following URL scheme to your `Info.plist`:

```xml
<key>CFBundleURLTypes</key>
<array>
    <dict>
        <key>CFBundleURLName</key>
        <string>GoogleSignIn</string>
        <key>CFBundleURLSchemes</key>
        <array>
            <string>YOUR_REVERSED_CLIENT_ID</string>
        </array>
    </dict>
</array>
```

Replace `YOUR_REVERSED_CLIENT_ID` with the reversed client ID from your `GoogleService-Info.plist`.

## 🔒 Security Features

### Row Level Security (RLS)

The authentication system implements comprehensive Row Level Security:

- **User Profiles**: Users can only access their own profile data
- **Conversations**: Users can only view, create, update, and delete their own conversations
- **Automatic Profile Creation**: New user profiles are created automatically upon registration

### Data Protection

- All sensitive data is encrypted in transit and at rest
- User sessions are managed securely by Supabase
- Authentication tokens are automatically refreshed
- Proper logout clears all local session data

## 🎨 UI Features

### Liquid Glass Design

The authentication UI features a beautiful liquid glass design with:

- **Animated backgrounds** with gradient transitions
- **Glass morphism effects** for cards and input fields
- **Smooth animations** for state transitions
- **Responsive design** that works on all iOS devices

### User Experience

- **Seamless sign-in/sign-up** toggle
- **Real-time form validation**
- **Password visibility toggle**
- **Google OAuth integration**
- **Comprehensive error handling**
- **Loading states** with beautiful animations

## 📱 App Flow

### Authentication States

1. **Loading**: App checks for existing session
2. **Unauthenticated**: Shows sign-in/sign-up screen
3. **Authenticated**: Shows main app with conversation access
4. **Error**: Displays appropriate error messages

### Navigation Flow

```
App Launch
    ↓
Check Auth State
    ↓
┌─────────────────┐    ┌──────────────────┐
│ Unauthenticated │ or │   Authenticated  │
│                 │    │                  │
│ • Sign In       │    │ • Main App       │
│ • Sign Up       │    │ • Conversations  │
│ • Google OAuth  │    │ • Settings       │
└─────────────────┘    └──────────────────┘
```

## 🛠 Development

### Testing Authentication

1. **Email/Password Sign Up**
   - Use a valid email address
   - Password must be at least 6 characters
   - Check your email for confirmation (if enabled)

2. **Google Sign In**
   - Requires proper Google OAuth setup
   - Works on device and simulator

3. **Session Management**
   - Sessions persist across app launches
   - Automatic token refresh
   - Secure logout

### Debugging

Enable debug logging to monitor authentication:

```swift
// In SupabaseAuthService
print("✅ [Auth] User signed in: \(email)")
print("🔓 [Auth] User signed out")
print("❌ [Auth] Error: \(error)")
```

## 🚨 Troubleshooting

### Common Issues

1. **"Supabase URL not configured"**
   - Make sure you've created `SupabaseConfig.swift` from the template
   - Verify your Supabase URL and anon key are correct

2. **Google Sign-In not working**
   - Check that `GoogleService-Info.plist` is added to the project
   - Verify the URL scheme in `Info.plist`
   - Make sure Google OAuth is configured in Supabase

3. **Database errors**
   - Run the SQL commands from the template to set up tables
   - Check that RLS policies are enabled

### Getting Help

- Check the Supabase documentation: [supabase.com/docs](https://supabase.com/docs)
- Google Sign-In documentation: [developers.google.com/identity](https://developers.google.com/identity)
- iOS development: [developer.apple.com](https://developer.apple.com)

## 🎯 Next Steps

After setting up authentication:

1. **Test the complete flow** on device and simulator
2. **Customize the UI** to match your brand
3. **Add additional OAuth providers** if needed
4. **Implement user profile features**
5. **Set up conversation history** with user context

The authentication system is now ready to secure your Guido travel assistant! 🌍✈️
