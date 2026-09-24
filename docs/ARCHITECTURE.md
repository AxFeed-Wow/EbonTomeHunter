# Architecture du code

Addon Lua 5.1 pour le client WotLK 3.3.5a. Environ 7 500 lignes réparties en 24 modules, un
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
| 3 | `TomeData.lua` | **généré** : les 148 tomes (`ns.TomeData[itemId]`) | | |
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
| 17 | `Net.lua` | réseau caché entre utilisateurs `ns.Net` | CHAT_MSG_CHANNEL | LOGIN, SETTINGS_CHANGED → SIGHTINGS_CHANGED |
| 18 | `Comm.lua` | envoi direct de wishlist (chuchotement d'addon) `ns.Comm` | CHAT_MSG_ADDON (préfixe ETH) | |
| 19 | `Loot.lua` | tomes obtenus : alertes + lieu de drop `ns.Loot` | LOOT_OPENED, LOOT_CLOSED, CHAT_MSG_LOOT, COMBAT_LOG_EVENT_UNFILTERED, BAG_UPDATE, PLAYER_ENTERING_WORLD | BAGS_CHANGED, READY |
| 20 | `UI.lua` | fenêtre principale `ns.UI` | | CATALOG_CHANGED, WISHLIST_CHANGED, PRICES_CHANGED, KNOWN_CHANGED, SCAN_STATE, SETTINGS_CHANGED, READY |
| 21 | `AuctionHouse.lua` | onglets Tomes / Wishlist de l'HV `ns.AH` | AUCTION_HOUSE_SHOW, AUCTION_HOUSE_CLOSED | AUCTION_UI_LOADED, DATABASE_READY, SEARCH_RESULTS, … |
| 22 | `Minimap.lua` | bouton de minimap | | LOGIN, SETTINGS_CHANGED |
| 23 | `Options.lua` | panneaux Interface > AddOns (principal + « Réseau et alertes ») | | → SETTINGS_CHANGED |
| 24 | `Tutorial.lua` | tour guidé `ns.Tutorial` | | READY |

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
| `SIGHTINGS_CHANGED` | | lieux du réseau changés (Net) → le catalogue les rattache |
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
| `sightings[itemId]` | lieux de drop du réseau (12 max par tome) : `{ itemId, mapFile, x, y, npcId, mob, zone, at, by, finders = { [nom] = true } }` |
| `npcIds[nom de monstre en minuscules]` | id de PNJ appris (liens Wowhead) |
| `lastSync`, `syncFrom` | synchronisation réseau : dernière demande, point de reprise d'un gros rattrapage |
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
- Sans `TomeData`, repli sur `ProjectEbonhold.PerkDatabase` (lecture seule) et les lieux du hub.
- Index : `byItem`, `bySpell` (toutes les variantes d'Echo), `byName`, `byTomeName` (toutes les
  graphies), `byEchoKey`.
- `AttachSightings(row)` : `locations` = lieux statiques + lieux du réseau (`Net.Locations`), ceux
  qui ont un point sur la carte d'abord ; `location` = le premier.
- `LearnTome(name, itemId)` : tome vu à l'HV ou dans les sacs, gardé dans `DB.tomes` ;
  `AddLearnedRow` crée une ligne pour un tome inconnu.
- `MigrateKeys()` convertit les clés des anciennes versions (id d'Echo, nom) en item id.

### Scan.lua (HV)
- **Une requête à la fois**. Chaque page attend `CanSendAuctionQuery()` (15 s max), puis
  `QueryAuctionItems(nom, nil, nil, 0, 0, 0, page, false, nil)`. Sans réponse
  `AUCTION_ITEM_LIST_UPDATE` en 8 s, la page est renvoyée (2 fois au plus).
- **Scan complet** : requête « Tome of Echo », 60 pages max. Les annonces sont reliées à leur tome
  par l'item id du lien, le nom ne sert qu'en repli. On garde le prix unitaire le plus bas et le
  nombre d'annonces. Après un scan **complet**, les tomes absents passent à « pas en vente ».
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
    un checkpoint encore plus proche mais verrouillé.
  - `Sources(itemId)` : une entrée par monstre de chaque lieu, triée.
  - `GoBest` vise la source au checkpoint le plus proche. Il refuse si le joueur est déjà plus près
    d'une source que tout checkpoint.
  - `GoTo` exécute `UseCheckpoint(id)` : jamais en combat, démontage au sol, une demande toutes les
    3 s. La confirmation est une option (`confirmTeleport`).

### Loot.lua (tomes obtenus)
Un tome peut arriver de deux façons.
1. **Fenêtre de butin** : la ligne « You receive loot » arrive. Le mob est l'unité morte survolée
   (cadavre cliqué), sinon la cible morte, capturée à LOOT_OPENED. La source n'est valable que si la
   fenêtre est ouverte, ou fermée depuis 5 s au plus.
2. **Greedy Scavenger**, le familier d'Ebonhold : il ramasse lui-même et dépose dans les sacs **sans
   aucune ligne de chat**.
   - **Détection** : en comparant le nombre de tomes des sacs 0 à 4 à chaque `BAGS_CHANGED`. Sont
     ignorés :
     - les hausses quand une fenêtre d'échange est ouverte (ou l'était au BAG_UPDATE brut) :
       marchand, banques (dont la banque étendue et le stockage du Vide), courrier, échange, HV,
       métier, quête, gossip, boutique, achat, extraction ;
     - les 10 s qui suivent un écran de chargement ;
     - les objets déjà annoncés par leur ligne de chat (pas de double alerte).
   - **Mob** : le journal de combat retient les créatures touchées par soi ou le groupe puis mortes
     (`UNIT_DIED`). Si toutes les morts de la dernière minute sont le même mob, c'est lui ; sinon le
     lieu seul est envoyé. La position est celle du joueur.

`Loot.Obtained(itemId)` déclenche l'alerte wishlist, puis `Net.Report` avec la source.

### Net.lua (réseau caché)
- **Canal** : le canal de discussion `ebontomehunter` est rejoint 10 s après la connexion et retiré
  des fenêtres de chat. Des filtres masquent ses messages et ses notices. Son numéro est revérifié
  avant chaque envoi.
- **Format** : `ETHN1~<type>~<charge>`, 240 octets max, jamais de `|`, coupures sans casser un
  caractère UTF-8, un envoi toutes les 0,3 s.
  - `D` : un drop, `itemId^mapFile^x^y^npcId^mob^zone^heure^trouveur^appris` (x et y de 0 à 1000).
  - `Q` : demande de synchronisation, `qid^depuis`.
  - `S` : réponse, `qid~suite~enreg;enreg;…`. qid `0` : lieux envoyés sans demande.
  - `appris` (10e champ, depuis 2.1.0, ignoré par 2.0.0) : quand l'expéditeur a enregistré le lieu,
    sur son horloge. Chaque lieu stocké a son `rx` (notre heure d'enregistrement, remise à jour quand
    le lieu gagne un trouveur ou son mob) ; sans `rx` (données 2.0.0), on prend `at`.
- **Réception** : validation (tome connu, positions de 0 à 1000, date plausible, date future ramenée
  à maintenant).
- **Même endroit** : même carte, moins de 4 % d'écart, même mob. Le lieu gagne alors un trouveur
  (10 max). Un lieu sans mob fusionne avec le même endroit et récupère le mob s'il arrive ensuite.
- **Boîte d'envoi** (`netOutbox`) : une trouvaille à nous, faite sans autre utilisateur entendu
  depuis 30 min, y est gardée (encodée ; 50 max, 30 jours). Au premier message d'un utilisateur
  absent depuis 30 min, elle part en `S` qid `0`. Couper le réseau la vide.
- **Synchronisation** : 15 s après la connexion, au plus toutes les 10 min. La longueur du qid
  distingue deux sortes de demande :
  - **4 chiffres hexa (2.0.0)** : lieux *trouvés* après `depuis` (`at`), du plus ancien au plus
    récent ; celui qui a le plus à envoyer répond en premier, les autres voient la réponse et se
    taisent. Inchangé pour ne pas perturber la reprise des clients 2.0.0.
  - **5 chiffres hexa (2.1.0)** : lieux *appris* après `depuis` (`rx`). Chaque répondant note les
    lieux entendus dans les réponses à ce qid et, à son tour, n'envoie que ce qui manque.
  - Notre `depuis` : `syncFrom` (reprise) ; sinon `syncedAt` − 10 min (début de notre dernière
    synchro complète) ; sinon 0 si on n'a jamais demandé ; sinon (données 2.0.0) le lieu le plus
    récent − 10 min.
  - Réponses par 30 (sans couper une même seconde), drapeau « suite ». On reprend au plus bas point
    atteint par les répondants qui avaient une suite (5 lots par session), `syncFrom` sert de reprise.
  - Fin de session (4 s sans nouvelle partie, ou 12 s sans aucune réponse une fois la demande
    partie) : ligne `NetSynced` si des lieux sont arrivés ; puis, si quelqu'un a répondu ou est en
    ligne, envoi en qid `0` de nos lieux appris depuis `depuis`, avant la session, que personne n'a
    cités (60 max, les plus récents ; un lieu n'est renvoyé que s'il a changé).
  - Synchro inachevée (`syncedAt` < `lastSync`) : nouvelle demande quand un utilisateur absent
    depuis 30 min se manifeste (5 s après, au plus une par minute, 10 par session de jeu).
- **État** : `Net.IsJoined()` et `/eth net` regardent si le canal est vraiment rejoint (le jeu le
  refuse au-delà de 10 canaux).

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
- Les lieux d'EbonholdHub sont lus en jeu, jamais copiés.
- Le réseau et les chuchotements valident tout ce qu'ils reçoivent. Aucune donnée reçue n'est
  exécutée.
- Les listes sont virtuelles (quelques lignes recyclées, jamais une frame par tome). Les frames ne
  se détruisent pas en WoW : elles sont créées une fois, à la première ouverture.
