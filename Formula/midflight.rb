class Midflight < Formula
  desc "On-demand consult with Codex, Gemini, Antigravity, OpenCode, Oz, Grok, or Claude"
  homepage "https://github.com/Abeansits/mid-flight"
  url "https://github.com/Abeansits/mid-flight/archive/refs/tags/v1.19.2.tar.gz"
  sha256 "0797ab7cece987943fff5c14efc68dc41c8fbe75f49bc82cfcd4278666cbb5a5"
  license "MIT"
  head "https://github.com/Abeansits/mid-flight.git", branch: "main"

  depends_on "bash"

  def install
    libexec.install "bin", "scripts", "commands", "prompts", "hosts", "docs",
                    ".claude-plugin", "LICENSE", "README.md", "ROADMAP.md"
    chmod 0755, libexec/"bin/midflight"
    bin.install_symlink libexec/"bin/midflight"
  end

  test do
    assert_match(/\Amidflight \d+\.\d+\.\d+\n/, shell_output("#{bin}/midflight --version"))
    assert_path_exists libexec/"scripts/query.sh"
    assert_path_exists libexec/".claude-plugin/plugin.json"
  end
end
