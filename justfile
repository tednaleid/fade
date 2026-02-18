# ABOUTME: Build, test, and install tasks for the fade slideshow app.
# ABOUTME: Provides release build, install, test, lint, and combined check.

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

# Run tests
test:
    swift test

# Run SwiftLint
lint:
    swiftlint lint Sources/ Tests/

# Run tests and lint
check: test lint

# Build and run with example images (for quick testing)
run *ARGS:
    swift run fade ./example {{ARGS}}
