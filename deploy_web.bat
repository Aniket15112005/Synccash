
set -e

echo "=== Building Flutter web ==="
flutter build web --release

echo "=== Removing deprecated Flutter service worker ==="
# Flutter generates a self-destructing flutter_service_worker.js that
# unregisters itself and force-reloads the page on every activate.
# Firebase Hosting CDN headers (firebase.json) handle caching instead.
rm -f build/web/flutter_service_worker.js

echo "=== Deploying to Firebase Hosting ==="
firebase deploy --only hosting

echo "=== Done ==="
