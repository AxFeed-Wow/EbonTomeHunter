# EbonTomeHunter — addon World of Warcraft 3.3.5a pour le serveur Project Ebonhold

**Réponds en français à l'utilisateur.** Le code et ses commentaires sont en anglais ; les textes
affichés en jeu existent en anglais et en français (`Locale.lua`).

## En bref

EbonTomeHunter (anciennement *EbonTomePrices*, renommé en 2.0.0) aide à **trouver, acheter et
farmer les tomes d'Echo** de Project Ebonhold (serveur WotLK 3.3.5a « Rogue-Lite ») :
- prix relevés à l'hôtel des ventes (HV), avec achat depuis deux onglets ajoutés à l'HV ;
- wishlist par personnage ;
- tomes déjà appris ;
- lieux de drop sur la carte du monde et téléportation au checkpoint le plus proche des monstres ;
- liens Wowhead (WotLK) des monstres ;
- réseau caché entre utilisateurs qui partage les lieux de drop ;
- alertes de loot (y compris le familier *Greedy Scavenger*) ;
- partage de wishlist ;
- tutoriel en jeu.

Tout le détail visible par le joueur : `docs/FEATURES.md`.

- Client : WotLK **3.3.5a build 12340, Lua 5.1**. L'erreur n°1 est d'écrire du code *retail*
  (`SetColorTexture`, `C_Timer`, `BackdropTemplate`, `IsInGroup`…) : il plante en jeu.
  Voir `docs/WOW-335.md` **avant toute modification**.
- Serveur : Project Ebonhold, avec son addon serveur `ProjectEbonhold` (voir `docs/EBONHOLD.md`).

## Carte du dépôt

```
CLAUDE.md                 ce fichier (lu automatiquement)
README.md                 page GitHub, bilingue anglais / français (présentation, installation, commandes)
CONTRIBUTING.md SECURITY.md  contribuer, signaler une faille (bilingues)
CHANGELOG.md              historique des versions (l'entrée d'une version = notes de sa release)
LICENSE                   MIT, © AxFeed-Wow
.github/                  CI (workflows/check.yml), release sur tag (workflows/release.yml),
                          formulaires d'issues, modèle de pull request
.gitattributes            fins de ligne ; exclut tests/ de l'archive installée par Ebonhold Addon Manager
EbonTomeHunter/           L'ADDON = ce qui est copié dans Interface/AddOns/EbonTomeHunter
  EbonTomeHunter.toc      ordre de chargement des fichiers, SavedVariables, version
  *.lua                   un fichier par module (rôle de chacun : docs/ARCHITECTURE.md)
  TomeData.lua MapData.lua  GÉNÉRÉS depuis le client (tools/extract_ebonhold_data.py) : ne pas éditer
  tests/scenario.lua      scénario de test hors jeu (jamais installé ni publié dans le zip)
tools/                    validation, tests, installation, publication, extraction de données
reference/data/           données extraites du client (régénérables) + itemcache_seen.json (à garder)
docs/                     documentation détaillée (index ci-dessous)
```

## Démarrer une session (machine neuve)

1. Python 3.10+ puis `pip install lupa mpyq` (`lupa` : Lua 5.1 du validateur ; `mpyq` : lecture
   des archives MPQ du client, seulement pour l'extraction de données).
2. `python tools/check.py` → doit afficher `ALL CHECKS PASSED`. C'est l'état de référence.
3. Dossier du jeu : par défaut `C:/ebonhold` (sinon variable d'environnement `WOW_DIR`, ou
   `--wow <dossier>` des outils). Demander à l'utilisateur s'il est ailleurs sur cette machine.

## Règles d'or (non négociables)

1. **API 3.3.5a uniquement** (`docs/WOW-335.md`). Dans le doute, chercher le nom dans
   `tools/api_globals_335.txt` / `tools/api_events_335.txt`, sinon protéger par `type(X) == "function"`.
2. **ProjectEbonhold en lecture seule** : passer par `ns.PE.Service/Call` (fail-closed), ne jamais
   écrire dans ses tables, ne jamais appeler `ProjectEbonhold.onEventReceived` (il écrase son handler).
   L'addon doit marcher (en mode dégradé) **sans** ProjectEbonhold : le validateur teste les deux cas.
3. **Données d'EbonholdHub** (lieux de drop) : « All rights reserved » → lues en jeu à l'exécution,
   **jamais copiées** dans ce dépôt.
4. **Ne jamais commiter ni publier** : la source de ProjectEbonhold (`_extracted/`, locale),
   les SavedVariables / `WTF` de l'utilisateur, des noms de personnages ou de compte réels, les
   données d'EbonholdHub. `.gitignore` couvre les dossiers ; relire les diffs quand même.
5. **Tout texte affiché** passe par `ns.L.Clé`, avec la version anglaise ET française.
6. **Un seul global public** : `EbonTomeHunter` (= `ns`), plus `EbonTomeHunterDB`,
   `EbonTomeHunterCharDB` (SavedVariables) et `SLASH_EBONTOMEHUNTER*`. Tout le reste est `local`.
7. **Pas de bibliothèque externe** (Ace3, LibDBIcon…) : `Widgets.lua` fournit le kit d'UI.
8. **Actions à conséquences** (acheter, téléporter, envoyer des messages) : une à la fois, avec
   délai, jamais en combat quand c'est protégé, confirmation disponible en option.
9. **Après chaque modification : `python tools/check.py`**. Il faut 0 erreur ET 0 avertissement, en
   anglais et en français, et une locale complète. Toute logique nouvelle ou corrigée doit avoir
   son test dans `EbonTomeHunter/tests/scenario.lua` (voir `docs/DEVELOPMENT.md`).
10. Le faux client est permissif : « OK » ne garantit pas le comportement en jeu. Relire la
    logique (ordre de chargement, `nil` de `GetItemInfo`, combat) et le dire franchement à
    l'utilisateur quand rien n'a été testé en jeu.

## Faire une modification (workflow)

1. Lire les modules concernés (`docs/ARCHITECTURE.md` dit qui fait quoi) et `docs/WOW-335.md`.
2. Coder dans le style existant : modules `ns.X`, bus `ns.On/ns.Fire`, évènements via
   `ns.RegisterEvent`, timers `ns.Timer.After`, UI avec `ns.Widgets`, options dans
   `DB_DEFAULTS.options` (Core.lua) + une case dans `Options.lua`.
3. Ajouter / adapter le scénario de test, puis `python tools/check.py` jusqu'à ALL CHECKS PASSED.
4. Mettre à jour la doc touchée (`docs/FEATURES.md`, `README.md`, `docs/ARCHITECTURE.md`) et une
   entrée dans `CHANGELOG.md` ; monter la version (`Core.lua` `ns.version` ET `.toc` `## Version`)
   quand c'est livré.
5. Installer en jeu si l'utilisateur le veut : `python tools/install.py` (sauvegarde l'ancienne
   version dans `backups/`, vérifie la copie). **Nouveau fichier dans le `.toc` → redémarrage complet
   du jeu** (un `/reload` ne charge pas les fichiers ajoutés) ; sinon `/reload` suffit.
