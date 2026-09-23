# Fonctionnalités (ce que voit le joueur, et comment ça marche exactement)

Distances : en « mètres » du jeu (= yards du client anglais).

## 1. Ouvrir l'addon

- **Ouverture :** `/eth` (ou `/tomehunter`), ou clic gauche sur le bouton de la minimap. Clic droit
  sur le bouton : les options ; glisser : le déplacer autour de la minimap.
- **Infobulle du bouton :** tomes en wishlist, leur coût total, combien n'ont pas encore de prix,
  tomes appris par ce personnage (X/148), date du dernier scan.
- **Première ouverture de la fenêtre :** le tutoriel démarre (§15). Tant qu'il n'a pas été vu, une
  ligne dans le chat le signale à la connexion.

## 2. Le catalogue

- **Les 148 tomes** viennent de `TomeData.lua`, extrait du client. 128 ont leur vrai nom d'objet,
  leur qualité et leur description vus en jeu.
- **Tome inconnu :** un tome vu à l'HV ou dans les sacs mais absent des données (nouveau patch) est
  ajouté automatiquement.
- **Lieux de drop :** ils sont lus en jeu dans **EbonholdHub** (ou EbonCompletionist) et convertis en
  coordonnées de la vraie carte. S'y ajoutent les lieux trouvés par les joueurs (§11). Sans aucun de
  ces deux addons, seuls les lieux du réseau existent.

## 3. La fenêtre principale

- **Onglets :** « Tous les tomes » et « Wishlist (n) ».
- **Recherche :** dans le nom du tome, le lieu et les monstres.
- **Filtres :**
  - « En vente » : présents au dernier scan ;
  - « Lieu connu » : au moins un lieu placé sur la carte ;
  - « À apprendre » : pas encore appris par ce personnage, grisé sans ProjectEbonhold.
- **Tri :** clic sur Tome / Lieu / Prix / Quantité ; un second clic inverse le sens (mémorisé).
- **Une ligne :**
  - l'icône, bordée de la couleur de qualité ; coche verte = appris, sablier jaune = appris mais
    désactivé dans le journal des Echoes ;
  - le nom et le lieu principal (+N = autres lieux) ;
  - le prix le plus bas (nombre d'annonces entre parenthèses) ;
  - la quantité voulue.
- **Boutons d'une ligne :**
  - − / + : quantité voulue (à partir de 1, le tome est dans la wishlist) ;
  - **Carte** : Localiser (§6) ;
  - **Portail** : téléportation (§9) ;
  - **Patte** : fenêtre Sources (§7) ;
  - **Croix** : retirer de la wishlist.
- **Infobulle d'une ligne :**
  - appris ou non, et la description ;
  - jusqu'à 4 lieux, avec coordonnées, monstres et « trouvé par X » ;
  - le prix, sa tendance, et la date du scan.
- **Maj-clic sur une ligne :** le lien du tome dans le chat.
- **Pied de fenêtre :** coût de la wishlist, nombre de tomes avec prix, dernier scan ou progression.
- **Bouton « ? » :** relance le tutoriel.

## 4. Les prix

- **Lancer un scan :** « Scanner l'HV » (fenêtre) ou « Tout scanner » (onglet Tomes de l'HV).
  L'hôtel des ventes doit être ouvert.
- **Déroulement :** requête « Tome of Echo », page par page, une requête à la fois dès que le serveur
  l'accepte. Chaque annonce est lue : nom, quantité, prix d'achat immédiat, vendeur.
- **Prix retenu :** le prix **unitaire** le plus bas (achat immédiat ÷ quantité), plus le nombre
  d'annonces. Les 20 derniers relevés de chaque tome sont gardés, pour la tendance (hausse / baisse).
- **Tome disparu :** après un scan complet, il passe « pas en vente » ; son dernier prix reste affiché
  en gris.
- **Conservation :** prix communs à tous les personnages du compte, gardés d'une session à l'autre.
- **Options :** scan automatique à l'ouverture de l'HV si le dernier date de plus de 30 min ;
  effacer les prix.

## 5. L'hôtel des ventes

- **Deux onglets en plus**, après ceux de Blizzard / Auctionator : **Tomes** et **Wishlist**. Une
  option les masque, une autre ouvre l'HV directement sur Tomes.
