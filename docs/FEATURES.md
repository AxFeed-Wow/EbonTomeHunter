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
- **Ordre des lieux d'un tome :** ceux vus lâcher le tome le plus souvent d'abord (lieu principal de
  la liste, bulle d'aide, Localiser, téléportation) ; un lieu listé que personne n'a vu le lâcher
  passe après, un lieu du réseau non retrouvé depuis 90 jours aussi, une source périmée en dernier.
- **Lieux de drop :** ils sont lus en jeu dans **EbonholdHub** (ou EbonCompletionist) et convertis en
  coordonnées de la vraie carte. S'y ajoutent les lieux trouvés par les joueurs (§11) et les sources
  de l'atlas d'EbonBuilds. Sans EbonholdHub ni EbonCompletionist, seuls ces deux-là existent.
- **Atlas d'EbonBuilds :** EbonBuilds note, chez ses utilisateurs, sur quel monstre et dans quelle
  zone chaque tome est tombé, et met ces sources en commun entre eux. L'addon les lit en jeu dans les
  données d'EbonBuilds (jamais modifiées) :
  - pour chaque tome, les **8 sources les plus vues** qu'aucune autre source ne cite déjà (même nom
    de monstre) ; une source sans monstre seulement si aucune autre de l'atlas ne donne sa zone ;
  - le lieu est le nom de la zone. Un point sur la carte seulement là où EbonBuilds en a noté un (les
    loots de son utilisateur) ; sinon la téléportation vise le **centre de la zone** (distance avec
    « ~ »), et un raid ou un donjon n'a pas de point ;
  - noms de zone en anglais (client anglais) : sur un client dans une autre langue, la zone reste un
    nom, sans point ni téléportation ;
  - la fenêtre Sources et la bulle d'aide disent « atlas EbonBuilds : N drop(s) » ; l'atlas est relu
    quand il change (vérifié toutes les minutes).
