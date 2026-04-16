# IOS i-recommend

This folder contains an **iOS-native refactor** of the original web-based i-recommend project.

## Important
- The original repository code was not modified.
- This iOS version is provided as a separate app codebase that can live in a new repository named **`IOS i-recommend`**.

## What this app does
- Requests Apple Music authorization from the user.
- Loads the user's library playlists.
- Generates lightweight recommendations based on playlist genres.
- Plays previews for recommended tracks.

## Apple App Store readiness notes
To ship to the Apple App Store, make sure to:
1. Add your Apple Developer Team + Bundle Identifier in Xcode.
2. Enable **MusicKit** capability in Signing & Capabilities.
3. Add `NSAppleMusicUsageDescription` in `Info.plist`.
4. Use real recommendation/business logic and test on physical iOS devices.
5. Complete App Privacy metadata in App Store Connect.

## Project structure
- `iRecommendIOS/iRecommendIOSApp.swift` – App entry point.
- `iRecommendIOS/Views/ContentView.swift` – Main UI.
- `iRecommendIOS/ViewModels/RecommendationViewModel.swift` – UI logic.
- `iRecommendIOS/Services/AppleMusicService.swift` – Music authorization + playlist + catalog calls.
- `iRecommendIOS/Models/` – Data models.

## Create the separate repository
From your terminal:

```bash
cd "IOS i-recommend"
git init
git add .
git commit -m "Initial iOS-native i-recommend app"
git branch -M main
git remote add origin <your-new-repo-url>
git push -u origin main
```

