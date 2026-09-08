@echo off
setlocal

echo === Universal AI Hub - Windows Build ===
where flutter >nul 2>nul
if errorlevel 1 (
  echo Flutter was not found in PATH.
  echo Install Flutter and Android Studio, then run flutter doctor.
  exit /b 1
)

flutter doctor
if errorlevel 1 exit /b 1
flutter clean
if errorlevel 1 exit /b 1
flutter pub get
if errorlevel 1 exit /b 1
flutter analyze
if errorlevel 1 exit /b 1
flutter test
if errorlevel 1 exit /b 1
flutter build apk --release
if errorlevel 1 exit /b 1

echo.
echo APK created at:
echo build\app\outputs\flutter-apk\app-release.apk
pause
