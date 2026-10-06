# Project Ebonhold : ce que l'addon utilise

Project Ebonhold est un serveur WotLK 3.3.5a en mode « Rogue-Lite » (royaume `Rogue-Lite (Live)`).
Au-dessus du client standard, il y a trois couches :
1. **L'addon serveur `ProjectEbonhold`**, livré dans le client (`Data/patch-4.MPQ`) : Echoes, tomes,
   checkpoints, runs… Global `ProjectEbonhold`.
2. **La DLL du client (`ebonhold.dll`)** : quelques fonctions Lua en plus (`EbonholdOpenURL`…).
3. **L'extension AwesomeWotLK** : `CopyToClipboard`, `C_NamePlate`, `GetItemInfoInstant`…

**Aucune de ces API n'est documentée officiellement : elles peuvent changer à chaque patch.** Pour
vérifier une fonction, lire la source réelle :
`python tools/extract_pe_source.py` → `_extracted/ProjectEbonhold/`. Les fichiers utiles sont
`projectebonhold.lua` (tous les codes de messages CS / SS) et `modules/<système>/*_service.lua`.
Cette source appartient au serveur : lecture locale uniquement, **jamais commitée ni publiée**.

## Règles

- **Échouer proprement** : chaque accès passe par `ns.PE.Service/Call` (vérification de type +
  `pcall`). Sans ProjectEbonhold, la fonction concernée se désactive sans erreur.
- **Lecture seule** : ne jamais écrire dans une table de ProjectEbonhold (ni ajouter un champ à ses
  lignes).
- **Ne jamais appeler `ProjectEbonhold.onEventReceived`** : il ne garde qu'un seul callback par
  message et écraserait celui de ProjectEbonhold. Pour réagir à un message du serveur, écouter
  soi-même `CHAT_MSG_ADDON` (préfixe `AAM0x9`), comme `Known.lua`.

## Services utilisés

### PerkService (tomes appris) — `Known.lua`
- `GetDiscoveredEchoes()` → `[echoSpellId] = nombre obtenu`. C'est la liste du serveur (message 530,
  demandé à la connexion), sinon le cache par personnage de ProjectEbonhold. **Un tome est appris si
  son Echo (item id du tome − 100 000) y figure** : c'est la règle de l'infobulle « Already learned »
  de ProjectEbonhold (`modules/echoTome/echo_tome_tooltip.lua`).
- `IsTomeEchoDisabled(echoId)` : appris mais retiré du tirage (journal des Echoes).

