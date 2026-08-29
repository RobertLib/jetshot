# ASO: the reasoning, the competition, and the alternatives

Numbers in brackets are character counts. The limits are 30 for the name, 30 for
the subtitle and 100 for keywords.

## Where we are starting from

Jetshot is already on the store (id `6754814450`, live since 27 January 2026), so
this is not a launch — it is a rewrite of a listing that has been running for
seven months on one English localisation. What is live today:

```
Name      Jetshot – Space Shooter        (23)
Subtitle  Epic boss fights & power-ups   (28)
Language  English only
```

Three things are wrong with it, and all three are fixable in one submission.

**Seven characters of the name are unused, and the subtitle is spent on words
nobody types.** *Epic*, *fights* and *power-ups* are not queries. The subtitle is
the second most heavily weighted field there is and it is currently indexing
almost nothing.

**There is no Czech localisation on the store**, although the app itself has been
fully Czech since 1.0.6. Each localisation carries its own name, subtitle and
keyword field, and indexing is per-storefront and per-locale — so adding `cs`
does not merely translate the page, it opens a second index in the Czech
storefront that did not exist before. It is the single largest piece of free
keyword real estate on the table.

**The description is written as if it were indexed.** It is not: on iOS the
description and the promotional text are conversion fields only, never search
fields. The live text says "arcade space shooter" nine times, which buys exactly
zero ranking and costs the first three lines — the only part most people read.

## What we are up against

Every one of these was pulled off the store before the copy in this directory was
written. Ratings counts are US, August 2026.

| App | Subtitle | Category | Rating | Ratings | Money |
|---|---|---|---|---|---|
| Galaxy Attack: Alien Shooter | Classic Space War Invasion | Casual | 9+ | 652 000 | Free + IAP (crystals $0.99–$19.99, $9.99 battle pass) |
| 1945 Air Force: Airplane Games | — | Action | 12+ | 430 000 | Free + IAP |
| Galaxy Attack: Space Shooter | Alien shooter - Classic game! | Casual | 4+ | 350 000 | Free + IAP |
| Galaxiga: Classic Arcade Game | 80s Alien Space Galaxy Shooter | Casual | 4+ | 26 000 | Free + IAP (to $49.99) |
| Phoenix 2 | The best space shooter | Action | 4+ | 26 000 | Free + IAP (to $49.99, $4.99 VIP) |
| Sky Force Reloaded | — | Action | 9+ | 11 000 | Free + IAP |
| Space Shooter - Sky Champ | — | Casual | 12+ | 3 200 | Free + IAP |
| **Jetshot** | | Action | 4+ | **1** | **Free, nothing to buy** |

Four things follow from that table.

**We cannot win the head terms.** *space shooter*, *galaxy shooter* and *alien
shooter* are held by apps with six-figure rating counts and a user-acquisition
budget. A listing with one rating does not rank on them whatever it puts in its
name, and Apple weights ratings and retention alongside text. Spending the whole
name on those terms is how you end up ranking for nothing at all.

**The long tail is winnable, and it is where the intent is.** *space shooter
offline*, *no wifi space game*, *arcade shooter no ads*, *shmup*, *bullet hell
offline*, *single player space shooter* — these are thin enough to rank on, and
whoever types them is describing this app exactly. Note what the store returns
today for "space shooter offline": the same freemium titles, none of which is
actually offline, plus one app with a single rating. That is a gap.

**"No ads, no purchases" is the whole differentiator, and it is a conversion
lever as much as a keyword.** Every competitor in that table sells crystals, gems
or a battle pass, and the reviews on all of them say the same thing about it —
one Galaxiga review in the sample complains that the later worlds are unreachable
without spending. That is why the promise is in the subtitle (which is read in
the search results, not only on the page), in the first paragraph of the
description, and on the last screenshot.

**The competitors' subtitles are pure keyword stuffing** — "80s Alien Space
Galaxy Shooter" is six nouns and no sentence. There is room to be the listing
that reads like a person wrote it while still indexing well, and that is what the
subtitles below do: keywords in the first half, the promise in the second.

## What is in use

```
en-US   Jetshot: Offline Space Shooter  (30)   Retro arcade shmup, no ads   (26)
en-GB   Jetshot: Offline Space Shooter  (30)   Retro bullet hell, no ads    (25)
cs      Jetshot: Vesmírná střílečka     (27)   Arkáda offline, bez reklam   (26)
```

