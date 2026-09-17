# State of Mind — Frontend

Minimal Flutter app containing only the animated shader background. No other
UI (no buttons, no navigation, no Rive) has been added yet — this is a
bootstrap so the frontend exists and runs.

## What's here

- `lib/main.dart` — a bare `MaterialApp` (dark theme, no app bar) whose home
  screen is just `ShaderBackground()`, full-screen.
- `lib/shader_background.dart` — loads the fragment shader and repaints it
  every frame via a `Ticker`.
- `assets/shaders/background.frag` — the animated background shader (GLSL,
  compiled by Flutter's shader compiler at build time).

## Prerequisites

- Flutter SDK **3.47.4** (stable channel). Any recent stable 3.x SDK with
  fragment shader support (`flutter build`/`flutter run` invoking `impellerc`)
  should work, but 3.47.4 is the version this project was verified against.
- The [Flutter and Dart extensions](https://marketplace.visualstudio.com/items?itemName=Dart-Code.flutter)
  for VS Code (search "Flutter" in the Extensions panel — installing it also
  pulls in the Dart extension).

## Run locally in VS Code

1. Open the `frontend/` folder in VS Code (or open the repo root and use the
   integrated terminal `cd frontend`).
2. Install dependencies:

   ```bash
   flutter pub get
   ```

3. Run the app:

   ```bash
   flutter run -d chrome
   ```

   or, for a native desktop/mobile target instead of the browser:

   ```bash
   flutter run
   ```

   (pick a connected device/emulator when prompted).

4. Sanity check the project analyzes cleanly:

   ```bash
   flutter analyze
   ```

   This should report "No issues found!".
