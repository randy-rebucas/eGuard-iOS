# eGuard App Store Deployment Guide

This guide covers taking the eGuard iOS app from a local Xcode build to a release on the App Store. It is written against the project as it stands on 2026-10-03. Where the project is not yet ready for a step, the guide says so and tells you what to change.

## 1. What ships

eGuard is a single iOS app with three embedded extensions. All four must be signed, versioned, and provisioned together.

| Target | Product type | Bundle identifier | Purpose |
|---|---|---|---|
| `eGuard` | Application | `com.devcom.eguard` | Parent app and child device mode |
| `eGuardActivityMonitor` | App extension | `com.devcom.eguard.eGuardActivityMonitor` | Device Activity monitor: schedules, usage thresholds, shields |
| `eGuardActivityReport` | ExtensionKit extension | `com.devcom.eguard.eGuardActivityReport` | Device Activity report UI |
| `eGuardShieldConfiguration` | App extension | `com.devcom.eguard.eGuardShieldConfiguration` | Custom shield screen for blocked apps |

Key facts about the build:

| Setting | Value |
|---|---|
| Deployment target | iOS 27.0 |
| Device family (app) | iPhone only |
| Marketing version | 1.0 |
| Build number | 1 |
| Signing style | Automatic |
| App Group | `group.com.devcom.eguard` |
| Backend | `https://www.eguard.family/api/mobile/v1` and `/api/device/v1` |
| Push | APNs through Firebase Cloud Messaging |

The `eGuardTests` and `eGuardUITests` targets are not shipped. They still carry placeholder bundle identifiers (`com.yourcompany.*`), which is harmless for release but worth tidying.

## 2. Accounts and portal setup

Do these once, in the Apple Developer portal and App Store Connect, before the first archive.

### 2.1 Apple Developer Program

1. Enroll the publishing entity (the company behind `eguard.family`) in the Apple Developer Program. Family Controls distribution is only granted to organizations that can show the app is a parental control product, so enroll as an organization, not an individual, if at all possible.
2. Note the Team ID. You will need it for the project, for Firebase, and for the universal links file on the website.

### 2.2 Identifiers and capabilities

Register the four bundle identifiers listed above as explicit App IDs. Enable these capabilities:

| Capability | App | Monitor | Report | Shield |
|---|---|---|---|---|
| Family Controls | Yes | Yes | Yes | Yes |
| App Groups (`group.com.devcom.eguard`) | Yes | Yes | No | No |
| Push Notifications | Yes | No | No | No |
| Sign in with Apple | Yes | No | No | No |
| Associated Domains | Yes, see 2.4 | No | No | No |

These match the entitlements files already in the repo (`eGuard/eGuard.entitlements` and the three extension entitlements files), except Associated Domains, which is not yet in the project.

### 2.3 Family Controls distribution entitlement

This is the step most likely to block a release, so start it first.

The Family Controls entitlement works automatically for development builds on your own devices. It does **not** work for TestFlight or App Store builds until Apple approves a distribution request for your team. Submit the request at:

```
https://developer.apple.com/contact/request/family-controls-distribution
```

Submit one request per bundle identifier that uses the entitlement, so four in total. Describe eGuard as a parental control app that lets a parent restrict apps, web content, and screen time on a child's device, and that the child device mode is the only place Screen Time data is read. Approval typically takes days to weeks. Once approved, Xcode's automatic signing will pick up the `Family Controls (Distribution)` entitlement in App Store and TestFlight provisioning profiles without any project change.

Until approval arrives, archives will export for Development but fail validation for App Store distribution with an entitlement error on `com.apple.developer.family-controls`.

### 2.4 Associated Domains and the URL scheme (currently missing)

The app parses verification, password reset, and invite links in two forms:

- `https://www.eguard.family/verify-email?token=…`, `/reset-password`, `/accept-invite`
- `eguard://verify-email?token=…` and the same three paths

Neither form is registered in the project yet, so the system will never hand these URLs to the app. To make them work before release:

1. Add the Associated Domains capability to the `eGuard` target in Xcode with the entry `applinks:www.eguard.family`.
2. Host an `apple-app-site-association` file at `https://www.eguard.family/.well-known/apple-app-site-association` that lists `TEAMID.com.devcom.eguard` and the three paths.
3. Add a URL Type to the `eGuard` target's Info tab with scheme `eguard` and identifier `com.devcom.eguard`.

Do these in Xcode, not by editing the project file by hand.

### 2.5 Push notifications

The parent app receives alert pushes through Firebase Cloud Messaging (FCM). The server sends to an FCM registration token, not a raw APNs token.

