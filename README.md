# guildphone-sync

Keeps a World of Warcraft guild's roster up to date on
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

## Licence

MIT. See [LICENSE](LICENSE).
