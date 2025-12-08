class Scrap < Formula
  desc "Fast, interactive note-taking CLI tool with integrated explorer interface"
  homepage "https://github.com/zachanderson/scrap"
  version "1.0.0"
  
  on_macos do
    if Hardware::CPU.arm?
      url "https://github.com/zachanderson/scrap/releases/download/v1.0.0/scrap-macos-arm64.tar.gz"
      sha256 "REPLACE_WITH_ARM64_SHA256"
    else
      url "https://github.com/zachanderson/scrap/releases/download/v1.0.0/scrap-macos-x86_64.tar.gz"
      sha256 "REPLACE_WITH_X86_64_SHA256"
    end
  end

  on_linux do
    url "https://github.com/zachanderson/scrap/releases/download/v1.0.0/scrap-linux-x86_64.tar.gz"
    sha256 "REPLACE_WITH_LINUX_SHA256"
  end

  license "MIT"

  depends_on "fzf"
  depends_on "bat"

  def install
    bin.install "scrap"
    
    # Install the explorer script
    (libexec/"scripts").install "scripts/explorer.sh"
    
    # Create a wrapper script that sets the environment variable
    (bin/"scrap").write <<~EOS
      #!/bin/bash
      export SCRAP_SCRIPTS_PATH="#{libexec}/scripts"
      exec "#{libexec}/scrap" "$@"
    EOS
    
    # Install the actual binary
    libexec.install "scrap"
  end

  test do
    system "#{bin}/scrap", "help"
  end
end