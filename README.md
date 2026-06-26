# Phenom dev-environment installer (double-click)

A friendly, click-driven installer for the Phenom developer environment on the **Mac Studio**.
No Terminal typing required.

## Get it

Download the latest launcher:

**https://github.com/Phenom-earth/dev-environment-installer/releases/latest/download/install-mac.command**

## Run it

1. Double-click `install-mac.command` in Finder.
   - First time only: if macOS says it is from an unidentified developer, **right-click the file → Open → Open**.
2. Follow the on-screen dialogs:
   - it installs the small tools it needs (Homebrew, gh, git) if missing,
   - it asks for the credentials Matt provided and stores them in the macOS **Keychain**,
   - it asks (with a folder picker) where to keep developer data,
   - it downloads and runs the real installer (`Phenom-earth/sablier-weblogon` `bin/install.sh`).

A Terminal window appears to show progress; you never type in it. A full log is written to
`~/PhenomDevEnvironment/`.

## What it sets up

The Cloudflare-Access (Cognito) sign-in service, the secure tunnel, the Qwen3-TTS voice +
mlx-whisper transcription helpers, and the Sablier wake-on-request access layer, so the team
can sign in at **code.thephenom.app**, enroll a cloned voice, and land in their persistent
code-server workspace.

This launcher is the public, click-driven front door. The engine is the private
`Phenom-earth/sablier-weblogon` repo (it is cloned with the GitHub token you paste during setup).
