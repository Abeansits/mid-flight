class Midflight < Formula
  desc "On-demand consult with Codex, Gemini, Antigravity, OpenCode, Oz, Grok, or Claude"
  homepage "https://github.com/Abeansits/mid-flight"
  url "https://github.com/Abeansits/mid-flight/archive/refs/tags/v1.19.1.tar.gz"
  sha256 "5038bc5bd12b1e12ab857dda0cfb6a5b008ae4db3b441bdddcae0a5a76d7e015"
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
