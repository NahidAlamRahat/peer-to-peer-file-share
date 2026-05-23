@echo off
echo ==========================================
echo    Auto-Deploy Script for PeerTransfer
echo ==========================================
echo.

echo [1/4] Building latest APK...
call flutter build apk --release
if %errorlevel% neq 0 (
    echo [Error] Failed to build APK.
    pause
    exit /b %errorlevel%
)

echo.
echo [2/4] Copying APK to Web folder...
if not exist web\apk mkdir web\apk
copy /Y build\app\outputs\flutter-apk\app-release.apk web\apk\PeerTransfer.apk

echo.
echo [3/4] Adding changes to Git...
git add .
git commit -m "deploy: update app with latest APK"

echo.
echo [4/4] Pushing to GitHub (Vercel will auto-deploy)...
git push

echo.
echo ==========================================
echo  Deploy completed successfully! 
echo  Vercel is now updating your website.
echo ==========================================
pause
