@echo off
echo.
echo  Building Flutter web...
flutter build web --pwa-strategy offline-first
if %errorlevel% neq 0 goto error

echo.
echo  Replacing Flutter SW with stub to prevent conflicts...
echo // Flutter SW stub - caching handled by CDN headers > build\web\flutter_service_worker.js

echo.
echo  Copying FCM service worker...
copy /Y web\firebase-messaging-sw.js build\web\firebase-messaging-sw.js
if %errorlevel% neq 0 goto error

echo.
echo  Deploying to Firebase Hosting...
firebase deploy --only hosting
if %errorlevel% neq 0 goto error

echo.
echo  Done! App is live at https://synccash-d9c04.web.app
goto end

:error
echo.
echo  Something went wrong. Check the error above.
exit /b 1

:end    