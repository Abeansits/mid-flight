# MidFlight roadmap

Install, config, and modes are in the [README](README.md) and [standalone usage](docs/standalone-usage.md). `midflight --help` is the short calling contract. This page is what is current, then a short record of what already shipped.

## Current

Homebrew is the install. The repo is not named `homebrew-*`, so the tap needs the git URL:

```bash
brew tap Abeansits/mid-flight https://github.com/Abeansits/mid-flight
brew install Abeansits/mid-flight/midflight
```

`Formula/midflight.rb` installs the tagged archive it names. That tag is v1.18.0 until a formula update lands on `main`. `brew install --HEAD Abeansits/mid-flight/midflight` tracks `main`. `brew tap Abeansits/mid-flight` with no URL looks for `Abeansits/homebrew-mid-flight`, which does not exist. `brew install --formula ./Formula/midflight.rb` is not a tap, and current Homebrew rejects it.

Release order: publish the tag, update the formula `url` and `sha256`, land that change on `main`, then `brew upgrade`. Stable Homebrew does not serve the new tag before that formula change. The checklist is in the README [Releasing](README.md#releasing) section.

Video analysis keeps a configured or `-p` provider of `agy` or `gemini`. Any other provider prefers `agy` on `PATH`, else Gemini. A link is downloaded with `yt-dlp` and analyzed as a file. The size limit is 100MB on `agy` and 20MB on Gemini, and `ffmpeg` shrinks what does not fit. Video generation is Grok. A readable PNG or JPEG opening frame that conflicts with `--aspect` exits 2. An unreadable frame warns on stderr and continues.

Nothing else is queued.

## Shipped

- v1.8.0 — `agy` provider (alias `antigravity`). `provider=gemini` remains for enterprise and API-key users. Video prefers `agy` on `PATH`, else Gemini. A pinned `agy` or `gemini` stays.
- v1.9.0 — Codex, Grok Build, and Cursor host adapters. Codex and Grok refuse a circular provider unless the allow flag is set. There is no `provider=cursor`.
- v1.10.0 — `grok` (alias `grok-build`) and `claude` as providers.
- v1.11.0 — `--git-status` and `--diff`, capped at 100 KiB per section.
- v1.12.0 — dual-consult (`--dual`, `--providers`). Consult-only. Stdout headings are `## Provider A`, `## Provider B`, and `## Where they differ`. No merged opinion.
- v1.13.0 — Codex consult uses `--sandbox read-only`. Implement uses `workspace-write`.
- v1.14.0 — `scripts/install.sh` and a HEAD-only formula. The custom installer is gone. Homebrew is the install path. `scripts/release.sh prepare` still writes the version to `.claude-plugin/plugin.json` and `.claude-plugin/marketplace.json`.
- v1.15.1 — dual-consult rebuilds the temp `$HOME` overlay for each side (`ln -sfn`).
- v1.20.0 — video links are downloaded with `yt-dlp` and analyzed as files. The size limit is per provider (100MB `agy`, 20MB Gemini). `ffmpeg` shrinks an oversized file and converts a format the provider does not read. Staged files keep their extension. `agy` is told to open the file with its file-reading tool.
- Cursor skills live only under `hosts/cursor/`. There is no separate grok-bot host.
- The formula installs a tagged archive under Homebrew `libexec`, so `bin/midflight` still finds `scripts/` and `.claude-plugin/` from its real path.

## Out of scope unless asked

- Automatic background review or hook-based enforcement
- Replacing the user's main agent
- Adding a CLI only to collect another model. OpenCode already routes many models. A new provider is a flag contract. Waitlist: Cursor `agent -p --mode=ask`, GitHub Copilot `copilot -p`.
