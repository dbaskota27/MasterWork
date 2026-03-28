# Mobile Store Flutter — Build Instructions

## One-time Setup

### 1. Edit your store credentials
Open `lib/config.dart` and fill in:
- `supabaseUrl` — from supabase.com → your project → Settings → API
- `supabaseAnonKey` — from the same page
- `storeName`, `storeAddress`, `storePhone`, `storeEmail`
- `paymentQrLink` — your Venmo/PayPal.me/UPI link (leave `''` to hide QR)
- `users` — change the passwords!

### 2. Install Flutter (if not already installed)
Download: https://docs.flutter.dev/get-started/install/macos/mobile-android
- Extract to `~/development/flutter`
- Add to PATH: `export PATH="$PATH:$HOME/development/flutter/bin"`

### 3. Install JDK 17
Download Temurin 17 from: https://adoptium.net/
Or via Homebrew: `brew install --cask temurin17`

### 4. Install Android command-line tools
Download from: https://developer.android.com/studio#command-line-tools-only
```bash
mkdir -p ~/development/android-sdk/cmdline-tools
unzip commandlinetools-*.zip -d ~/development/android-sdk/cmdline-tools
mv ~/development/android-sdk/cmdline-tools/cmdline-tools ~/development/android-sdk/cmdline-tools/latest

export ANDROID_HOME=~/development/android-sdk
export PATH=$PATH:$ANDROID_HOME/cmdline-tools/latest/bin

# Accept licenses and install build tools
sdkmanager --licenses
sdkmanager "platform-tools" "platforms;android-34" "build-tools;34.0.0"
```

### 5. Run flutter doctor
```bash
flutter doctor
```
All required checks should pass (Android toolchain, no iOS needed).

---

## Build the APK

```bash
cd ~/Documents/MasterWork/mobile_store_flutter

# Get packages
flutter pub get

# Build release APK
flutter build apk --release
```

The APK will be at:
`build/app/outputs/flutter-apk/app-release.apk`

**Copy to your phone:**
```bash
adb install build/app/outputs/flutter-apk/app-release.apk
```
Or just transfer the `.apk` file to your phone via cable/Google Drive and open it.
(Enable "Install from unknown sources" in Android Settings → Security.)

---

## Run in debug mode (connected phone or emulator)
```bash
flutter run
```

---

## Supabase Table Schema
Your existing Supabase tables are used as-is. Make sure these columns exist:

**products**: `id`, `name`, `barcode`, `price`, `stock`, `category`, `image_url`, `created_at`

**customers**: `id`, `name`, `phone`, `email`, `created_at`

**invoices**: `id`, `customer_name`, `customer_phone`, `items` (jsonb), `marked_price`, `discount`, `customer_pays`, `amount_received`, `change_given`, `payment_type`, `created_at`

If the `invoices` table is missing the new columns, run this in Supabase SQL Editor:
```sql
ALTER TABLE invoices ADD COLUMN IF NOT EXISTS marked_price numeric DEFAULT 0;
ALTER TABLE invoices ADD COLUMN IF NOT EXISTS discount numeric DEFAULT 0;
ALTER TABLE invoices ADD COLUMN IF NOT EXISTS customer_pays numeric DEFAULT 0;
ALTER TABLE invoices ADD COLUMN IF NOT EXISTS amount_received numeric DEFAULT 0;
ALTER TABLE invoices ADD COLUMN IF NOT EXISTS change_given numeric DEFAULT 0;
ALTER TABLE invoices ADD COLUMN IF NOT EXISTS payment_type text DEFAULT 'cash';
```
