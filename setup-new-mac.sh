#!/usr/bin/env bash
#
# setup-new-mac.sh — provision a fresh Mac from your current one.
#
# MODEL: run this ON THE NEW MAC. It PULLS settings from the old Mac over SSH
#        (rsync) and re-clones your repos fresh from GitHub. The old Mac is
#        never modified.
#
# USAGE:
#   1. On the NEW mac, copy this whole folder over once:
#        scp -r <oldhost>:~/mac-sync ~/mac-sync
#   2. Edit OLDHOST below (or pass it as env: OLDHOST=myoldmac ./setup-new-mac.sh)
#   3. Run all phases:        ./setup-new-mac.sh
#      Or run some phases:    ./setup-new-mac.sh ssh dotfiles repos
#
# Phases (in safe order): ssh dotfiles config bin terminal vscode brew repos
#
# Notes:
#   - SSH keys are copied first because cloning uses git@github.com.
#   - Repos are re-cloned clean from GitHub. Uncommitted changes and unpushed
#     local branches on the old mac are NOT carried over (by your choice).
#   - Re-running is safe: existing files are overwritten, existing repos skipped.

set -uo pipefail

# ---- CONFIG -----------------------------------------------------------------
OLDHOST="${OLDHOST:-CHANGE_ME}"        # ssh host/alias of your current mac
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# -----------------------------------------------------------------------------

C_OK=$'\033[32m'; C_HDR=$'\033[1;34m'; C_WARN=$'\033[33m'; C_OFF=$'\033[0m'
hdr() { printf '\n%s==> %s%s\n' "$C_HDR" "$1" "$C_OFF"; }
ok()  { printf '%s    %s%s\n' "$C_OK" "$1" "$C_OFF"; }
warn(){ printf '%s    %s%s\n' "$C_WARN" "$1" "$C_OFF"; }

require_oldhost() {
  if [ "$OLDHOST" = "CHANGE_ME" ]; then
    echo "ERROR: set OLDHOST (edit the script or run: OLDHOST=myoldmac $0 ...)" >&2
    exit 1
  fi
}

# pull <remote path> <local dest> <label>  — copy one file/dir from the old mac
pull() {
  rsync -azP "$OLDHOST:$1" "$2" 2>/dev/null && ok "$3" || warn "skip: $3"
}

# ============================================================================
phase_ssh() {
  require_oldhost
  hdr "SSH keys & config (needed for git@github.com clones)"
  mkdir -p "$HOME/.ssh"
  for f in config known_hosts id_ed25519 id_ed25519.pub \
           id_ed25519_api_test id_ed25519_api_test.pub vpn-amnezia.pem; do
    pull "~/.ssh/$f" "$HOME/.ssh/" "ssh: $f"
  done
  chmod 700 "$HOME/.ssh"
  chmod 600 "$HOME/.ssh/"* 2>/dev/null
  chmod 644 "$HOME/.ssh/"*.pub 2>/dev/null
  # load the key into the agent + macOS keychain ONCE, so the 17 repo clones
  # don't each prompt for the key passphrase
  ssh-add --apple-use-keychain "$HOME/.ssh/id_ed25519" 2>/dev/null \
    && ok "key cached in agent/keychain" || warn "ssh-add: enter passphrase above if prompted"
  # warm github host key so the first clone doesn't prompt
  ssh-keyscan github.com 2>/dev/null >> "$HOME/.ssh/known_hosts" 2>/dev/null
  sort -u "$HOME/.ssh/known_hosts" -o "$HOME/.ssh/known_hosts" 2>/dev/null
  ok "verifying GitHub SSH auth..."
  ssh -o StrictHostKeyChecking=accept-new -T git@github.com 2>&1 | grep -q "successfully authenticated" \
    && ok "GitHub SSH works" || warn "GitHub SSH NOT confirmed — fix before 'repos' phase"
}

phase_dotfiles() {
  require_oldhost
  hdr "Shell & misc dotfiles"
  for f in .zshrc .zprofile .zshenv .bashrc .profile \
           .gitconfig .tmux.conf .vimrc; do
    pull "~/$f" "$HOME/" "$f"
  done
}

phase_config() {
  require_oldhost
  hdr "~/.config (gh, git, iterm2, zed, htop, fish, yarn)"
  mkdir -p "$HOME/.config"
  for d in gh git iterm2 zed htop fish yarn; do
    pull "~/.config/$d" "$HOME/.config/" ".config/$d"
  done
}

phase_bin() {
  require_oldhost
  hdr "~/bin and ~/git-scripts"
  pull "~/bin/"         "$HOME/bin/"         "~/bin"
  pull "~/git-scripts/" "$HOME/git-scripts/" "~/git-scripts"
  warn "note: ~/bin/github-mcp-server is a compiled binary — fine if the new mac is also Apple Silicon (arm64), otherwise re-download it."
}

phase_terminal() {
  require_oldhost
  hdr "Terminal settings (iTerm2 + Terminal.app)"
  warn "Quit iTerm2 and Terminal.app now so cached prefs don't clobber these."
  pull "~/Library/Preferences/com.googlecode.iterm2.plist" "$HOME/Library/Preferences/" "iTerm2 plist"
  pull "~/Library/Preferences/com.apple.Terminal.plist"    "$HOME/Library/Preferences/" "Terminal.app plist"
  # force the prefs system to reload from the copied plists
  defaults import com.googlecode.iterm2 "$HOME/Library/Preferences/com.googlecode.iterm2.plist" 2>/dev/null
  defaults import com.apple.Terminal     "$HOME/Library/Preferences/com.apple.Terminal.plist" 2>/dev/null
  killall cfprefsd 2>/dev/null
  ok "imported; restart the terminal app to see colors/profiles"
}

