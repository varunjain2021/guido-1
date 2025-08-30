# Adding Supabase via Swift Package Manager

Since Supabase Swift SDK is not available through CocoaPods, we need to add it via Swift Package Manager in Xcode.

## 📦 Add Supabase Swift Package

### Step 1: Open Xcode Project
1. Open `guido-1.xcworkspace` (not the .xcodeproj file)
2. Make sure you're using the workspace since we have CocoaPods

### Step 2: Add Package Dependency
1. In Xcode, go to **File** → **Add Package Dependencies...**
2. Enter the Supabase Swift SDK URL:
   ```
   https://github.com/supabase/supabase-swift
   ```
3. Click **Add Package**
4. Select the version (use **Up to Next Major Version** with **2.0.0**)
5. Click **Add Package** again

### Step 3: Select Package Products
Select the following products to add to your target:
- ✅ **Supabase** (main SDK)
- ✅ **Auth** (authentication)
- ✅ **PostgREST** (database operations)
- ✅ **Storage** (file storage - optional)
- ✅ **Realtime** (real-time subscriptions - optional)

### Step 4: Verify Installation
1. Build the project (⌘+B) to make sure everything compiles
2. The Supabase imports should now work in your Swift files

## 🔧 Alternative: Manual SPM Configuration

If you prefer to add it manually to Package.swift (for pure SPM projects):

```swift
dependencies: [
    .package(url: "https://github.com/supabase/supabase-swift", from: "2.0.0")
]
```

## ✅ Next Steps

After adding the Supabase package:

1. **Configure your Supabase credentials** in `SupabaseConfig.swift`
2. **Set up your Supabase project** following the main setup guide
3. **Test the authentication flow**

The authentication code is already written and ready to use once Supabase is properly added!

## 🚨 Troubleshooting

### Build Errors
- Make sure you're opening the `.xcworkspace` file, not `.xcodeproj`
- Clean build folder (⌘+Shift+K) and rebuild
- Check that all package products are properly linked

### Import Errors
- Verify the package was added to the correct target
- Check that the import statements match the added products:
  ```swift
  import Supabase
  import Auth
  import PostgREST
  ```

### Version Conflicts
- Use "Up to Next Major Version" for most stable experience
- If you encounter conflicts, try "Exact Version" with latest stable release
