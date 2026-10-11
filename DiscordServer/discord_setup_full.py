#!/usr/bin/env python3
"""
Deep Descent — Discord server builder.

Creates roles, categories, channels, permission overwrites, and posts the
welcome / rules / role-picker / verify messages for the Deep Descent community
server. Self-assign roles and the verify gate use buttons (no privileged
intents required).

USAGE
    python discord_setup.py setup   # build everything (safe to re-run)
    python discord_setup.py run     # keep the bot online so the buttons work

The script is idempotent: re-running "setup" updates existing roles/channels
instead of duplicating them.

TOKEN
    Set the DISCORD_BOT_TOKEN environment variable, OR drop the token into a
    file named "bot_token.txt" next to this script (already git-ignored).
    Never paste the token anywhere public.
"""

import os
import sys
import discord

# ============================ CONFIG ============================
# Palette from the Deep Descent GDD: deep navy / rusted orange / emergency red.

# name, colour, hoist (show separately in member list), mentionable, permissions
ROLES = [
    {"name": "Captain",         "colour": 0xB01E1E, "hoist": True,  "mentionable": False, "perms": {"administrator": True}},
    {"name": "First Mate",      "colour": 0xC85A17, "hoist": True,  "mentionable": False, "perms": {"administrator": True}},
    {"name": "Moderator",       "colour": 0x2E86C1, "hoist": True,  "mentionable": False, "perms": {
        "kick_members": True, "ban_members": True, "moderate_members": True,
        "manage_messages": True, "manage_nicknames": True, "manage_threads": True,
        "mute_members": True, "deafen_members": True, "move_members": True,
        "view_audit_log": True, "read_message_history": True}},
    {"name": "Trial Mod",       "colour": 0x5DADE2, "hoist": True,  "mentionable": False, "perms": {
        "manage_messages": True, "moderate_members": True, "read_message_history": True}},
    {"name": "Engineer",        "colour": 0xE59866, "hoist": True,  "mentionable": False, "perms": {
        "manage_messages": True, "manage_events": True, "mention_everyone": True}},
    {"name": "Content Creator", "colour": 0x9B59B6, "hoist": True,  "mentionable": False, "perms": {}},
    {"name": "Supporter",       "colour": 0xF1C40F, "hoist": True,  "mentionable": False, "perms": {}},
    {"name": "Tester",          "colour": 0x1ABC9C, "hoist": True,  "mentionable": True,  "perms": {}},
    {"name": "Bots",            "colour": 0x7F8C8D, "hoist": True,  "mentionable": False, "perms": {}},
    {"name": "Verified Member", "colour": 0x88A0A8, "hoist": False, "mentionable": False, "perms": {}},
    # Achievement / lore badges (grant these in-game or by hand)
    {"name": "Escaped",         "colour": 0x2ECC71, "hoist": False, "mentionable": False, "perms": {}},
    {"name": "Taken",           "colour": 0x7B241C, "hoist": False, "mentionable": False, "perms": {}},
    {"name": "Lorekeeper",      "colour": 0x8E44AD, "hoist": False, "mentionable": False, "perms": {}},
    # Self-assign notification pings
    {"name": "Announcements",   "colour": 0x000000, "hoist": False, "mentionable": True,  "perms": {}},
    {"name": "Devlog Ping",     "colour": 0x000000, "hoist": False, "mentionable": True,  "perms": {}},
    {"name": "Playtest Ping",   "colour": 0x000000, "hoist": False, "mentionable": True,  "perms": {}},
    {"name": "Events",          "colour": 0x000000, "hoist": False, "mentionable": True,  "perms": {}},
    # Self-assign cosmetic colours
    {"name": "Navy",            "colour": 0x1B2A4A, "hoist": False, "mentionable": False, "perms": {}},
    {"name": "Rust Orange",     "colour": 0xC85A17, "hoist": False, "mentionable": False, "perms": {}},
    {"name": "Emergency Red",   "colour": 0xB01E1E, "hoist": False, "mentionable": False, "perms": {}},
]

ROLE_ORDER = [r["name"] for r in ROLES]              # top -> bottom in the list
STAFF_ROLES = ["Captain", "First Mate", "Moderator", "Engineer"]  # may post in read-only channels

