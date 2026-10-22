# NexField Drawings — 100% Native iOS App (Swift + SwiftUI + PDFKit)

This folder (`C:\Users\vduls\.gemini\antigravity\scratch\NexFieldDrawingsIOS`) contains the complete **100% Native iOS App** for **NexField Drawings**, matching the Android app 1-to-1 and connected to `https://nexfield.co.uk`.

---

## Included Features
- **Full Cloud & Offline Sync:** Connects to `https://nexfield.co.uk/api.php` (`login`, `token_login`, `get_project_data`, `save_annotation`) with local iPhone offline storage and 3-way conflict-free merge.
- **Native Apple `PDFKit` + `CoreGraphics` Engine:** Crisp multi-page PDF rendering, vector annotations, and multi-page annotated PDF export via the native iOS Share Sheet.
- **Exact Same Editor UI & Smart Tools:**
  - Clean bottom dock with **`↩️ | ↪️`**, **`Tools ▲`**, **`🔄`**, and **`⛶`**.
  - Simplified floating additional toolbar with **ONLY** the 5 controls: **`✋ Move`**, **`● Colour ▼`** (with **`☑ Fill`** inside), **`📋 Clone`**, **`🗑️ Delete`**, and **`3px ▼`** thickness.
  - Tap any object on the canvas to cycle **`Move (✋)` → `Resize (⤡)` → `Rotate (🔄)`**.
  - **Proportional Resizing:** Dragging corner handles keeps exact shape proportions for triangles, circles, and squares.
  - **Smart Level Alignment Guide & Smart `📋 Clone`:** Automatically aligns same-type objects on the same level and clones at the exact same distance, level, and direction.

---

## How to Compile `.ipa` Without a Mac PC (Free GitHub Actions Cloud Mac)

1. Create a free repository on [GitHub](https://github.com/new) (it can be private or public) and push this folder (`NexFieldDrawingsIOS`):
   ```powershell
   cd C:\Users\vduls\.gemini\antigravity\scratch\NexFieldDrawingsIOS
   git init
   git add .
   git commit -m "Initial Native iOS Swift/SwiftUI App"
   git branch -M main
   git remote add origin https://github.com/<your-username>/NexFieldDrawingsIOS.git
   git push -u origin main
   ```
2. Open the **Actions** tab on your GitHub repository.
3. The workflow **[`.github/workflows/build-ios.yml`](.github/workflows/build-ios.yml)** will automatically start on a **macOS 14 + Xcode 15** cloud machine, generate `NexFieldDrawings.xcodeproj`, compile the Swift app, and output **`NexFieldDrawings-iOS-IPA` (`NexFieldDrawings.ipa`)**.
4. Download **`NexFieldDrawings.ipa`** from the workflow run artifacts.

---

## How to Install `NexFieldDrawings.ipa` onto an iPhone from Windows
- **Method A — Free (Personal/Testing via Sideloadly on Windows):**
  1. Download and open **[Sideloadly](https://sideloadly.io/)** on your Windows PC.
  2. Connect your iPhone via USB cable, drag `NexFieldDrawings.ipa` into Sideloadly, enter your Apple ID, and click **Start**.
  3. On your iPhone, go to **Settings → General → VPN & Device Management**, trust your Apple ID, and open **NexField Drawings**.
- **Method B — Team / Client Distribution (Apple TestFlight / App Store):**
  - If you have an Apple Developer Account (\$99/year), upload the `.ipa` to **App Store Connect / TestFlight** so any iPhone user can install it with one tap.
