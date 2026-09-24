# Historique des versions

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
