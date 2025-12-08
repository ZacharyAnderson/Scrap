#!/bin/bash
set -e

echo "Setting up Homebrew distribution for Scrap..."

# Check if we're in a git repository
if ! git rev-parse --git-dir > /dev/null 2>&1; then
    echo "This directory is not a Git repository. Initializing..."
    git init
    git add .
    git commit -m "Initial commit"
fi

echo ""
echo "Next steps to complete the Homebrew setup:"
echo ""
echo "1. Create a GitHub repository:"
echo "   - Go to GitHub and create a new repository called 'scrap'"
echo "   - Add this repository as the remote:"
echo "     git remote add origin https://github.com/YOUR_USERNAME/scrap.git"
echo "     git branch -M main"
echo "     git push -u origin main"
echo ""
echo "2. Create a release:"
echo "   - Run: ./build-release.sh"
echo "   - Create a tag: git tag v1.0.0"
echo "   - Push the tag: git push origin v1.0.0"
echo "   - Go to GitHub > Releases > Create a new release"
echo "   - Upload the files from the releases/ directory"
echo ""
echo "3. Create a Homebrew tap repository:"
echo "   - Create a new GitHub repository called 'homebrew-scrap'"
echo "   - Copy Formula/scrap.rb to that repository"
echo "   - Update the SHA256 hashes in the formula with the actual hashes"
echo ""
echo "4. Get SHA256 hashes for your releases:"
echo "   shasum -a 256 releases/*.tar.gz"
echo ""
echo "5. Test the installation:"
echo "   brew tap YOUR_USERNAME/scrap"
echo "   brew install scrap"
echo ""

# Check if dependencies are available
echo "Checking dependencies..."
command -v fzf >/dev/null 2>&1 && echo "✓ fzf is installed" || echo "✗ fzf is missing (brew install fzf)"
command -v bat >/dev/null 2>&1 && echo "✓ bat is installed" || echo "✗ bat is missing (brew install bat)"
echo ""

echo "Setup script completed! Follow the steps above to finish the setup."