- **Tomes :**
  - à gauche les tomes (par défaut seulement ceux en vente, un bouton affiche tout) ;
  - un clic lance une recherche exacte ;
  - à droite ses annonces, triées par prix unitaire ;
  - la moins chère qui n'est pas la tienne est présélectionnée.
- **Wishlist :** « Chercher la wishlist » cherche chaque tome voulu, l'un après l'autre.
- **Acheter (ou double-clic) :**
  1. L'addon vérifie qu'il y a un prix d'achat immédiat, que ce n'est pas ton annonce, que tu as
     assez d'or et qu'aucun achat n'est en cours.
  2. Il demande une confirmation avec le montant (option, activée par défaut). Il affiche un
     avertissement orange si le tome est déjà appris.
  3. Juste avant d'acheter, il revérifie l'annonce (nom, quantité, prix, vendeur). Si elle a changé,
     il recharge et n'achète rien d'autre à la place.
  4. **Résultat :**
     - quand le serveur confirme, la quantité est déduite de la wishlist (option) ;
     - en cas d'erreur (déjà vendu, or insuffisant…), elle est affichée ;
     - sans réponse au bout de 6 s, la liste est rechargée et la wishlist n'est pas touchée.

## 6. La carte du monde

- **Localiser :**
  - ouvre la carte de la zone du lieu, avec une étoile qui pulse et le nom du tome ;
  - écrit la zone et les coordonnées dans le chat ;
  - un nouveau clic passe au lieu suivant du tome.
- **Marqueurs :** un rond pour chaque lieu de chaque tome de la wishlist (option).
- **Sur un marqueur :**
  - clic : le tome dans la fenêtre ;
  - **Maj-clic** : Sources ;
  - **Ctrl-clic** : téléportation au plus près de **ce lieu**.

## 7. La fenêtre Sources (bouton patte)

- **Une ligne par monstre de chaque lieu**, dans cet ordre :
  1. les sources joignables par téléportation, la plus proche d'un checkpoint en premier ;
  2. celles sans checkpoint débloqué sur ce continent ;
  3. celles sans position.
- **Chaque ligne indique :**
  - le monstre (#id s'il est connu, « recherche » sinon, « créature d'Ebonhold » si elle n'existe pas
    sur Wowhead) et le lieu ;
  - le checkpoint et sa distance (vert), ou le checkpoint à débloquer (orange) ;
  - ta distance si tu es sur le même continent ;
  - les boutons **TP** et **Wowhead**.

## 8. Liens Wowhead

- **Format :** section WotLK Classic, `https://www.wowhead.com/wotlk/npc=<id>/<nom>` quand l'id est
  connu, sinon une recherche WotLK par nom.
- **Jamais de lien d'objet :** les tomes d'Ebonhold n'existent pas sur Wowhead. Pas de lien non plus
  pour une créature propre au serveur (id ≥ 50 000).
- **Id du monstre :** appris quand on cible ou survole un monstre cité dans les lieux de drop, ou
  quand on le loote. Les lieux du réseau l'apportent aussi.
- **Ouverture :** dans le navigateur via le client Ebonhold (`EbonholdOpenURL`). Sinon le lien est
  copié (extension AwesomeWotLK), ou sélectionné pour Ctrl+C.

## 9. La téléportation

- **Checkpoints pris en compte :** ceux de ProjectEbonhold (maîtres de vol, pierres de rencontre)
  que le personnage a **débloqués**, de sa faction.
- **Calcul :**
  - pour chaque lieu du tome, le checkpoint débloqué le plus proche sur le même continent, à vol
    d'oiseau ;
  - avec plusieurs sources, la source retenue est celle qui a le checkpoint le plus proche.
- **Où la lancer :**
  - le bouton portail d'une ligne ;
  - `/eth tp <tome>` (nom complet ou morceau unique, utilisable en macro) ;
  - Ctrl-clic sur un marqueur ;
  - TP dans Sources.
- **Règles :**
  - téléportation **directe** (la confirmation est une option désactivée par défaut) ;
  - jamais en combat ;
  - descente de monture au sol, pas en vol ;
  - une demande toutes les 3 s au plus.
- **Déjà sur place :** si tu es plus près d'une source que tout checkpoint, le portail et `/eth tp`
  ne téléportent pas et l'écrivent. Sources et Ctrl-clic téléportent quand même.
- **Aucun checkpoint débloqué :** l'addon redemande la liste à ProjectEbonhold, qui l'envoie après
  la connexion.