- **Indice du serveur :** le journal des Echos de ProjectEbonhold donne pour chaque tome une phrase
  « Can be found on … » (type d'ennemis ou boss). L'addon la lit en jeu et l'affiche dans la bulle
  d'aide de la liste et en haut de la fenêtre Sources.
- **Tomes de raid** (20 tomes qu'EbonholdHub ne place nulle part) : rattachés aux boss de la
  **Citadelle de la Couronne de glace** et du **Sanctum rubis** que nomme ce journal (le conseil des
  princes de sang : les trois princes). Le lieu affiché est l'entrée du raid, avec l'id du boss (lien
  Wowhead exact, TP vers le checkpoint le plus proche, sources périmées).
- **Aucun lieu du tout :** la liste affiche l'indice du serveur en gris, sinon « inconnu » (elle
  n'affichait rien).

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
- **Annonces pas encore chargées :** une annonce d'un objet que le client ne connaît pas encore
  (premier passage, cache vidé) arrive sans nom. La page attend ses données jusqu'à 3 s. Si elles
  n'arrivent pas, le chat le dit, les tomes non vus **gardent leur état** (pas de faux « pas en
  vente ») et une recherche exacte ne change pas le prix enregistré.
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
  1. **les sources vues lâcher le tome le plus souvent** : joueurs du réseau qui l'ont trouvé là,
     drops de l'atlas d'EbonBuilds, drops comptés par les compteurs de cadavres (les tiens et ceux
     des autres). Une source listée que personne n'a vu le lâcher (peut-être obsolète) passe après ;
  2. à égalité : les sources joignables par téléportation, la plus proche d'un checkpoint en
     premier ; celles dont seule la zone est connue (atlas d'EbonBuilds), mesurées depuis le centre
     de la zone ; celles sans checkpoint débloqué sur ce continent ; celles sans position ;
  3. puis les lieux du réseau non retrouvés depuis 90 jours, et en dernier les sources périmées.
- **Chaque ligne indique :**
  - le monstre (#id s'il est connu, « recherche » sinon, « créature d'Ebonhold » si elle n'existe pas
    sur Wowhead) et le lieu ;
  - « N drop(s) vu(s) » quand des drops y ont été vus ;
  - le checkpoint et sa distance (vert), ou le checkpoint à débloquer (orange) ; « ~ » devant la
    distance quand elle part du centre de la zone ;
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
  - une source dont seule la zone est connue (atlas d'EbonBuilds) : depuis le centre de la zone
    (distance avec « ~ »), et seulement si aucune source précise n'a de checkpoint ;
  - un lieu dans un **raid ou un donjon** (carte de l'instance, sans point sur les cartes du monde) :
    depuis la pierre de rencontre de son entrée (checkpoint de ProjectEbonhold du même nom, par
    exemple « Black Temple ») ;
  - avec plusieurs sources, la source retenue est la première de la fenêtre Sources (la plus vue
    lâcher le tome) qu'un checkpoint dessert ; jamais une source périmée tant que la première est
    bonne.
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
- **Build Echo Builder** (project-ebonhold.com/tools/echo-builder) : la même case accepte son lien
  (« Copy link »), son texte (« Copy build », qui finit par le lien) ou le build seul
  (`200044-200479-…`). Le lien contient les ids des Echos (`?b=id[.piles]-…[!verrouillés]&c=classe`).
  - Un Echo dont l'id exact est débloqué par un tome devient ce tome, en **1 exemplaire** (le tome
    débloque l'Echo, quel que soit le nombre de piles).
  - L'aperçu sépare : **tomes apprenables** (ajoutés), **déjà appris** (non ajoutés), **Echos de
    base** sans tome (ignorés), avec leurs noms. Après l'import, les listes complètes s'affichent
    dans le chat.
  - Si le build contient des tomes déjà appris par ce personnage, une case **« Ajouter aussi les N
    tome(s) déjà appris »** apparaît (décochée) : cochée, ils sont ajoutés quand même (pour un autre
    personnage, ou pour les revendre). Elle se décoche après chaque import.
  - Sur les 546 Echos d'Echo Builder, 157 seulement ont un tome (tous connus de l'addon) : les
    autres s'obtiennent sans tome. Le tome d'un Echo rare ne couvre pas ses versions commune et peu
    commune, qui ont leur propre id et sont de base.
- **Envoi direct :** « Envoyer à : » (+ bouton Cible) ou `/eth send Nom`, par message d'addon
  chuchoté.
  - Le joueur doit avoir l'addon : il reçoit « X vous envoie une wishlist » → Voir / Ignorer, et
    Voir ouvre l'import avec l'aperçu.
  - L'expéditeur reçoit un accusé de réception, « pas de réponse » après 12 s, ou « refusé ».
  - Au plus 3 envois par minute sont acceptés d'un même joueur.

## 11. Le réseau entre joueurs

- **EbonAPI :** le partage passe par l'addon **EbonAPI** (Siphelis,
  [github.com/Siphelis/EbonAPI](https://github.com/Siphelis/EbonAPI), aussi dans Ebonhold Addon
  Manager), que chaque joueur installe à part. Sans lui, tes trouvailles restent chez toi et tout le
  reste marche ; le chat le dit une fois par version de l'addon, 20 s après la connexion.
- **Quand tu obtiens un tome sur un monstre**, à la main ou par le Greedy Scavenger, ou que tu le
  vois dans la fenêtre de butin sans le prendre (sacs pleins, jet gagné par un autre) :
  - l'addon note le tome, la position, le monstre et son id (ou les monstres possibles, §12), la
    zone, l'heure et **ton nom de personnage** ;
  - il garde ce lieu et le publie s'il est nouveau ou s'il confirme un lieu connu (3 s après :
    plusieurs changements partent ensemble).
- **Un jeu de données par tome** (`T<id du tome>`) : ses lieux, ceux de tous les joueurs mis
  ensemble, 12 au plus (les plus confirmés, puis les plus récents). EbonAPI le transmet de joueur en
  joueur : annonce 15 s après un changement, échange avec chaque joueur qui arrive, puis un tour
  toutes les 2 min avec ceux qui n'ont pas les mêmes données.
- **Permanent :** EbonAPI garde dans ses données sauvegardées les jeux de données de tous ses addons,
  aussi chez les joueurs qui n'ont pas EbonTomeHunter mais un autre addon d'EbonAPI (AutoCallboard,
  SkillTreeAutoLoad…). Une trouvaille arrive donc **même entre joueurs jamais connectés en même temps** :
  elle passe par ceux qui les ont croisés.
- **Fusion :** chaque client prend un jeu de données plus récent que le sien, y fusionne ce qu'il sait
  et, s'il sait plus, republie l'union.
  - Même carte, à moins de 4 % de la carte et même monstre = même lieu, qui gagne « +1 joueur ».
  - Chaque client garde les mêmes valeurs (plus petit nom de trouveur, plus petit point, texte de
    zone le plus précis, plus grand nombre de joueurs, date la plus récente) : tout le monde finit
    avec le même texte, sans republier sans fin.
  - L'état d'un jeu de données est l'heure × 1000 plus une somme de contrôle de son texte : deux
    joueurs d'un groupe qui publient des lieux différents dans la même seconde n'ont pas le même
    état, et l'un prend celui de l'autre.
- **À la réception :** tome connu, position sur la carte, date plausible. Refusés : un code
  d'échappement de WoW (`|c` couleur, `|H` lien…) ou un caractère de contrôle (l'addon n'en publie
  jamais), un jeu de données daté de plus d'un jour dans le futur.
- **Alerte :** un nouveau lieu d'un tome de ta wishlist, trouvé il y a moins d'une heure, s'affiche
  dans le chat (qui, quel tome, où, sur quel monstre).
- **Sources périmées :** les compteurs de cadavres et les signalements (§11 bis) voyagent dans un
  second jeu de données par tome (`E<id>`) : pour chaque source et chaque joueur, sa ligne la plus
  récente.
- **Premier lancement de la 3.0 :** les lieux connus avant (2.x) sont gardés et publiés.
- **Bouton réseau** (fenêtre principale, à gauche de Scan) : **Réseau** (EbonAPI dans son canal),
  **Connexion…**, **Sans EbonAPI** ou **Réseau coupé**.
  - Bulle d'aide : lieux et tomes connus, tomes partagés sur le réseau, version de l'addon (et une
    plus récente si EbonAPI en a vu une). La bulle d'aide du bouton de la minimap reprend ces lignes.
  - Clic : annonce tout de suite tes données aux joueurs connectés, toutes les 30 s au plus.
- **`/eth net`** affiche l'état ; **`/eth net sync`** fait comme le clic.
- **Couper le réseau** (options, sous-panneau « Réseau et alertes ») : rien n'est publié ni pris en
  compte. En le rallumant, ce qu'EbonAPI a reçu entre-temps est fusionné et tes trouvailles publiées.
- **Nouvelle version :** EbonAPI annonce la version de chaque addon et prévient lui-même quand une
  version plus récente d'EbonTomeHunter existe.
- **Limites :**
  - les versions 2.x (leur propre canal caché) et 3.x ne se voient pas ;
  - les lieux reçus ne sont pas vérifiables (chacun affiche qui l'a trouvé et combien l'ont confirmé) ;
  - EbonAPI ne rejoint son canal que si un addon s'en sert : EbonAPI seul ne transmet rien ;
  - WoW limite chaque personnage à **10 canaux de discussion**. EbonAPI utilise un canal caché commun
    à tous ses addons ; s'ils sont tous pris, ni envoi ni réception. Pour libérer une place :
    `/chatlist`, `/leave <numéro>`, puis `/reload` ;
  - EbonAPI rejoint son canal dès la connexion, parfois avant que le jeu te rende tes propres
    canaux : l'un d'eux peut alors changer de numéro ;
  - un jeu de données forgé, daté très loin dans le futur, est refusé par EbonTomeHunter mais gardé
    tel quel par EbonAPI chez les joueurs qui n'ont qu'un autre de ses addons : chez eux, ce tome ne
    se met plus à jour. Les utilisateurs d'EbonTomeHunter continuent de se l'échanger directement.

## 11 ter. L'historique des drops

Bouton **Historique** de la fenêtre principale, ou `/eth history`.
- Tous les lieux de drop partagés sur le réseau, **du plus récent au plus ancien** (300 au plus) :
  **quand**, **quel tome** (couleur de qualité), **qui** l'a trouvé (+N : joueurs qui l'ont
  confirmé), **où** (zone - sous-zone), **quel monstre**.
- Case **« Mes trouvailles seulement »**.
- Un clic sur une ligne ouvre la fenêtre Sources du tome.

## 11 quater. Statistiques de kills

- L'addon compte, par créature (id de PNJ), les monstres que toi ou ton groupe avez combattus puis
  tués : une écriture dans une table par kill, 600 créatures au plus (les moins tuées sont
  oubliées). Aucun impact visible sur le jeu.
- Ces compteurs ne sont envoyés **que sur demande** de l'addon de développement (`/ethdev stats`,
  pour le mainteneur), par le canal d'EbonAPI : les 60 créatures les plus tuées et le total, une
  réponse toutes les 30 s au plus. Rien n'est envoyé automatiquement. Couper le réseau coupe aussi
  ces réponses.

