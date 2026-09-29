# LIFT

LIFT is a Flutter app for gym members and gym teams. It brings workout planning and logging, gym membership tools, equipment information, and training progress into one place.

## What’s included

- Sign-up, sign-in, gym registration, and joining a gym
- A gym pass and membership details
- Workout templates, live workout logging, and a training calendar
- Machine catalogue, machine details, and QR scan flow
- Workout history, progress views, and recovery visualisations
- Gym articles, member profiles, and account settings

Some screens currently use sample or local development data. Firebase-backed authentication, gym, machine, and article services are selected automatically when Firebase is configured.

## Requirements

- Flutter SDK compatible with Dart `^3.7.2`
- A platform toolchain for the target you want to run (Android Studio for Android, Xcode for iOS/macOS, or the relevant desktop tooling)

## Run locally

```sh
flutter pub get
flutter run
```

To list available devices:

```sh
flutter devices
```

Without Firebase platform configuration, the app falls back to local development authentication and local or in-memory repositories where supported. This is useful for exploring the app, but local development accounts and data are not a production backend.

## Firebase setup

Firebase is optional for a local run. To use Firebase services:

1. Create or choose a Firebase project.
2. Register the platforms you intend to run and add their native Firebase configuration files using the Firebase Flutter setup guide.
3. Enable the Firebase products used by the app, including Authentication and Cloud Firestore.
4. Deploy the repository’s Firestore rules and indexes:

   ```sh
   firebase deploy --only firestore:rules,firestore:indexes
   ```

The repository contains `firestore.rules` and `firestore.indexes.json`, with the deployment mapping in `firebase.json`. Review and harden the rules for your deployment before onboarding real users.

## Project layout

```text
lib/
  app/          App setup, routing, and session state
  features/     Auth, gym, workout, progress, profile, and other screens
  shared/       Models, services, and reusable widgets
assets/         Branding, icons, and recovery illustrations
```

## Useful commands

```sh
flutter analyze       # Static analysis
flutter test          # Run the Flutter tests
flutter build apk     # Build an Android APK
flutter build ios     # Build for iOS (requires macOS and Xcode)
```