phase_vscode() {
  require_oldhost
  hdr "VS Code settings + extensions"
  local dest="$HOME/Library/Application Support/Code/User"
  local src="~/Library/Application\\ Support/Code/User"   # backslash protects the space on the remote shell
  mkdir -p "$dest"
  pull "$src/settings.json"    "$dest/" "settings.json"
  pull "$src/keybindings.json" "$dest/" "keybindings.json"
  pull "$src/snippets"         "$dest/" "snippets"
  if command -v code >/dev/null 2>&1 && [ -f "$SCRIPT_DIR/vscode-extensions.txt" ]; then
    while read -r ext; do
      [ -n "$ext" ] && code --install-extension "$ext" --force >/dev/null 2>&1 && ok "ext: $ext"
    done < "$SCRIPT_DIR/vscode-extensions.txt"
  else
    warn "'code' CLI not found or vscode-extensions.txt missing — install VS Code + shell command first"
  fi
}

phase_brew() {
  hdr "Homebrew + Brewfile"
  if ! command -v brew >/dev/null 2>&1; then
    warn "Homebrew not installed. Install it, then re-run: $0 brew"
    warn '  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"'
    return
  fi
  if [ -f "$SCRIPT_DIR/Brewfile" ]; then
    brew bundle --file="$SCRIPT_DIR/Brewfile" && ok "brew bundle done"
  else
    warn "Brewfile not found next to script"
  fi
}

# ---- repos ------------------------------------------------------------------
# clone_repo <dir> <origin-url> [name=url ...extra remotes]
clone_repo() {
  local dir="$HOME/$1"; shift
  local origin="$1"; shift
  if [ -d "$dir/.git" ]; then warn "exists, skip: $dir"; return; fi
  hdr "clone $(basename "$dir")"
  if git clone "$origin" "$dir"; then
    for r in "$@"; do
      git -C "$dir" remote add "${r%%=*}" "${r#*=}" 2>/dev/null && ok "remote ${r%%=*}"
    done
    ok "done: $dir (fetch extra remotes on demand)"
  else
    warn "clone failed: $dir"
  fi
}

phase_repos() {
  hdr "Re-cloning repos from GitHub (clean)"
  clone_repo playwright git@github.com:yury-s/playwright.git \
    dgozman=git@github.com:dgozman/playwright.git \
    hbenl=git@github.com:hbenl/playwright.git \
    pavelfeldman=git@github.com:pavelfeldman/playwright.git \
    upstream=git@github.com:microsoft/playwright.git \
    whimboo=https://github.com/whimboo/playwright.git
  git -C "$HOME/playwright" config pull.ff only 2>/dev/null

  clone_repo playwright-browsers git@github.com:yury-s/playwright-browsers.git \
    upstream=git@github.com:microsoft/playwright-browsers.git
  clone_repo playwright-cli git@github.com:microsoft/playwright-cli.git \
    fork=git@github.com:yury-s/playwright-cli.git
  clone_repo playwright-internal git@github.com:microsoft/playwright-internal.git \
    fork=git@github.com:yury-s/playwright-internal.git
  clone_repo playwright-java git@github.com:yury-s/playwright-java.git \
    upstream=git@github.com:microsoft/playwright-java.git
  git -C "$HOME/playwright-java" config pull.ff only 2>/dev/null
  git -C "$HOME/playwright-java" config pull.rebase true 2>/dev/null
  clone_repo playwright-mcp git@github.com:yury-s/playwright-mcp.git \
    pavelfeldman=git@github.com:pavelfeldman/playwright-mcp.git \
    upstream=git@github.com:microsoft/playwright-mcp.git
  clone_repo playwright-mobile git@github.com:microsoft/playwright-mobile.git
  clone_repo playwright-vscode git@github.com:microsoft/playwright-vscode.git \
    fork=git@github.com:yury-s/playwright-vscode.git

  # WebKit: clean clone is large/slow. After cloning, git-webkit setup restores
  # the WebKit-specific git config (diff drivers, credential helper, includes).
  # clone_repo webkit git@github.com:WebKit/WebKit.git \
  #   browser_upstream=https://github.com/WebKit/WebKit.git \
  #   fork=git@github.com:yury-s/WebKit.git
  # if [ -d "$HOME/webkit/.git" ]; then
  #   git -C "$HOME/webkit" config pull.rebase true 2>/dev/null
  #   warn "webkit: run  (cd ~/webkit && Tools/Scripts/git-webkit setup)  to restore WebKit git config"
  # fi
}

# ============================================================================
ALL=(ssh dotfiles config bin terminal vscode brew repos)
run=("$@"); [ ${#run[@]} -eq 0 ] && run=("${ALL[@]}")
for p in "${run[@]}"; do
  if declare -f "phase_$p" >/dev/null; then "phase_$p"; else warn "unknown phase: $p"; fi
done
hdr "Done. Open a new shell to pick up dotfiles."
