#!/bin/bash
set -e

# Clean and create release directory
echo "Cleaning previous builds..."
if [ -d "releases" ]; then
    rm -f releases/*.tar.gz 2>/dev/null || true
    rm -rf releases/scrap-* 2>/dev/null || true
fi
mkdir -p releases

echo "Building release binaries..."

# macOS ARM64 (Apple Silicon)
echo "Building for macOS ARM64..."
zig build -Doptimize=ReleaseFast -Dtarget=aarch64-macos
cp zig-out/bin/scrap releases/scrap-macos-arm64

# macOS x86_64 (Intel)
echo "Building for macOS x86_64..."
zig build -Doptimize=ReleaseFast -Dtarget=x86_64-macos
cp zig-out/bin/scrap releases/scrap-macos-x86_64

# Linux x86_64
echo "Building for Linux x86_64..."
zig build -Doptimize=ReleaseFast -Dtarget=x86_64-linux
cp zig-out/bin/scrap releases/scrap-linux-x86_64

# Create tarballs
echo "Creating release archives..."

# Verify binaries exist
echo "Checking binaries..."
ls -la releases/scrap-*

cd releases

# Create tarball with scripts
for binary in scrap-macos-arm64 scrap-macos-x86_64 scrap-linux-x86_64; do
    platform=${binary#scrap-}
    echo "Packaging ${platform}..."
    
    # Create directory structure with different name to avoid conflict
    temp_dir="package-${platform}"
    mkdir -p "$temp_dir"
    cp "$binary" "$temp_dir/scrap"
    cp -r "../src/scripts" "$temp_dir/"
    
    # Create tarball
    tar -czf "${binary}.tar.gz" "$temp_dir/"
    
    # Clean up temp directory
    rm -rf "$temp_dir"
done

echo "Release builds completed!"
echo "Files created:"
ls -la *.tar.gz