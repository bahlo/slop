# Tomato 🍅

A tiny macOS menubar time tracker with start/stop semantics and 45/15 break
reminders. The menubar item shows a timer icon plus the time tracked today;
the menu shows today's and this week's totals.

- **Start/stop** from the menubar (⌘T while the menu is open).
- **Edit entries** in a window: fix start/end times (e.g. forgot to stop),
  delete, or add manual entries.
- **Break reminders** after a configurable work interval (default 45 min):
  a floating panel offers *Start Break* (stops tracking, counts down 15 min,
  then reminds you to resume), *Snooze*, or *Skip*. Sleeping the Mac for
  longer than a break counts as one. Turn them off in Settings to use Tomato
  as a plain time tracker.
- **Local storage**: human-readable JSON in
  `~/Library/Application Support/Tomato/` (entries + settings), written
  atomically. The running entry is persisted immediately, so a crash or
  restart never loses time.

## Build

Requires only the Xcode Command Line Tools (no Xcode):

```sh
make app        # builds dist/Tomato.app (release, ad-hoc signed)
open dist/Tomato.app
```

Move `dist/Tomato.app` to `/Applications` if you like it.

## Develop

```sh
make test       # unit tests (TomatoCore is UI-free and fully tested)
make smoke      # selftest + live-launch checks (needs a GUI session)
swift run       # run the menubar app unbundled
```

`TOMATO_DATA_DIR=/some/dir` overrides the storage location (used by the
smoke tests to keep real data untouched).
