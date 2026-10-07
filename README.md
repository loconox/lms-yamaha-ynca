# Yamaha YNCA Amp Control for Lyrion Music Server

A [Lyrion Music Server](https://lyrion.org/) (formerly Logitech Media Server / Squeezebox Server) plugin
that automatically powers a Yamaha amplifier on when playback starts, and back to standby after a period
of silence, using the YNCA network protocol.

## Features

- Powers the amplifier **on** as soon as any player starts playing.
- Switches the amplifier back to **standby** after a configurable delay (default 5 minutes) once nothing
  is playing on any player.
- Optionally selects an **input** on the amplifier a few seconds after power on, to make sure it's ready
  to accept the command.
- The input dropdown is populated live from the amplifier (showing the custom names you gave your HDMI/AV/
  Audio jacks) when it's reachable, with a generic fallback list otherwise.
- Configuration page: amplifier IP/hostname, YNCA port, power-off delay, startup input, input-switch delay.

## Requirements

- A Yamaha AV receiver that supports the YNCA protocol over the network (TCP, default port 50000).
- Lyrion Music Server 8.0 or later.
- The amplifier and the Lyrion server must be reachable over the same local network.

## Installation

### Option A - Add the repository (recommended)

1. In Lyrion, go to **Settings > Plugins > Additional Repositories**.
2. Add this URL:
   ```
   https://raw.githubusercontent.com/<owner>/<repo>/main/repo.xml
   ```
3. Go back to **Settings > Plugins**, find "Yamaha YNCA Amp Control" and enable it.
4. Restart the server.

### Option B - Manual install

1. Copy the `Plugins/YamahaYNCA` directory into the server's `Plugins` folder (the one next to `Slim/`,
   e.g. `/usr/share/squeezeboxserver/Plugins` or `/usr/share/lyrion/Plugins` depending on your install).
2. Restart the server.

## Configuration

Go to **Settings > Plugins > Yamaha YNCA Amp Control** and fill in:

| Field | Description |
|---|---|
| Amplifier IP address or hostname | IP of the amp on your local network (e.g. `192.168.1.50`). Leave empty to disable the plugin. |
| YNCA network port | TCP port for the YNCA protocol. Defaults to `50000`. |
| Power off delay (minutes) | Minutes without playback on any player before the amp goes to standby. Default `5`. |
| Input to select on power on | Input automatically selected after power on. "Don't change" keeps the amp's last used input. |
| Delay before input change (seconds) | Wait time after power on before switching input, to let the amp finish booting. Default `2`. |

## How it works

The plugin polls every 10 seconds whether any Lyrion player is actively playing
(`Slim::Player::Client::clients()` / `isPlaying()`). On the first player found playing, it sends
`@MAIN:PWR=On` to the amp, then (if configured) `@MAIN:INP=<input>` after the configured delay. When no
player has been playing for longer than the power-off delay, it sends `@MAIN:PWR=Standby`.

Commands are sent over a short-lived TCP connection, following the YNCA protocol documented in
[`doc/Yamaha-YNCA-Receivers.pdf`](doc/Yamaha-YNCA-Receivers.pdf).

## Building and releasing

```sh
make build     # produces dist/YamahaYNCA.zip
make sha1       # prints the zip's sha1
make version    # prints the version declared in install.xml
make repo-xml   # regenerates repo.xml (needs a GitHub 'origin' remote, or REPO=owner/name)
```

To publish a new release:

1. Bump `<version>` in `Plugins/YamahaYNCA/install.xml`.
2. Tag and push: `git tag vX.Y && git push origin vX.Y`.
3. The `.github/workflows/release.yml` workflow builds the zip, publishes it as a GitHub Release asset,
   and updates `repo.xml` on `main` automatically.

## License

GPLv2, consistent with Lyrion Music Server and its plugin ecosystem.
