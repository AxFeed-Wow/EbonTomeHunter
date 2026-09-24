# Développer : outils, tests, recettes

## Installation de l'environnement

- Python 3.10 ou plus récent.
- `pip install lupa mpyq` : `lupa` embarque un vrai Lua 5.1 pour le validateur ; `mpyq` ne sert
  qu'aux outils qui lisent les archives du client.
- Le jeu : le client Project Ebonhold, par défaut dans `C:/ebonhold` (sinon `--wow <dossier>` ou la
  variable d'environnement `WOW_DIR`).

## Les outils (`tools/`)

| Commande | Rôle |
|---|---|
| `python tools/check.py` | **à lancer après chaque modification** : validateur en client anglais puis français, et contrôle de la locale. Il faut ALL CHECKS PASSED (0 erreur, 0 avertissement) |
| `python tools/validate_addon.py EbonTomeHunter` | le validateur seul, avec le détail des messages (`WOW_LOCALE=frFR` pour un client français) |
| `python tools/check_locale.py` | textes : anglais et français au complet, clés utilisées et définies |
| `python tools/install.py [--wow DIR] [--remove-legacy] [--dry-run]` | copie l'addon dans le jeu (sans `tests/`) après avoir sauvegardé la version installée dans `backups/`, puis vérifie octet par octet |
| `python tools/package.py` | `dist/EbonTomeHunter-<version>.zip` pour une release (vérifie que les versions du `.toc` et de `Core.lua` concordent) |
| `python tools/extract_ebonhold_data.py --lua-tomes EbonTomeHunter/TomeData.lua --lua-maps EbonTomeHunter/MapData.lua` | régénère les données depuis le client (voir `docs/DATA.md`) |
| `python tools/extract_pe_source.py` | extrait la source de ProjectEbonhold dans `_extracted/` pour la **lire** (jamais commitée) |
| `python tools/migrate_savedvariables.py [--dry-run]` | migration unique des sauvegardes de l'ancien nom (EbonTomePrices), jeu fermé |
| `tools/build_whitelist.py` | a produit `api_globals_335.txt` à partir du FrameXML 3.3.5a (rarement utile) |

## Relever des données en jeu (addon de dev)

`tools/dev/EbonTomeHunterDev/` : petit addon **pour l'utilisateur seul**, jamais publié (hors du
dossier de l'addon, donc ni dans le zip ni dans l'archive installée par Ebonhold Addon Manager).
- Installation : `python tools/install_dev.py --wow <dossier du jeu>`, puis **redémarrage complet**.
- `/ethdev dump` : photo en lecture seule (Echos de ProjectEbonhold + infobulles des Echos et des
  tomes, Echos appris, checkpoints, services de ProjectEbonhold et leurs fonctions).
- `/ethdev log on|off` : journal (cadavres ouverts avec id du monstre et position, tomes obtenus,
  codes des messages serveur `AAM0x9`). `/ethdev clear` vide tout.
- Le jeu n'écrit le fichier qu'au `/reload` ou à la déconnexion. À lire ensuite :
  `WTF/Account/<compte>/SavedVariables/EbonTomeHunterDev.lua` (données personnelles : ne jamais
  les copier dans le dépôt).
- La sauvegarde de l'addon lui-même (`SavedVariables/EbonTomeHunter.lua`) se lit de la même façon
  (lieux du réseau, compteurs de cadavres, ids de monstres), par exemple avec `lupa`.

Sur GitHub, le workflow `Check` (`.github/workflows/check.yml`) lance `tools/check.py` sous Linux à
chaque push et pull request, et le workflow `Release` construit la release à chaque tag `vX.Y.Z`
(voir `docs/RELEASING.md`).

## Le validateur et le faux client

`validate_addon.py` fait trois choses :
1. **Analyse statique.**
   - Syntaxe Lua 5.1 ; `.toc` (fichiers listés, SavedVariables).
   - Chaque nom global utilisé doit exister en 3.3.5a (`api_globals_335.txt`, 35 000 noms tirés du
     FrameXML).
   - Détection des API *retail* ; évènements connus du client (`api_events_335.txt`).
   - Textures référencées.
2. **Démarrage dans un faux client** (`wow_mock.lua`), **deux fois** : avec un faux ProjectEbonhold,
   puis sans. Chaque fichier est chargé dans l'ordre du `.toc`, puis viennent ADDON_LOADED,
   PLAYER_LOGIN, les commandes slash et les panneaux d'options.
3. **Scénario** `EbonTomeHunter/tests/scenario.lua`, exécuté dans ce faux client après le démarrage,
   avec et sans ProjectEbonhold. Environ 260 vérifications.

