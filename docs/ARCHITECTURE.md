# Architecture du code

Addon Lua 5.1 pour le client WotLK 3.3.5a. Environ 10 300 lignes réparties en 29 modules, un
fichier par responsabilité. Chaque fichier reçoit `local addonName, ns = ...` : `ns` est la table
partagée entre tous les fichiers de l'addon, exposée en global sous le nom `EbonTomeHunter`
(macros, autres addons, tests).

## Ordre de chargement (`EbonTomeHunter.toc`)

L'ordre compte : un module n'appelle au **chargement** que ceux listés avant lui. Les appels faits
plus tard (clics, évènements) peuvent viser n'importe quel module.

| # | Fichier | Rôle | Évènements du jeu | Bus : écoute → émet |
|---|---|---|---|---|
| 1 | `Locale.lua` | table `ns.L` : anglais + surcharge française si `GetLocale() == "frFR"` ; une clé absente renvoie son nom | | |
| 2 | `Core.lua` | version, SavedVariables et valeurs par défaut, bus `ns.On/ns.Fire`, timers, évènements multi-écouteurs, adaptateur `ns.PE`, démarrage, commandes `/eth` | ADDON_LOADED, PLAYER_LOGIN, BAG_UPDATE | → DATABASE_READY, LOGIN, READY, AUCTION_UI_LOADED, BAGS_CHANGED, SETTINGS_CHANGED |
| 3 | `TomeData.lua` | **généré** : les 160 tomes (`ns.TomeData[itemId]`) | | |
| 4 | `MapData.lua` | **généré** : bornes monde de chaque carte (`ns.MapData.maps`) et calibrage des images d'EbonholdHub (`ns.MapData.hub`) | | |
| 5 | `Widgets.lua` | kit d'UI sombre `ns.Widgets` (W) : fenêtre, boutons, onglets, liste virtuelle, en-têtes triables, zone de texte, pièces d'or, cases à cocher, curseurs | | |
| 6 | `Catalog.lua` | catalogue `ns.Catalog` : lignes de tomes + index, lieux de drop, tomes découverts, migration des anciennes clés | | SIGHTINGS_CHANGED → CATALOG_CHANGED |
| 7 | `Prices.lua` | prix enregistrés `ns.Prices` | | → PRICES_CHANGED |
| 8 | `Scan.lua` | moteur de requêtes HV `ns.Scan` : scan complet, recherches exactes, file d'attente ; tomes des sacs | AUCTION_ITEM_LIST_UPDATE, AUCTION_HOUSE_CLOSED | → SCAN_STATE, SEARCH_RESULTS, PRICES_CHANGED, CATALOG_CHANGED |
| 9 | `Wishlist.lua` | wishlist du personnage `ns.Wishlist` | | → WISHLIST_CHANGED |
| 10 | `Known.lua` | tomes appris `ns.Known` (via ProjectEbonhold) | CHAT_MSG_ADDON (code 530) | BAGS_CHANGED, READY → KNOWN_CHANGED |
| 11 | `Buy.lua` | achat vérifié `ns.Buy` | CHAT_MSG_SYSTEM, UI_ERROR_MESSAGE, AUCTION_HOUSE_CLOSED | → PURCHASE, SEARCH_RESULTS, SCAN_STATE |
| 12 | `Share.lua` | chaîne de partage + fenêtre Partager `ns.Share` | | WISHLIST_CHANGED |
| 13 | `WorldMap.lua` | géométrie des cartes, marqueurs, « Localiser » `ns.WorldMap` | WORLD_MAP_UPDATE | WISHLIST_CHANGED, CATALOG_CHANGED, SETTINGS_CHANGED |
| 14 | `Wowhead.lua` | liens Wowhead WotLK, ids de PNJ appris `ns.Wowhead` | UPDATE_MOUSEOVER_UNIT, PLAYER_TARGET_CHANGED | CATALOG_CHANGED |
| 15 | `Travel.lua` | téléportation au checkpoint le plus proche `ns.Travel` | | |
| 16 | `Sources.lua` | fenêtre Sources (monstres, TP, Wowhead) `ns.Sources` | | CATALOG_CHANGED |
| 17 | `History.lua` | historique des drops `ns.History` | | SIGHTINGS_CHANGED |
| 18 | `Link.lua` | réseau maison : canal de discussion caché `ebontomehunternet`, empreintes et lignes qui manquent `ns.Link` | CHAT_MSG_CHANNEL (+ filtres d'affichage) | LOGIN |
| 19 | `NetApi.lua` | adaptateur EbonAPI, gardé de côté (mêmes fonctions que `Link.lua`) `ns.NetApi` | (EbonAPI : READY, SHARE_RECEIVED, CHANNEL_JOINED / LOST ; opérations KQ / KA) | |
| 20 | `Net.lua` | données du réseau entre joueurs (lieux, fusion, textes) `ns.Net`, choisit le transport | | READY, LOGIN, SETTINGS_CHANGED → SIGHTINGS_CHANGED, NET_SYNC_STATE, NET_STATS |
| 21 | `Comm.lua` | envoi direct de wishlist (chuchotement d'addon) `ns.Comm` | CHAT_MSG_ADDON (préfixe ETH) | |
| 22 | `Hints.lua` | quel monstre a lâché un tome de l'Œil du charognard `ns.Hints` | UPDATE_MOUSEOVER_UNIT, PLAYER_TARGET_CHANGED, NAME_PLATE_UNIT_ADDED | |
| 23 | `Loot.lua` | tomes obtenus : alertes + lieu de drop `ns.Loot` | LOOT_OPENED, LOOT_CLOSED, CHAT_MSG_LOOT, COMBAT_LOG_EVENT_UNFILTERED, BAG_UPDATE, PLAYER_ENTERING_WORLD | BAGS_CHANGED, READY → CORPSE_OPENED, CORPSE_CLOSED, TOME_DROPPED, TOME_OBTAINED |
| 24 | `Evidence.lua` | sources qui ne lâchent plus leur tome `ns.Evidence` | | CORPSE_*, TOME_DROPPED, CATALOG_CHANGED → SIGHTINGS_CHANGED |
| 25 | `UI.lua` | fenêtre principale `ns.UI` | | CATALOG_CHANGED, WISHLIST_CHANGED, PRICES_CHANGED, KNOWN_CHANGED, SCAN_STATE, SETTINGS_CHANGED, NET_SYNC_STATE, READY |
| 26 | `AuctionHouse.lua` | onglets Tomes / Wishlist de l'HV `ns.AH` | AUCTION_HOUSE_SHOW, AUCTION_HOUSE_CLOSED | AUCTION_UI_LOADED, DATABASE_READY, SEARCH_RESULTS, … |
| 27 | `Minimap.lua` | bouton de minimap | | LOGIN, SETTINGS_CHANGED |
| 28 | `Options.lua` | panneaux Interface > AddOns (principal + « Réseau et alertes ») | | → SETTINGS_CHANGED |
| 29 | `Tutorial.lua` | tour guidé `ns.Tutorial` | | READY |

`## OptionalDeps` : EbonAPI, ProjectEbonhold, EbonholdHub, EbonCompletionist, EbonBuilds, Auctionator
(chargés avant nous quand ils sont là). EbonAPI n'est plus utilisé par défaut (3.4.0) ; il n'est
**jamais** copié dans le dépôt ni modifié : sa licence (PolyForm Strict) l'interdit. Seul son
adaptateur (`NetApi.lua`) est à nous.

## Socle (Core.lua)

- **SavedVariables** : `EbonTomeHunterDB` (compte) et `EbonTomeHunterCharDB` (personnage). Le client
  **remplace** ces globales juste avant `ADDON_LOADED` : les valeurs par défaut (`DB_DEFAULTS`,
  `CHAR_DEFAULTS`) sont appliquées au chargement ET à `ADDON_LOADED` (`ns.InitDatabase`). Toujours
  lire `ns.DB` / `ns.CDB` / `ns.Opt()` au moment de l'appel, jamais une référence gardée d'avant.
- **Bus** : `ns.On(message, fn)` / `ns.Fire(message, ...)`. Chaque écouteur passe par un `pcall` ;
  une erreur va au gestionnaire d'erreurs du jeu sans bloquer les autres.
- **Évènements du jeu** : `ns.RegisterEvent(event, fn)`. Plusieurs modules peuvent écouter le même
  évènement. L'inscription est protégée par un `pcall` : un évènement inconnu de ce client ne doit
  pas interrompre le chargement du fichier.
- **Timers** : `ns.Timer.After(sec, fn)`, sur une frame `OnUpdate` (pas de `C_Timer` en 3.3.5a stock).
- **ProjectEbonhold** : `ns.PE.Service(nom)` renvoie la table du service ou nil ;
  `ns.PE.Call(service, fonction, ...)` l'appelle sous `pcall`. C'est le **seul** accès autorisé.
- **Démarrage** : PLAYER_LOGIN → `LOGIN`, puis `Bootstrap` attend ProjectEbonhold ou les données
  d'EbonholdHub (30 s au plus). Il construit alors le catalogue, lit les sacs et émet `READY`.
- **Sacs** : BAG_UPDATE arrive en rafale. Le premier lance un timer de 1,5 s, puis
  `Scan.ScanBags` apprend les tomes et `BAGS_CHANGED` est émis.
- **`ns.Print(texte)` / `ns.Print(format, ...)`** : un texte seul n'est jamais passé à `format`, car
  des données reçues du réseau peuvent contenir `%`.

## Messages du bus

| Message | Arguments | Émis quand |
|---|---|---|
| `DATABASE_READY` | | SavedVariables prêtes (ADDON_LOADED) |
| `LOGIN` | | PLAYER_LOGIN |
| `READY` | | catalogue construit après la connexion |
| `AUCTION_UI_LOADED` | | Blizzard_AuctionUI chargé (à la demande) |
| `BAGS_CHANGED` | | sacs relus (1,5 s après un BAG_UPDATE) |
| `CATALOG_CHANGED` | | catalogue reconstruit, tome découvert, lieux changés |
| `SIGHTINGS_CHANGED` | | lieux du réseau ou preuves changés → le catalogue les rattache |
| `NET_SYNC_STATE` | (expéditeur) | transport prêt, canal rejoint ou perdu, lignes reçues, réseau allumé / coupé |
| `NET_STATS` | résultats | réponses à une demande de statistiques (15 s après) |
| `CORPSE_OPENED` / `CORPSE_CLOSED` | guid, nom, npcId | butin d'un cadavre ouvert / fermé (Evidence) |
| `TOME_DROPPED` | itemId, nom, npcId | un tome est tombé de ce monstre (pris ou non) |
| `TOME_OBTAINED` | itemId, mob, npcId, candidats, raison, kills | tome de l'Œil du charognard et son attribution (addon de dev) |
| `WISHLIST_CHANGED` | | ajout, retrait ou quantité changée |
| `PRICES_CHANGED` | | prix enregistrés changés |
| `SCAN_STATE` | | progression / état du moteur HV |
| `SEARCH_RESULTS` | itemId | recherche exacte terminée ou page rechargée |
| `PURCHASE` | listing | achat confirmé par le serveur |
| `KNOWN_CHANGED` | | liste des tomes appris relue |
| `SETTINGS_CHANGED` | key, value | option changée (`ns.SetOption`) |

## Données sauvegardées

`EbonTomeHunterDB` (commun à tous les personnages du compte) :

| Clé | Contenu |
|---|---|
| `meta.version` | version qui a écrit la sauvegarde |
| `prices[itemId]` | `{ min, listings, at, seen, prevMin, hist = { {at, min, listings} ×20 max } }` : `min` = prix unitaire le plus bas vu (gardé quand le tome n'est plus en vente), `listings` = annonces au dernier passage (0 = pas en vente) |
| `lastScan` | `time()` du dernier scan complet |
| `tomes[nomNormalisé]` | tomes vus à l'HV / dans les sacs : `{ name, echo, itemId, firstSeen, lastSeen, seen, key }` |
| `sightings[itemId]` | lieux de drop du réseau (12 max par tome) : `{ itemId, mapFile, x, y, npcId, mob, zone, at, by, finders = { [nom] = true }, n, cands, inferred }` : `n` = nombre de joueurs dit par un jeu de données, `cands` = monstres possibles `{ npcId, name }` (4 max) d'un lieu sans monstre, `inferred` = monstre déduit de plusieurs drops |
| `npcIds[nom de monstre en minuscules]` | id de PNJ appris (liens Wowhead) |
| `corpses`, `evidence`, `reports` | sources périmées (Evidence.lua) : nos compteurs, ceux des autres, les signalements |
| `killStats[npcId]` | `{ n, name, last }` : créatures tuées par le joueur ou le groupe (600 max) |
| `discovered[itemId]` | `true` : tome plus récent que l'addon découvert en jeu (Catalog.lua), dit une fois au joueur |
| `apiHint` | version pour laquelle « installez EbonAPI » a déjà été dit (seulement si `USE_EBONAPI` est vrai et EbonAPI absent) |
| `updateTold` | version plus récente déjà annoncée dans le chat |
| `evidenceName`, `ownNames` | nom unique sous lequel partent nos compteurs (Evidence.lua), et les personnages du compte (leurs lignes ne comptent pas comme celles d'un autre joueur) |
| `tutorialDone` | version du tutoriel déjà vue (0 = jamais) |
| `options` | toutes les options (voir `DB_DEFAULTS.options` dans Core.lua) |

`EbonTomeHunterCharDB` (par personnage) : `wishlist[itemId] = { qty }`.

**Identité d'un tome** : son **item id** (300xxx, égal à l'id de son sort de tome). L'Echo qu'il
débloque vaut l'item id moins 100 000. Un tome inconnu de `TomeData` (nouveau patch) a pour
identité son nom normalisé (chaîne) ; `ns.Key` accepte les deux.

## Modules en détail

### Catalog.lua
- `Build()` part de `ns.TomeData` : une ligne par tome, avec `itemId`, `spellId`, `echoes`, `name`
  (nom de l'Echo), `tomeName` (« Tome of Echo: X »), `quality` et `desc`. Il y ajoute
  `staticLocations` (lieux d'EbonholdHub / EbonCompletionist, lus en jeu).
- Index : `byItem`, `bySpell` (toutes les variantes d'Echo), `byName`, `byTomeName` (toutes les
  graphies), `byEchoKey`.
- `AttachSightings(row)` : `locations` = lieux statiques (sinon boss de raid) + lieux du réseau
  (`Net.Locations`). Triés : pas périmés d'abord, pas vieux de 90 jours, **les plus vus** (`drops`
  = max de `seen`, joueurs du réseau, et de `Evidence.Drops` de ses monstres),
  puis sur la carte, puis `order` ; `location` = le premier.
- `LearnTome(name, itemId)` : tome vu à l'HV ou dans les sacs, gardé dans `DB.tomes` ;
  `AddLearnedRow` crée une ligne pour un tome inconnu.
- `BuildFromServer(AddRow)` : un tome plus récent que l'addon est découvert dans la liste d'Echos
  de ProjectEbonhold (`PerkDatabase`, via `ns.PE`) : une entrée dont `isTome` est vrai ou dont
  `requiredSpell` est de 300000 à 399999 (= id d'objet du tome). Un tome absent de `TomeData` reçoit
  une ligne complète (`discovered = true` : prix, wishlist, appris, lieux, réseau) ; les nouvelles
  variantes d'Echo d'un tome connu lui sont rattachées (`bySpell`, `echoes`). Le joueur est prévenu
  une fois par tome (`ScanLearned`, `DB.discovered[itemId] = true`).
- `MigrateKeys()` convertit les clés des anciennes versions (id d'Echo, nom) en item id.

### Scan.lua (HV)
- **Une requête à la fois**. Chaque page attend `CanSendAuctionQuery()` (15 s max), puis
  `QueryAuctionItems(nom, nil, nil, 0, 0, 0, page, false, nil)`. Sans réponse
  `AUCTION_ITEM_LIST_UPDATE` en 8 s, la page est renvoyée (2 fois au plus).
- **Scan complet** : requête « Tome of Echo », 60 pages max. Les annonces sont reliées à leur tome
  par l'item id du lien, le nom ne sert qu'en repli. On garde le prix unitaire le plus bas et le
  nombre d'annonces. Après un scan **complet**, les tomes absents passent à « pas en vente ».
- **Annonces sans nom** : `GetAuctionItemInfo` renvoie un nom `nil` tant que le client n'a pas les
  données de l'objet (FrameXML les cache : « Bug 145328 ») ; `AUCTION_ITEM_LIST_UPDATE` revient
  quand elles arrivent. La page est relue toutes les 0,5 s pendant 3 s au plus (`WaitForNames`) ;
  après, le travail est `partial` : un scan ne passe pas les absents à « pas en vente »
  (`L.ScanPartial` dans le chat), une recherche exacte n'enregistre pas de prix.
- **Recherche exacte** d'un tome : 5 pages max. Elle ne garde que les annonces de ce tome (la
  recherche par nom est une sous-chaîne) et les trie par prix unitaire, les enchères sans achat
  immédiat en dernier. Résultats dans `Scan.results[itemId]`.
- `Scan.loaded` décrit ce que contient la liste « list » de l'HV (requête et page). Un hook sur
  `QueryAuctionItems` l'invalide quand quelqu'un d'autre interroge l'HV.

### Buy.lua
`PlaceAuctionBid("list", index, buyout)` agit sur un **index de la page chargée**. Avant d'acheter,
`FindOnPage` retrouve l'annonce (même nom, quantité, prix, vendeur). Si elle a bougé, la page est
rechargée et rien n'est acheté à sa place.
- **Vérifications** : prix d'achat immédiat, pas sa propre annonce, or suffisant, aucun achat en
  cours.
- **Réussite** : `CHAT_MSG_SYSTEM` = `ERR_AUCTION_BID_PLACED` / `ERR_AUCTION_WON_S`.
- **Échec** : `UI_ERROR_MESSAGE` dans une liste blanche d'erreurs.
- **Sans réponse** au bout de 6 s : la liste est rechargée.
- Après un achat, la quantité est déduite de la wishlist (option).

### Known.lua
Un tome est appris si son Echo (item id − 100 000) figure dans
`ProjectEbonhold.PerkService.GetDiscoveredEchoes()`. C'est la même règle que l'infobulle « Already
learned » de ProjectEbonhold. `IsTomeEchoDisabled(echoId)` indique un tome appris mais retiré du
tirage. La liste est relue quand le message serveur 530 passe (écouté, sans toucher aux handlers de
ProjectEbonhold), quand les sacs changent et à `READY`.

### WorldMap.lua
- **Coordonnées monde** : `WorldPosition(loc)` renvoie `map, worldX, worldY`, où `map` est l'id
  d'instance (0 = Royaumes de l'Est, 1 = Kalimdor, 530 = Outreterre, 571 = Norfendre). Deux sources
  de lieux :
  - lieux d'EbonholdHub : pourcentages de **leurs images**, convertis avec `MapData.hub[slug]` ;
  - lieux du réseau : fractions 0..1 de la carte de zone `loc.mapFile`, converties avec
    `MapData.maps[file]`.
- `MapPosition(info, map, wx, wy)` donne la position sur une carte du jeu.
- `BestZone(loc)` choisit la carte de zone qui montre le mieux un lieu.
- `TravelPosition(loc)` : `WorldPosition`, sinon le centre de la carte de zone `loc.mapFile` (source
  sans point) avec un 4e retour `true` (approximatif).
- **Marqueurs** : sur `WorldMapButton`, une étoile pulsante pour le tome localisé et un rond par lieu
  de chaque tome de la wishlist. Clic : la fenêtre ; Maj : Sources ; Ctrl : téléportation.
- **Localiser** : ouvre la carte (`SetMapByID`, repli `SetMapZoom`) et passe au lieu suivant à
  chaque clic.
- `GetMapContinents` / `GetMapZones` renvoient des valeurs multiples en 3.3.5a (voir `PackCall`).
- `SetMapToCurrentZone()` n'est jamais appelé pendant que la carte est ouverte.

### Wowhead.lua / Sources.lua / Travel.lua
- **Liens** : `https://www.wowhead.com/wotlk/npc=<id>/<slug>`, ou une recherche
  `.../wotlk/search?q=`. **Jamais de lien d'objet.** Une créature du serveur (id ≥ 50 000, par
  exemple 600602 pour le Greedy Scavenger) n'a pas de lien.
- **Ids de PNJ** : lus dans le GUID (`0xF130` + entrée sur 6 chiffres hexadécimaux) au survol ou au
  ciblage d'un monstre cité dans les lieux de drop, ou au loot.
- **Travel, checkpoints** : `ProjectEbonhold.CheckpointService.GetCheckpoints()`.
  - Les champs `mapId` (= `GetCurrentMapAreaID()` = id WorldMapArea + 1), `x` et `y` sont
    convertis en coordonnées monde avec `MapData`.
  - Seuls les checkpoints de la faction sont gardés ; une pierre de rencontre listée plusieurs fois
    est dédoublonnée.
- **Travel, calcul** :
  - `Nearest(loc)` : checkpoint débloqué le plus proche sur le même continent (à vol d'oiseau), plus
    un checkpoint encore plus proche mais verrouillé ; `approx` quand la position est le centre de
    la zone (`FormatDistance(m, approx)` ajoute « ~ »).
  - `Entrance(loc)` : pour un lieu sans position (carte d'une instance, zone d'un raid),
    la pierre de rencontre (`kind` `MEETINGSTONE*`) dont le nom normalisé (minuscules, lettres et
    chiffres) égale le fichier de carte (`BlackTemple`, le même dans toutes les langues) ou le nom
    du lieu ; `Nearest` part alors de sa position (`near.entrance`).
  - `Sources(itemId)` : une entrée par monstre de chaque lieu, triée : pénalité (périmée 2, lieu
    réseau vieux de 90 jours 1), puis **drops vus** (max de `loc.seen` et de
    `Evidence.Drops(tome, monstre)`), puis accès (1 : checkpoint ; 1,5 : depuis le centre de la
    zone ; 2 : pas de checkpoint sur ce continent ; 3 : sans position), distance, ordre.
  - `Best` : la première source de cet ordre qu'un checkpoint dessert, sans passer d'une bonne
    source à une périmée. `GoBest` la vise ; il refuse si le joueur est déjà plus près d'une source
    que tout checkpoint.
  - `GoTo` exécute `UseCheckpoint(id)` : jamais en combat, démontage au sol, une demande toutes les
    3 s. La confirmation est une option (`confirmTeleport`).

### Loot.lua (tomes obtenus)
Un tome peut arriver de deux façons.
1. **Fenêtre de butin** : la ligne « You receive loot » arrive. Le mob est l'unité morte survolée
   (cadavre cliqué), sinon la cible morte, capturée à LOOT_OPENED. La source n'est valable que si la
   fenêtre est ouverte, ou fermée depuis 5 s au plus. Dès LOOT_OPENED, chaque tome présent dans les
   emplacements (`GetLootSlotLink`) est envoyé comme lieu de drop et émet `TOME_DROPPED`, pris ou
   non (sacs pleins, jet gagné par un autre) ; le ramasser ensuite ne renvoie rien (même lieu).
2. **Œil du charognard** (Scavenger's Eye, Toolbelt d'Ebonhold) : il ramasse lui-même et dépose dans les sacs **sans
   aucune ligne de chat**.
   - **Détection** : en comparant le nombre de tomes des sacs 0 à 4 à chaque `BAGS_CHANGED`. Sont
     ignorés :
     - les hausses quand une fenêtre d'échange est ouverte (ou l'était au BAG_UPDATE brut) :
       marchand, banques (dont la banque étendue et le stockage du Vide), courrier, échange, HV,
       métier, quête, gossip, boutique, achat, extraction ;
     - les 10 s qui suivent un écran de chargement ;
     - les objets déjà annoncés par leur ligne de chat (pas de double alerte).
   - **Mob** : le journal de combat retient les créatures touchées par soi ou le groupe, ou qui nous
     attaquent, puis mortes (`UNIT_DIED`), avec les sorts qu'on les a vues lancer (`SPELL_*`, 16 max
     par créature). `Hints.Attribute` choisit parmi les morts de la dernière minute ; la position est
     celle du joueur.

`Loot.Obtained(itemId)` déclenche l'alerte wishlist, puis `Net.Report` avec la source (ou les
candidats), et émet `TOME_OBTAINED` pour l'addon de dev.

### Hints.lua (Œil du charognard)
- **Indice** : `H.Parse(texte)` transforme la phrase « Can be found on … » de ProjectEbonhold en test :
  noms de créatures, sorts (anglais : listes par classe, soins, « stun », « caster dots »…), type
  de créature, classes, mots du nom (éléments). `H.Matcher(itemId)` le met en cache par texte.
- **Ce qu'on voit des monstres** : classe et type de créature (clé anglaise, noms localisés en
  anglais, français, allemand, espagnol) par id de PNJ, appris au survol, au ciblage, et sur les
  plaques de nom (`nameplateN`, unités du client Ebonhold ; `NAME_PLATE_UNIT_ADDED` et relecture des
  40 premières toutes les 2 s en combat). 2000 PNJ au plus, pour la session.
