# Homebrew formula sketch for MidFlight.
#
# The Abeansits/mid-flight tap is NOT published yet. From a checkout:
#
#   brew install --HEAD --formula ./Formula/midflight.rb
#
# After a matching GitHub release exists, add a stable `url` + `sha256` (see
# comment below) and then `brew install --formula ./Formula/midflight.rb`.
#
# Do not advertise `brew tap Abeansits/mid-flight` until that tap exists.

class Midflight < Formula
  desc "On-demand consult with Codex, Gemini, Antigravity, OpenCode, Oz, Grok, or Claude"
  homepage "https://github.com/Abeansits/mid-flight"
  license "MIT"
  head "https://github.com/Abeansits/mid-flight.git", branch: "main"

  # Stable bottle block — uncomment and fill sha256 when publishing a release:
  # url "https://github.com/Abeansits/mid-flight/archive/refs/tags/v1.14.0.tar.gz"
  # sha256 "REPLACE_WITH_TARBALL_SHA256"
  # version "1.14.0"

  depends_on "bash"

  def install
    # Keep repo layout so bin/midflight can resolve ../scripts and plugin.json.
    libexec.install "bin", "scripts", "commands", "prompts", "hosts", "docs"
    libexec.install ".claude-plugin"
    libexec.install "LICENSE", "README.md" if (buildpath/"LICENSE").exist?
    libexec.install "ROADMAP.md" if (buildpath/"ROADMAP.md").exist?

    chmod 0755, libexec/"bin/midflight"
    bin.install_symlink libexec/"bin/midflight"
  end

  test do
    assert_match(/\d+\.\d+\.\d+/, shell_output("#{bin}/midflight --version"))
  end
end
