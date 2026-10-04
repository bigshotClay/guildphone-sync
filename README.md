# guildphone-sync

The client-side half of [Guild Phone](https://guildphone.com), in public: the
in-game **addon** (`addon/`) and the **companion app** that uploads for you.
Neither holds a credential, neither talks to anything but guildphone.com, and
both are MIT licensed.

The companion app keeps a World of Warcraft guild's roster up to date on
[Guild Phone](https://guildphone.com), by watching the file the Guild Phone
addon writes when you log out.

**This repository exists so you can read what you are running.** Guild Phone
ships this as an executable for people who do not have Python, and asking
strangers to run an unsigned binary from a website is a lot to ask. So the
source is here, the build that produces the binary runs here in public, and
the checksum is published with each release. You can verify the download, or
skip it and run the script directly — they are the same program.

## What it does

The addon writes your guild's roster into WoW's `SavedVariables` when you
`/reload`, log out or exit. This watches that file and uploads it.

That is the whole program. It is one file, standard library only, no
dependencies.

## What it reads and sends

- **Reads:** `WTF/Account/*/SavedVariables/GuildPhone.lua` inside your WoW
  folder, and a small state file recording what it has already uploaded so it
  does not send the same roster twice.
- **Sends:** that roster — guild name, member names, ranks, classes — to
  `https://guildphone.com`, with a device token you generate in the portal.

It does not read anything else, it does not touch the game while it is
running, and it does not send anything about you that is not already visible
to everybody in your guild.

## What it is not

It does not interact with the game client, automate anything in game, or read
memory. It reads a file WoW itself wrote, after WoW wrote it. Nothing here
does anything a player could not do by opening that file and pasting it into
a web page — which is exactly what Guild Phone's manual path is.

## Running it

```sh
python3 guildphone-sync.py --token YOUR_TOKEN --once     # sync now and exit
python3 guildphone-sync.py --token YOUR_TOKEN            # watch and keep syncing
```

Generate the token in the Guild Phone portal. `--wow` points at your WoW
folder if it is not found automatically.

## Verifying a release

Every release carries the source and a `SHA256SUMS` file, and is built by the
workflow in `.github/workflows/`, from the commit the release is tagged on.
The build log is public. If a binary's checksum does not match the one in the
release, do not run it.

## The addon

`addon/GuildPhone/` is the in-game addon itself — plain Lua, no libraries, no
network access of any kind, because WoW addons cannot have one. It reads your
guild roster from the game and writes it into `SavedVariables`. Everything
after that is you, uploading a file, or the companion app above doing it for
you.

```
/gp claim CODE   claim this character with a code from guildphone.com
/gp status       is an export due, and why
/gp remind 14    change the reminder interval (default 7 days)
/gp remind off   stop reminding
```

It is for **WoW: Forever** and refuses to run on any other client.

Install it from [CurseForge](https://www.curseforge.com/wow/addons/guild-phone)
and it updates itself. Releases here are built and uploaded by
`.github/workflows/release.yml` on a `v*` tag, so the zip on CurseForge is
built from a commit you can read.

Guild Phone is a real PBX for guilds. It is **in-game only** — it does not
connect to real telephone networks and has **no emergency service**.

### Releasing

Bump `## Version` in `addon/GuildPhone/GuildPhone.toc`, add the entry to
`CHANGELOG.md`, then tag:

```sh
git tag v2.2.4 && git push --tags
```

`release.yml` packages with
[BigWigsMods/packager](https://github.com/BigWigsMods/packager) and uploads
to CurseForge project 1720217. The TOC version and the tag are separate
things and both matter: CurseForge rejects a duplicate `## Version`, and the
tag is what the file is named after.

On **4 November 2026** WoW: Forever launches and the interface number moves
off 16001. Nothing may be released after that date until `## Interface:` has
been checked against the launch client.

### Running the addon tests

`addon/tests/` runs the addon under real Lua 5.1 with the WoW API stubbed,
which is the same dialect the game uses.

```sh
sudo apt-get install -y lua5.1
for t in serialize_test remind_test name_test; do lua5.1 addon/tests/$t.lua; done
```

## Licence

MIT. See [LICENSE](LICENSE).
