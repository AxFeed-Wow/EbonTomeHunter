# Historique des versions

## Prochaine version

- **Réseau plus léger.** Les compteurs de cadavres (sources périmées) n'envoient plus que ce qui peut
  marquer une source : 100 cadavres sans le tome ou plus, ou un signalement « Disparu ? ». Avant,
  chaque drop et chaque série de 25 cadavres partait sur le réseau : sur les données relevées le
  2026-10-05, environ 150 Ko de compteurs, dont 98 % ne pouvaient rien marquer. Les drops arrivent
  toujours aux autres par les lieux de drop. Compatible avec la 3.x.
- **Plus de lieux « monstre inconnu ».** Un lieu sans son monstre ni candidats (laissé par les
  anciennes versions, environ 230 sur le réseau) n'est plus gardé ni partagé.
- **Le bon monstre au fil des drops.** Quand le Greedy Scavenger laisse un doute entre plusieurs
  monstres, un candidat qui est déjà une source connue du tome (lieu confirmé par un joueur,
  EbonholdHub, atlas, indice du serveur) devient le monstre, s'il est le seul dans ce cas. Si
  plusieurs candidats sont des sources connues, le doute reste (un tome peut tomber de plusieurs
  monstres).
- **Noms de zones cohérents.** Un lieu trouvé par un joueur d'une autre langue s'affichait sous son
  nom à lui (« Forêt du Chant de cristal », et même en cyrillique). Il s'affiche maintenant sous le
  nom anglais de sa carte, comme les autres sources, et une instance nommée dans un autre alphabet
  sous le nom de sa carte. Le texte envoyé sur le réseau ne change pas (compatible 3.x).
- Un drop dans une instance dont le client n'a pas la carte n'est plus pointé sur le continent
  (point faux) : le lieu garde son nom, la téléportation cherche sa pierre de rencontre.
- **Téléportation vers toutes les instances.** ProjectEbonhold n'a qu'une pierre de rencontre pour
  plusieurs instances (Auchindoun, Grottes du temps, Tempest Keep, Coilfang, Blackrock...), et
  aucune pour certaines : 245 des 640 lieux d'instance du réseau ne trouvaient pas leur pierre. Une
  table relie chaque instance à sa pierre, au point de téléportation de son entrée (Trial of the
  Crusader : Argent Tournament Grounds ; Violet Hold : Dalaran), ou à son entrée sur la carte
  (Citadelle des Flammes infernales : le point débloqué le plus proche). Les 640 sont couverts.
- **Le lieu principal est celui du monstre qui lâche le plus le tome.** Un même monstre trouvé à
  plusieurs endroits d'une zone, ou nommé dans plusieurs langues (« Revenant lié à la terre » =
  Earthbound Revenant), additionne ses drops et s'affiche sous un seul nom ; son meilleur endroit
  passe en premier. Exemple, Elemental Slayer : Earthbound Revenant (11 joueurs) à Wintergrasp.
- **Une source par monstre.** Un boss trouvé à tous les coins de sa salle (Sindragosa pour
  Permeating Chill), ou listé à la fois par EbonholdHub, le réseau et l'atlas, n'apparaît plus
  qu'une fois : tous ses drops, à son meilleur lieu (avec un point sur la carte, là où il a été vu le
  plus). Le « vous êtes déjà à côté » de la téléportation compte toujours tous ses endroits.
