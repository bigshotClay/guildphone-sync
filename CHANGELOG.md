# Guild Phone — addon changelog

Newest first. Each entry names what was actually wrong, because somebody who
tried a version and gave up needs to know the thing that defeated them is
fixed, and that it was not their fault.

## 2.2.3

**It now tells you what to do when you log in.**

If you installed Guild Phone, logged in, and nothing appeared to happen —
that was a bug, not you. The addon only ever spoke to guild officers with a
loaded roster. Everybody else got silence.

Now, eight seconds after you log in, once per character, it tells you how to
get a code and claim. Once per character, then never again. If you have
already claimed something, you will not see it at all.

Officers whose only authority is the officer note are also reminded to
re-export now; they were being skipped.

## 2.2.2

**Fixes half your name going missing.**

If you claimed a character without a guild, Guild Phone recorded only the
first half of its name — "Mouse" instead of "Mouse Nutz" — and that was the
name on your caller ID and the name the raid line read out.

On WoW: Forever, `UnitName("player")` returns two values: the name and the
**surname**. Everywhere else in World of Warcraft the second value is the
realm, so the addon read the first and threw the second away before the
export was even written.

## 2.2.1

**Says the step people were missing, and shows you what is queued.**

2.2.0 let one code claim every character you play. It did not say clearly
enough that the command still has to be run **on each character** — the game
only ever tells the addon about the character you are standing on. The panel
now lists what is queued, so "did it take?" is answerable before you upload
rather than after.

## 2.2.0

**One code claims every character you play.**

Claiming used to be one character at a time: a code, a login and an upload
for each alt. The addon now keeps one export per character instead of
overwriting a single slot. Run `/gp claim CODE` on each character, then
upload once, and every one of them is claimed.

Also fixed: a file can hold more than one export, and the website used to
take whichever came first — which, Lua tables having no order, was luck.

## 2.1.0

**Claiming works in one command now, and the bug that stopped it is fixed.**

If you tried to claim a character on 2.0.0 and the website told you your
export carried no claim code — that was this addon's fault, not yours. The
slash command wrote the export to one place and the options panel wrote it to
another, and the website could only read the panel's copy.

## 2.0.0

**Claiming now needs a code from the website.**

An export from 1.0.0 can no longer claim a character. Claiming used to work
from any export file, which meant a file left in your WTF folder, or one
somebody sent you, kept working indefinitely — and an export is editable
text. The website now issues a code and the addon carries it back inside the
export.
