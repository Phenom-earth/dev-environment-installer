#!/bin/bash
# install-mac.command — DOUBLE-CLICK installer for the Phenom dev-environment (Mac Studio).
#
# For a non-technical operator: download this one file, double-click it in Finder, and follow
# the on-screen dialogs. There is NO typing in Terminal. Every input is a native macOS dialog
# (buttons, password boxes, a folder picker). A Terminal window appears only to show progress.
#
# What it does, all via dialogs:
#   1. installs the small developer tools it needs (Homebrew, gh, git) if missing,
#   2. collects the credentials Matt gave you and stores them safely in the macOS Keychain,
#   3. asks where to keep developer data (a folder picker),
#   4. downloads the installer (the sablier-weblogon repo) and runs it non-interactively.
#
# The heavy lifting is bin/install.sh (the same engine); this file is just the friendly,
# click-driven front door for it.
set -uo pipefail

KEYCHAIN_SERVICE_PREFIX="phenom-dev-environment"
REPO="Phenom-earth/sablier-weblogon"
CLONE_DIR="$HOME/PhenomDevEnvironment/sablier-weblogon"
LOG="$HOME/PhenomDevEnvironment/install-$(date +%Y%m%d-%H%M%S).log"
mkdir -p "$(dirname "$LOG")"; exec > >(tee -a "$LOG") 2>&1

# ---- native dialog helpers (osascript) -----------------------------------------------------
osa() { /usr/bin/osascript -e "$1" 2>/dev/null; }
say()      { echo "[install] $*"; }
info()     { osa "display dialog \"$1\" buttons {\"OK\"} default button \"OK\" with title \"Phenom setup\" with icon note"; }
confirm()  { osa "display dialog \"$1\" buttons {\"Cancel\",\"Continue\"} default button \"Continue\" with title \"Phenom setup\" with icon note" | grep -q "Continue"; }
fail_box() { osa "display dialog \"$1\" buttons {\"OK\"} default button \"OK\" with title \"Phenom setup: needs attention\" with icon stop"; }
done_box() { osa "display dialog \"$1\" buttons {\"Done\"} default button \"Done\" with title \"Phenom setup: complete\" with icon note"; }
ask_text() { osa "text returned of (display dialog \"$1\" default answer \"$2\" buttons {\"OK\"} default button \"OK\" with title \"Phenom setup\")"; }
ask_secret() { osa "text returned of (display dialog \"$1\" default answer \"\" with hidden answer buttons {\"OK\"} default button \"OK\" with title \"Phenom setup\")"; }
pick_folder() { osa "POSIX path of (choose folder with prompt \"$1\")"; }

kc_set() { # kc_set <key> <value>
  [ -n "${2:-}" ] || return 0
  security add-generic-password -a "$USER" -s "$KEYCHAIN_SERVICE_PREFIX/$1" -w "$2" -U >/dev/null 2>&1
}
kc_has() { security find-generic-password -a "$USER" -s "$KEYCHAIN_SERVICE_PREFIX/$1" -w >/dev/null 2>&1; }

