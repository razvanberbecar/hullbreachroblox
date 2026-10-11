#!/usr/bin/env python3
"""
Deep Descent — post an announcement embed to #announcements.

Reuses the same bot + token as discord_setup.py. Edit TITLE / BODY / FOOTER and
run:  python post_announcement.py

Pings the opt-in "Announcements" notification role (never @everyone). Idempotent:
skips if the same-titled announcement is already among the latest posts.
"""
import os
import sys
import discord

ANNOUNCE_CHANNEL = "announcements"
PING_ROLE = "Announcements"          # opt-in notification role (mentionable)
ACCENT = discord.Colour(0x1B2A4A)    # deep navy, matches the rest of the bot's embeds

TITLE = "🤿 2-Player Co-op is Live"
BODY = (
    "You no longer have to descend alone.\n\n"
    "Deep Descent now has **2-player co-op** — team up with a friend and try to "
    "survive the flooding submarine together.\n\n"
    "**Two ways to team up** (main menu → **Play With a Friend**):\n"
    "📨  **Invite a Friend** — open a private dive and send them an invite\n"
    "🎲  **Quick Match** — get paired with another diver\n\n"
    "**Shared fate.** If the creature takes one of you, it takes you both — and if "
    "you reach an escape, you both make it out.\n\n"
    "Solo is still there whenever you want to face the dark alone.\n\n"
    "Grab a friend, put on your headphones, and go deep. 🌊"
)
FOOTER = "Sound is 50% of the horror. Bring headphones."


def load_token():
    tok = os.getenv("DISCORD_BOT_TOKEN")
    if tok:
        return tok.strip()
    path = os.path.join(os.path.dirname(os.path.abspath(__file__)), "bot_token.txt")
    if os.path.exists(path):
        with open(path, encoding="utf-8") as f:
            return f.read().strip()
    return None


intents = discord.Intents.default()
client = discord.Client(intents=intents)


@client.event
async def on_ready():
    try:
        print(f"Logged in as {client.user}")
        guild = None
        gid = os.getenv("GUILD_ID")
        if gid:
            guild = client.get_guild(int(gid))
        elif client.guilds:
            guild = client.guilds[0]
        if guild is None:
            print("ERROR: the bot is not in any server.")
            return

        ch = discord.utils.get(guild.text_channels, name=ANNOUNCE_CHANNEL)
        if ch is None:
            print(f"ERROR: #{ANNOUNCE_CHANNEL} not found in '{guild.name}'.")
            return

        # Avoid a duplicate if this exact announcement was already posted.
        async for m in ch.history(limit=15):
            if m.author.id == guild.me.id and m.embeds and m.embeds[0].title == TITLE:
                print("This announcement is already posted — skipping to avoid a duplicate.")
                return

        role = discord.utils.get(guild.roles, name=PING_ROLE)
        content = role.mention if (role and role.mentionable) else None
        embed = discord.Embed(title=TITLE, description=BODY, colour=ACCENT)
        embed.set_footer(text=FOOTER)
        allowed = discord.AllowedMentions(
            everyone=False, users=False, roles=[role] if role else False)

        await ch.send(content=content, embed=embed, allowed_mentions=allowed)
        print(f"Posted to #{ch.name} in '{guild.name}'"
              + (f" and pinged @{role.name}." if content else " (no ping role found)."))
    finally:
        await client.close()


def main():
    token = load_token()
    if not token:
        print("No token found. Set DISCORD_BOT_TOKEN or create bot_token.txt.")
        sys.exit(1)
    client.run(token)


if __name__ == "__main__":
    main()