- Un lieu sans monstre ni point sur la carte (« Unknown location » d'EbonholdHub) n'est plus listé
  quand le tome a un autre lieu.
- **Nouvelle version signalée.** Quand un joueur croisé sur le réseau a une version plus récente,
  une ligne d'EbonTomeHunter le dit dans le chat (une fois par version) et le bouton « Réseau »
  devient « Mise à jour ! » en orange ; un petit point rouge s'affiche sur l'icône de la minimap.
- **Moins de calculs à la réception.** Un lieu ou un compteur reçu ne recalcule plus que les
  sources de son tome, au lieu des 148 (notamment au login, quand des centaines de jeux de données
  arrivent).
- Nettoyage : le repli du catalogue « sans TomeData.lua » (toujours livré) et des fonctions jamais
  appelées sont retirés.

## 3.1.0 — 2026-09-29

Les sources où le tome tombe vraiment passent en premier. Compatible avec la 3.0.0 (même réseau),
aucun nouveau fichier : un `/reload` suffit après la mise à jour.

- **Les sources les plus farmées d'abord.** Les sources vues lâcher le tome le plus souvent passent
  en tête : lieu principal de la liste, fenêtre Sources, Localiser et téléportation.
  - Comptés : les joueurs du réseau qui l'ont trouvé là, les drops de l'atlas d'EbonBuilds, et les
    drops des compteurs de cadavres (les tiens et ceux des autres joueurs).
  - Un lieu listé que personne n'a vu lâcher le tome (peut-être obsolète, comme Lord Kazzak pour
    Demonic Awakening) passe après ; un lieu du réseau non retrouvé depuis 90 jours aussi.
  - La fenêtre Sources affiche « N drop(s) vu(s) ».
- **Raids et donjons** : un lieu trouvé dans une instance (pas de point sur les cartes du monde) se
  rejoint maintenant par téléportation, vers la pierre de rencontre de son entrée (par exemple
  « Black Temple »).
- La téléportation vise la première de ces sources qu'un checkpoint dessert, jamais une source
  périmée tant que la première est bonne.
- Outils : `validate_addon.py` teste aussi un addon qui dépend d'un autre (`## Dependencies`) quand
  cet autre est donné par `--with`.

## 3.0.0 — 2026-09-28

Le réseau change complètement : il passe par EbonAPI et n'est plus compatible avec les 2.x.

- **Réseau : passage par EbonAPI** ([Siphelis/EbonAPI](https://github.com/Siphelis/EbonAPI)), un
  addon à part que chaque joueur installe (Ebonhold Addon Manager ou GitHub). Sans lui, tout le reste
  marche et tes trouvailles restent chez toi ; le chat le dit une fois par version.
  - Chaque tome est un jeu de données d'EbonAPI : ses lieux de drop, ceux de tous les joueurs mis
    ensemble. EbonAPI les garde et les passe de joueur en joueur, **même entre joueurs jamais
    connectés en même temps**, et aussi par ceux qui utilisent un autre addon d'EbonAPI
    (AutoCallboard, SkillTreeAutoLoad…).
  - Un seul canal caché pour tous les addons d'EbonAPI, au lieu d'un par addon.
  - Chaque client fusionne les lieux de la même façon : tout le monde finit avec les mêmes données.
    Deux joueurs d'un groupe qui publient dans la même seconde ne s'écrasent pas.
  - Les compteurs de cadavres et les signalements « Plus bon ? » voyagent de la même façon.
  - Données refusées : un tome inconnu, une position hors carte, une date dans le futur, un code
    d'échappement de WoW (couleur `|c`, lien `|H`).
  - `/eth net sync` (et le bouton réseau) annonce tout de suite tes lieux aux joueurs connectés,
    toutes les 30 s au plus. Le bouton affiche *Réseau*, *Connexion…*, *Sans EbonAPI* ou *Réseau
    coupé* ; sa bulle d'aide dit combien de tomes sont partagés.
  - Retirés : `/eth net check`, `/eth net compare`, la synchro automatique toutes les 15 min et
    l'annonce des versions (EbonAPI prévient lui-même quand une version plus récente existe).
  - Les lieux déjà connus (2.x) sont gardés et publiés au premier lancement.
- **Greedy Scavenger : quel monstre a lâché le tome.** Le familier ramasse sans fenêtre de butin ;
  parmi les monstres tués dans la dernière minute, l'indice du serveur sur le tome (« Can be found
  on … ») départage :
  - un sort de l'indice que le monstre a lancé (journal de combat), son type de créature (plaques de
    nom, cible, survol), sa classe, une source déjà connue du tome, un mot de son nom ;
  - si aucun ne se détache, le lieu garde jusqu'à 4 monstres possibles (« un de : A / B ») ; chaque
    nouveau drop au même endroit, par n'importe quel joueur, ne garde que ceux tués à chaque fois, et
    quand il n'en reste qu'un, c'est le monstre du lieu.