1. In the Apple Developer portal, create an APNs authentication key (`.p8`) under Keys, with the Apple Push Notifications service enabled. Download it once; Apple will not let you download it again.
2. In the Firebase console, open project `eguard-6511b`, go to Project settings, Cloud Messaging, and upload the `.p8` key with its Key ID and your Team ID.
3. Download the iOS `GoogleService-Info.plist` for bundle `com.devcom.eguard` and place it at `eGuard/GoogleService-Info.plist`. The file is gitignored on purpose because it is per-environment. Without it the app still builds and runs, but logs an error at launch and never registers a push token.

The entitlements file sets `aps-environment` to `development`. Leave it. Xcode rewrites it to `production` when you export for App Store Connect or TestFlight.

### 2.6 Sign in with Apple

Sign in with Apple is enabled and the app sends a hashed nonce with each request. The backend must verify the identity token and nonce. Also configure a Services ID and the "Sign in with Apple" email relay domain for `eguard.family` in the portal so Hide My Email relay addresses can receive the app's verification emails.

### 2.7 App Store Connect record

Create the app in App Store Connect with:

- Platform iOS, bundle ID `com.devcom.eguard`, SKU of your choice.
- Primary language and the app name "eGuard".
- Privacy policy URL `https://www.eguard.family/privacy`.
- Category Utilities or Lifestyle. Do **not** choose the Kids category. eGuard is operated by parents, and the Kids category brings restrictions on third-party SDKs that would rule out Firebase.

## 3. Prepare the project for release

### 3.1 Set the team

The committed project sets `DEVELOPMENT_TEAM` to `4FQJ8S5TWT` on the `eGuard` target. Xcode clears this value in the local working copy when the signed-in Apple ID loses access to the team, and the result is a code signing identity of ad hoc (`-`) with no error until you archive. Before a release, open Signing & Capabilities for each of the four shipping targets and confirm the team is selected for both Debug and Release. Keep "Automatically manage signing" on, and do not commit a project file whose team has been emptied.

### 3.2 Versioning

All four shipping targets must carry the same marketing version and build number, or App Store Connect rejects the upload. The targets read `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` from their own build settings, so change them in one place: select the project, then each target's General tab, or use the command below from the repo root before archiving.

```sh
xcrun agvtool new-marketing-version 1.0.0
xcrun agvtool new-version -all 2
```

Every upload to App Store Connect needs a build number higher than any build already uploaded for that version.

### 3.3 Export compliance

The app uses only HTTPS to its own server. Add the Info key `ITSAppUsesNonExemptEncryption` with value `NO` to the `eGuard` target (Info tab, or the `INFOPLIST_KEY_ITSAppUsesNonExemptEncryption` build setting) so App Store Connect stops asking the encryption question on every build.

### 3.4 Privacy manifest

`eGuard/PrivacyInfo.xcprivacy` and `eGuardActivityMonitor/PrivacyInfo.xcprivacy` already exist. The app manifest declares:

- Collected data: email address, name, precise location, device ID. All linked to the user, none used for tracking.
- Accessed API: `UserDefaults`, reason `CA92.1`.
- No tracking, no tracking domains.

Keep the manifest in sync with the App Privacy answers in App Store Connect (section 5.2). If you add analytics, crash reporting, or any new data type, update both.

### 3.5 Pre-archive checklist

Run through this before every release archive.

- `GoogleService-Info.plist` is present at `eGuard/GoogleService-Info.plist` and is for project `eguard-6511b`.
- Team is set on all four targets and no signing warnings show in Signing & Capabilities.
- Version and build are identical across the four targets and the build number is new.
- The production API at `https://www.eguard.family` is live and accepts the mobile and device API calls the app makes. App Review will exercise sign in, child pairing, and alerts against it.
- The asset catalog contains a full `AppIcon` set with the 1024 pt marketing icon.
- The unit tests pass:

```sh
xcodebuild test \
  -project eGuard.xcodeproj \
  -scheme eGuard \
  -destination 'platform=iOS Simulator,name=iPhone 17'
```

- The app has been run on a physical iPhone in both parent mode and child device mode. Family Controls, Device Activity, shields, and push tokens do not work in the simulator.

## 4. Archive and upload

### 4.1 From Xcode

1. Select the `eGuard` scheme and the destination "Any iOS Device (arm64)".
2. Choose Product, Archive. The Release configuration builds and embeds the three extensions automatically.
3. In the Organizer, select the archive and click Validate App. Fix any entitlement or icon issues before continuing.
4. Click Distribute App, choose App Store Connect, then Upload. Accept the defaults for symbol upload and bitcode. Let Xcode manage signing.
5. Wait for the "Processing" state in App Store Connect to clear. This usually takes 10 to 30 minutes.

### 4.2 From the command line

Useful for CI or a repeatable local release. Create an `ExportOptions.plist` once:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>app-store-connect</string>
    <key>teamID</key>
    <string>YOUR_TEAM_ID</string>
    <key>signingStyle</key>
    <string>automatic</string>
    <key>uploadSymbols</key>
    <true/>
    <key>destination</key>
    <string>upload</string>