### PerkDropSources (indices de source) — `Catalog.DropHint`
`ProjectEbonhold.PerkDropSources[echoSpellId] = "Can be found on Mage-type enemies"` : l'indice que
montre le journal des Echos de ProjectEbonhold (`modules/perks/perks_data.lua`, lu par
`echo_journal.lua`). **148 entrées, une par tome** (l'Echo = id du tome − 100 000), en anglais :
types d'ennemis (« Mage-type », « enemies that cast Fear »), ou boss (« Lord Marrowgar », « the
Blood Prince Council », « in the Gunship Battle »). `PerkDropSourceByGroup[groupId]` est la même
chose par groupe d'Echos. L'addon le lit en jeu (bulle d'aide, fenêtre Sources, tome sans lieu) :
jamais copié. Il confirme les 20 boss de raid de `Catalog.RAID_BOSSES`.

### CheckpointService (téléportation) — `Travel.lua`
- `GetCheckpoints()` → liste de `{ id, name, kind, mapId, serverMapId, x, y, faction, factionAllowed,
  unlocked }` :
  - `kind` : `nil` = maître de vol, `"MEETINGSTONE"` / `"MEETINGSTONE_RAID"` = pierre de rencontre ;
  - `mapId` = valeur de `GetCurrentMapAreaID()` = **id WorldMapArea + 1** ; `x`, `y` = fractions
    0..1 sur cette carte de zone ;
  - `serverMapId` = continent (0 Royaumes de l'Est, 1 Kalimdor, 530 Outreterre, 571 Norfendre) ;
  - `unlocked` reste `false` pour tous tant que le serveur n'a pas répondu (message 800, demandé à
    l'entrée dans le monde).
- Une pierre de rencontre peut être listée plusieurs fois (même id, une fois par carte de zone
  voisine, même point) : dédoublonner par id.
- `UseCheckpoint(id)` envoie le message 801. Le serveur téléporte, ou refuse (combat…).
  ProjectEbonhold ne démonte pas le joueur ; EbonCompletionist fait
  `if IsMounted() and not IsFlying() then Dismount() end`.
- `RequestCheckpoints()` redemande la liste (message 800).
- Les bornes de cartes codées en dur dans son `checkpoint.lua` diffèrent un peu de celles du
  client pour Sombrivage et Gangrebois (~100 m) : l'addon utilise celles du client (`MapData.lua`).
- Quand on parle à un maître de vol, ProjectEbonhold ferme la carte des vols et ouvre la carte du
  monde avec ses propres marqueurs de checkpoints (clic = téléportation).

## Messages du serveur (préfixe `AAM0x9`)

Le serveur et ProjectEbonhold dialoguent par **messages d'addon en WHISPER au joueur lui-même** :
- requête : `SendAddonMessage("AAM0x9", "<code>" ou "<code>\t<args>", "WHISPER", UnitName("player"))` ;
- réponse : `CHAT_MSG_ADDON("AAM0x9", "<code>\t<corps>", "WHISPER", joueur)` ;
- réponses longues découpées : `<code>\t@<id 4 hex>\t<index 3 hex>/<total 3 hex>\t<tranche>`.

Codes utiles ici :

| Code | Sens |
|---|---|
| `530` | SEND_ECHO_DISCOVERY : liste des Echoes découverts (écouté par Known.lua) |
| `800` | REQUEST / SEND_CHECKPOINTS_DATA : ids de checkpoints débloqués, séparés par `;` |
| `801` | REQUEST_USE_CHECKPOINT `801\t<id>` (via `CheckpointService.UseCheckpoint`) |

Politesse réseau : au plus une requête toutes les quelques secondes par type ; le serveur peut
rendre muet un client trop bavard. `RegisterAddonMessagePrefix` n'existe pas en 3.3.5a.

## Identifiants

- **Tome** : item id == id de son sort de tome (**300xxx**) == `requiredSpell` des Echoes qu'il
  débloque (plusieurs variantes de qualité peuvent partager un tome).
  - **Echo** = item id du tome − 100 000 (200xxx).
  - Nom de l'objet : « Tome of Echo: <echo> » ; nom du sort : « Tome of <echo> ». Cinq noms diffèrent
    (« Eonar Seed » / « Eonar's Seed », « DragonKin »…) : faire correspondre par **item id** (le lien
    d'une enchère), le nom seulement en repli.
  - Recette (classe 9), empilable par 5, non lié (vendable à l'HV), qualité d'objet = qualité d'Echo
    max + 1. Infobulle : « Grants this character the ability to discover X when offered new Echoes. X: … ».
- **Tranches de sorts custom** :
  - 100000 : arbre de Soul Ash ;
  - 200000 : Echoes ;
  - 300000 : tomes ;
  - 400000 : Loot Grip ;
  - 500000 / 600000 : difficulté ;
  - 700000 : affixes ;
  - 900000 : mécaniques ;
  - 1000000 : Echoes de classe ;
  - 1200000 / 2300000 : apparences / montures.
- **Créatures propres au serveur** : ids à partir de 600601 (600601 « Goblin Merchant », 600602
  « Greedy scavenger »). Wowhead ne les connaît pas : l'addon ne fait pas de lien au-delà de 50 000
  (les créatures de WotLK s'arrêtent vers 40 000).
- **GUID de créature** (3.3.5a) : `0xF130` + entrée (6 chiffres hexadécimaux) + apparition (6 chiffres
  hexadécimaux) → `tonumber(guid:sub(7, 12), 16)`. `F150` = véhicule.

## Le familier Greedy Scavenger

Familier (compagnon) de ProjectEbonhold qui **ramasse lui-même le butin des cadavres** du joueur.
- Il se configure par menus gossip : qualité minimale, types d'objets, destruction automatique.
  GreedyScavengerUI redessine ces menus.
- **Ses objets arrivent dans les sacs sans aucune ligne `CHAT_MSG_LOOT`**, ni fenêtre de butin. Ce
  comportement a été constaté par EbonClearance, qui compte le butin par différence du contenu des
  sacs. EbonTomeHunter fait pareil (`Loot.lua`).
- Il « parle » dans le chat (« Greedy Scavenger gnaws on the corpse »). EbonClearance sait le rendre
  muet et le ré-invoquer quand il se perd : il surveille ses lignes sur `CHAT_MSG_MONSTER_SAY`,
  `_YELL`, `_WHISPER`, `_EMOTE`, `_PARTY` et `CHAT_MSG_SAY`, `_YELL`, `_EMOTE`, `_TEXT_EMOTE`, par
  l'auteur ou le texte (un familier peut être renommé : « Serv's Scavenger »).
- **Aucun signal par cadavre connu** (constaté par l'utilisateur, 2026-09-24) : il ramasse comme si
  le joueur avait looté, sans message. On ne sait donc pas quels cadavres il a fouillés : ses kills
  ne comptent pas comme « cadavres sans le tome » (`Evidence.lua`), sinon des sources encore bonnes
  seraient grisées à tort. Ses tomes, eux, sont détectés (sacs) et envoyés comme lieux de drop, ce
  qui rétablit la source.
- **Quel monstre** (`Hints.lua`, 3.0.0) : parmi les kills de la dernière minute, l'indice du serveur
  (« Can be found on … ») départage (sort vu dans le journal de combat, type de créature, classe,
  source connue) ; sinon le lieu garde des candidats, réduits à chaque nouveau drop au même endroit.
- **Enquête en cours** : `/ethdev scav on` (addon de dev) enregistre tout ce qui entoure ses
  ramassages (journal de combat, paroles et emotes, sacs, argent). Si ses lignes nomment le cadavre,
  l'attribution pourra s'en servir.

## Canaux « world » de ProjectEbonhold

`modules/worldChannel` propose au joueur (une fenêtre, `/worldchannel`) les canaux `world`,
`world-fr`, `world-de` et `world-es`, rejoints avec `/join` : ils sont donc gardés dans
`chat-cache.txt` et rétablis par le client à chaque connexion. ProjectEbonhold attend cette
restauration (jusqu'à 30 s) avant de proposer quoi que ce soit : rejoindre un canal pendant qu'elle
se fait l'enregistre deux fois et casse l'envoi (bugs #2664/#2676). Avec les canaux de zone et les
canaux cachés d'autres addons (EbonAffixAlert, EbonBuilds, EbonClearance, Nexus…), la limite des 10
canaux est vite atteinte. EbonTomeHunter 2.x rejoignait son propre canal après cette restauration ;
depuis 3.0.0 il passe par le canal commun d'EbonAPI, qu'EbonAPI rejoint dès `PLAYER_LOGIN` (avant la
restauration : un canal du joueur peut changer de numéro ; à signaler à son auteur).

## Fenêtres de ProjectEbonhold qui font entrer des objets dans les sacs

À ne pas confondre avec du butin (liste utilisée par `Loot.lua`) :
- `ExtBankFrame` (banque étendue) ;
- `VoidStorageFrame` ;
- `ModernShopFrame` (boutique) ;
- `ItemPurchasePopup` ;
- `EbonholdExtractionFrame` (extraction d'affixes).

## Fonctions du client utilisées

| Fonction | Origine | Usage |
|---|---|---|
| `EbonholdOpenURL(url)` | DLL Ebonhold | ouvrir un lien Wowhead dans le navigateur (toujours tester sa présence, appeler sous `pcall`) |
| `CopyToClipboard(text)` | AwesomeWotLK | bouton Copier (sinon : EditBox sélectionnée pour Ctrl+C) |
| unités `nameplate1`… | client Ebonhold | chaque plaque de nom a une vraie unité (`UnitClass`, `UnitCreatureType`… marchent), documenté par `modules/nameplates` de ProjectEbonhold ; `Hints.lua` y lit classe et type des monstres (`NAME_PLATE_UNIT_ADDED` quand l'extension a l'évènement, sinon relecture en combat) |

La DLL fournit aussi `EbonholdLog`, `EbonholdWorldToScreen`, `EbonholdGetPlayerPosition`,
`EbonholdRequestQuestPOI`, `ExtBank*`… ProjectEbonhold fournit un `C_Timer` en Lua, mais
EbonTomeHunter ne s'y fie pas et garde ses propres timers.

## Données d'EbonholdHub (lieux de drop)

- `EbonholdHub.EchoMapData.Locations[slug]`, avec `slug` = `"eastern-kingdoms"`, `"kalimdor"`,
  `"outland"` ou `"northrend"`. Chaque entrée : `{ tomeId, name, quality, description, x, y,
  placeName, mobs = {…}, notes }`. Repli : `EbonCompletionist.Data.EchoMap.Locations`, même format.
- `x`, `y` sont des **pourcentages de leurs propres images**, pas des cartes du jeu :
  - Royaumes de l'Est et Kalimdor : mosaïques de cartes de zones, bornes mesurées par recalage ;
  - Outreterre et Norfendre : les cartes de continent du jeu.
  - Le calibrage est dans `MapData.hub` (voir `docs/DATA.md`).
- « Unknown location » / « Anywhere » : coordonnées factices, ignorées.
- Licence d'EbonholdHub : **All rights reserved**. Ses données sont **lues en jeu à l'exécution**,
  jamais copiées dans ce dépôt.
- **Origine** : `EchoMapData.SOURCE_URL = "https://worldofechoes.pages.dev"`, carte web de fans citée
  par le guide du joueur officiel. Ses données (`assets/data/tomes.json` : `zones`, `tomes`,
  `locations` au même format) étaient identiques à celles d'EbonholdHub 2.0.4 le 2026-09-26 : 128
  tomes, 173 lieux, 98 tomes avec un vrai lieu. Licence non indiquée : ne rien copier non plus.

## Atlas d'EbonBuilds (sources de drop, depuis 3.0.0)

- **EbonBuilds** (5.5.4) tient un atlas communautaire des tomes, partagé entre ses utilisateurs
  (guilde, groupe, canal `ebonbuildssync`) : `EbonBuildsDB.tomeAtlas[itemId] = { name, sources =
  { ["Monstre\031Zone"] = nombre de drops } }` (`core/TomeAtlas.lua`, fusion par `max`). La zone est
  `GetRealZoneText()` (langue du client), le monstre la cible morte à l'ouverture du butin
  (« Unknown » sinon).
- Coordonnées : `EbonBuildsDB.tomeAtlasPinCoords[zone][nom du tome] = { x, y, n }`, moyenne des loots
  de l'utilisateur lui-même, **jamais partagées** entre joueurs.
- EbonBuilds n'expose pas de globale : seule sa sauvegarde (compte) se lit, après son chargement
  (`OptionalDeps`).
- Beaucoup de sources sont des raids et donjons (Ulduar, Naxxramas…) : pas de carte de zone.
- Sans licence indiquée : **lecture en jeu seulement** (`Atlas.lua`), jamais copié ni modifié.

## EbonAPI (réseau, depuis 3.0.0)

- Addon de Siphelis ([github.com/Siphelis/EbonAPI](https://github.com/Siphelis/EbonAPI), aussi dans
  Ebonhold Addon Manager), utilisé par les addons de Siphelis (AutoCallboard, SkillTreeAutoLoad, son
  EbonBuilds). Licence **PolyForm Strict** :
  usage non commercial permis, **ni redistribution ni modification** : il n'est jamais copié dans ce
  dépôt ni modifié ; chaque joueur l'installe, les tests le lisent là où il est.
- `EbonAPI:NewAddon(nom, majeure, mineure)` : poignée de l'addon (nil si EbonAPI est trop ancien, il
  le dit au joueur). Évènements `READY`, `CHANNEL_JOINED` (collants), `CHANNEL_LOST`,
  `SHARE_RECEIVED(évènement, addon, nom, état, expéditeur)`.
- **Jeux de données** : `Share(nom, état, texte)` (nom `[%w_]`, état entier, texte de 32 Ko au plus),
  `GetShared(nom[, addon])`, `SharedNames()`, `ShareRule(fn(nom, leurÉtat, monÉtat))` (par défaut :
  un état plus grand), `SyncShares()` (annonce manuelle, 30 s entre deux), `Unshare(nom)`. EbonAPI
  garde les jeux de **tous** les addons dans `EbonAPIDB` (compte) et les transmet : annonce 2 s après
  l'entrée dans le canal et 15 s après un changement, tour toutes les 2 min avec les pairs dont les
  données diffèrent (oubliés après 10 min), récupération par chuchotements.
- **Canal** : un seul canal caché, `ebonapi` (lignes `EA1:`), commun à ses addons, rejoint à
  `PLAYER_LOGIN` **seulement si un addon s'est inscrit** (`NewAddon`). File d'envoi : une ligne
  toutes les 0,15 s ; joueur absent détecté par « No player named … ».
- **Messages** : `Say(op, corps)` / `OnChannel(op, fn(expéditeur, corps))` (op alphanumérique, corps
  sans `|`, découpé en 16 lignes au plus).
- **Versions** : `Version(texte, url)` ; EbonAPI annonce les versions et prévient lui-même le joueur
  d'une version plus récente (`AvailableUpdate()`).
- Commandes : `/eapi status`, `/eapi trace 20 share`.

## Autres sources de données vues (non utilisées)

- **Site officiel** : `https://project-ebonhold.com/assets/dbc/echoes.json` (Echoes : nom, qualité,
  `requiredSpell` = tome, `tome = true`) et une API publique en lecture, `https://api.project-ebonhold.com/api/updates`
  (notes de mise à jour en Markdown, sans authentification). Le reste de l'API (bugs, personnages…)
  demande une connexion.

## Cartes particulières

Bois des Chants éternels, Terres Fantômes, Quel'Danas, Azuremyst, Brumesang (et Lune-d'argent,
l'Exodar) sont physiquement sur la carte **530**, mais dessinés sur les cartes des Royaumes de l'Est
et de Kalimdor (`shownOn` dans `MapData.lua`). Il ne faut pas les comparer aux points des cartes 0 / 1.

## Autres addons de la communauté

| Addon | Relation |
|---|---|
| Auctionator | les onglets de l'HV cohabitent : EbonTomeHunter s'ajoute après ses onglets |
| EbonholdHub / EbonCompletionist | source des lieux de drop (optionnelle) |
| EbonAPI | réseau entre joueurs (optionnel : sans lui, les lieux restent locaux) |
| EbonBuilds (vook) | atlas des tomes lu en jeu (sources en plus) |
| AutoCallboard, SkillTreeAutoLoad | utilisent EbonAPI : leurs utilisateurs transmettent aussi nos jeux de données |
| EbonClearance | gère aussi le Scavenger et le butin (aucun conflit connu) |
| GreedyScavengerUI | menus du Scavenger |
| PallyPilot / CallboardHunter | autre façon de se téléporter vers une zone (CallboardHunter) |