Between the name and the subtitle, `en-US` indexes *jetshot, offline, space,
shooter, retro, arcade, shmup, no, ads*. Apple combines terms within a locale, so
that alone assembles *offline space shooter*, *space shooter no ads*, *retro
arcade shooter*, *offline arcade*, *arcade shmup*, *retro space shooter* and
*space arcade* without spending a single keyword character on any of them.

Then the keyword field is chosen to combine with what is already there rather
than to stand alone. *wifi* is four characters, and because the subtitle carries
*no* it buys the whole *no wifi* family. *war* buys *space war* and *galaxy war*.
*ship* is not contained in *spaceship* as far as Apple is concerned — they are
separate tokens — and it buys *space ship*, which is how a large share of people
write it. *bullet* + *hell* buys the genre name that the audience most likely to
love a game with no shop actually uses.

`en-GB` deliberately overlaps `en-US` rather than filling in its gaps. It is the
second index in the Czech storefront, but it is the *only* index in the UK,
Ireland, Australia and New Zealand — and those are worth more than Czechia's
second slot, so it gets a full-strength set. The three terms it swaps (*arcade*
and *shmup* into keywords, *bullet hell* up into the subtitle) are the Czech
bonus: a Czech user typing "bullet hell" or "shmup" hits the en-GB index.

The Czech name keeps *střílečka* rather than the English *shooter* because that
is what Czech players type in Czech — and the ones who type "space shooter"
anyway are caught by en-GB in the same storefront. `cs` therefore never has to
carry English terms.

## App name

| Czech | | English | |
|---|---|---|---|
| Jetshot: Vesmírná střílečka | (27) | Jetshot: Offline Space Shooter | (30) |
| Jetshot: Kosmická střílečka | (27) | Jetshot: Arcade Space Shooter | (29) |
| Jetshot: Vesmírná akční arkáda | (30) | Jetshot: Retro Space Shooter | (28) |
| Jetshot: Střílečka offline | (26) | Jetshot: Space Shooter, No Ads | (30) |
| Jetshot – Vesmírná arkáda | (25) | Jetshot – Space Shooter | (23) ← live today |

Recommendation: keep **Jetshot** at the front and keep **offline** in the English
name. *Jetshot* is a brand with no search volume of its own, but it is the app's
identity, it is already live under it, and a name is the one field where the
brand has to sit. *Offline* is the one near-head term this app can genuinely
compete on, because most of the apps ranking for it are lying — they need a
connection for their shop — and because "offline games" is a real browsing
category on iOS, not just a query. `Jetshot: Arcade Space Shooter` (29) is the
fallback if *offline* ever moves into the subtitle instead.

