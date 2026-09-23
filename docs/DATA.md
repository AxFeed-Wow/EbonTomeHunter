# Données extraites du client : TomeData, MapData, reference/data

Deux fichiers de l'addon sont **générés** depuis le client local du jeu. Ne pas les éditer à la
main : on les régénère.

| Fichier | Contenu | Source dans le client |
|---|---|---|
| `EbonTomeHunter/TomeData.lua` | `ns.TomeData[itemId] = { name, echo, quality, echoes = {ids d'Echo}, verified, desc }` pour les 148 tomes | `Spell.dbc` custom (patch-5.MPQ), `perks_data.lua` de ProjectEbonhold (patch-4), cache d'objets du client |
| `EbonTomeHunter/MapData.lua` | `ns.MapData.maps[fichier] = { id, map, name, continent, city, shownOn, left, right, top, bottom }` + `ns.MapData.hub[slug]` | `WorldMapArea.dbc` et `AreaTable.dbc` (patch-M.MPQ) ; calibrage des images d'EbonholdHub (constantes de l'outil) |

## Régénérer (après un patch du serveur)

```
python tools/extract_ebonhold_data.py --client C:/ebonhold \
    --lua-tomes EbonTomeHunter/TomeData.lua --lua-maps EbonTomeHunter/MapData.lua
python tools/check.py
```
- Il faut `pip install mpyq lupa`.
- L'outil lit les archives `Data/*.MPQ` (lecture seule) et `Cache/WDB/enUS/itemcache.wdb`, puis
  réécrit `reference/data/` : `tomes.json`, `maps.json`, `achievements.json`, `summary.txt` et
  `custom_spells.json` (1,8 Mo, non versionné).
- Relire le diff de `TomeData.lua` : nouveaux tomes, noms changés, qualités. Adapter les tests si
  un nom utilisé par le scénario change.
- Les tests (`tests/scenario.lua`) utilisent les vraies données : un changement de données peut
  faire échouer un test, qu'il faut alors adapter.

## Noms réels des tomes et cache d'objets

- **Nom réel :** le nom réel d'un tome (et sa qualité, sa description) ne se lit que dans le cache
  d'objets du client. Un tome y entre quand le jeu l'a vu : survol, scan HV, sacs.
  - Un tome vu : `verified = true`.
  - Sinon le nom est déduit (« Tome of Echo: » + nom de l'Echo) et la qualité estimée.
- **Cache vidé :** le client **vide ce cache** de temps en temps (redémarrage après un patch…).
  L'outil garde donc les tomes déjà vus dans `reference/data/itemcache_seen.json` et les
  réinjecte à chaque extraction (option `--seen`). **Ne pas supprimer ce fichier** : c'est lui qui
  évite de perdre les noms vérifiés. En 2.0.0, 128 tomes sur 148 sont vérifiés.

## Cartes

- **Contenu :** les continents et zones des cartes 0, 1, 530 et 571 (sans les champs de bataille ni
  les étages de donjons). On y trouve l'id WorldMapArea (`SetMapByID`), le nom de fichier
  (`GetMapInfo()`), le nom anglais, un drapeau ville et les bornes monde en yards.
  - Point monde → carte : `x = (left − worldY) / (left − right)`, `y = (top − worldX) / (top − bottom)`.
  - Carte → monde : `worldY = left − x (left − right)`, `worldX = top − y (top − bottom)`.
- **`shownOn`** : zones de la carte 530 dessinées sur les Royaumes de l'Est (0) ou Kalimdor (1) :
  Bois des Chants éternels, Terres Fantômes, Quel'Danas, Lune-d'argent, Azuremyst, Brumesang,
  l'Exodar.
- **`hub`** : bornes monde des images d'EbonholdHub, dont les lieux de drop sont des pourcentages.
  - Royaumes de l'Est et Kalimdor : mosaïques recalées sur les cartes du jeu ; les constantes sont
    dans `HUB_IMAGES` de l'outil.
  - Outreterre et Norfendre : les cartes de continent du jeu.
  - Si EbonholdHub change ses images, il faudra refaire ce calibrage.

## Autres données de `reference/data/`

- `maps.json` et `tomes.json` : les mêmes données en JSON, pratiques à lire.
- `summary.txt` : ce que contient chaque tranche d'ids de sorts custom.
- `achievements.json` : succès custom du serveur (non utilisés par l'addon).
