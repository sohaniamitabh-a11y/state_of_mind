# State of Mind — Frontend

Flutter app for the mood-based recommendation picker. Kept fully separate
from the Python/SQL backend at the repo root — this package talks to a
swappable `ResultsRepository`, and the only implementation today is static
sample data.

## What's here

- `lib/main.dart` — `MaterialApp` (dark theme, no app bar) whose home is
  `HomeShell`: a `ShaderBackground` behind a foreground that swaps between
  the mood picker and the results page. The background stays mounted the
  whole time (an opaque `Navigator.push` would hide it).
- `lib/background/shader_background.dart` + `assets/shaders/background.frag`
  — the animated background shader, isolated in its own `RepaintBoundary`.
- `lib/mood/` — the five mood cards and the stacking-scroll picker.
  Cards use a mood-colored gradient border (no skewed glow strips). While
  the user scrolls, each card gets a tiny GPU-composited wobble derived
  from the scroll offset — no extra ticker. Landing copy is oversized
  frosted-glass type that picks up the five mood colors on hover.
- `lib/results/` — `ResultsRepository` interface + `StaticResultsRepository`
  (Vercel-shaped sample data) and the results page.

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