Ce que le faux client reproduit (fidèlement) :
- **SavedVariables :** comme le client, il **remplace les SavedVariables juste avant ADDON_LOADED**
  (sauvegarde ancienne et vide dans un passage, premier lancement dans l'autre).
- **Fenêtres de Blizzard** (marchand, banque, courrier, HV, quêtes, gossip…) : elles **démarrent
  fermées**, comme en jeu. Un test qui simule l'HV doit faire `AuctionFrame:Show()`.
- **Listes et champs :** `FauxScrollFrame_*` (barre, molette, décalage) ; `frame:GetPoint(i)` pour
  vérifier une position ; `EditBox:SetText` déclenche `OnTextChanged`.
- **Évènements inconnus :** un évènement inconnu du vrai client fait échouer `RegisterEvent`.

Il reste **permissif** : un « OK » ne prouve pas que ça marche en jeu. Il faut relire la logique
(ordre de chargement, `nil` possibles, combat) et dire à l'utilisateur ce qui reste à tester en jeu.

## Écrire un test (tests/scenario.lua)

Le scénario est un script Lua exécuté après le démarrage, avec ces fonctions :

| Fonction | Effet |
|---|---|
| `Fire(event, ...)` | déclenche un évènement du jeu |
| `CLEU(subEvent, srcGUID, srcName, srcFlags, dstGUID, dstName, dstFlags, ...)` | ligne de journal de combat |
| `Advance(secondes)` | fait avancer le temps (timers et OnUpdate) |
| `Player.health / maxHealth / combat / dead` | état du joueur (ex. `Player.combat = true`) |
| `Slash("/eth tp beast bane")` | exécute une commande |
| `Check(condition, "message")` | vérification (un échec = une erreur du validateur) |
| `ChatContains("texte")` | le chat contient-il ce texte ? |
| `Note("texte")` | ligne d'information dans le rapport (pratique pour déboguer) |

Techniques utilisées :
- **Remplacer une globale** du jeu pour simuler un état, par exemple
  `GetPlayerMapPosition = function() return 0.5, 0.5 end`,
  `UnitIsDead = function(unit) ... end` ou
  `ProjectEbonhold.CheckpointService = { GetCheckpoints = ..., UseCheckpoint = ... }` (dans la
  branche `if ProjectEbonhold then`).
- **Cliquer :** `bouton:GetScript("OnClick")(bouton)`, `ligne:GetScript("OnEnter")(ligne)`.
- **Popups :** remplacer `StaticPopup_Show` pour capturer l'appel, puis appeler
  `StaticPopupDialogs.X.OnAccept(nil, data)`.
- **Messages serveur ProjectEbonhold :**
  `Fire("CHAT_MSG_ADDON", "AAM0x9", code .. "\t" .. corps, "WHISPER", "Tester")`.
- **Réseau :** `Fire("CHAT_MSG_CHANNEL", texte, auteur, "", "5. ebontomehunter", "", "", 0, 5, "ebontomehunter")`.
- **Sacs :** redéfinir `GetContainerNumSlots` / `GetContainerItemLink` / `GetContainerItemInfo`,
  puis `Fire("BAG_UPDATE", 0)` et `Advance(2)`.
- **Ordre :** l'état est partagé d'une section à l'autre. Remettre ce qu'on a changé (options,
  fonctions remplacées), ou repartir d'un état propre au début de la section (voir le tutoriel).

Sections actuelles :
- catalogue ;
- migration des anciennes clés ;
- scan HV rejoué ;
- wishlist ;
- sacs ;
- carte du monde ;
- liste, tris et filtres ;
- tutoriel ;
- minimap ;
- tomes appris ;
- chaîne de partage ;
- marqueurs de carte ;
- liens Wowhead et Sources ;
- loot, réseau, synchronisation et Greedy Scavenger ;
- téléportation ;
- envoi direct ;
- onglets de l'HV : recherche et achat.

## Recettes

**Ajouter un texte affiché** : une clé dans la table anglaise `L` ET dans `fr` (Locale.lua). Côté
code : `L.MaCle` ou `format(L.MaCle, ...)`. `check_locale.py` signale tout oubli. Les textes du
serveur (noms d'Echoes, gossip) sont en anglais : comparer sur l'anglais.

**Ajouter une option** :
1. Une valeur par défaut dans `DB_DEFAULTS.options` (Core.lua).
2. Une case dans `Options.lua` (`W.CheckBox` + `Toggle("cle")`) avec ses textes.
3. La lire avec `ns.Opt().cle` au moment de l'usage. `ns.SetOption` émet `SETTINGS_CHANGED`.

**Ajouter un module** :
1. Un fichier `Nom.lua` qui commence par `local addonName, ns = ...` et `ns.Nom = {}`.
2. L'ajouter au `.toc` **après** les modules qu'il appelle au chargement.
3. En jeu, un nouveau fichier du `.toc` demande un **redémarrage complet**.

**Réagir à un évènement du jeu** : `ns.RegisterEvent("NOM", function(arg1, ...) end)` (plusieurs
modules peuvent écouter le même). Vérifier que l'évènement existe dans `tools/api_events_335.txt`.

**Appeler ProjectEbonhold** : `ns.PE.Call("Service", "Fonction", ...)`, ou
`ns.PE.Service("Service")` pour tester une présence. Toujours prévoir le cas où il est absent.
Pour savoir ce qui existe, lire sa source (`tools/extract_pe_source.py`) et `docs/EBONHOLD.md`.

**Nouveau message réseau** : garder la compatibilité, car les anciens clients ignorent un type
inconnu. Pour un changement de format incompatible, passer `ETHN1` en `ETHN2`. Toujours valider ce
qui est reçu, et rester sous 240 octets sans `|`.

**Les frames** : créées une seule fois (à la première ouverture), jamais recréées ; listes
virtuelles (`W.List`) pour tout ce qui est long.

## Conventions

- Code et commentaires en anglais ; commentaires brefs qui expliquent le **pourquoi**, surtout les
  contournements propres à 3.3.5a.
- Noms explicites, `local` partout.
- Actions à conséquences (achat, téléportation, envoi) : une à la fois, avec délai et garde-fous.
- Quand une donnée vient d'ailleurs (réseau, chuchotement, presse-papiers) : valider, limiter la
  taille, ne jamais l'exécuter.

## Déboguer en jeu

- `/console scriptErrors 1` affiche les erreurs Lua à l'écran.
- `C:/ebonhold/Logs/FrameXML.log` : erreurs de chargement (fichier absent du `.toc`, XML…).
  C'est le premier fichier à lire quand l'addon « ne fait rien ».
- `/eth net` : état du réseau ; `/eth help` : commandes.
- Après une modification : `/reload`, ou redémarrage complet si le `.toc` a de nouveaux fichiers.