6. Résumer à l'utilisateur, en français : ce qui change, ce qui a été vérifié, ce qu'il doit
   tester en jeu (`/console scriptErrors 1` affiche les erreurs Lua ; `C:/ebonhold/Logs/FrameXML.log`
   pour les erreurs de chargement).

## GitHub et livraison

Dépôt : **github.com/AxFeed-Wow/EbonTomeHunter** (compte `gh` : AxFeed-Wow). Détail : `docs/RELEASING.md`.
- **`main` = ce que reçoivent les joueurs** : Ebonhold Addon Manager (le logiciel de l'utilisateur)
  installe la branche `main` et propose la mise à jour quand le `## Version` du `.toc` change. Les
  releases ne servent qu'à l'installation à la main.
- Livrer : branche → `tools/check.py` → version (2 endroits) + CHANGELOG → `main` → tag `vX.Y.Z`
  poussé → le workflow `Release` construit le zip et crée la release.
- **Ne rien pousser (ni branche `main`, ni tag) sans demande explicite de l'utilisateur.**
- Commits avec l'identité git déjà configurée (adresse noreply de GitHub) : ne pas la changer.

## Environnement (pièges vécus)

- Windows + Git Bash : dans un heredoc bash, les `\` peuvent être mangés (`\1` devient un octet 0x01).
  Pour écrire du code ou des scripts contenant des antislashs, utiliser les outils Write/Edit ou un
  fichier de script, pas `python - <<EOF`.
- Le jeu **réécrit les SavedVariables à la fermeture** : ne jamais modifier `WTF/` jeu ouvert
  (voir `tools/migrate_savedvariables.py`).
- `C:/ebonhold/Cache/WDB` est vidé par le client de temps en temps : l'extraction garde les tomes déjà
  vus dans `reference/data/itemcache_seen.json` (ne pas le supprimer).

## Décisions déjà prises avec l'utilisateur

- Nom : EbonTomeHunter, commandes `/eth` et `/tomehunter`. Licence MIT, auteur affiché **AxFeed-Wow**.
- Présentation GitHub calquée sur AxFeed-Wow/EbonholdAddonManager (README bilingue, CONTRIBUTING,
  SECURITY, CI). Les mises à jour automatiques passent par ce logiciel, pas par l'addon.
- Limite des 10 canaux de discussion de WoW (« You can only be in 10 channels at a time. ») : quand
  le personnage est déjà dans 10 canaux, le réseau ne rejoint pas son canal caché. Décision : ne pas
  contourner, le signaler comme limite connue (README, `docs/FEATURES.md`).
- Téléportation **directe** au clic (la confirmation reste une option désactivée par défaut).
- Réseau activé par défaut (sinon personne ne partagerait), désactivable dans les options.
- Import des Echoes verrouillés **retiré** (jugé inutile) : ne pas le remettre.
- Liens Wowhead : monstres seulement (les tomes d'Ebonhold n'existent pas sur Wowhead).
- Un tome qui tombe sur plusieurs monstres / lieux : la téléportation vise la source dont le
  checkpoint est le plus proche ; la fenêtre *Sources* permet d'en choisir une autre.

## Index de la documentation

| Fichier | Contenu |
|---|---|
| `docs/FEATURES.md` | chaque fonctionnalité, ce que voit le joueur et comment elle marche exactement |
| `docs/ARCHITECTURE.md` | modules, ordre de chargement, bus de messages, données sauvegardées, protocoles, algorithmes |
| `docs/DEVELOPMENT.md` | outils, validateur et faux client, écrire un test, recettes (option, texte, module…), débogage |
| `docs/WOW-335.md` | règles du client 3.3.5a / Lua 5.1 : ce qui existe, ce qui n'existe pas, pièges |
| `docs/EBONHOLD.md` | ce que l'addon utilise de Project Ebonhold : services, messages serveur, IDs, familier… |
| `docs/DATA.md` | TomeData / MapData, extraction depuis le client, quand régénérer |
| `docs/RELEASING.md` | qui reçoit quoi (logiciel = `main`), versions, releases sur tag, CI, ce qui ne doit jamais être publié |