abort() { fail_box "$1

Nothing was changed that you need to undo. You can re-run this installer any time, or send this message to Matt:

$2"; exit 1; }

# ---- 0. welcome ----------------------------------------------------------------------------
confirm "Welcome. This will set up the Phenom developer environment on this Mac.\n\nIt takes a few minutes and will ask you a few questions with simple dialogs. You will not need to type any commands.\n\nClick Continue to begin." || { say "user cancelled at welcome"; exit 0; }

# ---- 0.5 confirm the BUILD/ORBSTACK macOS account ------------------------------------------
# Everything here (builds, containers, the voice services, the saved credentials) runs under
# the macOS account that is logged in right now, through THAT account's OrbStack. It must be
# the account the team uses for builds, or the whole environment lands in the wrong place.
CUR_USER="$(id -un)"
confirm "You are logged in to this Mac as:\n\n    $CUR_USER\n\nEverything will be built and run under THIS account, using its copy of OrbStack. It must be the account your team uses for builds and containers.\n\nIf this is NOT the build account, click Cancel, log out, log back in as the build account, and open this installer again.\n\nIs \"$CUR_USER\" the correct build account?" \
  || { info "No problem. Log in as the build account, then open this installer again."; say "wrong user ($CUR_USER); user cancelled"; exit 0; }

say "ensuring OrbStack is running for $CUR_USER"
if ! command -v docker >/dev/null 2>&1 || ! docker info >/dev/null 2>&1; then
  if [ -d "/Applications/OrbStack.app" ]; then
    confirm "OrbStack (which runs the containers) is not started yet for $CUR_USER. I will open it now. Click Continue, wait until OrbStack finishes starting, then setup continues automatically." || { say "user cancelled at OrbStack start"; exit 0; }
    open -a OrbStack 2>/dev/null
    for i in $(seq 1 45); do docker info >/dev/null 2>&1 && break; sleep 2; done
    docker info >/dev/null 2>&1 || abort "OrbStack did not finish starting in time." "OrbStack not ready for $CUR_USER after waiting; open it, wait until ready, re-run"
  else
    abort "OrbStack is not installed for this account ($CUR_USER). It is required to run the containers." "OrbStack.app not found for $CUR_USER; install OrbStack as the build account first"
  fi
fi
say "OrbStack is running for $CUR_USER"

# ---- 1. developer tools (Homebrew, gh, git) ------------------------------------------------
say "checking developer tools"
if ! command -v brew >/dev/null 2>&1; then
  if confirm "This Mac needs Homebrew (a free tool installer) first. I can install it now. You may be asked for this Mac's password (that is normal).\n\nInstall Homebrew now?"; then
    say "installing Homebrew (non-interactive)"
    NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" || abort "Homebrew could not be installed automatically." "Homebrew install failed; see $LOG"
    # make brew available in this session
    [ -x /opt/homebrew/bin/brew ] && eval "$(/opt/homebrew/bin/brew shellenv)"
    [ -x /usr/local/bin/brew ] && eval "$(/usr/local/bin/brew shellenv)"
  else
    abort "Homebrew is required to continue." "User declined Homebrew install"
  fi
fi
say "installing gh + git via Homebrew (skips if present)"
brew install gh git >/dev/null 2>&1 || true
command -v gh  >/dev/null 2>&1 || abort "The GitHub tool (gh) could not be installed." "gh install failed; see $LOG"

# ---- 2. credentials (collect once -> macOS Keychain) ---------------------------------------
info "Next I will ask for the credentials Matt gave you. They are stored only on this Mac, in the macOS Keychain. If something is already saved from a previous run, I will skip it."

if ! kc_has github-token; then
  t="$(ask_secret "Paste the GitHub access token Matt gave you (it stays on this Mac):")"; kc_set github-token "$t"
fi
if ! kc_has cloudflare-api-token; then
  t="$(ask_secret "Paste the Cloudflare token Matt gave you:")"; kc_set cloudflare-api-token "$t"
fi
if ! kc_has aws-access-key-id; then
  t="$(ask_text "Paste the AWS Access Key ID Matt gave you:" "")"; kc_set aws-access-key-id "$t"
fi
if ! kc_has aws-secret-access-key; then
  t="$(ask_secret "Paste the AWS Secret Access Key Matt gave you:")"; kc_set aws-secret-access-key "$t"
fi
CF_ACCESS_AUD="$(ask_text "Paste the Cloudflare Access Application ID (AUD) Matt gave you:" "")"

GH_TOKEN_VAL="$(security find-generic-password -a "$USER" -s "$KEYCHAIN_SERVICE_PREFIX/github-token" -w 2>/dev/null)"
[ -n "$GH_TOKEN_VAL" ] || abort "No GitHub token was provided, so the installer cannot be downloaded." "github-token missing in Keychain"

# ---- 3. where to keep developer data (folder picker) ---------------------------------------
info "Now choose the folder where developer data should be kept. An external SSD is best, so it survives updates."
DEV_DATA_ROOT="$(pick_folder "Choose the folder for developer data (ideally on the external SSD):")"
[ -n "$DEV_DATA_ROOT" ] || abort "No data folder was chosen." "DEV_DATA_ROOT not chosen"
say "data folder: $DEV_DATA_ROOT"

# ---- 4. download the installer + run it (non-interactive) -----------------------------------
say "downloading the installer"
mkdir -p "$(dirname "$CLONE_DIR")"
if [ -d "$CLONE_DIR/.git" ]; then
  git -C "$CLONE_DIR" pull --ff-only >/dev/null 2>&1 || true
else
  git clone --depth 1 "https://x-access-token:${GH_TOKEN_VAL}@github.com/${REPO}.git" "$CLONE_DIR" >/dev/null 2>&1 \
    || abort "The installer could not be downloaded (the GitHub token may be wrong or lack access)." "git clone $REPO failed"
fi

confirm "Everything is ready. I will now run the setup. A Terminal window shows the progress; you do not need to type anything.\n\nClick Continue to run it." || { say "user cancelled before run"; exit 0; }

say "running bin/install.sh (non-interactive)"
# install.sh's preflight reads the credentials from the Keychain; --yes skips the text go/no-go.
DEV_DATA_ROOT="$DEV_DATA_ROOT" CF_ACCESS_AUD="$CF_ACCESS_AUD" \
  bash "$CLONE_DIR/bin/install.sh" --yes
rc=$?

if [ "$rc" -eq 0 ]; then
  done_box "Setup finished successfully. Your team can now sign in at code.thephenom.app.\n\nA full log is saved here if you ever need it:\n$LOG"
else
  fail_box "Setup stopped before finishing. Nothing is broken: you can re-run this installer any time.\n\nPlease send this log file to Matt so he can see exactly what happened:\n$LOG"
fi
exit "$rc"
