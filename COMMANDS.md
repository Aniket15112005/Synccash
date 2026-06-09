# ==========================================================================
# SyncCash System Infrastructure - Environment Build Orchestration Commands
# ==========================================================================

# 1. Dependency Resolution & Pre-flight Inspection
flutter clean
flutter pub get

# 2. Native System Compilation & Project Packaging

## Build Android Release Package (App Bundle for Production Google Play Deployment)
flutter build appbundle --release

## Build iOS Release Package (Generates Pod Archives for App Store Connect Optimization)
flutter build ios --release --no-codesign

# 3. Firebase CLI Node Tool Configuration Pipeline
# Install the Google Firebase Toolkit globally within your terminal container environment
npm install -g firebase-tools

# Connect terminal context to authenticated Firebase Developer Console account
firebase login

# Launch automated project provision pipeline mapping Firestore rules and structural composite indexes
firebase deploy --only firestore