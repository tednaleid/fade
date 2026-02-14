# fade

A macOS command-line image slideshow viewer with cross-fade transitions.

## Features

- Displays JPG and PNG images from a directory with configurable fade transitions
- Keyboard and mouse navigation (next, previous, pause/play)
- Tag images using macOS Finder tags (Favorite/Green, Trash/Red) with arrow keys
- Trash-tagged images are shown desaturated
- Shuffle with optional seed for reproducible ordering
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

Or build manually:

```
swift build -c release
```

## Usage

```
fade [directory] [options]
```

`directory` defaults to the current directory.

### Options

| Flag | Default | Description |
|------|---------|-------------|
| `-d, --duration` | 10 | Seconds each image is displayed |
| `-f, --fade` | 1.5 | Fade transition duration in seconds |
| `-r, --random` | off | Shuffle image order |
| `-s, --seed` | auto | Seed for shuffle (UInt64), printed to stdout if auto-generated |
| `--no-loop` | off | Exit after showing all images once |
| `--actual-size` | off | Use `--width`/`--height` instead of fitting to screen |
| `--width` | 800 | Initial window width |
| `--height` | 1200 | Initial window height |
| `--foreground` | off | Keep the CLI attached instead of detaching to background |

### Controls

| Input | Action |
|-------|--------|
| Right arrow | Next image |
| Left arrow | Previous image |
| Up arrow | Tag toward Favorite (Trash > Untagged > Favorite) |
| Down arrow | Tag toward Trash (Favorite > Untagged > Trash) |
| Space | Toggle pause/play |
| Q / Escape | Quit |
| Click left 10% | Previous image |
| Click right 10% | Next image |
| Click center | Toggle pause/play |

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
```
