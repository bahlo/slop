# slop

[![CI](https://github.com/bahlo/slop/actions/workflows/ci.yml/badge.svg)](https://github.com/bahlo/slop/actions/workflows/ci.yml)

Small tools I wanted for myself.

> [!WARNING]
> **Everything in this repository was written by an LLM.** That includes the
> code, the tests, the build scripts, the docs, and this README. I described
> what I wanted, steered and tested the result, but I didn't write or
> line-by-line review it. No human wrote this code. It works on my machine, for
> my setup. Use it at your own risk.

## Tools

### [Tomato](Tomato/) 🍅

A menubar time tracker. Start and stop a timer from the menubar, which shows
the time tracked today. It reminds you to take a break after a work interval
(45 min by default; you can turn reminders off). You can edit past entries in a
window. Data is stored as JSON in `~/Library/Application Support/Tomato/`.
English and Danish. Requires macOS 15+.

### [webcam-hook](webcam-hook/)

A background agent that turns an Elgato Key Light on while your camera is in
use and off when it isn't. It polls CoreMediaIO once a second and talks to the
light's local HTTP API. Runs as a LaunchAgent. Requires macOS 14+.

## Building

Tomato and webcam-hook are Swift packages and build with just the Xcode Command
Line Tools. See the README in each directory.
