# mcp-google-keep

MCP server for Google Keep. Fork of [feuerdev/keep-mcp](https://github.com/feuerdev/keep-mcp) with SSE transport.

## Quick Start

```bash
# 1. Clone
git clone https://github.com/gellyfish-ai/mcp-google-keep.git
cd mcp-google-keep

# 2. Create credential file (see "Getting a Master Token" below)
mkdir -p ~/.config/gellyfish
cat > ~/.config/gellyfish/google-keep.env << 'EOF'
GOOGLE_EMAIL=your-email@gmail.com
MASTER_TOKEN=your-master-token
ANDROID_ID=your-hex-id
UNSAFE_MODE=true
EOF
chmod 600 ~/.config/gellyfish/google-keep.env

# 3. Run setup (creates venv, installs deps, creates launchd service, starts it)
./setup.sh
```

That's it. The server is now running on `http://localhost:8204` and will restart on boot.

## Getting a Master Token

The `gkeepapi` library uses an unofficial Google API. The password-based auth flow is broken — use the **cookie-based exchange:**

1. Open an **incognito/private** browser window
2. Go to `https://accounts.google.com/EmbeddedSetup`
3. Log in with your Google account (2FA works)
4. Click **"I agree"** — the page hangs on a loading screen forever. This is expected.
5. Open DevTools -> Application -> Cookies -> `accounts.google.com`
6. Copy the `oauth_token` cookie value
7. Run the exchange **immediately** (the cookie expires fast):

```bash
# If you haven't run setup.sh yet, create a temporary venv:
python3 -m venv .venv && .venv/bin/pip install gpsoauth

.venv/bin/python3 -c '
import gpsoauth, secrets
email = input("Email: ")
oauth_token = input("OAuth Token: ")
android_id = secrets.token_hex(8)
result = gpsoauth.exchange_token(email, oauth_token, android_id)
if "Token" in result:
    print(f"\nGOOGLE_EMAIL={email}")
    print(f"MASTER_TOKEN={result[\"Token\"]}")
    print(f"ANDROID_ID={android_id}")
    print("\nPaste these into ~/.config/gellyfish/google-keep.env")
else:
    print("FAILED:", result)
    print("The oauth_token cookie probably expired. Try again faster.")
'
```

**Important:** The master token is tied to the `ANDROID_ID`. Keep both.

## Manual Setup (without setup.sh)

If you prefer to do it yourself:

```bash
# 1. Clone and install
git clone https://github.com/gellyfish-ai/mcp-google-keep.git
cd mcp-google-keep
python3 -m venv .venv
.venv/bin/pip install -e .

# 2. Create credential file (see above)

# 3. Test it starts
CREDENTIALS_FILE=~/.config/gellyfish/google-keep.env .venv/bin/python -m server
# Should print: Uvicorn running on http://127.0.0.1:8204
# Ctrl+C to stop

# 4. Create launchd plist (replace paths with your actuals)
cat > ~/Library/LaunchAgents/com.gellyfish.mcp-google-keep.plist << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.gellyfish.mcp-google-keep</string>
    <key>ProgramArguments</key>
    <array>
        <string>$(pwd)/.venv/bin/python</string>
        <string>-m</string>
        <string>server</string>
    </array>
    <key>WorkingDirectory</key>
    <string>$(pwd)</string>
    <key>EnvironmentVariables</key>
    <dict>
        <key>CREDENTIALS_FILE</key>
        <string>$HOME/.config/gellyfish/google-keep.env</string>
    </dict>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>StandardOutPath</key>
    <string>$HOME/Library/Logs/mcp-google-keep.log</string>
    <key>StandardErrorPath</key>
    <string>$HOME/Library/Logs/mcp-google-keep.log</string>
</dict>
</plist>
EOF

# IMPORTANT: The heredoc above expands $(pwd) and $HOME automatically.
# Verify the plist has absolute paths:
cat ~/Library/LaunchAgents/com.gellyfish.mcp-google-keep.plist

# 5. Load the service
launchctl load ~/Library/LaunchAgents/com.gellyfish.mcp-google-keep.plist

# 6. Verify
curl -s http://localhost:8204/sse
# Should print: event: endpoint + session URL
```

## Managing the Service

```bash
# Logs
tail -f ~/Library/Logs/mcp-google-keep.log

# Stop
launchctl unload ~/Library/LaunchAgents/com.gellyfish.mcp-google-keep.plist

# Restart
launchctl unload ~/Library/LaunchAgents/com.gellyfish.mcp-google-keep.plist
launchctl load ~/Library/LaunchAgents/com.gellyfish.mcp-google-keep.plist
```

## Connecting MCP Clients

**Via mcp-remote (Claude Code, Claude Desktop):**
```json
{
  "mcpServers": {
    "google-keep": {
      "command": "npx",
      "args": ["-y", "mcp-remote", "http://localhost:8204/sse", "--allow-http"]
    }
  }
}
```

**Direct SSE:**
- SSE endpoint: `GET http://localhost:8204/sse`
- Message endpoint: `POST http://localhost:8204/messages/?session_id=<id>`

## Configuration

| Variable | Default | Description |
|----------|---------|-------------|
| `HOST` | `127.0.0.1` | Bind address |
| `PORT` | `8204` | Listen port |
| `MCP_TRANSPORT` | `sse` | Transport: `sse` or `stdio` |
| `CREDENTIALS_FILE` | `~/.config/gellyfish/google-keep.env` | Path to credentials |
| `GOOGLE_EMAIL` | — | Google account email |
| `MASTER_TOKEN` | — | Google master token |
| `UNSAFE_MODE` | `false` | Allow modifying all notes |

## Features

### Query and read
* `find` — search notes with filters (labels, colors, pinned, archived, trashed)
* `get_note` — get a note by ID

### Create and update
* `create_note` — create a note (auto-labeled `keep-mcp`)
* `create_list` — create a checklist
* `update_note` — update title/text
* `add_list_item` / `update_list_item` / `delete_list_item` — manage checklist items

### Note state
* `set_note_color` — DEFAULT, RED, ORANGE, YELLOW, GREEN, TEAL, BLUE, CERULEAN, PURPLE, PINK, BROWN, GRAY
* `pin_note` / `archive_note` / `trash_note` / `restore_note` / `delete_note`

### Labels, collaborators, media
* `list_labels` / `create_label` / `delete_label`
* `add_label_to_note` / `remove_label_from_note`
* `list_note_collaborators` / `add_note_collaborator` / `remove_note_collaborator`
* `list_note_media`

## Safe Mode

By default, modification operations only work on notes created by this MCP (labeled `keep-mcp`). Set `UNSAFE_MODE=true` to modify any note.

## Security

- **Credentials live outside the repo** at `~/.config/gellyfish/google-keep.env` (mode 600)
- Binds to `127.0.0.1` — localhost only
- Clients connect via HTTP and never see credentials
- The master token has **full Google account access** — treat it like a password
- Uses unofficial Google Keep API — Google could break this at any time

## Docker

```bash
docker compose up -d
```

Mount credentials as a read-only volume:
```yaml
services:
  mcp-google-keep:
    volumes:
      - ~/.config/gellyfish/google-keep.env:/run/secrets/credentials.env:ro
    environment:
      - CREDENTIALS_FILE=/run/secrets/credentials.env
```

## Troubleshooting

* **BadAuthentication on token exchange:** The `oauth_token` cookie expires within seconds. Grab it and run the exchange immediately.
* **DeviceManagementRequiredOrSyncDisabled:** Check https://admin.google.com/ac/devices/settings/general → "Turn off mobile management (Unmanaged)".
* **Service won't start:** Check `tail -20 ~/Library/Logs/mcp-google-keep.log`
* **Credential file not found:** The log prints which path it tried. Set `CREDENTIALS_FILE` env var to override.

## License

MIT — Original work by [Jannik Feuerhahn](https://github.com/feuerdev/keep-mcp)