- **Infobulle du portail :** destination, distance, monstre, autres sources, checkpoint plus proche à
  débloquer, « vous êtes déjà à X m ».

## 10. Partager une wishlist

- **Exporter :** bouton « Partager » ou `/eth share`. La wishlist devient un texte
  (`ETH1:auteur:tomes:contrôle`), déjà sélectionné pour Ctrl+C (bouton Copier avec AwesomeWotLK).
- **Importer :** colle un texte, un aperçu s'affiche (auteur, tomes, exemplaires), puis :
  - **Fusionner** ajoute les tomes absents et garde la plus grande quantité ;
  - **Remplacer** écrase la wishlist, après confirmation.
- **Robustesse :** un texte tronqué ou modifié est refusé (code de contrôle). Le texte est retrouvé
  même au milieu d'un message. Les tomes inconnus sont ignorés et comptés. Les chaînes `ETP1:` de
  l'ancien nom (EbonTomePrices) sont encore lues.
- **Envoi direct :** « Envoyer à : » (+ bouton Cible) ou `/eth send Nom`, par message d'addon
  chuchoté.
  - Le joueur doit avoir l'addon : il reçoit « X vous envoie une wishlist » → Voir / Ignorer, et
    Voir ouvre l'import avec l'aperçu.
  - L'expéditeur reçoit un accusé de réception, « pas de réponse » après 12 s, ou « refusé ».
  - Au plus 3 envois par minute sont acceptés d'un même joueur.

## 11. Le réseau entre joueurs

- **Canal caché :** l'addon rejoint un canal de discussion caché 10 s après la connexion. Rien ne
  s'affiche dans le chat.
- **Quand tu obtiens un tome sur un monstre**, à la main ou par le Greedy Scavenger :
  - l'addon note le tome, la position, le monstre et son id, la zone, l'heure et **ton nom de
    personnage** ;
  - il garde ce lieu et l'envoie aux autres s'il est nouveau, ou pour confirmer un lieu connu.
- **Chez les autres :**
  - le message est vérifié (tome connu, position et date plausibles) ;
  - même carte, à moins de 4 % de la carte et même monstre = même lieu, qui gagne « +1 joueur » ;
  - au plus 12 lieux par tome.
- **Résultat :** un tome « Unknown location » finit par avoir un vrai lieu, sur la carte, dans
  Localiser et pour la téléportation.
- **Synchronisation à la connexion** (15 s après, au plus toutes les 10 min) :
  - tu demandes ce que tu as manqué ;
  - l'utilisateur qui en sait le plus répond, les autres se taisent ;
  - la réponse arrive par lots de 30 lieux, jusqu'à 5 lots par session, et reprend à la connexion
    suivante.
- `/eth net` affiche l'état. Le réseau se coupe dans les options (sous-panneau « Réseau et
  alertes »).
- **Limites :**
  - le réseau ne relie que les joueurs connectés en même temps, en principe de la même faction ;
  - les lieux reçus ne sont pas vérifiables (chacun affiche qui l'a trouvé et combien l'ont confirmé) ;
  - WoW limite chaque personnage à **10 canaux de discussion**. S'ils sont tous pris (canaux de zone,
    canaux « world », canaux cachés d'autres addons…), le jeu refuse le canal caché avec « You can
    only be in 10 channels at a time. » : ni envoi ni réception pendant la session. L'addon ne le
    détecte pas (`/eth net` affiche quand même « connecté »). Pour libérer une place : `/chatlist`,
    `/leave <numéro>`, puis `/reload`.

## 12. D'où vient un tome (loot à la main ou Greedy Scavenger)

- **Loot à la main :** le monstre est le cadavre ouvert (celui sous la souris, sinon la cible
  morte), à la position où la fenêtre de butin s'est ouverte.
