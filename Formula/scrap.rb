class Scrap < Formula
  desc "Fast, interactive note-taking CLI tool with integrated explorer interface"
  homepage "https://github.com/zachanderson/scrap"
  version "1.0.0"
  
  on_macos do
    if Hardware::CPU.arm?
      url "https://github.com/zachanderson/scrap/releases/download/v1.0.0/scrap-macos-arm64.tar.gz"
      sha256 "5b795abac4f1c51790505b4711b6ca705340ec385121fdf60b6701e0ef30f4e8"
    else
      url "https://github.com/zachanderson/scrap/releases/download/v1.0.0/scrap-macos-x86_64.tar.gz"
      sha256 "e1ff62f3228fe728ee09912792e85ce2a42b0c906e528b1ad58a88add03e402c"
    end
  end

  on_linux do
    url "https://github.com/zachanderson/scrap/releases/download/v1.0.0/scrap-linux-x86_64.tar.gz"
    sha256 "9cc274cb7ff6b9088843cc64765f14166fec305aeca318cae78f1f1829d4878f"
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