## 11 bis. Les sources qui ne lâchent plus leur tome

Un monstre listé pour un tome (EbonholdHub ou réseau) peut ne plus le lâcher après un patch.
- **Preuve automatique :** quand tu ouvres le butin d'un cadavre d'un monstre listé et que le tome
  n'y est pas, l'addon compte un « cadavre sans le tome » pour ce tome et ce monstre (un cadavre
  rouvert ne compte qu'une fois). Un tome présent dans la fenêtre mais pas pris (sacs pleins, jet
  gagné par un autre) compte comme un drop. Seuls les cadavres que **tu** loots comptent : on est sûr qu'il n'y
  avait pas le tome. Le Greedy Scavenger n'est pas compté. Ces compteurs sont partagés sur le réseau.
- **Signalement :** le bouton **« Plus bon ? »** de la fenêtre Sources signale la source (recliquer :
  « Annuler »).
- **Source jugée périmée** quand, depuis le dernier drop connu (le tien, celui d'un autre, un lieu du
  réseau) : **assez de cadavres sans le tome pour que la malchance ne l'explique plus**, ou **3
  joueurs** l'ont signalée, ou **toi** tu l'as signalée (pour toi seulement).
- **Malchance :** un tome rare peut manquer beaucoup de cadavres de suite. Le seuil suit donc le taux
  de drop de la source :
  - taux = drops ÷ cadavres dans l'historique de tous les compteurs de la source (sans la série en
    cours, celle qu'on juge), plus un a priori de 1 sur 200 qui pèse comme 200 cadavres ;
  - seuil = le nombre de cadavres sans le tome que la malchance ne donne qu'1 fois sur 100
    (ln 0,01 ÷ ln (1 − taux)), entre 500 et 5000. Exemples : rien vu → 1 sur 200 → 919 cadavres ;
    1 drop sur 3000 cadavres → 5000 ; 20 drops sur 1000 → 500 ;
  - un autre joueur compte pour la moitié du seuil au plus : il en faut au moins deux, ou toi seul ;
  - **un seul drop remet la source bonne**, même après une longue série sans : la malchance ne
    prouve rien.
