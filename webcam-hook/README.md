# webcam-hook

A small macOS background tool that turns an Elgato Key Light on while a camera
is in use, and off when it isn't.

Once a second it asks CoreMediaIO whether a camera whose name contains
`Facecam` is running (`kCMIODevicePropertyDeviceIsRunningSomewhere`). An
unplugged camera counts as off. When the state changes it sends

```
PUT http://elgato-key-light-air-eaa5.local:9123/elgato/lights
{"numberOfLights":1,"lights":[{"on":1}]}
```

(or `"on":0`). Only `on` is sent, so brightness and colour temperature stay as
they are. A failed request is retried on the next tick. At startup it reads the
light once (GET) and logs whether it's reachable.

Requires macOS 14 or newer.

## Install

```sh
make install     # build (release), copy to ~/.local/bin, install + bootstrap the LaunchAgent
make logs        # tail -f ~/Library/Logs/webcam-hook.log
make uninstall   # bootout and remove the binary and plist
```

The agent (`launchd/me.arne.webcam-hook.plist`) runs at login and is kept
alive by launchd.

## Configuration

| Flag                | Env var                 | Default                                                     |
| ------------------- | ----------------------- | ----------------------------------------------------------- |
| `--camera <name>`   | `WEBCAM_HOOK_CAMERA`    | `Facecam` (substring of the camera name)                    |
| `--light-url <url>` | `WEBCAM_HOOK_LIGHT_URL` | `http://elgato-key-light-air-eaa5.local:9123/elgato/lights` |

Flags win over env vars. To change them for the LaunchAgent, add the flags to
`ProgramArguments` in `launchd/me.arne.webcam-hook.plist` (there's a commented
example) and run `make install` again.

`webcam-hook --check` lists the cameras (`*` marks matches, with their
running state), reads the light's state once, and exits. It never changes the
light.

## Finding a light's hostname

```sh
dns-sd -B _elg._tcp                              # browse; note the instance name
dns-sd -L "Elgato Key Light Air EAA5" _elg._tcp  # resolve it; prints host and port
```

The second command prints something like
`can be reached at elgato-key-light-air-eaa5.local.:9123`. The URL is then
`http://<host>:<port>/elgato/lights`.

## Permissions

### Local Network

Since macOS 15, programs need the Local Network permission to reach `.local`
hosts. Tools run from Terminal are exempt, but **LaunchAgents are not**. Without
the permission, requests from the agent fail with
`NSURLErrorDomain -1009 "The Internet connection appears to be offline"`, even
though the same binary works fine from a shell.

macOS identifies the program by its code signature. There's no Apple-issued
signing identity here, so I chose ad hoc signing with a stable identifier over
wrapping it in an `.app` bundle:

- `Support/Info.plist` is embedded in the binary (`__TEXT,__info_plist`, see
  `Package.swift`). It carries the bundle ID `me.arne.webcam-hook` and an
  `NSLocalNetworkUsageDescription`, so the prompt has a name and a reason.
- `make install` re-signs the installed binary with
  `codesign --force --sign - --identifier me.arne.webcam-hook`, which binds
  that Info.plist to the signature.

On first start of the agent, macOS shows a Local Network prompt for
webcam-hook. Click Allow. The startup log line `light reachable: …` confirms
it worked. If you see `light not reachable` instead, check System Settings →
Privacy & Security → Local Network.

Caveat: an ad hoc signature's identity is the hash of the binary. Reinstalling
the same build keeps the permission, but after a code change macOS may treat it
as a new program and ask again (or block it until you allow it in System
Settings). Signing with an Apple Development or Developer ID certificate would
avoid that.

### Camera

None needed: the tool only reads whether a camera is running, it never opens
one.

Note: inside a sandboxed shell, CoreMediaIO returns an empty device list, so
the camera always looks off there. Test outside the sandbox.