- **Score** (`H.Score`) : fort (3) nom de l'indice, sort de l'indice vu, bon type (−3 si autre
  type) ; moyen (2) bonne classe (−1 si autre), source connue du tome (`H.KnownSources` : lieux et
  noms de l'indice) ; faible (1) un mot de l'indice dans le nom.
- **Attribution** (`H.Attribute`) : un seul monstre → lui ; sinon le meilleur s'il vaut au moins 2 et
  dépasse strictement le suivant ; sinon jusqu'à 4 candidats, les mieux notés puis les plus récents
  (un indice faible n'écarte personne).


### Net.lua / Link.lua / NetApi.lua (réseau entre joueurs)
- **Partage des rôles** : `Net.lua` tient les **données** (lieux de chaque tome, fusion, textes des
  jeux de données) ; un **transport** les porte entre les joueurs. `Net.Connect()` choisit
  `ns.Link` (par défaut) ou `ns.NetApi` si la constante `USE_EBONAPI` (en tête de `Net.lua`, `false`)
  est vraie. Les deux offrent les mêmes fonctions : `Connect`, `Ready`, `Start`, `Stop`,
  `Changed(nom)`, `Joined`, `Sync`, `Say(op, corps)`, `Listen(op, fn)`, `Count`, `Newer`
  (+ `PeerCount`, `Stats`, `SeeVersion` pour `Link`). `Net.lua` appelle `Net.Import(nom, texte)` à la
  réception et `transport.Changed(nom)` quand un jeu change (`Publish`, 3 s plus tard, changements
  groupés). `Net.DatasetNames / DatasetText / DatasetKnown` disent au transport ce que nous gardons.
- **Link.lua** (le réseau maison) : canal de discussion caché `ebontomehunternet` (le 3.3.5a stock n'a
  pas de canal d'addon pour tout le royaume). Version du protocole `E4` en tête de chaque ligne. Rien
  n'est envoyé pour comparer les données sauf des **empreintes**, et seules les lignes qui manquent
  partent (une ligne = un lieu, une source ; le texte d'un jeu = lignes séparées par `;`). Messages :
  - `P nom~ligne;ligne` : lignes nouvelles (un drop = une ligne ; résultat d'une fusion) ;
  - `A F~jeux~version` : annonce de l'empreinte globale `F` de tout ce que nous gardons, à la
    connexion puis toutes les 15 min (+ 0 à 2 min) par **un seul** joueur : entendre un `A` remet
    le minuteur des autres ;
  - `B F~paquets` : réponse à un `A` d'empreinte différente : les empreintes des 48 paquets
    (id d'objet modulo 48) ; les joueurs qui ont les mêmes données répondent une fois ;
  - `L paquet!nom=hash,…` : l'annonceur liste ses jeux des paquets qui diffèrent ;
  - `D nom~hash~i~n~lignes` : texte complet d'un jeu dont l'autre a une autre version (ou aucune) ;
    qui sait plus de lignes répond par un `P` ;
  - `G nom,nom,…` : « envoyez-moi ces jeux » ;
  - `X op~id~i~n~texte` : message libre en morceaux (statistiques `KQ` / `KA`).
  - **Débit** : une ligne de 240 caractères au plus (jamais de `|`) toutes les 0,4 s (AzerothCore
    rend muet un client qui envoie 10 lignes en une seconde). Les réponses attendent un délai
    aléatoire et sont **annulées** si un autre joueur les a données entre-temps ; des disjoncteurs
    (3 réponses par jeu en 10 min, 3 textes de joueurs en cours d'envoi) arrêtent les échanges sans
    fin. Les lignes reçues sont validées par `Net.lua` et `Evidence.lua` comme toute donnée d'un
    joueur.
  - **Mesures du banc de test** : joueurs à jour = 1 ligne par quart d'heure pour tout le réseau,
    quel que soit leur nombre ; un nouveau venu sans donnée face à 1 287 lieux (160 tomes × 8) est
    complet en environ 4 min, pour environ 730 lignes envoyées par les autres, à environ 3 lignes/s.
  - **Canal** : rejoint seulement quand le client a rendu ses canaux au joueur (liste de
    `GetChannelList` stable, 8 s au moins après la connexion, 30 s au plus), car rejoindre pendant
    la restauration change leurs numéros et casse l'envoi. Il prend l'une des **10 places** de canaux
    du personnage : si les 10 sont prises, `NetChannelsFull` une fois, puis nouvel essai tout seul
    dès qu'une place se libère (sans insister : 10 s, puis 300 s entre deux essais). Le canal et ses
    notices « joint / quitté » sont masqués de toutes les fenêtres de discussion.
  - **Diagnostic** : `Link.Stats()` (lignes envoyées / reçues) et `Link.PeerCount()` (joueurs
    entendus depuis moins de 30 min) alimentent `/eth net` et l'infobulle du bouton Réseau.
- **NetApi.lua** (gardé de côté) : l'adaptateur de l'addon EbonAPI (Siphelis), jamais copié ni modifié
  (licence). Chaque jeu de données `Net.lua` est un jeu EbonAPI : `EbonAPI:NewAddon("EbonTomeHunter",
  1, 0)` sous `pcall` (nil : absent ou trop ancien), `Version`, `ShareRule(Accept)` (seulement nos
  noms `T` / `E` + id, état plus grand que le nôtre et pas plus d'un jour dans le futur),
  écouteurs `SHARE_RECEIVED`, `CHANNEL_JOINED`, `CHANNEL_LOST`, `READY` (collant), opérations de
  canal `KQ` / `KA`. **État** d'un jeu = `max(time() × 1000, état gardé + 1)` + somme de contrôle du
  texte (0 à 999) : deux textes différents publiés dans la même seconde n'ont pas le même état.
  Désactivé depuis 3.4.0 (EbonAPI ne marche plus bien depuis la mise à jour v2 du serveur) ;
  `USE_EBONAPI = true` y revient, à tester quand il sera corrigé.
- **Jeu de données par tome** `T<itemId>` : `lieu;lieu;…` (12 max, `Better` : plus de joueurs, puis
  plus récent, puis texte), lieu = `itemId^mapFile^x^y^npcId^mob^zone^trouvé^trouveur^joueurs^candidats`
  (x, y de 0 à 1000 ; `candidats` = `npcId:Nom,…` seulement sans mob, triés par id puis nom, 200
  octets par lieu au plus). Noms nettoyés de `~^;|` et des caractères de contrôle, coupés sans casser
  un caractère UTF-8.
- **Publication** (`Publish` → `Flush` 3 s après, changements groupés) : `transport.Changed(nom)` ;
  `Link` relit le jeu et, si son texte a changé, envoie en `P` les lignes que les autres n'ont pas
  encore vues (`Net.HasNews`).
- **Réception** (`Net.Import(nom, texte)`, appelée par le transport) : `ImportPlaces` décode
  chaque lieu (`Net.Decode` : pas de `|` ni de contrôle, au moins 9 champs, tome du catalogue, x et
  y de 0 à 1000, date plausible gardée telle que dite (même un peu en avance sur notre horloge : un seul texte pour tous), un monstre ou des candidats), `Net.Add` le
  fusionne, et renvoie aussi si notre texte a une ligne que le reçu n'a pas (`Net.HasNews`), pour que
  le transport réponde.
- **Sans monstre ni candidats** (versions anciennes) : refusé à la réception, jamais publié, retiré
  de la sauvegarde au démarrage (`Tidy`). Alerte wishlist pour un lieu nouveau trouvé depuis moins d'1 h.
- **Fusion** (`Net.Add`, `SameSpot`) : même carte, moins de 4 % d'écart, même monstre (ou candidats
  compatibles). Le lieu gagne le trouveur (10 max) ou le nombre dit (`n`), la date la plus récente, le
  monstre s'il manquait ; deux listes de candidats se réduisent à leur intersection (`Narrow`), un
  seul restant devient le monstre (`inferred`). **Affinage** (`Refine`, après chaque réception ou
  drop, et au démarrage) : un lieu à candidats dont un seul est une source connue du tome (lieu
  confirmé n'importe où, `Hints.KnownSources` : EbonholdHub, indice du serveur) prend ce
  monstre (`inferred`) et fusionne avec un lieu de ce monstre au même endroit ; plusieurs sources
  connues parmi les candidats : le doute reste. `Converge` rend les champs identiques sur tous les
  clients : plus petit nom de trouveur, plus petit point (millièmes), texte de zone le plus long puis
  le plus grand.
- **Démarrage** (`Start`, quand le transport et le catalogue sont prêts) : `transport.Start()` ;
  `Link` lit nos jeux (6 par tick, sans à-coup à la connexion), rejoint le canal, puis annonce
  15 à 30 s après y être entré. Même chose quand le réseau est rallumé (`SETTINGS_CHANGED`).
- **Sans transport** (seulement si `USE_EBONAPI` est vrai et EbonAPI absent ou trop ancien) : les
  lieux restent locaux ; `NetNeedApi` une fois par version, 20 s après `LOGIN` (`DB.apiHint`).
- **État** (`Net.SyncState()`) : `off`, `noapi` (voir ci-dessus), `joining` (canal pas encore
  rejoint), `online` ; `Net.DatasetCount()` = nos tomes sur le réseau. `Net.ForceSync()`
  (`/eth net sync`, bouton) : `transport.Sync()`, 30 s entre deux annonces forcées.
  `Net.NewerVersion()` : la plus récente version entendue (`A` d'un autre joueur). `Net.TrafficText()` :
  lignes envoyées / reçues et joueurs entendus (`/eth net`).
- **Statistiques** (`/ethdev stats`) : `transport.Say("KQ", qid)` ; chaque client répond après 1 à 5 s, au
  plus toutes les 30 s, `KA` `qid^total^npcId:n;…` (60 créatures ; `Link` les découpe en messages `X`). `Net.RequestStats()` rassemble les réponses 15 s et émet `NET_STATS`
  { [nom] = { total, kills } }. Compteurs : `Loot.CountKill` à chaque `UNIT_DIED` d'une créature
  combattue, `DB.killStats[npcId] = { n, name, last }`, 600 au plus.

### Evidence.lua (sources périmées)
- **Source** = un monstre listé pour un tome (EbonholdHub, ou lieu du réseau). Clé du monstre :
  `#npcId` (même clé dans toutes les langues du client), sinon le nom en minuscules ; une source
  est cherchée sous ses deux clés.
- **Nos cadavres** (`corpses[itemId@mob] = { n, since, drop, total, drops, stamp }`) : à
  l'ouverture du butin d'un cadavre (`CORPSE_OPENED`, GUID compté une seule fois) d'un monstre listé
  pour des tomes, chaque tome absent de ce cadavre compte +1 (`n` et `total`) à la fermeture (+5 s de
  grâce). Un tome looté, ou seulement présent dans la fenêtre de butin, remet `n` à 0 et compte un
  drop (`drops`, `total` gardé : le taux de la source), même pour un monstre non listé
  (`TOME_DROPPED`). L'Œil du charognard n'est pas compté (on ne sait pas quels cadavres il ramasse).
- **Partage** : jeu de données `E<itemId>`, une ligne par source et par joueur,
  `mob^joueur^n^depuis^dernierDrop^total^drops^signalement^tampon` (triées par mob puis joueur).
  Seules les lignes utiles circulent : ≥ 100 cadavres sans le tome, un signalement, ou notre propre
  ligne une fois partie (`told` : sa remise à 0 et un signalement retiré suivent). Les drops passent
  par les lieux (`T<itemId>`). Notre ligne part tous les 100 cadavres et à chaque signalement
  (`stamp` = maintenant, `Net.PublishEvidence`). **Notre propre ligne dit le compteur tel qu'il était
  à la dernière annonce** (multiple de 100 cadavres, `SharedText`) : le texte, donc son empreinte,
  ne change pas à chaque cadavre. Reçu (`ImportShared`) : pour chaque (source, joueur), la ligne au tampon le
  plus récent (la nôtre aussi : un nouvel ordinateur retrouve ses compteurs) ; refusées : `|` ou
  contrôle, drops > total, valeurs ou dates impossibles. 50 joueurs max par source, les mêmes sur chaque client : ceux dont on a entendu parler en dernier (tampon du compteur ou signalement), puis par nom (`MakeRoom` à la réception, `Capped` dans le texte). Les filtres de caractères sont écrits en octets (`%z\1-\31\127`), pas avec `%c` / `%s` qui suivent les réglages régionaux de la machine. Au-delà de
  30 000 octets (limite d'EbonAPI, 32 Ko par jeu, gardée), seules les lignes les plus récentes partent (tampon,
  puis texte : le même choix sur chaque client).
- **Verdict** : dernier drop connu = max(nos drops, ceux des autres, lieux du réseau de ce tome avec
  ce monstre). Ne comptent que les compteurs commencés après ce drop et les signalements postérieurs.
  - **Seuil** (`E.Threshold`) : taux = (drops + 1) ÷ (cadavres + 200) sur l'historique de chaque
    compteur (`total − n` : sans la série en cours, qu'on juge) ; seuil = ⌈ln 0,01 ÷ ln (1 − taux)⌉
    borné à [500, 5000] (1 % laissé à la malchance).
  - Périmée si cadavres ≥ seuil (un autre joueur pèse la moitié du seuil au plus : il en faut deux,
    ou soi-même seul), ou ≥ 3 signalements, ou notre propre signalement (pour nous seulement).
  - `E.Verdict` renvoie aussi `oneIn` (1 ÷ taux, affiché « d'habitude 1 sur N ») et le seuil.
- **Drops vus** (`E.Drops`) : somme des `drops` de notre compteur et de ceux des autres joueurs pour
  ce tome et ce monstre ; sert à l'ordre des sources (catalogue, `Travel.Sources`).
- **Effets** : `Travel.Sources` classe bonnes sources, puis lieux réseau vieux de plus de 90 jours,
  puis sources périmées (la TP vise la meilleure) ; `Catalog.AttachSightings` préfère un lieu dont
  tous les monstres ne sont pas périmés ; la fenêtre Sources grise la ligne avec la raison, et son
  bouton « Plus bon ? » signale / retire.

### Comm.lua (envoi direct)
`SendAddonMessage("ETH", msg, "WHISPER", nom)` :
- `WL:<id>:<part>:<parts>:<tranche de 200>` : la chaîne de partage, découpée.
- `WLA:<id>:<n>` : accusé de réception.
- `WLN:<id>` : refus (option du destinataire).

Pas de réponse en 12 s : message « pas de réponse ». Anti-spam : 3 offres par minute et par
expéditeur.

### Share.lua (chaîne de partage)
Format `ETH1:<auteur>:<entrées>:<contrôle>` :
- les entrées sont triées par id, `<id − 300000>[x<qté>]`, ou `#<id>` hors de cette plage ;
- le contrôle vaut 6 chiffres hexadécimaux de `h = (h × 31 + octet) mod 16777213` sur tout ce qui
  précède.

Les chaînes `ETP1:` de l'ancien nom sont encore lues. Une chaîne tronquée ou modifiée est refusée.
Exemple : `ETH1:Bob:22x3,569x2,570:3f38d1`.

**Build Echo Builder** (`S.DecodeEchoBuild`, essayé avant la chaîne `ETH1`) : on cherche
`echo-builder…?b=` dans le texte (lien, ou texte « Copy build » qui finit par le lien), sinon un build
seul `2xxxxx[-…]`. `%21`, `%2D`, `%2E` sont décodés. Partie avant `!` (après : Echos verrouillés,
ignorés), jetons `id` ou `id.piles`, ids de 200000 à 299999, chacun une fois. `Catalog.FindBySpell(id)`
(id exact de l'Echo débloqué par un tome) → tome à ajouter (1 exemplaire, dédoublonné), ou déjà appris
(`Known.IsKnown`) ; pas de tome → Echo de base, nommé par `GetSpellInfo`. `c=` donne la classe
affichée. Résultat marqué `echoBuild` ; l'aperçu et `S.Import` affichent les trois groupes.
Données de référence du site : `https://project-ebonhold.com/assets/dbc/echoes.json` (546 Echos,
dont 157 avec un tome, tous dans `TomeData.lua`).

### UI.lua / AuctionHouse.lua / Tutorial.lua
- **Fenêtre principale** (780×540, 16 lignes de 24 px, liste virtuelle `W.List`).
  - `UI.parts` expose ses éléments au tutoriel.
  - `UI.Show(itemId)` fait défiler jusqu'au tome et le fait clignoter.
- **HV** : les onglets sont créés au chargement de Blizzard_AuctionUI (`AuctionTabTemplate`, après
  ceux de Blizzard et d'Auctionator). Un `hooksecurefunc("AuctionFrameTab_OnClick")` affiche le
  panneau, avec deux listes virtuelles et les boutons Acheter / Actualiser / Fermer.
- **Tutoriel** : 14 étapes, chacune `{ title, text, target(), side }`.
  - La cible est résolue à l'affichage.
  - Le cadre lumineux est non cliquable (`EnableMouse(false)`) ; la bulle est bornée à l'écran.
  - `VERSION` (à monter quand on ajoute des étapes) est comparée à `DB.tutorialDone`.

## Choix et contraintes à connaître

- Tout accès à ProjectEbonhold passe par `ns.PE` et reste en lecture seule. L'addon est testé
  **avec et sans** ProjectEbonhold.
- Les lieux d'EbonholdHub sont lus en jeu, jamais copiés ni modifiés.
- EbonAPI est gardé de côté (`NetApi.lua`, `USE_EBONAPI = false`) et reste une dépendance facultative
  installée à part : jamais copiée, jamais modifiée (licence). Le réseau n'en a pas besoin.
- Le réseau prend l'une des 10 places de canaux de discussion du personnage, et n'est rejoint
  qu'une fois les canaux rendus par le client (voir Link.lua ci-dessus).
- Le réseau et les chuchotements valident tout ce qu'ils reçoivent. Aucune donnée reçue n'est
  exécutée.
- Les listes sont virtuelles (quelques lignes recyclées, jamais une frame par tome). Les frames ne
  se détruisent pas en WoW : elles sont créées une fois, à la première ouverture.