# access: "public"  -> everyone can view
#         [names]    -> only those roles (+ staff + Bots) can view
CATEGORIES = [
    {"name": "INFORMATION", "access": "public", "channels": [
        {"name": "welcome",       "readonly": True},
        {"name": "rules",         "readonly": True},
        {"name": "announcements", "readonly": True},
        {"name": "get-roles",     "readonly": True},
        {"name": "verify",        "readonly": True},
    ]},
    {"name": "COMMUNITY", "access": ["Verified Member"], "channels": [
        {"name": "general"},
        {"name": "media"},
        {"name": "off-topic"},
        {"name": "suggestions"},
        {"name": "General VC", "type": "voice"},
        {"name": "Lounge",     "type": "voice"},
    ]},
    {"name": "THE SUBMARINE", "access": ["Verified Member"], "channels": [
        {"name": "game-discussion"},
        {"name": "lore-and-theories"},
        {"name": "spoilers"},
        {"name": "bug-reports"},
        {"name": "devlog", "readonly": True},
    ]},
    {"name": "SUPPORTERS", "access": ["Supporter"], "channels": [
        {"name": "supporter-chat"},
        {"name": "Supporter VC", "type": "voice"},
    ]},
    {"name": "TESTING", "access": ["Tester"], "channels": [
        {"name": "playtest-news", "readonly": True},
        {"name": "tester-chat"},
        {"name": "tester-feedback"},
        {"name": "tester-bugs"},
    ]},
    {"name": "STAFF", "access": ["Moderator", "Engineer"], "channels": [
        {"name": "staff-chat"},
        {"name": "mod-log"},
        {"name": "dev-planning"},
        {"name": "run-ratings"},  # Developer Commentary webhook target (in-game run submissions land here)
    ]},
]

NOTIFICATION_ROLES = [
    ("Announcements", "📢"),
    ("Devlog Ping",   "🛠️"),
    ("Playtest Ping", "🤿"),
    ("Events",        "🎉"),
]
COLOUR_ROLES = [
    ("Navy",          "🟦"),
    ("Rust Orange",   "🟧"),
    ("Emergency Red", "🟥"),
]

ACCENT = discord.Colour(0x1B2A4A)  # deep navy for embeds

# ============================ HELPERS ============================

def role_by_name(guild, name):
    return discord.utils.get(guild.roles, name=name)


def overwrites_for(guild, access, readonly=False):
    """Build permission overwrites for a category or channel."""
    everyone = guild.default_role
    ow = {}
    if access == "public":
        if readonly:
            ow[everyone] = discord.PermissionOverwrite(
                view_channel=True, send_messages=False, add_reactions=False,
                create_public_threads=False, create_private_threads=False)
            for rn in STAFF_ROLES:
                r = role_by_name(guild, rn)
                if r:
                    ow[r] = discord.PermissionOverwrite(send_messages=True)
        # public + not readonly -> inherit defaults (empty)
    else:
        ow[everyone] = discord.PermissionOverwrite(view_channel=False)
        for rn in list(access) + STAFF_ROLES + ["Bots"]:
            r = role_by_name(guild, rn)
            if not r:
                continue
            can_send = (rn in STAFF_ROLES) or (not readonly)
            ow[r] = discord.PermissionOverwrite(
                view_channel=True, send_messages=can_send, read_message_history=True)
    return ow


async def ensure_role(guild, cfg):
    perms = discord.Permissions(**cfg["perms"])
    colour = discord.Colour(cfg["colour"])
    existing = role_by_name(guild, cfg["name"])
    if existing:
        await existing.edit(colour=colour, hoist=cfg["hoist"],
                            mentionable=cfg["mentionable"], permissions=perms,
                            reason="Deep Descent setup")
        return existing
    return await guild.create_role(name=cfg["name"], colour=colour,
                                   hoist=cfg["hoist"], mentionable=cfg["mentionable"],
                                   permissions=perms, reason="Deep Descent setup")


async def ensure_category(guild, name, overwrites):
    existing = discord.utils.get(guild.categories, name=name)
    if existing:
        await existing.edit(overwrites=overwrites)
        return existing
    return await guild.create_category(name, overwrites=overwrites, reason="Deep Descent setup")


async def ensure_text(guild, name, category, overwrites):
    existing = discord.utils.get(guild.text_channels, name=name)
    if existing:
        await existing.edit(category=category, overwrites=overwrites)
        return existing
    return await guild.create_text_channel(name, category=category,
                                           overwrites=overwrites, reason="Deep Descent setup")


async def ensure_voice(guild, name, category, overwrites):
    existing = discord.utils.get(guild.voice_channels, name=name)
    if existing:
        await existing.edit(category=category, overwrites=overwrites)
        return existing
    return await guild.create_voice_channel(name, category=category,
                                            overwrites=overwrites, reason="Deep Descent setup")


