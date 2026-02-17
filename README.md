# fade

A macOS command-line image slideshow viewer with cross-fade transitions.

## Features

- Displays JPG and PNG images from a directory with configurable fade transitions
- Keyboard and mouse navigation (next, previous, pause/play)
- Tag images using macOS Finder tags (Favorite/Green, Trash/Red) with arrow keys
- Forward navigation automatically skips trash-tagged images
- Backward navigation shows all images, including trash (for recovery)
- Trash-tagged images are shown desaturated
- Shuffle with optional seed for reproducible ordering
- Directory is rescanned every 12 seconds to pick up new images
- Runs as a background process by default, returning control to the terminal immediately

## Requirements

- macOS 13.0 or later
- Swift 5.9 or later

## Install

```
git clone <repo-url>
cd fade
just install
```

This builds a release binary and symlinks it to `~/.local/bin/fade`.

To add an "Open in Fade" right-click option in Finder, create a Quick Action in
Automator: set "Workflow receives" to files or folders in Finder, add a Run Shell
Script action with "Pass input" set to "as arguments", and use
`~/.local/bin/fade "$1"` as the script.

Or build manually:

```
swift build -c release
```

## Usage

```
fade [directory-or-file] [options]
```

`directory-or-file` defaults to the current directory. If a file path is given,
fade opens the containing directory and starts on that image.

### Options

| Flag | Default | Description |
|------|---------|-------------|
| `-d, --duration` | 10 | Seconds each image is displayed |
| `-f, --fade` | 1.5 | Fade transition duration in seconds |
| `-r, --random` | off | Shuffle image order |
| `-s, --seed` | auto | Seed for shuffle (UInt64), printed to stdout if auto-generated |
| `--scan` | 30 | Seconds between directory rescans for new images |
| `--no-loop` | off | Exit after showing all images once |
| `--actual-size` | off | Use `--width`/`--height` instead of fitting to screen |
| `--width` | 800 | Initial window width |
| `--height` | 1200 | Initial window height |
| `--slider` | off | Start with comparison slider visible |
| `--foreground` | off | Keep the CLI attached instead of detaching to background |

### Controls

| Input | Action |
|-------|--------|
| Right arrow | Next untrashed image |
| Left arrow | Previous image (including trash) |
| Up arrow | Tag toward Favorite (Trash > Untagged > Favorite) |
| Down arrow | Tag toward Trash (Favorite > Untagged > Trash) |
| S | Toggle comparison slider (current vs next image) |
| Space | Toggle pause/play |
| Q / Escape | Quit |
| Click left 10% | Previous image (including trash) |
| Click right 10% | Next untrashed image |
| Click center | Toggle pause/play |

All navigation and tagging actions show a brief directional arrow indicator on the
corresponding edge of the screen. When tagging results in Favorite or Trash, the
slideshow auto-advances to the next untrashed image after the indicator fades.

### Comparison slider

Press S to enter slider mode, which shows a vertical divider with a draggable handle.
The current image is on the left, the next image on the right. Drag the handle to
compare the two images. Left/right arrows advance both images as a pair. Up/down
arrows tag the comparison (right) image, using the same Favorite/Trash cycle as
normal mode. After tagging as Favorite or Trash, the next comparison candidate loads
automatically. Press S or Escape to exit slider mode. Entering slider mode pauses
the slideshow; exiting restores the previous play state. Click zones are disabled
while the slider is active.

## Examples

```
# Show images in ~/Pictures with default settings
fade ~/Pictures

# 5-second display, 2-second fade, shuffled
fade ~/Photos -d 5 -f 2 -r

# Reproducible shuffle order
fade ~/Photos --random --seed 42

# Show all images once and exit
fade ./images --no-loop

# Start on a specific image
fade ~/Photos/sunset.jpg

# Start on an image with slider comparison
fade ~/Photos/sunset.jpg --slider
```
