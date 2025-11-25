@echo off
echo ========================================
echo Building VentIQ Admin App for Appwrite
echo ========================================

echo.
echo 1. Cleaning previous build...
flutter clean

echo.
echo 2. Getting dependencies...
flutter pub get

echo.
echo 3. Building web app with HTML renderer...
flutter build web --release --web-renderer html --base-href /

echo.
echo 4. Copying redirect files to build directory...
copy "web\_redirects" "build\web\_redirects"
copy "web\.htaccess" "build\web\.htaccess"

echo.
echo 5. Verifying build output...
if exist "build\web\index.html" (
    echo ✅ Build successful - index.html found
) else (
    echo ❌ Build failed - index.html not found
    exit /b 1
)

if exist "build\web\_redirects" (
    echo ✅ _redirects file copied successfully
) else (
    echo ❌ _redirects file not found in build directory
)

if exist "build\web\.htaccess" (
    echo ✅ .htaccess file copied successfully
) else (
    echo ❌ .htaccess file not found in build directory
)

echo.
echo ========================================
echo Build completed successfully!
echo.
echo Next steps:
echo 1. Upload the contents of 'build\web' to Appwrite
echo 2. Configure Appwrite to serve index.html for all routes
echo 3. Test the deployment
echo ========================================
pause
