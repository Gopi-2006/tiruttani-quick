## HOW TO GENERATE YOUR RELEASE KEYSTORE

⚠️ IMPORTANT: Keep this file and your keystore PRIVATE. Never commit to git.

### Step 1: Generate the keystore
Run this command in your terminal (replace values as needed):

```
keytool -genkey -v -keystore key.jks -keyalg RSA -keysize 2048 -validity 10000 -alias thiruttaniquick
```

You'll be prompted for:
- Keystore password (remember this)
- Key alias password (can be same)
- Your name, org, city, country

### Step 2: Create key.properties in blinkit_customer/android/ and blinkit_admin/android/
(A template file is already placed there for you — fill it in)

### Step 3: Build the release AAB
```
flutter build appbundle --release
```

The signed .aab file will be at:
  build/app/outputs/bundle/release/app-release.aab