Do not put "Free" or "Zdarma" in the name or subtitle. Guideline 2.3.7 treats
price in the name as grounds for rejection; "no ads" is a feature statement and
is fine, and *free*/*zdarma* live safely in the keyword field.

The home-screen name (`INFOPLIST_KEY_CFBundleDisplayName`) stays
"Jetshot – Space Shooter". Apple only requires that it not differ in *meaning*
from the store name, and it does not.

## Subtitle

| Czech | | English | |
|---|---|---|---|
| Arkáda offline, bez reklam | (26) | Retro arcade shmup, no ads | (26) |
| Padesát úrovní, bez reklam | (26) | Retro bullet hell, no ads | (25) |
| Akční arkáda, bez reklam | (24) | 50 levels, 50 bosses, no ads | (28) |
| Retro arkáda bez reklam | (23) | Arcade shmup, no ads or IAP | (27) |
| Střílečka bez reklam a nákupů | (29) | Bullet hell arcade, offline | (27) |

`50 levels, 50 bosses, no ads` is the strongest of these on conversion and the
weakest on indexing — digits and *levels* buy little. It is the one to try if the
listing turns out to get impressions but no taps.

## Keywords

In use:

```
en-US  galaxy,alien,spaceship,ship,bullet,hell,endless,boss,level,neon,laser,asteroid,wifi,war,free,solo   (97)
en-GB  galaxy,alien,spaceship,ship,arcade,shmup,endless,boss,level,neon,laser,asteroid,wifi,war,free,solo  (98)
cs     vesmír,kosmická,lodě,stíhačka,akční,hra,hry,zdarma,retro,neon,laser,asteroidy,wifi,internetu,boss   (97)
```

Alternative sets, if you end up tuning by performance:

```
# EN, no-freemium angle (leans hardest on the differentiator)
galaxy,alien,spaceship,ship,purchases,premium,paid,wifi,internet,boss,level,free,solo,neon    (90)

# EN, retro / classic-arcade angle (pairs with a "Retro Space Shooter" name)
galaxy,alien,spaceship,ship,classic,80s,pixel,vector,neon,boss,level,wave,dodge,free,solo     (89)

# EN, skill / bullet-hell angle (pairs with the "Retro bullet hell" subtitle)
galaxy,alien,spaceship,ship,dodge,reflex,skill,hardcore,combo,chain,boss,level,wave,free      (88)

# CZ, jednoduchá hra / rodina angle
vesmír,kosmická,lodě,stíhačka,jednoduchá,hra,hry,zdarma,děti,rodina,neon,wifi,internetu       (87)

# CZ, výzva a rekordy angle
vesmír,kosmická,lodě,stíhačka,výzva,těžká,reflexy,skóre,rekordy,boss,úrovně,hra,hry,zdarma    (90)
```

Rules, so that editing does not break it:

- Separate with a comma and **no space after the comma** — a space counts towards
  the limit of 100.
- Do not repeat words from the name or the subtitle; Apple indexes those
  separately and a word paid for twice is still indexed once. **This binds the
  name against the subtitle too.** It is why *offline*, *space*, *shooter*,
  *retro*, *arcade*, *shmup* and *ads* are absent from the English keyword list
  and *vesmírná*, *střílečka*, *arkáda*, *offline* and *reklam* from the Czech
  one.
- Do not put an English plural next to its singular (*boss* and *bosses*); Apple
  pairs them itself. That is why the list says *boss* and *level*, not *bosses*
  and *levels*.
- **Czech bends that rule on purpose.** Apple's Czech stemming cannot be relied on
  to undo declension, so *hra* and *hry* both stand, and *vesmír* stands beside
  *vesmírná* in the name because Apple tokenises those as separate words rather
  than as one containing the other.
- Do not name competing games — grounds for rejection. This rules out the
  otherwise tempting *galaga*, *galaxian* and *space invaders*, all of which are
  trademarks as well.
- Do not reach for a word just because it is free. *puzzle*, *rpg* and *idle* are
  not what this game is, and an off-relevance term buys nothing while costing
  characters — and relevance is itself a ranking input.
- *free* / *zdarma* is only worth the characters if the game really is free. It
  is, and with no purchases either, which is rarer and worth the space.

## The fields that are not the keyword field

**In-App Events** are the largest piece of indexed text still unclaimed. The event
**name (30)** and **short description (50)** are both indexed for search, and up
to ten events can be live at once — 800 characters against the 160 that the name,
subtitle and keyword field come to together. Endless mode is built for it: a
weekly "Endless Weekend" event indexes terms the main listing has no room for.
Nothing here is needed to ship, so it belongs to the version after this one.

**Custom Product Pages** (up to 70 per app) can now surface in organic search
against a keyword cluster, each with its own screenshots and promotional text.
One aimed at "offline / no ads" and one aimed at "bullet hell / challenge" would
be the obvious pair, and they cost no review cycle to swap.

**Screenshots are not indexed but decide the tap.** See [screenshots.md](screenshots.md).

## Shorter description, if you decide on a terser version

Each paragraph is one long line on purpose. App Store Connect keeps newlines
exactly as pasted, so a paragraph wrapped at 80 columns here comes out ragged on
the device while every other paragraph reflows — paste these as they are.

**EN**

```
A real arcade space shooter: fifty hand-built levels, a boss at the end of every one, and an endless run for when they are done.

Your guns stack to eight barrels and carry between levels — and every life you lose costs you one. Thirteen power-ups, twenty-seven enemies, twelve kinds of moving obstacle, and a chain multiplier that pays up to x8 for kills that land close together and drops the moment you take a hit.

Drag anywhere to fly. The guns fire themselves.

No ads. No in-app purchases. No account. No energy timers. Plays offline.
```

**CZ**

```
Opravdová vesmírná arkáda: padesát ručně stavěných úrovní, na konci každé z nich boss, a nekonečná hra pro chvíli, kdy je všechny dohraješ.

Zbraně se skládají až na osm hlavní a přecházejí mezi úrovněmi — a každý ztracený život tě stojí jednu. Třináct vylepšení, dvacet sedm nepřátel, dvanáct druhů pohyblivých překážek a násobič série, který platí až x8 za zásahy rychle za sebou a zmizí, jakmile jednou schytáš.

Táhni prstem kamkoli a loď letí. Zbraně střílejí samy.

Bez reklam. Bez nákupů. Bez účtu. Bez čekání. Hraje se offline.
```
