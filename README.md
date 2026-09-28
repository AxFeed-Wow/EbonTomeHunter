# EbonTomeHunter

Find, buy and farm the **Echo tomes** of Project Ebonhold: Auction House prices and purchases, wishlist, drop places on the map, teleport near the mobs, drops shared between players.

**English** | [Français](#français)

[![Check](https://github.com/AxFeed-Wow/EbonTomeHunter/actions/workflows/check.yml/badge.svg)](https://github.com/AxFeed-Wow/EbonTomeHunter/actions/workflows/check.yml)
[![Latest release](https://img.shields.io/github/v/release/AxFeed-Wow/EbonTomeHunter)](https://github.com/AxFeed-Wow/EbonTomeHunter/releases/latest)
![WoW 3.3.5a](https://img.shields.io/badge/WoW-3.3.5a-1f6feb)
[![License: MIT](https://img.shields.io/badge/license-MIT-green)](LICENSE)

> **EbonTomeHunter is an independent community project.** It is not affiliated with, endorsed by,
> or officially associated with Project Ebonhold or Blizzard Entertainment.

## Features

* **Catalogue of the 148 tomes**: lowest Auction House price, number of listings, trend, drop
  places, mobs, and the tomes your character already learned (green check).
* **Auction House**: two extra tabs (*Tomes*, *Wishlist*).
  * Full scan, wishlist search, listings sorted by unit price.
  * One-click purchase, with a confirmation and a fresh check of the listing right before buying.
* **Wishlist** per character, with its total cost. Share it as a text to copy, or send it directly
  to a player who has the addon.
* **World map**: *Locate* opens the map on the drop place; the tomes of your wishlist are marked on
  it.
* **Teleport** to the unlocked checkpoint (flight master, meeting stone) nearest to the mobs that
  drop the tome most often; for a raid or a dungeon, to the meeting stone of its entrance.
* **Sources window**: every mob that drops the tome, the ones seen dropping it most often first,
  with the number of drops seen, its Wowhead (WotLK) link and a teleport.
  A source that no longer drops the tome (more looted corpses without it than bad luck explains,
  given its drop rate, or reported by 3 players) is greyed and comes last.
* **Network between players** (with the EbonAPI addon): when a user loots a tome, the place is
  shared with the others, even with players who are never online at the same time. A tome listed
  as "Unknown location" ends up with a real place.
* **EbonBuilds atlas**: the drop sources seen by the EbonBuilds users are added, read in game.
* **Alerts** when you, your group or another player find a tome of your wishlist. It also works
  with the *Greedy Scavenger* pet, which loots without any chat message: the server's hint of the
  tome tells which of the mobs you killed dropped it.
* **Step-by-step tutorial** on first opening (the "?" button shows it again).
* English and French interface.

Every feature in detail (in French): [docs/FEATURES.md](docs/FEATURES.md).

## Installation

### Requirements

* The Project Ebonhold client (World of Warcraft 3.3.5a).
* Recommended: **ProjectEbonhold** (shipped with the client: tomes learned, teleport),
  **EbonholdHub** (drop places) and **[EbonAPI](https://github.com/Siphelis/EbonAPI)** (by
  Siphelis, also in Ebonhold Addon Manager: sharing drop places with the other players). Optional:
  **EbonBuilds** (its tome atlas adds drop sources). Without them, the related features simply
  turn off.

### With Ebonhold Addon Manager

[Ebonhold Addon Manager](https://github.com/AxFeed-Wow/EbonholdAddonManager) installs
EbonTomeHunter and keeps it up to date.

### Manually

1. Download `EbonTomeHunter-x.y.z.zip` from the
   [latest release](https://github.com/AxFeed-Wow/EbonTomeHunter/releases/latest).
2. Extract it into `World of Warcraft/Interface/AddOns/`. You must get
   `Interface/AddOns/EbonTomeHunter/EbonTomeHunter.toc`.
3. Restart the game completely, then type `/eth` (or click the minimap button).

Coming from *EbonTomePrices* (the former name): delete its folder, otherwise both load.

## Commands

| Command | Effect |
|---|---|
| `/eth` | open / close the window |
| `/eth tp <tome>` | teleport to the checkpoint nearest to where the tome drops |
| `/eth share` | share / import a wishlist (also an Echo Builder link or build) |
| `/eth send <name>` | send your wishlist to a player |
| `/eth net` | network status (`sync`: announce your drop places to the players online now) |
| `/eth history` | drop history (who found which tome, where, on which mob) |
| `/eth tuto` | show the tutorial again |
| `/eth options` | options (also in Interface > AddOns) |
| `/eth help` | every command |

`/tomehunter` works too.

## Known limitations

* **Sharing needs EbonAPI**, a separate addon (it is not included, its licence forbids it). Without
  it, your finds stay on your computer; the chat says so once.
* **"You can only be in 10 channels at a time."** WoW allows 10 chat channels per character.
  EbonAPI uses one hidden channel for every addon that relies on it. When the 10 are taken (General,
  Trade, LocalDefense, LookingForGroup, world channels…), it cannot join it: you neither receive
  nor share drop places. Everything else works. To free a slot: `/chatlist` lists your channels,
  `/leave <number>` leaves one you do not use, then `/reload`.
* EbonAPI joins its channel as soon as you log in, sometimes before the game gives you back your
  own channels: one of them may then get another number (`/5` instead of `/4`…). This comes from
  EbonAPI, not from EbonTomeHunter.
* Drop places travel from player to player through EbonAPI, also through players who run another
  addon that uses it: a find reaches you once you meet one of them, which can take a few minutes.
* Versions 2.x used their own channel: they do not see the finds of 3.x, and the reverse.
* The drop places received from other players cannot be verified: each one shows who found it and
  how many players confirmed it.

## Privacy

The network shares, through EbonAPI, the place where you got a tome with **your character name**
("found by"), and your counts of corpses looted without a tome and your "Gone?" reports (stale
sources). EbonAPI keeps these data and passes them on to its other users, who keep them too. You can
turn it off in the options (*Network and alerts*). The addon sends nothing else, except your wishlist
when you send it to someone yourself, and, only when the maintainer asks for statistics, how many of
each creature you killed.

## Contributing

Contributions are welcome: see [CONTRIBUTING.md](CONTRIBUTING.md). In short: Python 3.10+,
`pip install lupa`, then `python tools/check.py` must print `ALL CHECKS PASSED` (validator and test
scenario in a fake WoW client, with and without ProjectEbonhold, in English and in French; with
EbonAPI next to the repository, the network tests run with several players).

The technical documentation, in French, is in [docs/](docs/). [CLAUDE.md](CLAUDE.md) is the entry
point.

## Security

If you find a security issue (for example a network message that could trigger an action or break
the interface of other players), please do not open a public issue: see [SECURITY.md](SECURITY.md).

## Disclaimer

EbonTomeHunter is an independent community addon. It is not affiliated with Project Ebonhold,
Blizzard Entertainment, or the authors of the addons it reads or uses (ProjectEbonhold,
EbonholdHub, EbonBuilds, EbonAPI). The drop places shown on the map come from EbonholdHub and
EbonBuilds, read in game at runtime: they are not included in this repository. EbonAPI is a
separate addon by Siphelis, under its own licence, installed by each player: it is not included
either. World of Warcraft is a trademark of Blizzard Entertainment.

## License

Released under the MIT License, © 2026 AxFeed-Wow. See [LICENSE](LICENSE).

---

<a id="français"></a>

# EbonTomeHunter (Français)

Trouver, acheter et farmer les **tomes d'Echo** de Project Ebonhold : prix et achats à l'hôtel des ventes, wishlist, lieux de drop sur la carte, téléportation près des monstres, drops partagés entre joueurs.

[English](#ebontomehunter) | **Français**

> **EbonTomeHunter est un projet communautaire indépendant.** Il n'est ni affilié, ni approuvé, ni
> officiellement associé à Project Ebonhold ou à Blizzard Entertainment.

## Fonctionnalités

* **Catalogue des 148 tomes** : prix le plus bas à l'hôtel des ventes, nombre d'annonces, tendance,
  lieux de drop, monstres, tomes déjà appris par ton personnage (coche verte).
* **Hôtel des ventes** : deux onglets en plus (*Tomes*, *Wishlist*).
  * Scan complet, recherche de la wishlist, annonces triées par prix unitaire.
  * Achat en un clic, avec confirmation et revérification de l'annonce juste avant d'acheter.
* **Wishlist** par personnage, avec son coût total. Elle se partage par un texte à copier, ou
  s'envoie directement à un joueur qui a l'addon.
* **Carte du monde** : « Localiser » ouvre la carte sur le lieu de drop ; les tomes de la wishlist y
  sont marqués.
* **Téléportation** au checkpoint débloqué (maître de vol, pierre de rencontre) le plus proche des
  monstres qui lâchent le plus souvent le tome ; pour un raid ou un donjon, à la pierre de rencontre
  de son entrée.
* **Fenêtre Sources** : chaque monstre qui lâche le tome, ceux vus le lâcher le plus souvent en
  premier, avec le nombre de drops vus, son lien Wowhead (version WotLK) et une téléportation. Une
  source qui ne lâche plus le tome (plus de cadavres lootés sans lui que la malchance ne l'explique,
  vu son taux de drop, ou signalée par 3 joueurs) est grisée et passe en dernier.
* **Réseau entre joueurs** (avec l'addon EbonAPI) : quand un utilisateur loote un tome, le lieu est
  partagé avec les autres, même avec ceux qui ne sont jamais connectés en même temps. Un tome
  « Unknown location » finit ainsi par avoir un vrai lieu.
* **Atlas d'EbonBuilds** : les sources de drop vues par les utilisateurs d'EbonBuilds s'ajoutent, lues
  en jeu.
* **Alertes** quand toi, ton groupe ou un autre joueur trouvez un tome de ta wishlist. Ça marche
  aussi avec le familier *Greedy Scavenger*, qui ramasse sans laisser de message : l'indice du
  serveur sur le tome dit lequel des monstres tués l'a lâché.
* **Tutoriel pas à pas** à la première ouverture (le bouton « ? » le remontre).
* Interface en anglais et en français.

Le détail exact de chaque fonction : [docs/FEATURES.md](docs/FEATURES.md).

## Installation

### Prérequis

* Le client Project Ebonhold (World of Warcraft 3.3.5a).
* Recommandés : **ProjectEbonhold** (livré avec le client : tomes appris, téléportation),
  **EbonholdHub** (lieux de drop) et **[EbonAPI](https://github.com/Siphelis/EbonAPI)** (de Siphelis,
  aussi dans Ebonhold Addon Manager : partage des lieux de drop avec les autres joueurs). Facultatif :
  **EbonBuilds** (son atlas des tomes ajoute des sources). Sans eux, les fonctions concernées se
  désactivent simplement.

### Avec Ebonhold Addon Manager

[Ebonhold Addon Manager](https://github.com/AxFeed-Wow/EbonholdAddonManager) installe EbonTomeHunter
et le tient à jour.

### À la main

1. Télécharger `EbonTomeHunter-x.y.z.zip` depuis la
   [dernière release](https://github.com/AxFeed-Wow/EbonTomeHunter/releases/latest).
2. L'extraire dans `World of Warcraft/Interface/AddOns/`. On doit obtenir
   `Interface/AddOns/EbonTomeHunter/EbonTomeHunter.toc`.
3. Relancer complètement le jeu, puis taper `/eth` (ou cliquer sur le bouton de la minimap).

Ancienne version (*EbonTomePrices*) : supprimer son dossier, sinon les deux se chargent.

## Commandes

| Commande | Effet |
|---|---|
| `/eth` | ouvrir / fermer la fenêtre |
| `/eth tp <tome>` | se téléporter au checkpoint le plus proche de là où le tome tombe |
| `/eth share` | partager / importer une wishlist (aussi un lien ou un build Echo Builder) |
| `/eth send <nom>` | envoyer sa wishlist à un joueur |
| `/eth net` | état du réseau (`sync` : annoncer tout de suite tes lieux de drop aux joueurs connectés) |
| `/eth history` | historique des drops (qui a trouvé quel tome, où, sur quel monstre) |
| `/eth tuto` | revoir le tutoriel |
| `/eth options` | options (aussi dans Interface > AddOns) |
| `/eth help` | toutes les commandes |

`/tomehunter` marche aussi.

## Limites connues

* **Le partage demande EbonAPI**, un addon à part (il n'est pas inclus, sa licence l'interdit). Sans
  lui, tes trouvailles restent sur ton ordinateur ; le chat le dit une fois.
* **« You can only be in 10 channels at a time. »** WoW limite chaque personnage à 10 canaux de
  discussion. EbonAPI utilise un seul canal caché pour tous les addons qui s'en servent. Quand les
  10 sont pris (General, Trade, LocalDefense, LookingForGroup, canaux « world »…), il ne peut pas le
  rejoindre : tu ne reçois ni ne partages de lieux de drop. Tout le reste fonctionne. Pour libérer
  une place : `/chatlist` liste tes canaux, `/leave <numéro>` quitte celui que tu n'utilises pas,
  puis `/reload`.
* EbonAPI rejoint son canal dès la connexion, parfois avant que le jeu te rende tes propres canaux :
  l'un d'eux peut alors changer de numéro (`/5` au lieu de `/4`…). Cela vient d'EbonAPI, pas
  d'EbonTomeHunter.
* Les lieux de drop circulent de joueur en joueur par EbonAPI, aussi par ceux qui utilisent un autre
  addon qui s'en sert : une trouvaille t'arrive dès que tu croises l'un d'eux, ce qui peut prendre
  quelques minutes.
* Les versions 2.x utilisaient leur propre canal : elles ne voient pas les trouvailles des 3.x, et
  inversement.
* Les lieux de drop reçus des autres joueurs ne sont pas vérifiables : chacun affiche qui l'a trouvé
  et combien de joueurs l'ont confirmé.

## Vie privée

Le réseau partage, par EbonAPI, le lieu où tu as obtenu un tome avec **ton nom de personnage**
(« trouvé par »), ainsi que tes comptes de cadavres lootés sans le tome et tes signalements « Plus
bon ? » (sources périmées). EbonAPI garde ces données et les transmet à ses autres utilisateurs, qui
les gardent aussi. Tu peux couper le réseau dans les options (*Réseau et alertes*). L'addon n'envoie
rien d'autre, sauf ta wishlist quand tu l'envoies toi-même à quelqu'un, et, seulement quand le
mainteneur demande des statistiques, combien de chaque créature tu as tuées.

## Contribuer

Les contributions sont les bienvenues : voir [CONTRIBUTING.md](CONTRIBUTING.md#contribuer-à-ebontomehunter).
En bref : Python 3.10+, `pip install lupa`, puis `python tools/check.py` doit afficher
`ALL CHECKS PASSED` (validateur et scénario de test dans un faux client WoW, avec et sans
ProjectEbonhold, en anglais et en français ; avec EbonAPI à côté du dépôt, les tests réseau tournent
avec plusieurs joueurs).

La documentation technique est dans [docs/](docs/), en commençant par [CLAUDE.md](CLAUDE.md).

## Sécurité

Si tu trouves un problème de sécurité (par exemple un message réseau qui déclencherait une action ou
casserait l'interface des autres joueurs), ne le signale pas dans une issue publique : voir
[SECURITY.md](SECURITY.md#politique-de-sécurité).

## Avertissement

EbonTomeHunter est un addon communautaire indépendant. Il n'est affilié ni à Project Ebonhold, ni à
Blizzard Entertainment, ni aux auteurs des addons qu'il lit ou utilise (ProjectEbonhold,
EbonholdHub, EbonBuilds, EbonAPI). Les lieux de drop affichés sur la carte viennent d'EbonholdHub et
d'EbonBuilds, lus en jeu : ils ne sont pas inclus dans ce dépôt. EbonAPI est un addon à part de
Siphelis, sous sa propre licence, installé par chaque joueur : il n'est pas inclus non plus. World of
Warcraft est une marque de Blizzard Entertainment.

## Licence

Publié sous licence MIT, © 2026 AxFeed-Wow. Voir [LICENSE](LICENSE).