async def already_posted(channel):
    """True if this bot has already posted in the channel (avoid duplicates)."""
    async for m in channel.history(limit=10):
        if m.author.id == channel.guild.me.id:
            return True
    return False

# ============================ BUTTONS / VIEWS ============================

class SelfRoleButton(discord.ui.Button):
    def __init__(self, role_name, emoji):
        super().__init__(label=role_name, emoji=emoji,
                         style=discord.ButtonStyle.secondary,
                         custom_id=f"selfrole::{role_name}")
        self.role_name = role_name

    async def callback(self, interaction: discord.Interaction):
        role = role_by_name(interaction.guild, self.role_name)
        if role is None:
            return await interaction.response.send_message(
                "That role no longer exists.", ephemeral=True)
        member = interaction.user
        if role in member.roles:
            await member.remove_roles(role, reason="Self-role toggle")
            await interaction.response.send_message(f"❌ Removed **{role.name}**", ephemeral=True)
        else:
            await member.add_roles(role, reason="Self-role toggle")
            await interaction.response.send_message(f"✅ Added **{role.name}**", ephemeral=True)


def make_selfrole_view(pairs):
    view = discord.ui.View(timeout=None)
    for name, emoji in pairs:
        view.add_item(SelfRoleButton(name, emoji))
    return view


def register_persistent_views(client):
    """Register views so the buttons keep working across restarts."""
    client.add_view(make_selfrole_view(NOTIFICATION_ROLES))
    client.add_view(make_selfrole_view(COLOUR_ROLES))

# ============================ CONTENT ============================

async def post_welcome(guild):
    ch = discord.utils.get(guild.text_channels, name="welcome")
    if not ch or await already_posted(ch):
        return
    embed = discord.Embed(
        title="🌊 Welcome to Deep Descent",
        description=(
            "You wake as the sole survivor of a crashed submarine on the ocean floor. "
            "The water is rising, the power is out, and something is listening.\n\n"
            "This is the official community for **Deep Descent**, a first-person "
            "atmospheric submarine horror game for Roblox.\n\n"
            "**Start here:**\n"
            "1. Read the <#rules-placeholder> in ⁠**#rules**.\n"
            "2. Click **Enter the Submarine** in ⁠**#verify** to unlock the server.\n"
            "3. Grab notification + colour roles in ⁠**#get-roles**.\n"
            "4. Say hello in ⁠**#general**."),
        colour=ACCENT)
    embed.set_footer(text="Sound is 50% of the horror. Bring headphones.")
    await ch.send(embed=embed)


async def post_rules(guild):
    ch = discord.utils.get(guild.text_channels, name="rules")
    if not ch or await already_posted(ch):
        return
    rules = [
        "**1. Be respectful.** No harassment, hate speech, slurs, or bigotry.",
        "**2. Keep it 13+.** No NSFW, gore-for-shock, or disturbing content beyond the game's own horror tone.",
        "**3. No spam or self-promo** outside the channels made for it.",
        "**4. Tag spoilers.** Endings, secrets, and story go in ⁠**#spoilers**. Don't ruin the fear for others.",
        "**5. Use the right channels.** Bugs → ⁠**#bug-reports**, ideas → ⁠**#suggestions**.",
        "**6. No leaks or datamining dumps.** Respect the devs' work-in-progress.",
        "**7. Staff have final say.** Follow reasonable requests from the crew.",
        "**8. Discord ToS & Roblox Community Standards apply** at all times.",
    ]
    embed = discord.Embed(
        title="📜 Ship's Standing Orders (Rules)",
        description="\n\n".join(rules),
        colour=discord.Colour(0xB01E1E))
    embed.set_footer(text="Breaking these can get you warned, muted, or removed. Don't be the reason we add rule 9.")
    await ch.send(embed=embed)


async def post_role_picker(guild):
    ch = discord.utils.get(guild.text_channels, name="get-roles")
    if not ch or await already_posted(ch):
        return
    notif = discord.Embed(
        title="🔔 Notification Roles",
        description=("Choose what pings you want. Click to toggle on/off.\n\n"
                     "📢 **Announcements** — big news\n"
                     "🛠️ **Devlog Ping** — behind-the-scenes progress\n"
                     "🤿 **Playtest Ping** — when a test build goes live\n"
                     "🎉 **Events** — community events & streams"),
        colour=ACCENT)
    await ch.send(embed=notif, view=make_selfrole_view(NOTIFICATION_ROLES))

    colours = discord.Embed(
        title="🎨 Colour Roles",
        description=("Pick your name colour from the Deep Descent palette.\n\n"
                     "🟦 **Navy**  🟧 **Rust Orange**  🟥 **Emergency Red**"),
        colour=ACCENT)
    await ch.send(embed=colours, view=make_selfrole_view(COLOUR_ROLES))


