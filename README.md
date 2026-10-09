# Omarchy Custom Plugins

Custom high-performance bar widgets and plugins built for [Omarchy](https://github.com/omarchy/omarchy) (Quickshell).

---

## Included Plugins

| Plugin | ID | Description | Tech Stack |
| :--- | :--- | :--- | :--- |
| **System Resources** | `rustam.resources` | Real-time resource monitor on the top bar (CPU %, RAM GB & %, Disk, Network, Thermals, Top Processes with 1-click process termination). | C++17 (`/proc` scraper) + QML |
| **Medication Tracker** | `rustam.meds` | Scheduled pill reminder on the top bar (`med💊`). Turns **red** when doses are due, normal once taken. Single-click to mark taken (blue), double-click to undo (red). | Python 3 + QML |

---

## Quick Installation on Any Omarchy System

Follow these 3 simple steps to install these plugins on any machine running Omarchy:

### Step 1: Copy Plugins to Omarchy Directory

Copy the plugin folders into `~/.config/omarchy/plugins/`:

```bash
mkdir -p ~/.config/omarchy/plugins

# Copy both plugins
cp -r rustam.resources ~/.config/omarchy/plugins/
cp -r rustam.meds ~/.config/omarchy/plugins/
```

### Step 2: Add to `shell.json`

Open `~/.config/omarchy/shell.json` in your editor and:

1. Add the plugin IDs to the `"plugins"` array:
   ```json
   "plugins": [
     "rustam.resources",
     "rustam.meds"
   ]
   ```

2. Place them in your desired bar layout (`"left"`, `"center"`, or `"right"`):
   ```json
   "layout": {
     "left": [
       { "id": "rustam.resources" }
     ],
     "center": [
       { "id": "rustam.meds" }
     ]
   }
   ```

### Step 3: Reload Omarchy Shell

```bash
omarchy restart shell
```

Both plugins will immediately appear and function on your bar!

---

## Plugin Details

### 1. `rustam.resources` (System Resource Monitor)

- **Features**:
  - **Top Bar Pill**: Displays live CPU % and RAM usage (GB / total) with visual progress bar indicator.
  - **Interactive Popup**:
    - Detailed CPU per-core breakdown & thermal sensors.
    - RAM usage breakdown (Used, Free, Available, Buffers/Cached).
    - Disk I/O & filesystem storage meters.
    - Network upload & download speeds.
    - Live top process list sorted by CPU or Memory usage.
    - In-popup process killer with confirmation prompt.
- **Backend**:
  - `res_stats.cpp`: Scrapes `/proc/stat`, `/proc/meminfo`, `/proc/diskstats`, `/proc/[pid]/stat`, and `/sys/class/hwmon/` directly with sub-millisecond execution times.
  - Precompiled binary `res_stats` is included for `x86_64` Linux systems.
  - To compile on any other architecture (e.g. ARM64 / Apple Silicon / Raspberry Pi):
    ```bash
    cd rustam.resources
    ./build.sh
    ```

---

### 2. `rustam.meds` (Medication Tracker)

- **Features**:
  - **Top Bar Pill**: Displays `med💊`.
    - **Red**: When any dose in the active window has not been taken yet.
    - **Normal Bar Color**: Once all doses for the active window are taken.
  - **Schedule Windows**:
    - **Morning Window (5:00 AM – 5:00 PM)**: Tracks `Magnesium 1` and `B12 1`. Must be taken before 5:00 PM.
    - **Evening Window (5:00 PM – 5:00 AM)**: Tracks `Magnesium 2` and `B12 2`.
  - **Pill Interactions**:
    - Single click: Marks pill taken (transitions button color from red to blue).
    - Double click: Accidental toggle protection; unmarks pill back to red.
  - **Persistence**:
    - Automatically persists daily state to `~/.config/omarchy/meds-state.json`.
    - Automatically rolls over to a new day at 5:00 AM each morning without manual resets.
- **Backend**:
  - `meds_helper.py`: Lightweight Python 3 script handling daily time-window schedules and state persistence.

---

## Portability & Troubleshooting

- **No Hardcoded Usernames**: Both plugins use dynamic `Qt.resolvedUrl(".")` pathing, meaning they adapt automatically to any username or filesystem path.
- **Executable Permissions**: If scripts fail to execute after copying to a new system, ensure permissions are set:
  ```bash
  chmod +x ~/.config/omarchy/plugins/rustam.resources/res_stats
  chmod +x ~/.config/omarchy/plugins/rustam.meds/meds_helper.py
  ```
- **Dependencies**:
  - `python3` (standard on Arch Linux / Omarchy)
  - `g++` (only if you need to recompile `res_stats.cpp` on non-x86_64 architectures)