- **Sources périmées : le seuil suit le taux de drop de la source.**
  - Un tome rare peut manquer beaucoup de cadavres de suite par simple malchance : une source n'est
    grisée qu'au-delà du nombre de cadavres sans le tome que la malchance n'explique qu'1 fois sur
    100 (entre 500 et 5000).
  - Le taux vient de l'historique de tous les compteurs (drops / cadavres) ; la raison affichée le
    dit (« d'habitude 1 sur N »).
  - Un seul drop, même après une longue série sans, rend la source bonne.
- **Atlas d'EbonBuilds** : les sources de drop que ses utilisateurs ont vues (monstre et zone) sont
  ajoutées, lues en jeu dans les données d'EbonBuilds, jamais modifiées.
  - Au plus 8 par tome, celles qu'aucune autre source ne cite déjà.
  - Point sur la carte quand EbonBuilds en a noté un ; sinon la téléportation vise le centre de la
    zone, et la distance s'affiche avec « ~ ».
- **Scan de l'HV** : une annonce d'un tome que le client ne connaissait pas encore (premier passage,
  cache vidé) arrivait sans nom et était ignorée, et le tome pouvait passer « pas en vente » à tort.
  - La page attend maintenant ces données, 3 s au plus.
  - Si elles n'arrivent pas, le chat le dit et rien n'est marqué « pas en vente ».
- **Sources périmées** : un tome visible dans la fenêtre de butin mais pas pris (sacs pleins, jet
  gagné par un autre) compte comme un drop, et son lieu est partagé. Avant, ce cadavre comptait
  « sans le tome ».
- **Sécurité** : l'auteur d'une chaîne de wishlist partagée est nettoyé des codes d'échappement.
- Textes anglais : « Hint: » au lieu de « Hint : ».
- Addon de dev : `/ethdev scav on|off` enregistre tout ce qui entoure un ramassage du Greedy
  Scavenger (journal de combat, paroles et emotes du familier, sacs, argent) ; `/ethdev stats`
  passe par EbonAPI.
- Nouveaux fichiers `Hints.lua` et `Atlas.lua` : **relancer complètement le jeu** après la mise à
  jour.

## 2.2.0 — 2026-09-24

- **Import d'un build Echo Builder** (project-ebonhold.com/tools/echo-builder) dans la wishlist :
  dans `/eth share`, coller son lien (« Copy link »), son texte (« Copy build ») ou le build seul.
  - Les Echos qui ont un tome deviennent ce tome (1 exemplaire).
  - L'aperçu sépare les tomes apprenables (ajoutés), déjà appris (non ajoutés) et les Echos de base,
    sans tome (ignorés), avec leurs noms ; les listes complètes s'affichent dans le chat.
  - Une case « Ajouter aussi les tomes déjà appris » permet de les mettre quand même en wishlist.
- Une chaîne de wishlist fabriquée à la main (code de contrôle faux) reste refusée.
- **Indices du serveur** : la phrase « Can be found on … » du journal des Echos de ProjectEbonhold
  s'affiche dans la bulle d'aide et la fenêtre Sources.
- **Tomes de raid** : les 20 tomes qu'EbonholdHub ne place nulle part sont rattachés aux boss de la
  Citadelle de la Couronne de glace et du Sanctum rubis que nomme ce journal, avec lien Wowhead et
  téléportation vers l'entrée du raid.
- Un tome sans aucun lieu affiche l'indice du serveur, sinon « inconnu », au lieu de rien.
- Correction : une ligne de tome dont l'id d'objet est encore inconnu ne provoque plus d'erreur.
- **`/eth net check`** : qui, parmi les utilisateurs connectés, a les mêmes données que toi.
- **`/eth net sync`** : synchro complète pour toi seul (tout redemander, tout de suite).
- `/eth net check` montre aussi la dernière info et les trouvailles de chacun.
- **`/eth net compare <nom>`** : les lieux qu'un joueur a et pas toi, et l'inverse.
- **Nouvelle version** : l'addon prévient quand un autre utilisateur a une version plus récente.
- **Historique des drops** (bouton Historique, `/eth history`) : quand, quel tome, qui, où, quel
  monstre ; filtre « mes trouvailles », clic = Sources.
- Statistiques de kills par créature, envoyées seulement à la demande de l'addon de dev.
- Greedy Scavenger : après des kills de plusieurs monstres différents, le monstre retenu est celui
  qui est une source connue du tome (moins de lieux sans monstre).
- Nouveau fichier `History.lua` : **relancer complètement le jeu** après la mise à jour.
- **Synchro automatique toutes les 15 min**, et un bouton réseau dans la fenêtre : « À jour » ou
  non (bulle d'aide : dernière synchro, version de l'addon), clic = synchro complète.

## 2.1.0 — 2026-09-24

- **Réseau : les lieux circulent même quand les joueurs ne sont pas connectés en même temps.**
  - Une trouvaille faite sans personne en ligne est gardée et renvoyée dès qu'un autre utilisateur
    se manifeste.
  - La synchro demande ce que les autres ont appris depuis ta dernière synchro : une vieille
    trouvaille arrivée tard circule aussi.
  - Chaque utilisateur connecté complète la réponse avec ce qu'elle ne contenait pas, et celui qui
    demande envoie à son tour ce qu'il sait et que personne n'a cité.
  - Une synchro restée sans réponse repart quand quelqu'un arrive.
  - Une ligne dans le chat dit combien de nouveaux lieux la synchro a apportés.
- **Sources périmées** (un monstre qui ne lâche plus un tome depuis un patch) :
  - chaque cadavre que tu loots sans le tome est compté pour ce monstre, et les compteurs sont
    partagés ;
  - bouton « Plus bon ? » dans la fenêtre Sources pour signaler une source ;
  - à 500 cadavres sans le tome (au moins deux joueurs, ou toi seul) ou 3 signalements, la source
    est grisée avec la raison et passe en dernier pour la téléportation. Rien n'est supprimé, et un
    nouveau drop la rétablit.
- Lieux du réseau : les plus récents d'abord, l'âge affiché (« trouvé il y a … »), ceux non retrouvés
  depuis 90 jours après les autres.
- Nouveau fichier : **relancer complètement le jeu** après la mise à jour (un `/reload` ne suffit
  pas).
- `/eth net` dit si le canal caché est vraiment rejoint (il affichait « connecté » même quand le
  jeu le refusait à cause de la limite des 10 canaux).
- Compatible avec la 2.0.0 : les deux versions se comprennent.

## 2.0.0 — 2026-09-23

- **Nouveau nom : EbonTomeHunter** (anciennement EbonTomePrices).
  - Dossier `EbonTomeHunter`, sauvegardes `EbonTomeHunterDB` / `EbonTomeHunterCharDB` (migration :
    `tools/migrate_savedvariables.py`), commandes `/eth` et `/tomehunter`.
  - Chaînes de partage `ETH1:`. Les `ETP1:` de l'ancien nom sont encore lues.
  - Réseau renommé : canal caché `ebontomehunter`, protocole `ETHN1`, préfixe d'addon `ETH`.
    Incompatible avec les anciennes versions.
- Relecture complète du code :
  - le catalogue n'écrit plus dans la base d'Echoes de ProjectEbonhold ;
  - la recherche exacte d'un tome découvert après un patch retrouve ses annonces ;
  - l'affichage ne plante plus sur un « % » reçu du réseau ;
  - le copier-coller est protégé ;
  - la carte retrouve les zones de Quel'Thalas et d'Azuremyst en repli ;
  - un double évènement à l'achat est supprimé.
- Dossier de projet autonome :
  - documentation (`CLAUDE.md`, `docs/`) ;
  - outils : `check`, `install`, `package`, migration, extraction.
- Publication sur GitHub (AxFeed-Wow/EbonTomeHunter), sous licence MIT :
  - README en anglais et en français, guide de contribution, politique de sécurité, formulaires
    d'issues et modèle de pull request ;
  - contrôles automatiques à chaque push, release automatique (zip et SHA-256) à chaque tag ;
  - compatible avec Ebonhold Addon Manager (le scénario de test n'est pas installé).
- Limite connue : le réseau ne marche pas quand le personnage est déjà dans 10 canaux de discussion
  (« You can only be in 10 channels at a time. ») ; le README explique comment libérer une place.

## 1.6.1

- **Greedy Scavenger** : ses tomes (déposés dans les sacs sans message) sont détectés.
  - Alerte wishlist.
  - Lieu envoyé au réseau, avec le monstre tué dans la dernière minute s'il n'y en a qu'une sorte.
  - Banques, courrier, marchand, échange, boutique… ne comptent pas comme du butin.
- Un lieu sans monstre fusionne avec le même endroit et récupère son monstre plus tard.
- Faux client de test : les fenêtres de Blizzard démarrent fermées, comme en jeu.

## 1.6.0

- Tutoriel pas à pas (14 étapes) à la première ouverture ; bouton « ? », `/tuto`, option.
- Données des tomes : l'extraction garde les tomes déjà vus quand le client vide son cache ; 128 tomes
  vérifiés.

## 1.5.1

- Retrait de l'import des Echoes verrouillés (bouton et import automatique).

## 1.5.0

- Téléportation au checkpoint débloqué le plus proche des monstres :
  - bouton dans la liste, `/tp <tome>`, Ctrl-clic sur un marqueur ;
  - pour plusieurs sources, la plus accessible ;
  - pas en combat ; démontage au sol.
- Fenêtre Sources (chaque monstre : checkpoint, distance, TP, Wowhead), qui remplace la fenêtre des
  liens Wowhead.
- Cartes de Quel'Thalas, Quel'Danas, Azuremyst et Brumesang ajoutées aux données.
- Pas de lien Wowhead pour les créatures propres au serveur.

## 1.4.0

- Envoi direct d'une wishlist à un joueur (message d'addon, accusé, refus, anti-spam).
- Réseau caché entre utilisateurs :
  - lieux de drop partagés, pour qu'un tome « Unknown location » soit localisé ;
  - synchronisation à la connexion, par lots avec reprise.
- Alertes : tome de la wishlist looté par moi, par le groupe, trouvé par le réseau.
- Liens Wowhead (section WotLK) des monstres ; id des PNJ appris au ciblage, au survol et au loot.

## 1.3.0

- Partage de wishlist par une chaîne à copier / coller (fusion, remplacement, code de contrôle).
- Tomes déjà appris par le personnage (coche verte, sablier, filtre « À apprendre »).

## 1.2.0

- Onglets **Tomes** et **Wishlist** dans l'hôtel des ventes : scan, recherche, achat vérifié.
- Panneau d'options, bouton de minimap, fenêtre principale redessinée (thème sombre et bronze).
- Correctif : la base est initialisée à ADDON_LOADED (les tomes appris à l'HV n'étaient pas sauvegardés).

## 1.0 – 1.1

- Premières versions (EbonTomePrices) :
  - prix des tomes relevés à l'hôtel des ventes ;
  - wishlist avec coût total ;
  - catalogue complet tiré des données du client ;
  - lieux de drop (EbonholdHub) et marqueurs sur la carte du monde.
