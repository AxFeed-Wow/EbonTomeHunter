# Versions, installation, publication sur GitHub

Dépôt : https://github.com/AxFeed-Wow/EbonTomeHunter (auteur affiché : AxFeed-Wow, licence MIT).
La présentation (README bilingue, CONTRIBUTING, SECURITY, modèles d'issues et de PR, CI) suit celle
d'AxFeed-Wow/EbonholdAddonManager.

## Qui reçoit quoi

- **Ebonhold Addon Manager** (le logiciel de l'utilisateur, AxFeed-Wow/EbonholdAddonManager) installe
  et met à jour l'addon depuis la **branche `main`**, pas depuis les releases :
  - il lit le `## Version` de `EbonTomeHunter/EbonTomeHunter.toc` sur `main` et ne propose une mise à
    jour que si cette version diffère de celle installée ;
  - il télécharge l'archive de la branche (`archive/refs/heads/main.zip`), y trouve
    `EbonTomeHunter/EbonTomeHunter.toc` et copie **tout** le dossier `EbonTomeHunter/` ;
  - `EbonTomeHunter/tests/` est exclu de cette archive par `.gitattributes` (`export-ignore`).

  Donc **`main` = ce que reçoivent les joueurs**. Un changement poussé sur `main` sans montée de
  version n'est pas proposé en mise à jour, mais arrive dans toute nouvelle installation : on
  travaille sur une branche et on fusionne dans `main` avec la montée de version.
- **Installation à la main** : le zip de la release, construit par `tools/package.py` (dossier
  `EbonTomeHunter/` sans `tests/`, avec `LICENSE.txt`).

## Numéro de version

Versionnage sémantique `MAJEUR.MINEUR.CORRECTIF` :
- **MAJEUR** : changement incompatible (sauvegardes renommées, format réseau ou de partage cassé,
  commandes renommées). Exemple : la 2.0.0, qui renomme l'addon.
- **MINEUR** : nouvelle fonctionnalité.
- **CORRECTIF** : corrections.

La version s'écrit à **deux endroits** : `EbonTomeHunter/Core.lua` (`ns.version = "x.y.z"`) et
`EbonTomeHunter/EbonTomeHunter.toc` (`## Version: x.y.z`). `tools/package.py` refuse s'ils diffèrent.
Chaque version a son entrée en haut de `CHANGELOG.md` : `## x.y.z — AAAA-MM-JJ`, puis les changements
en français. Cette entrée devient les notes de la release.

## Livrer une version

Toujours sur demande explicite de l'utilisateur (pousser sur `main` = livrer aux joueurs).

1. Sur une branche : les changements, `python tools/check.py` → ALL CHECKS PASSED, la version montée
   aux deux endroits, l'entrée du CHANGELOG.
2. Fusionner dans `main` (pull request, ou push direct pour un petit correctif) et vérifier que le
   workflow `Check` est vert : `gh run list --limit 3`.
3. `git tag vX.Y.Z` puis `git push origin vX.Y.Z`. Le workflow `Release` :
   - relance les contrôles ;
   - vérifie que le tag correspond au `## Version` du `.toc` ;
   - construit `EbonTomeHunter-X.Y.Z.zip` et son `.sha256` ;
   - crée la release avec l'entrée du CHANGELOG comme notes.
4. Vérifier : `gh run watch`, puis `gh release view vX.Y.Z`. Donner le lien à l'utilisateur.

Tag raté : `gh release delete vX.Y.Z --cleanup-tag --yes`, corriger, recommencer.

Sans GitHub (essai local) : `python tools/package.py` → `dist/EbonTomeHunter-x.y.z.zip`, et
`python tools/install.py` chez l'utilisateur. Nouveau fichier dans le `.toc` → **redémarrage complet**
du jeu, sinon un `/reload` suffit.

## Intégration continue

- `.github/workflows/check.yml` : `python tools/check.py` sur Ubuntu, à chaque push et pull request.
  Le badge du README en montre l'état.
- `.github/workflows/release.yml` : à chaque tag `v*`, décrit ci-dessus. Il utilise le jeton
  `GITHUB_TOKEN` du workflow : aucun secret à configurer.

## Première publication (2026-09-23)

Dépôt créé en **privé**, pour relecture par l'utilisateur avant de le rendre public. Au passage en
public :
- `gh repo edit AxFeed-Wow/EbonTomeHunter --visibility public --accept-visibility-change-consequences` ;
- activer le signalement privé des failles (SECURITY.md y renvoie) :
  `gh api -X PUT repos/AxFeed-Wow/EbonTomeHunter/private-vulnerability-reporting` ;
- ajouter l'addon au catalogue d'Ebonhold Addon Manager (c'est l'utilisateur qui le fait, dans son
  logiciel) : dossier `EbonTomeHunter`, dépôt `AxFeed-Wow/EbonTomeHunter`, branche `main`. Le
  README renvoie déjà vers le logiciel.

## Ce qui ne doit jamais être publié

| Quoi | Pourquoi | Protection |
|---|---|---|
| `_extracted/` (source de ProjectEbonhold) | code du serveur, pas le nôtre | `.gitignore` |
| `WTF` / SavedVariables, noms réels de personnages ou de comptes | données personnelles | ne jamais les copier dans le dépôt |
| données d'EbonholdHub | « All rights reserved » | l'addon les lit en jeu, rien n'est copié |
| `backups/`, `dist/` | fichiers locaux ; les zips vont dans les releases | `.gitignore` |
| `reference/data/custom_spells.json` | 1,8 Mo, régénérable | `.gitignore` |
| `.claude/settings.local.json` | réglages personnels de Claude Code | `.gitignore` |

Avant chaque commit, relire `git status` et le diff. Par exemple : `grep -rn -i "C:/Users" .`.
