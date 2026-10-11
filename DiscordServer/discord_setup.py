#!/usr/bin/env python3
"""
Deep Descent — Discord announcement / welcome poster.

Minimal utility: connect as the bot, post one message, and exit.
It does NOTHING else — no roles, channels, rules, verify, or role pickers.
(Verification is handled by Bloxlink; self-assign roles by Carl-bot/Onboarding.)

The previous full server-builder is kept as `discord_setup_full.py`.

USAGE
    python discord_setup.py            # post the update to #announcements (default)
    python discord_setup.py announce   # same as above
    python discord_setup.py welcome    # (re)post the #welcome message instead

Both are idempotent — re-running won't double-post the same message.
Edit ANNOUNCEMENT_TITLE / ANNOUNCEMENT_BODY below to change what gets announced.

TOKEN
    Set DISCORD_BOT_TOKEN, or put the token in bot_token.txt next to this script.
    (Optional) set GUILD_ID if the bot is in more than one server.
"""

import os
import sys
import discord

ACCENT = discord.Colour(0x1B2A4A)         # deep navy (welcome)
UPDATE_ACCENT = discord.Colour(0xC1502E)  # rusted orange (announcements)

# --- Announcement content -------------------------------------------------
# Player-facing on purpose: no ending/mechanic spoilers. Edit freely.
ANNOUNCEMENT_TITLE = "🔧  Dev Update — Visual Overhaul"
ANNOUNCEMENT_BODY = (
    "New progress from the ocean floor. Here's what's changed aboard the wreck:\n\n"
    "**🎨 The whole submarine has been re-skinned** — detailed corroded metal, rust "
    "and peeling paint across every corridor, wall and ceiling.\n\n"
    "**💡 Rooms are getting hand-detailed** — the captain's quarters now has its desk, "
    "lamp and the small personal effects the crew left behind.\n\n"
    "**🐛 Glitch pass** — fixed flickering at the bulkhead doors, shimmering floors and "
    "texture pop-in while you move. Rendering is smoother across the whole boat.\n\n"
    "🎧 *Play with headphones. Stay quiet. Stay hidden.*"
)


def channel_ref(guild, name):
    """A clickable #channel mention if it exists, else plain '#name'."""
    ch = discord.utils.get(guild.text_channels, name=name)
    return ch.mention if ch else f"#{name}"


async def post_welcome(guild):
    ch = discord.utils.get(guild.text_channels, name="welcome")
    if ch is None:
        print("No #welcome channel found — nothing posted.")
        return

    # Don't double-post: if the bot already has a message here, skip.
    async for m in ch.history(limit=10):
        if m.author.id == guild.me.id:
            print("Welcome message already present — nothing to do. "
                  "(Delete it and re-run to repost.)")
            return

    embed = discord.Embed(
        title="🌊  Welcome to Deep Descent",
        description=(
            "You wake as the sole survivor of a sunken submarine on the ocean floor. "
            "The water is rising, the power is dead, and something in the dark is listening.\n\n"
            "This is the official community for **Deep Descent** — a first-person "
            "atmospheric submarine horror game on Roblox.\n\n"
            "**🔑 Get started**\n"
            f"**1.** Read the {channel_ref(guild, 'rules')}\n"
            f"**2.** Go to {channel_ref(guild, 'verify')} and run `/verify` to link your "
            "Roblox account and unlock the ship\n"
            f"**3.** Grab your ping & color roles in {channel_ref(guild, 'get-roles')}\n"
            f"**4.** Surface in {channel_ref(guild, 'general')} and say hello\n\n"
            "**🎧 One warning:** play with headphones on. Sound is half the horror.\n\n"
            "*Stay quiet. Stay hidden. Not everyone makes it back.*"),
        colour=ACCENT)
    embed.set_footer(text="Deep Descent")
    await ch.send(embed=embed)
    print(f"Posted the welcome message in #{ch.name}.")


async def post_announcement(guild):
    ch = discord.utils.get(guild.text_channels, name="announcements")
    if ch is None:
        print("No #announcements channel found — nothing posted.")
        return

    # Idempotent: skip only if THIS announcement (same title) is already up,
    # so future edited announcements can still post.
    async for m in ch.history(limit=25):
        if (m.author.id == guild.me.id and m.embeds
                and m.embeds[0].title == ANNOUNCEMENT_TITLE):
            print("This announcement is already posted — nothing to do. "
                  "(Delete it and re-run to repost, or change the title/body for a new one.)")
            return

    embed = discord.Embed(title=ANNOUNCEMENT_TITLE, description=ANNOUNCEMENT_BODY,
                          colour=UPDATE_ACCENT)
    embed.set_footer(text="Deep Descent")
    await ch.send(embed=embed)
    print(f"Posted the announcement in #{ch.name}.")


# --------------------------- bootstrap ---------------------------
_done = False
MODE = "announce"  # "announce" (default) or "welcome"; set from argv in main()
intents = discord.Intents.default()  # no privileged intents needed
client = discord.Client(intents=intents)


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


@client.event
async def on_ready():
    global _done
    if _done:
        return
    _done = True
    print(f"Logged in as {client.user}")

    guild = pick_guild(client)
    if guild is None:
        print("No server found. Invite the bot first, or set GUILD_ID.")
        await client.close()
        return

    try:
        if MODE == "welcome":
            await post_welcome(guild)
        else:
            await post_announcement(guild)
    except discord.Forbidden as e:
        print("Permission error — the bot must be able to view and send in the "
              "target channel:", e)
    await client.close()


def main():
    global MODE
    if len(sys.argv) > 1:
        arg = sys.argv[1].lower()
        if arg in ("announce", "welcome"):
            MODE = arg
        else:
            print(f"Unknown argument '{sys.argv[1]}'. Use 'announce' (default) or 'welcome'.")
            sys.exit(1)
    token = load_token()
    if not token:
        print("No token found. Set DISCORD_BOT_TOKEN or create bot_token.txt.")
        sys.exit(1)
    client.run(token)


if __name__ == "__main__":
    main()
