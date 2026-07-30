# gha

Fast GitHub Actions status for the current repo, right from your terminal.

Mirrors the repo's Actions page — latest runs across **all** branches by default —
with live-ticking timers, an interactive `fzf` picker, and desktop notifications
when a run finishes. Runs on **macOS and Linux**.

## Usage

```
gha            latest runs across ALL branches (the Actions page)
gha -i         interactive picker (fzf): preview jobs, open, logs, rerun
gha -L         live view: timers tick every $GHA_INTERVAL (1s) from cache;
               network refresh every $GHA_POLL (6s) in the background
gha pr         checks for the current branch's open PR
gha -b         only the CURRENT git branch
gha <branch>   only a specific branch
gha -f         only failed/cancelled runs
gha -n N       show N runs (default 15)
gha -w         watch newest run live in the FOREGROUND (blocks)
gha -N         watch newest run in the BACKGROUND + notify on finish
gha --web      open the Actions page in a browser
gha --demo     preview the UX with synthetic data (try: gha --demo -L, -i -L)
```

Repo resolution: `$GHA_REPO`, else the `upstream`/`origin` remote of the current
repo, else whatever `gh` resolves for the directory.

## Requirements

- [`gh`](https://cli.github.com) (authenticated) and [`jq`](https://jqlang.github.io/jq/)
- `bash` 4+
- `fzf` and `curl` — for interactive mode (`-i`)
- **Linux only:** `xdg-utils` (for `--web`) and `libnotify`/`notify-send` (for `-N` banners).
  Both degrade gracefully if absent.

## Install

Clone anywhere, then symlink the script onto your `PATH`:

```sh
git clone git@github.com:julioest/gha.git ~/dev/gha
ln -s ~/dev/gha/gha ~/.local/bin/gha   # or any dir on your PATH
```

## Quick check

No network or `gh` needed — `--demo` renders synthetic runs:

```sh
gha --demo -n 4      # static table
gha --demo -L        # live, ticking timers
gha --demo -i -L     # interactive picker, live
```