async def post_verify(guild):
    ch = discord.utils.get(guild.text_channels, name="verify")
    if not ch or await already_posted(ch):
        return
    embed = discord.Embed(
        title="🔒 Airlock — Verify with Roblox",
        description=("The rest of the server is sealed until you link your Roblox account.\n\n"
                     "**How to get aboard:**\n"
                     "1. Type **/verify** in this channel.\n"
                     "2. Follow Bloxlink's link and sign in with Roblox.\n"
                     "3. Come back — you'll get the **Verified Member** role automatically "
                     "and the ship opens up.\n\n"
                     "This keeps out bots and drifters, and ties you to your in-game identity."),
        colour=ACCENT)
    embed.set_footer(text="Verification is handled by Bloxlink.")
    await ch.send(embed=embed)

# ============================ SETUP RUN ============================

async def run_setup(guild):
    print(f"Building '{guild.name}' ...")

    created = {}
    for cfg in ROLES:
        created[cfg["name"]] = await ensure_role(guild, cfg)
        print("  role:", cfg["name"])

    # Best-effort ordering (the bot cannot move roles above its own role).
    try:
        total = len(ROLE_ORDER)
        positions = {created[n]: total - i for i, n in enumerate(ROLE_ORDER) if n in created}
        await guild.edit_role_positions(positions=positions)
        print("  role order applied")
    except (discord.Forbidden, discord.HTTPException) as e:
        print("  (couldn't auto-order roles — drag them manually if needed):", e)

    for cat in CATEGORIES:
        category = await ensure_category(guild, cat["name"],
                                         overwrites_for(guild, cat["access"], readonly=False))
        print("category:", cat["name"])
        for ch in cat["channels"]:
            ow = overwrites_for(guild, cat["access"], readonly=ch.get("readonly", False))
            if ch.get("type") == "voice":
                await ensure_voice(guild, ch["name"], category, ow)
            else:
                await ensure_text(guild, ch["name"], category, ow)
            print("   #", ch["name"])

    await post_welcome(guild)
    await post_rules(guild)
    await post_role_picker(guild)
    await post_verify(guild)
    print("Done. ⚓")

# ============================ BOOTSTRAP ============================

def load_token():
    tok = os.getenv("DISCORD_BOT_TOKEN")
    if tok:
        return tok.strip()
    path = os.path.join(os.path.dirname(os.path.abspath(__file__)), "bot_token.txt")
    if os.path.exists(path):
        with open(path, encoding="utf-8") as f:
            return f.read().strip()
    return None


def pick_guild(client):
    gid = os.getenv("GUILD_ID")
    if gid:
        return client.get_guild(int(gid))
    if len(client.guilds) == 1:
        return client.guilds[0]
    if len(client.guilds) > 1:
        print("Bot is in multiple servers — set GUILD_ID to pick one:")
        for g in client.guilds:
            print(f"   {g.name}: {g.id}")
    return client.guilds[0] if client.guilds else None


MODE = sys.argv[1] if len(sys.argv) > 1 else "setup"
_done = False

intents = discord.Intents.default()  # no privileged intents needed
client = discord.Client(intents=intents)


@client.event
async def on_ready():
    global _done
    if _done:
        return
    _done = True
    print(f"Logged in as {client.user}")
    register_persistent_views(client)

    guild = pick_guild(client)
    if guild is None:
        print("No server found. Invite the bot first (see README), or set GUILD_ID.")
        await client.close()
        return

    if MODE == "setup":
        try:
            await run_setup(guild)
        except discord.Forbidden as e:
            print("Permission error. Move the bot's role NEAR THE TOP of the role list "
                  "and make sure it was invited with Administrator.\n", e)
        await client.close()
    else:
        print(f"Listening for button clicks on '{guild.name}'. Ctrl+C to stop.")


def main():
    token = load_token()
    if not token:
        print("No token found. Set DISCORD_BOT_TOKEN or create bot_token.txt "
              "next to this script.")
        sys.exit(1)
    if MODE not in ("setup", "run"):
        print("Usage: python discord_setup.py [setup|run]")
        sys.exit(1)
    client.run(token)


if __name__ == "__main__":
    main()
