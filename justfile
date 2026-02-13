# ABOUTME: Build and install tasks for the fade slideshow app.
# ABOUTME: Provides release build, install (symlink to ~/.local/bin), and clean.

# Build release binary
build:
    swift build -c release

# Install: build release and symlink into ~/.local/bin
install: build
    mkdir -p ~/.local/bin
    ln -sf "$(swift build -c release --show-bin-path)/fade" ~/.local/bin/fade

# Remove build artifacts
clean:
    swift package clean

# Build and run with example images (for quick testing)
run *ARGS:
    swift run fade ./example {{ARGS}}
