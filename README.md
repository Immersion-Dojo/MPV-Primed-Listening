# MPV-Primed-Listening

## What Is **Primed Listening**?
*Primed listening* is a language learning technique that turns videos with translated subtitles into a useful tool to acquire language without lookups or reading. The way it works is right before each dialogue line is spoken, subtitles in a language you know (eg:English) are briefly shown on the screen while the video pauses, then the video resumes and the subtitle is hidden while you listen to the target language audio. Primed listening boosts your listening comprehension by **priming** your brain with the upcoming line's meaning just before you hear it. It is a time efficient method of making otherwise too difficult content more comprehensible and enjoyable to watch.

`primed_listening.lua` automates this workflow inside the mpv media player.

> Tip: don't consciously think too hard about how the target language you are hearing relates on a word by word level to the subtitle.
---

## Installation

1. **Download** `primed_listening.lua` from this repository.  
2. Copy it into your mpv `scripts` directory:

| OS        | Path                                                         |
|-----------|--------------------------------------------------------------|
| Windows   | `%APPDATA%\mpv\scripts\`           |
| Linux / macOS     | `~/.config/mpv/scripts/`                                     |

> Create the folder if it doesn’t exist. mpv loads the script automatically at startup.

---

## Usage

1. **Toggle Primed Listening** on/off with **`n`** (default key).  
3. While enabled, mpv will:
   - Pause at each subtitle line.  
   - Display the known-language subtitle for a calculated duration.  
   - Resume playback and hide the subtitle 

### Key bindings & options

| Action / Behaviour                                                                 | Windows / Linux Keys | macOS Keys |
|------------------------------------------------------------------------------------|----------------------|------------|
| **Toggle Primed Listening on / off**                                               | `n`                  | `n`        |
| **Increase** `pause_per_char` by +0.01 s per character                             | `Ctrl + n`           | `Cmd + n`  |
| **Decrease** `pause_per_char` by -0.01 s per character (floor 0.01 s)              | `Ctrl + b`           | `Cmd + b`  |


---

## script opts

Adjustments to the pause per character parameter are automatically written to `script-opts/primed_listening.conf` so they persist across sessions.

---

Primed listening as a technique was devloped by Matt vs Japan in his immersion Dojo community. Credit to Alex Smith for writing the first impelementation of this script. 
Join the immersion dojo here: https://www.skool.com/mattvsjapan