- **Greedy Scavenger** (familier d'Ebonhold qui ramasse tout seul) : il ne laisse **aucun message**.
  - L'addon voit le tome **apparaître dans les sacs**.
  - Il prend le monstre que toi ou ton groupe avez combattu puis tué dans la dernière minute, si
    c'est un seul type de monstre. Sinon il envoie le lieu seul, qu'un autre joueur pourra
    compléter. La position est la tienne.
  - Aucun monstre tué dans la dernière minute : pas de lieu.
- **Pas comptés comme du loot :**
  - ce qui arrive par une banque (dont la banque étendue et le stockage du Vide), le courrier, un
    marchand, un échange, l'HV, un métier, une quête, un dialogue de PNJ, la boutique, l'achat ou
    l'extraction d'Ebonhold ;
  - les 10 s qui suivent un écran de chargement.
- **Pas de lieu envoyé :** coffres, sacs ouverts depuis l'inventaire (le lieu serait faux), pêche,
  tome gagné aux dés après la fermeture du butin.
- **Une seule alerte :** loot à la main = une ligne de chat + une hausse dans les sacs, comptées une
  seule fois.

## 13. Les alertes

- **Tu obtiens un tome de ta wishlist :** grand message au centre de l'écran, plus un son.
- **Un membre du groupe en loote un à la main :** une ligne dans le chat, plus un son. Le Scavenger
  d'un autre joueur ne laisse aucun message : invisible.
- **Un joueur du réseau en trouve un (nouveau lieu) :** une ligne avec le lieu et le monstre.
- Chaque alerte se coupe dans les options, le son aussi.

## 14. Tomes appris

- **Source :** ProjectEbonhold, qui envoie la liste des Echoes découverts à la connexion. C'est la
  même source que son infobulle « Already learned ».
- **Désactivé** signifie que le tome a été retiré du tirage dans le journal des Echoes.
- **Mise à jour :** quand le serveur renvoie la liste (tome utilisé) et quand les sacs changent.

## 15. Le tutoriel

- **Déroulé :** 14 étapes. Un cadre doré entoure chaque partie de la fenêtre et une bulle
  l'explique (Précédent / Suivant / Passer). Les étapes :
  1. Bienvenue.
  2. Onglets, puis recherche et filtres.
  3. La liste, puis déjà appris ?
  4. Wishlist (− / +).
  5. Boutons Carte / Portail / Patte / Croix.
  6. Prix, puis hôtel des ventes (ses onglets éclairés s'il est ouvert).
  7. Partager.
  8. Carte du monde.
  9. Réseau.
  10. Bouton de minimap, puis par où commencer.
- **Lancement :** une fois par compte, à la première ouverture. Il se relance avec « ? », `/eth tuto`
  ou « Revoir le tutoriel » (options).
- **Arrêt :** fermer la fenêtre, Échap ou Passer l'arrête, et il ne revient plus tout seul.

## 16. Options (Interface > AddOns > EbonTomeHunter)

- **Panneau principal :**
  - bouton de minimap, taille de la fenêtre, recentrer ;
  - marqueurs de la wishlist sur la carte, confirmation des téléportations (désactivée par défaut) ;
  - HV : onglets, ouverture sur Tomes, confirmation d'achat (activée par défaut), déduction de la
    wishlist, scan automatique ;
  - effacer les prix, reconstruire le catalogue, revoir le tutoriel.
- **Sous-panneau « Réseau et alertes » :** réseau, alerte pour moi / le groupe / le réseau, son,
  réception des wishlists, et l'état du réseau.

## 17. Commandes

| Commande | Effet |
|---|---|
| `/eth` (ou `/tomehunter`) | ouvrir / fermer la fenêtre |
| `/eth share` (`export`, `import`) | partager / importer une wishlist |
| `/eth send <nom>` | envoyer sa wishlist à un joueur |
| `/eth net` | état du réseau |
| `/eth tp <tome>` | se téléporter au checkpoint le plus proche de là où le tome tombe |
| `/eth tuto` | relancer le tutoriel |
| `/eth options` | panneau d'options |
| `/eth minimap` | afficher / masquer le bouton de la minimap |
| `/eth scan` | scanner l'HV (ouvert) |
| `/eth rebuild` | reconstruire le catalogue |
| `/eth bags` | chercher des tomes inconnus dans les sacs |
| `/eth help` | rappel des commandes |

## 18. Ce qui est enregistré

- **Pour tout le compte :** prix et historique, dernier scan, tomes découverts, lieux du réseau, ids
  des monstres, options, tutoriel vu.
- **Par personnage :** la wishlist.

## Limites connues

- **Prix :** ce sont ceux du dernier scan ; l'HV change vite.
- **Lieux :** ceux d'EbonholdHub sont parfois approximatifs ou « Unknown location ».
- **Téléportation :** distance à vol d'oiseau (montagnes et mers ignorées) ; c'est le serveur qui
  décide (il peut refuser).
- **Tomes appris :** l'information dépend de ProjectEbonhold (sans lui, pas de coches).
- **Réseau :** joueurs connectés en même temps, même faction, informations non vérifiables.
