# Contributing to EbonTomeHunter

**English** | [Français](#contribuer-à-ebontomehunter)

Thank you for your interest. Bug reports, fixes, translations, documentation improvements and
feature ideas are welcome.

## Before contributing

Check the existing issues and pull requests first. For a significant change, open an issue to
discuss the approach before writing code.

## Reporting a bug

Use the [bug report form](../../issues/new?template=bug_report.yml). Useful information: the addon
version (top of its options panel, or `## Version` in `EbonTomeHunter.toc`), your client language,
the steps to reproduce, and the full Lua error if there is one (`/console scriptErrors 1` shows
them). Do not include your account name, password or other personal data.

## Feature requests

Use the [feature request form](../../issues/new?template=feature_request.yml): explain the problem
the feature solves, how you picture it, and why it is useful.

## Development setup

1. Python 3.10 or later, then `pip install lupa` (Lua 5.1 for the validator). `mpyq` is only needed
   to regenerate the data extracted from the game client (see `docs/DATA.md`).
2. `python tools/check.py` must print `ALL CHECKS PASSED`. It runs the validator and the test
   scenario (`EbonTomeHunter/tests/scenario.lua`) in a fake WoW client, with and without
   ProjectEbonhold, with an English and a French client, then checks the locale. 0 error and
   0 warning are required.
3. To try a change in game: `python tools/install.py` (add `--wow <game folder>` when the game is not
   in `C:/ebonhold`). A new file in the `.toc` needs a full restart of the game; otherwise `/reload`
   is enough.

The technical documentation is written in French, in [docs/](docs/). Read
[docs/WOW-335.md](docs/WOW-335.md) before changing any code, and
[docs/DEVELOPMENT.md](docs/DEVELOPMENT.md) to write a test.

## Rules

* **WoW 3.3.5a API only (Lua 5.1).** Retail code (`C_Timer`, `SetColorTexture`,
  `BackdropTemplate`, `IsInGroup`…) breaks in game. When in doubt, look the name up in
  `tools/api_globals_335.txt` and `tools/api_events_335.txt`.
* **Every displayed text** goes through `ns.L`, in English **and** in French (`Locale.lua`).
* **One public global**: `EbonTomeHunter`, plus the SavedVariables. Everything else is `local`.
* **No external library** (Ace3, LibDBIcon…): `Widgets.lua` provides the UI kit.
* **ProjectEbonhold is read-only**: go through `ns.PE`, never write into its tables. The addon must
  keep working without it.
* **EbonholdHub data** ("All rights reserved") is read in game at runtime and **never copied** into
  this repository.
* **Actions with consequences** (buying, teleporting, sending messages): one at a time, with a
  delay, never in combat when the action is protected.
* New or fixed logic gets its test in `EbonTomeHunter/tests/scenario.lua`.
* Code, comments and identifiers are written in English.

## Pull requests

1. Work on a branch and open a pull request to `main`. **`main` is what players get**: Ebonhold
   Addon Manager installs the addon from the `main` branch, so `main` must always be releasable.
2. Keep the change focused, and explain what changes and why.
3. `python tools/check.py` passes. The CI runs it on every push and pull request.
4. Update the documentation you touched (`docs/FEATURES.md`, `README.md`, `docs/ARCHITECTURE.md`)
   and add an entry to `CHANGELOG.md`.
5. Say whether the change was tested in game. The fake client is permissive: "OK" does not
   guarantee the behaviour in game.

Versions, tags and releases: [docs/RELEASING.md](docs/RELEASING.md).

## Security issues

Do not report security vulnerabilities through public issues. See [SECURITY.md](SECURITY.md).

## License

By contributing, you agree that your contributions are distributed under the project's
[MIT License](LICENSE).

---

<a id="contribuer-à-ebontomehunter"></a>

# Contribuer à EbonTomeHunter

[English](#contributing-to-ebontomehunter) | **Français**

Merci de ton intérêt. Les signalements de bugs, correctifs, traductions, améliorations de la
documentation et idées de fonctionnalités sont les bienvenus.

## Avant de contribuer

Vérifie d'abord les issues et pull requests existantes. Pour un changement important, ouvre une issue
pour discuter de l'approche avant d'écrire du code.

## Signaler un bug

Utilise le [formulaire de bug](../../issues/new?template=bug_report.yml). Informations utiles : la
version de l'addon (en haut de son panneau d'options, ou `## Version` dans `EbonTomeHunter.toc`), la
langue du client, les étapes pour reproduire, et l'erreur Lua complète s'il y en a une
(`/console scriptErrors 1` les affiche). N'inclus ni nom de compte, ni mot de passe, ni autre donnée
personnelle.

## Demandes de fonctionnalités

Utilise le [formulaire de suggestion](../../issues/new?template=feature_request.yml) : explique quel
problème la fonctionnalité résout, comment tu l'imagines, et pourquoi elle est utile.

## Environnement de développement

1. Python 3.10 ou plus récent, puis `pip install lupa` (Lua 5.1 du validateur). `mpyq` ne sert qu'à
   régénérer les données extraites du client du jeu (voir `docs/DATA.md`).
2. `python tools/check.py` doit afficher `ALL CHECKS PASSED`. Il lance le validateur et le scénario de
   test (`EbonTomeHunter/tests/scenario.lua`) dans un faux client WoW, avec et sans ProjectEbonhold,
   avec un client anglais et un client français, puis vérifie la locale. Il faut 0 erreur et
   0 avertissement.
3. Pour essayer en jeu : `python tools/install.py` (ajouter `--wow <dossier du jeu>` si le jeu n'est
   pas dans `C:/ebonhold`). Un nouveau fichier dans le `.toc` demande de relancer complètement le jeu ;
   sinon un `/reload` suffit.

La documentation technique est en français, dans [docs/](docs/). Lis
[docs/WOW-335.md](docs/WOW-335.md) avant de toucher au code, et [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md)
pour écrire un test.

## Règles

* **API WoW 3.3.5a uniquement (Lua 5.1).** Le code *retail* (`C_Timer`, `SetColorTexture`,
  `BackdropTemplate`, `IsInGroup`…) plante en jeu. Dans le doute, chercher le nom dans
  `tools/api_globals_335.txt` et `tools/api_events_335.txt`.
* **Tout texte affiché** passe par `ns.L`, en anglais **et** en français (`Locale.lua`).
* **Un seul global public** : `EbonTomeHunter`, plus les SavedVariables. Tout le reste est `local`.
* **Pas de bibliothèque externe** (Ace3, LibDBIcon…) : `Widgets.lua` fournit le kit d'interface.
* **ProjectEbonhold en lecture seule** : passer par `ns.PE`, ne jamais écrire dans ses tables.
  L'addon doit continuer de marcher sans lui.
* **Les données d'EbonholdHub** (« All rights reserved ») sont lues en jeu à l'exécution et **jamais
  copiées** dans ce dépôt.
* **Actions à conséquences** (acheter, téléporter, envoyer des messages) : une à la fois, avec un
  délai, jamais en combat quand l'action est protégée.
* Toute logique nouvelle ou corrigée a son test dans `EbonTomeHunter/tests/scenario.lua`.
* Le code, les commentaires et les identifiants sont écrits en anglais.

## Pull requests

1. Travaille sur une branche et ouvre une pull request vers `main`. **`main` est ce que reçoivent les
   joueurs** : Ebonhold Addon Manager installe l'addon depuis la branche `main`, qui doit donc
   toujours être publiable.
2. Garde le changement ciblé, et explique ce qui change et pourquoi.
3. `python tools/check.py` passe. La CI le lance à chaque push et pull request.
4. Mets à jour la documentation touchée (`docs/FEATURES.md`, `README.md`, `docs/ARCHITECTURE.md`) et
   ajoute une entrée dans `CHANGELOG.md`.
5. Dis si le changement a été testé en jeu. Le faux client est permissif : « OK » ne garantit pas le
   comportement en jeu.

Versions, tags et releases : [docs/RELEASING.md](docs/RELEASING.md).

## Problèmes de sécurité

Ne signale pas de faille de sécurité dans une issue publique. Voir
[SECURITY.md](SECURITY.md#politique-de-sécurité).

## Licence

En contribuant, tu acceptes que tes contributions soient distribuées sous la
[licence MIT](LICENSE) du projet.
