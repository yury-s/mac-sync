# Migrate to a new Mac

Pull-based, clean setup. Everything runs **on the new Mac**, reading from the
old Mac over SSH. The old Mac is never modified.

## Steps

1. **From the new Mac**, copy this folder over once:
   ```sh
   scp -r <oldhost>:~/mac-sync ~/mac-sync
   cd ~/mac-sync
   ```
   `<oldhost>` is the SSH host/alias of your current machine.

2. Set the old host and run:
   ```sh
   OLDHOST=<oldhost> ./setup-new-mac.sh
   ```
   Run a subset of phases instead:
   ```sh
   OLDHOST=<oldhost> ./setup-new-mac.sh ssh dotfiles repos
   ```

## Phases (run in this order)

| Phase      | What it does |
|------------|--------------|
| `ssh`      | Copies `~/.ssh` keys/config, verifies `git@github.com` auth. **Run first** — clones need it. |
| `dotfiles` | `.zshrc .zprofile .zshenv .bashrc .profile .gitconfig .tmux.conf .vimrc` |
| `config`   | `~/.config/{gh,git,iterm2,zed,htop,fish,yarn}` (incl. GitHub CLI login) |
| `bin`      | `~/bin` and `~/git-scripts` |
| `terminal` | iTerm2 + Terminal.app prefs (quit those apps first) |
| `vscode`   | VS Code `settings.json`, `keybindings.json`, snippets + reinstalls extensions |
| `brew`     | `brew bundle` from the captured `Brewfile` (install Homebrew first) |
| `repos`    | Re-clones all `playwright*` + `webkit` from GitHub, re-adds every remote |

## Notes / things to do by hand

- **Repos are clean clones.** Uncommitted changes and unpushed local branches
  on the old mac are **not** carried over (your choice). The default branch is
  checked out; switch branches as needed.
- **WebKit:** after cloning, restore its special git config:
  ```sh
  cd ~/webkit && Tools/Scripts/git-webkit setup
  ```
- **`~/bin/github-mcp-server`** is a compiled binary — fine if the new Mac is
  also Apple Silicon; otherwise re-download for the right arch.
- **SSH private keys** are copied as-is over SSH. If you'd rather not, generate
  a fresh key on the new Mac and add it to GitHub instead, then skip the key
  files in the `ssh` phase.

## Files in this folder

- `setup-new-mac.sh` — the script
- `Brewfile` — Homebrew formulae/casks snapshot
- `vscode-extensions.txt` — VS Code extension IDs
