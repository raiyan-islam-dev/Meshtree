# MeshTree

Turn a folder of photos into a textured 3D model — no scanner, no LiDAR rig, just your camera roll.

![MeshTree demo](docs/demo.gif)
<!-- Replace with a real screen recording: drop a photo folder in, watch it reconstruct, rotate the finished model. This is the single highest-impact thing to add before shipping. -->

**[⬇ Download the latest build →](https://github.com/raiyan-islam-dev/Meshtree/releases/latest)**

## Quick start

1. Download the latest release above and drag `MeshTree.app` into `/Applications`.
2. First launch: right-click the app → **Open** (it isn't notarized yet, so Gatekeeper will otherwise block it). If macOS still refuses, run `xattr -cr /Applications/MeshTree.app` in Terminal and try again.
3. Drag a folder of overlapping photos of an object onto the window, or click **Select Folder**.
4. Pick a quality level and hit **Start Reconstruction**.
5. Spin the finished model, then **Save 3D Model** to export a `.usdz`.

## Features

- Drag-and-drop or native macOS folder picker to load a batch of photos
- Thumbnail grid so you can spot and remove bad shots before reconstruction
- On-device 3D reconstruction powered by Apple's Object Capture (`PhotogrammetrySession`) — five quality levels, Low to Ultra
- Interactive 3D preview (rotate, zoom) of the finished mesh, no other app needed
- One-click export to `.usdz`, ready for AR Quick Look, Reality Composer, or any USD-compatible tool
- Cancel mid-reconstruction and it cleans up its own temp files automatically

## Running locally

Requirements:
- macOS 12 Monterey or later, **Apple Silicon strongly recommended** (Object Capture also runs on Intel Macs with a 4GB+ discrete GPU, but not on integrated graphics). The app checks `PhotogrammetrySession.isSupported` on launch and will tell you if your Mac can't run it.
- Xcode 13 or later

```bash
git clone https://github.com/raiyan-islam-dev/Meshtree.git
cd Meshtree
open MeshTree.xcodeproj
```

Select the MeshTree scheme and press **⌘R**.

## How it works

The core is Apple's Object Capture API (`PhotogrammetrySession`), which handles the actual structure-from-motion reconstruction. MeshTree's job is orchestration: copying the selected photos into a scratch directory, kicking off a session at the chosen `Request.Detail`, and streaming `requestProgress` / `processingComplete` events back into the UI so the progress bar and 3D preview stay in sync — including a clean cancel path that tears down the session and deletes its temp files.

Reconstruction quality is very sensitive to blurry source photos, so MeshTree also includes a sharpness checker (`ImageCheck.swift`): each image is converted to grayscale, convolved with a 3×3 Laplacian kernel via Accelerate's `vImage`, and the variance of the result is used as a blur score — low variance means blurry. It also flags images that are unreadable or below a minimum resolution. *(Currently a standalone module — not yet wired into the photo grid, but the scoring logic is ready to surface as warnings before reconstruction.)*

## Credits

Built with Apple's [RealityKit Object Capture](https://developer.apple.com/documentation/realitykit/realitykit-object-capture) and [SceneKit](https://developer.apple.com/documentation/scenekit). Made for [Stardance](https://stardance.hackclub.com), by Hack Club.

## AI usage

AI was used for debugging and polishing this project.

## License

MIT — see [LICENSE](LICENSE).
<!-- Add an actual LICENSE file when you push the real repo; GitHub can generate one for you during repo creation. -->