- **Rien n'est supprimé :** la source est grisée dans la fenêtre Sources, avec la raison (« ne le
  lâche probablement plus (0 drop sur 950 cadavres lootés (d'habitude 1 sur 200)) »), et passe en
  dernier pour la téléportation et Localiser. Si le tome y retombe, elle redevient normale.
- **Âge des lieux du réseau :** la fenêtre Sources affiche « trouvé il y a … ». Les plus récents
  passent devant, et un lieu non retrouvé depuis 90 jours passe après les autres.

## 12. D'où vient un tome (loot à la main ou Greedy Scavenger)

- **Loot à la main :** le monstre est le cadavre ouvert (celui sous la souris, sinon la cible
  morte), à la position où la fenêtre de butin s'est ouverte.
- **Greedy Scavenger** (familier d'Ebonhold qui ramasse tout seul) : il ne laisse **aucun message**.
  - L'addon voit le tome **apparaître dans les sacs**. La position est la tienne.
  - Un seul type de monstre combattu puis tué dans la dernière minute (toi ou ton groupe) : c'est
    lui.
  - Plusieurs : **l'indice du serveur** sur le tome (« Can be found on … ») les départage :
    - fort : son nom est celui de l'indice, il a été vu **lancer un sort de l'indice** (journal de
      combat), son **type de créature** est celui de l'indice (vu sur sa plaque de nom, en cible ou
      au survol) ;
    - moyen : sa classe correspond (« Mage-type enemies »), c'est une source connue du tome (lieux
      d'EbonholdHub, du réseau, boss de raid, atlas d'EbonBuilds) ;
    - faible : un mot de son nom (« Fire Elemental » : flame, ember…) ;
    - un monstre qui se détache (au moins « moyen ») est retenu.
  - Sinon le lieu garde jusqu'à **4 monstres possibles**, les plus probables d'abord (« un de : A /
    B »). Chaque nouveau drop au même endroit, le tien ou celui d'un autre joueur, ne garde que les
    monstres tués à chaque fois ; quand il n'en reste qu'un, il devient le monstre du lieu (« déduit
    de plusieurs drops »).
  - Aucun monstre tué dans la dernière minute : pas de lieu.
  - Les sorts des indices sont en anglais : sur un client dans une autre langue, seuls le nom, la
    classe, le type et les sources connues servent.
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
- **Un joueur du réseau en trouve un (nouveau lieu, trouvé il y a moins d'une heure) :** une ligne
  avec le lieu et le monstre.
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
| `/eth history` | historique des drops |
| `/eth send <nom>` | envoyer sa wishlist à un joueur |
| `/eth net` (`sync`) | état du réseau (annoncer tes lieux maintenant) |
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
