# 🎞️ Nastarxa Image Combiner

A desktop image-sequence combiner built with AutoHotkey v2 for quickly turning image folders or MP4 clips into animations, videos, GIFs, and contact sheets.

Designed for animation workflows, frame previews, exposure timing, and fast local rendering using `ffmpeg`.

![Platform](https://img.shields.io/badge/platform-Windows-lightgrey)
![Language](https://img.shields.io/badge/language-AutoHotkey_v2-green)

---

## 🖼 Image Preview

![1](docs/images/1.png)

---

## ✨ Features

### 📂 File Management

* Queue images and MP4 clips
* Drag & drop files or folders
* Add entire folders instantly
* Local bundled `ffmpeg` support

### 🧩 Sequence Editing

* Reorder items
* Duplicate selected frames
* Remove entries
* Sort automatically
* Reverse sequence order
* Per-item exposure control

### 👀 Preview & Timeline

* Live output preview
* Duration timeline
* Frame exposure visualization
* FPS-based timing calculation

### 🎬 Export Formats

| Format        | Supported |
| ------------- | --------- |
| GIF           | ✅         |
| MP4           | ✅         |
| AVI           | ✅         |
| WebM          | ✅         |
| PNG Sequence  | ✅         |
| Contact Sheet | ✅         |

### 🗂️ Project Workflow

* Save & load presets
* Save & load project files
* Persistent workflow setup
* Reusable export settings

---

# 🖼️ Contact Sheets

Generate animation sheets automatically from your sequence.

## Features

* Adjustable `per sheet` count
* Multi-sheet splitting
* Automatic numbering
* PNG export

## Example

```txt
20 frames
per sheet = 16
```

Output:

```txt
animation_sheet01.png
animation_sheet02.png
```

---

# ⚙️ Requirements

* Windows
* AutoHotkey v2
* ffmpeg

The ffmpeg is configured to use the repo copy only.

---

# 📦 Repository Structure

| File                          | Description                  |
| ----------------------------- | ---------------------------- |
| `Nastarxa Image Combiner.ahk` | Main application             |
| `ffmpeg/`                     | Bundled local ffmpeg runtime |
| `Combiner.ico`                | Application icon             |

---

# 🚀 Usage

1. Install `AutoHotkey v2`
2. Extract `ffmpeg` into the same directory as the script 
3. Run `Nastarxa Image Combiner.ahk`
4. Add images or folders
5. Adjust exposure, FPS, size, and output format
6. Click `Generate`

---

# 🛠️ Default Settings

| Setting           | Default          |
| ----------------- | ---------------- |
| FPS               | `24`             |
| Contact Per Sheet | `16`             |
| Renderer          | Bundled `ffmpeg` |

---

# 📌 Notes

* `WebM` export uses settings compatible with the bundled ffmpeg build
* Avoids the common `auto_alt_ref` transparency issue
* Output files are generated in the selected output folder
* Works fully offline using local tools only
* Download and extract ffmpeg into the same directory as the script before running the application

---

## 📄 License

MIT
See [LICENSE](/LICENSE).

---

## ⚠️ Disclaimer

This project was developed with the assistance of AI tools.
AI was used to support code writing, refactoring, and documentation, while the design direction, features, and final implementation were guided and reviewed by the author.
