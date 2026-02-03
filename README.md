# SetWorkspace ⚡

One-click dev environment launcher for macOS. Start all your repos with correct Node version, latest code, and dev servers.

## What It Does

Click **Start** and SetWorkspace:
1. Switches to the correct Node version (via nvm)
2. Checks out the right branch and pulls latest
3. Installs dependencies (yarn/npm)
4. Runs your dev command

All repos start in parallel. Status shows real-time progress.

## Screenshot

```
┌─────────────────────────────────────┐
│ ⚡ SetWorkspace               🔄   │
├─────────────────────────────────────┤
│ ▼ peakflo           node 20.17.0   │
│   ● peakflo-web          [running] │
│   ● billing-api          [running] │
│   ● upload-function      [running] │
│                     [Stop All]     │
├─────────────────────────────────────┤
│ ⚙️ Config                    Quit  │
└─────────────────────────────────────┘
```

## Installation

1. Download `SetWorkspace.app` from [Releases](https://github.com/sageships/SetWorkspace/releases)
2. Move to `/Applications`
3. First launch: Right-click → Open (bypass Gatekeeper for unsigned app)
4. Edit config at `~/.setworkspace/config.json`

## Configuration

Config lives at `~/.setworkspace/config.json`:

```json
{
  "workspaces": [
    {
      "name": "peakflo",
      "nodeVersion": "20.17.0",
      "repos": [
        {
          "name": "peakflo-web",
          "path": "~/Developer/peakflo-web",
          "branch": "main",
          "install": "yarn",
          "run": "yarn dev"
        },
        {
          "name": "billing-api",
          "path": "~/Developer/billing-api",
          "branch": "main",
          "install": "yarn",
          "run": "yarn emulators"
        }
      ]
    }
  ]
}
```

### Config Options

| Field | Required | Description |
|-------|----------|-------------|
| `name` | ✅ | Workspace name |
| `nodeVersion` | ❌ | Node version to use (requires nvm) |
| `repos[].name` | ✅ | Display name |
| `repos[].path` | ✅ | Repo path (supports `~`) |
| `repos[].branch` | ❌ | Branch to checkout + pull |
| `repos[].install` | ❌ | Install command (e.g., `yarn`, `npm install`) |
| `repos[].run` | ✅ | Dev server command |

## Features

- **One-click start/stop** for entire workspace
- **Individual repo control** - start/stop single repos
- **Real-time status** - see setup progress (nvm → git → install → running)
- **Multiple workspaces** - configure different projects
- **Auto-cleanup** - stops all processes when you quit

## Requirements

- macOS 13+
- [nvm](https://github.com/nvm-sh/nvm) (if using `nodeVersion`)

## Building from Source

```bash
swift build -c release
```

## License

MIT
