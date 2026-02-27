# PDF Share — Setup Guide

Fluera Engine includes a native share feature for exported PDFs.  
It uses Android's `Intent.ACTION_SEND` with `FileProvider` — **zero external dependencies**.

## Android Setup

### 1. Add FileProvider to `AndroidManifest.xml`

Inside `<application>` in `android/app/src/main/AndroidManifest.xml`:

```xml
<provider
    android:name="androidx.core.content.FileProvider"
    android:authorities="${applicationId}.fileprovider"
    android:exported="false"
    android:grantUriPermissions="true">
    <meta-data
        android:name="android.support.FILE_PROVIDER_PATHS"
        android:resource="@xml/file_paths" />
</provider>
```

### 2. Create `file_paths.xml`

Create `android/app/src/main/res/xml/file_paths.xml`:

```xml
<?xml version="1.0" encoding="utf-8"?>
<paths>
    <cache-path name="cache" path="." />
</paths>
```

This grants the share intent read access to files in the app's cache/temp directory.

## How It Works

1. PDF is exported and saved to the app's temp directory
2. `SharePlugin.kt` creates a `content://` URI via `FileProvider`
3. Android's share chooser opens — user picks WhatsApp, Email, Drive, etc.
4. If `FileProvider` is not configured, a fallback SnackBar confirms the export

## iOS

Not yet implemented. The fallback SnackBar will show on iOS.
