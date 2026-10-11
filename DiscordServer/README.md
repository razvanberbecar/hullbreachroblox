# Deep Descent — Discord Server Builder

Automates building the community Discord server: roles, categories, channels,
permissions, and the welcome / rules / role-picker / verify messages.
Self-assign roles and the verify gate use **buttons** (no privileged intents).

## What it creates

- **Roles** (top → bottom): Captain, First Mate, Moderator, Trial Mod, Engineer,
  Content Creator, Supporter, Tester, Bots, Verified Member, achievement badges
  (Escaped / Taken / Lorekeeper), notification pings, and colour roles.
- **Categories & channels**: INFORMATION (public, read-only), COMMUNITY and
  THE SUBMARINE (gated behind *Verified Member*), SUPPORTERS (Supporters + staff),
  TESTING (Testers + staff only), and STAFF (staff only).
- **Verify gate**: unverified users only see INFORMATION until they verify their
  Roblox account via **Bloxlink** (`/verify`), which grants *Verified Member*.
  See "Roblox verification" below.
- **Self-assign roles**: notification + colour buttons in `#get-roles`.

Everything is themed to the game's navy / rust / emergency-red palette. Edit the
`ROLES` and `CATEGORIES` lists at the top of `discord_setup.py` to customise.

## One-time setup

### 1. Create the server
In Discord, click **+** → *Create My Own*. Name it (e.g. "Deep Descent").

### 2. Create a bot application
1. Go to https://discord.com/developers/applications → **New Application**.
2. Open **Bot** → **Add Bot** → **Reset Token** → copy the token.
   - Keep "Public Bot" off if you don't want others adding it.
   - You do **not** need any Privileged Gateway Intents for this script.

### 3. Invite the bot with admin
1. **OAuth2 → URL Generator**: scope `bot`, permission **Administrator**.
2. Open the generated URL, pick your server, authorise.
3. In **Server Settings → Roles**, drag the bot's role **near the top** of the
   list (it can only manage roles/channels below itself).

### 4. Install dependencies
```bash
pip install -r requirements.txt
```

### 5. Provide the token
Either set an environment variable, or create `bot_token.txt` next to the script
(it's git-ignored — never commit or paste it publicly):

PowerShell (this session):
```powershell
$env:DISCORD_BOT_TOKEN = "your-token-here"
```

Or:
```
DiscordServer/bot_token.txt   ->  your-token-here
```

## Run it

Build the server (safe to re-run — it updates instead of duplicating):
```bash
python discord_setup.py setup
```

Keep the bot online so the **buttons** (verify + self-roles) respond:
```bash
python discord_setup.py run
```

> The buttons only work while the bot is running in `run` mode. For 24/7 uptime,
> host it on any always-on machine or a small VPS / free bot host.

## Roblox verification (Bloxlink)

Verification is handled by the dedicated **Bloxlink** bot, not our script. Our
script only creates the `Verified Member` role and gates the channels behind it —
Bloxlink is what grants that role after a Roblox login.

1. Invite Bloxlink: https://blox.link → **Invite Bloxlink** (allow *Manage Roles*).
2. In **Server Settings → Roles**, drag **Bloxlink's** role **above**
   `Verified Member` and `Supporter` (a bot can only assign roles below itself).
3. Open the Bloxlink dashboard (https://blox.link/dashboard) or use `/settings`:
   - Set the **Verified role** to `Verified Member`.
   - (Optional) set an **Unverified role**, and a nickname template
     (e.g. use the member's Roblox username).
4. Members run **/verify** in `#verify` and sign in with Roblox.

> If you already ran `setup` once with the old verify button, delete the old
> message in `#verify`, then re-run `python discord_setup.py setup` so it posts
> the new Bloxlink instructions.

## Supporter role

`Supporter` is a gold badge with its own `#supporter-chat` and `Supporter VC`.
Discord can't detect Roblox donations directly, so grant it one of two ways:

- **Manually** — staff assign the role after a donation.
- **Automatically (later)** — once Bloxlink verification is live, add a Bloxlink
  bind: *owns game pass `<your donation pass ID>` → give `Supporter`*. Set it via
  Bloxlink's `/binds` or dashboard. (Check whether the specific bind is free or
  requires Bloxlink Pro.)

## Notes & troubleshooting

- **"Permission error" / roles not created** → the bot's role isn't high enough,
  or it wasn't invited with Administrator. Fix the role position (step 3) and
  re-run.
- **Multiple servers** → set `GUILD_ID` to target one:
  `$env:GUILD_ID = "123456789012345678"`.
- **Achievement roles** (Escaped / Taken / Lorekeeper) are created empty — grant
  them from your game (via a bot/webhook) or by hand.
- Re-running `setup` is idempotent, but it won't delete channels/roles you remove
  from the config — delete those in Discord yourself.
