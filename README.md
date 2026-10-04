# guildphone-sync

The client-side half of [Guild Phone](https://guildphone.com), in public: the
in-game **addon** (`addon/`) and the **companion app** that uploads for you.
Neither holds a credential, neither talks to anything but guildphone.com, and
both are MIT licensed.

The companion app keeps a World of Warcraft guild's roster up to date on
[Guild Phone](https://guildphone.com), by watching the file the Guild Phone
addon writes when you log out.

**This repository exists so you can read what you are running.** The
companion app is `guildphone-sync.py`, in the root of this repository, and
that file is the whole program — there is nothing compiled, and there is no
`.exe`.

That is on purpose. An unsigned download from a publisher nobody has heard
of puts a *“Windows protected your PC”* box in front of you, and clicking
past that warning is exactly the habit a scam needs you to have. So Windows
users install **Python 3 from the Microsoft Store**, which Microsoft signs
and which installs without a warning, and then run the same readable script
macOS and Linux run. The artifact is the source. A release publishes that
file and a `SHA256SUMS` covering it, from a public workflow in this
repository, on the commit the release is tagged on.

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

**Windows first:** install **Python 3** from the Microsoft Store — search
the Store for it, or type `python` in Terminal and Windows will offer it to
you. macOS and most Linux already have Python 3. Then:

```sh
python3 guildphone-sync.py --token YOUR_TOKEN --once     # sync now and exit
python3 guildphone-sync.py --token YOUR_TOKEN            # watch and keep syncing
python3 guildphone-sync.py --install --token YOUR_TOKEN  # run it at every logon
python3 guildphone-sync.py --uninstall                   # stop doing that
```

On Windows that is `python`, not `python3`. Generate the token in the Guild
Phone portal. `--wow` points at your WoW folder if it is not found
automatically.

`--install` prints the file it is about to write and the command it is about
to run before it does either, and it is always for your user only — it never
asks for administrator, sudo or a password. It registers a Task Scheduler
entry on Windows, a LaunchAgent on macOS, and a user systemd service on
Linux. Your token goes in `~/.guildphone-token`, not into the service file,
because a token in a unit file is readable by anyone who can list your
processes.

## Verifying a download

Every companion release carries exactly two files: `guildphone-sync.py` and
a `SHA256SUMS` listing its sha256. Both are produced by
[`.github/workflows/release-companion.yml`](.github/workflows/release-companion.yml)
from the commit the release is tagged on, and that run's log is public.

Put the two files in the same folder and run one command:

```sh
sha256sum -c SHA256SUMS          # macOS: shasum -a 256 -c SHA256SUMS
```

It must print `guildphone-sync.py: OK`. If it does not, do not run the
script. You can also skip the release entirely and read this repository
directly — the file here is the file in the release.

There is no binary to verify, because there is no binary. Anybody telling
you to download a Guild Phone `.exe` is not us.

## Releasing the companion

The companion and the addon do not version together, and `v*` already
belongs to the addon — `release.yml` packages it for CurseForge and cuts the
GitHub release for that tag itself. So the companion uses its own prefix:

```sh
git tag sync-v1.3.0 && git push --tags
```

That fires
[`.github/workflows/release-companion.yml`](.github/workflows/release-companion.yml),
which checks that the script parses, answers `--help` and imports nothing
outside the standard library, then publishes `guildphone-sync.py` and
`SHA256SUMS` as a GitHub release. It needs **no secrets at all** — it writes
a release in this repository and nothing else — and it has no `pull_request`
trigger, for the reason written at the top of the file.

There is no packaging step and no PyInstaller. Do not add one.

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

### Releasing the addon

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