</dict>
</plist>
```

Then archive and upload:

```sh
xcodebuild archive \
  -project eGuard.xcodeproj \
  -scheme eGuard \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -archivePath build/eGuard.xcarchive \
  -allowProvisioningUpdates

xcodebuild -exportArchive \
  -archivePath build/eGuard.xcarchive \
  -exportOptionsPlist ExportOptions.plist \
  -exportPath build/export \
  -allowProvisioningUpdates
```

For CI, authenticate with an App Store Connect API key by adding `-authenticationKeyPath`, `-authenticationKeyID`, and `-authenticationKeyIssuerID` to both commands. The CI job must also write `GoogleService-Info.plist` into `eGuard/` from a secret before building, since the file is not in the repo.

### 4.3 TestFlight

Every uploaded build is available to the internal testing group right away once processing finishes. Before the first external TestFlight build, Apple runs a lighter review and the Family Controls distribution entitlement (section 2.3) must already be approved. Use TestFlight to verify on real devices:

- Parent sign in with email and with Apple.
- Child device pairing with a code, then a restriction applied from the parent app appears on the child device.
- A shield appears when a blocked app is opened.
- An alert push arrives on the parent phone with the app in the background.
- Location sharing from a child device shows on the parent's Location tab.

## 5. App Store Connect listing

### 5.1 Version information

- Screenshots for the iPhone sizes App Store Connect currently requires. The app is iPhone only, so no iPad set is needed. Capture both the parent dashboard and the child device mode.
- Description, keywords, support URL `https://www.eguard.family`, marketing URL optional.
- Age rating: answer the questionnaire honestly. The app has no objectionable content; it will land at 4+.

### 5.2 App Privacy

Answer so the public nutrition label matches `PrivacyInfo.xcprivacy`:

| Data type | Collected | Linked to user | Used for tracking | Purpose |
|---|---|---|---|---|
| Email address | Yes | Yes | No | App functionality |
| Name | Yes | Yes | No | App functionality |
| Precise location | Yes | Yes | No | App functionality |
| Device ID | Yes | Yes | No | App functionality |

Precise location is collected only from a device in child mode after a parent turns on location sharing. Say so in the review notes, because reviewers compare the label against the location usage string.

### 5.3 Account deletion

Guideline 5.1.1(v) requires in-app account deletion when the app supports account creation. eGuard offers deletion in Settings, Account, and links to `https://www.eguard.family/delete-account`. Confirm the web page is live before submission.

### 5.4 Review notes and demo account

Sign in is required, so App Review needs a working account. Provide in the review notes:

- A parent demo account (email and password) on the production backend with at least one child already added.
- A second set of instructions for child device mode: how to choose "This is my child's device" and a pairing code that stays valid for the review window, or a note that the reviewer can generate one from the demo parent account.
- A short explanation that the Screen Time and Family Controls APIs are used solely for parental control, that no Screen Time data leaves the child device except the aggregated usage floor sent to the parent's account, and that the location permission is only requested in child mode.
- The Family Controls distribution request reference, if Apple gave you one.

Expect questions under guidelines 5.1.1 (data collection), 5.1.4 (kids), and 5.5 (Screen Time API). Parental control apps are reviewed closely, so a clear demo path shortens the cycle.

## 6. Release and after

1. In App Store Connect, attach the processed build to the version, complete the listing, and submit for review.
2. Choose manual release so you control the moment the app goes live, especially for the first version while the backend is being watched.
3. After approval, release, then monitor the Xcode Organizer for crashes and App Store Connect for review-related rejections.
4. Tag the released commit in git with the marketing version and build number, for example `v1.0.0-build2`.

### 6.1 Shipping an update

- Bump the build number on all four targets, and the marketing version when user-visible changes warrant it.
- Re-run the pre-archive checklist in section 3.5.
- Any change to collected data types or new third-party SDKs means updating `PrivacyInfo.xcprivacy` and the App Privacy answers in the same release.
- A new entitlement or capability means a new provisioning profile. Automatic signing handles it, but Validate App first.

## 7. Known gaps before a first submission

In order of likely impact:

1. **Family Controls distribution entitlement not yet requested.** Nothing can reach TestFlight or the App Store until it is approved. See 2.3.
2. **Team cleared in the local working copy.** The committed project has the team, but the local project file had it emptied and signing resolved to ad hoc. See 3.1.
3. **Universal links and the `eguard://` scheme are not registered.** Email links will open in Safari instead of the app. See 2.4.
4. **`GoogleService-Info.plist` must be supplied out of band.** The gitignored file is required for push to work in the release build. See 2.5.
5. **Export compliance key not set.** Minor, but saves a step per upload. See 3.3.
6. **Push and the Screen Time usage ladder are verified by build and symbol inspection only.** They still need a run on a physical iPhone before release. See 4.3.
