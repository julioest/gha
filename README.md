# gha

Fast GitHub Actions status for one repo or many, right from your terminal.

Mirrors the repo's Actions page — latest runs across **all** branches by default —
with live-ticking timers, an interactive `fzf` picker, and desktop notifications
when a run finishes. Point it at a list of repos and it merges them into **one
table sorted by recency**, which is the thing `gh` structurally cannot do: `gh` is
scoped to a directory or a `-R` flag by design. Runs on **macOS and Linux**.

<img src="docs/01-default.png" width="880" alt="gha showing the latest runs across all branches: a running deploy, a queued lint, a passing CI run and a failing one.">

## Usage

```
gha            latest runs across ALL branches (the Actions page)
gha -R O/R     just this repo (`-R .` resolves it from the git remote)
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
gha --ascii    plain ASCII marks, for fonts with no symbol coverage
```

## Repos

With nothing configured, `gha` behaves as it always has: one repo, resolved from
the current directory. Scope is resolved first-match-wins:

| | |
|---|---|
| `-R owner/repo` | one repo, explicitly (`-R .` = this directory's) |
| `$GHA_REPO` | one repo |
| `$GHA_REPOS` | many, comma/space/newline separated |
| `~/.config/gha/repos` | many, one `owner/repo` per line, `#` comments allowed |
| *(nothing)* | the `upstream`/`origin` remote here, else `gh`'s answer |

```sh
mkdir -p ~/.config/gha
cat > ~/.config/gha/repos <<'EOF'
# the ones I actually watch
acme/api-server
acme/web-frontend
acme/infra          # terraform + nightly drift
EOF
gha            # all three, merged, newest first
gha -f         # ... only what broke
gha -R .       # ... just the repo I'm standing in
```

A repo column appears as soon as there is more than one repo, and it is the
**last** column to drop as the window narrows — workflow and event go first,
because a table that has lost the repo column is not a multi-repo table any more.

`gha pr` is always about the branch you are on, so it ignores the list and uses
the current directory's repo.

## Polling cost

The run list is fetched with `If-None-Match`, and GitHub does not charge a `304
Not Modified` against the primary rate limit. Measured over a 60-second `gha -L`
session at the default `$GHA_POLL=6`:

| | requests issued | rate limit consumed |
|---|---|---|
| unconditional (before) — 1 repo | 10 | **10** |
| conditional — 1 repo | 10 | **1** |
| conditional — 3 repos | 28 | **5** |

The request count does not change; the *cost* does. Unconditionally that is 600
requests/hour per repo, so a list of eight would spend 4800 of the 5000/hour
budget just idling. Conditionally an idle repo costs nothing at all, and you only
pay for the polls where something actually changed.

Repos are fetched **concurrently**, so a list of eight takes one round trip, not
eight.

## Screens

`gha -i` opens an `fzf` picker. The preview pane shows the selected run's jobs,
and the footer keys open it on GitHub, tail logs, rerun, or watch in the background.

<img src="docs/04-picker.png" width="880" alt="The interactive picker: a run list on top, the selected run's jobs in a preview pane below.">

`gha pr` narrows to the checks on the current branch's open PR.

<img src="docs/02-pr.png" width="880" alt="gha pr listing the workflow checks for the current branch's pull request.">

`gha -f` shows only what broke.

<img src="docs/03-failed.png" width="880" alt="gha -f showing only the failed run.">

## Requirements

- [`gh`](https://cli.github.com) (authenticated) and [`jq`](https://jqlang.github.io/jq/)
- `bash` 3.2+ (the stock macOS `/bin/bash` is fine)
- `fzf` and `curl` — for interactive mode (`-i`)
- **Linux only:** `xdg-utils` (for `--web`) and `libnotify`/`notify-send` (for `-N` banners).
  Both degrade gracefully if absent.
- A terminal font with basic symbol coverage, for the `✓ ✗ ● ○` status marks.
  Menlo, SF Mono and JetBrains Mono are fine; **Monaco has none of them** and will
  show boxes. Run `gha --ascii` (or set `GHA_ASCII=1`) for plain ASCII marks
  instead, which also switches `fzf`'s border to ASCII.

## Install

Clone anywhere, then symlink the script onto your `PATH`:

```sh
git clone https://github.com/julioest/gha.git ~/dev/gha
ln -s ~/dev/gha/gha ~/.local/bin/gha   # or any dir on your PATH
```

`~/.local/bin` is not on `PATH` by default on macOS. Either add it
(`export PATH="$HOME/.local/bin:$PATH"` in your shell profile) or symlink
into a directory that already is, such as `/usr/local/bin`.

## Quick check

No network or `gh` needed — `--demo` renders synthetic runs:

```sh
gha --demo -n 4      # static table
gha --demo -L        # live, ticking timers
gha --demo -i -L     # interactive picker, live
```

## Tests

```sh
tests/run.sh          # golden renders + width invariant + helper unit tests
tests/run.sh --update # regenerate the fixtures
```

Needs `python3` and `jq`. See [tests/README.md](tests/README.md) for what each
suite asserts and why the display-width measurement lives in python.

## License

MIT. See [LICENSE](LICENSE).
