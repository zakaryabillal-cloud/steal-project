# RIFT HEIST — Plan V2 (validé)

> Statut : **Phases 1 (Fondations), 2 (Monde V2) et 3 (Audio dynamique) terminées.** Phases 4 à 11 : non commencées (attente d'autorisation).

Boucle principale conservée : *Faille → Reliques → Vol/PvP → Sanctuaire → Essence → Progression → contenu plus difficile → récompenses rares.*
Boucle secondaire V2 : *Collecter → améliorer → Power ↑ → boss → drops exclusifs / Forge → build & collection → contenu supérieur*,
qui coexiste avec *Voler → poursuivre → défendre → sécuriser* sans le remplacer.

---

## 1. Décisions validées

| Sujet | Décision |
|---|---|
| Protection pendant un boss | **Oui** : protection « Expédition » du Sanctuaire pendant la participation au combat uniquement (fin à la mort, à la sortie ou à la fin du combat). |
| Reliques de boss | **Piédestaux trophées non volables** (1–3, débloqués par le Power record). Les reliques de la Faille restent volables et au cœur du PvP. |
| Bouton Frappe | **Uniquement dans l'arène.** Hors arène : aucun système de PV, gameplay centré sur vol / poursuite / défense / capacités / contrôle. |
| Daily Rewards | Calendrier 7 jours **sans remise à zéro** (un jour manqué met en pause). |
| Boutique Robux | Cosmétiques + confort : **2ᵉ preset de loadout**, **plafond hors-ligne étendu**. **Pas de boost d'Essence achetable** au lancement. Jamais : vitesse de vol, protections, puissance de capacités, reliques, loot/chance de boss, coffres aléatoires payants. |
| Ordre des phases | Fondations → Monde V2 → Audio → Capacités → Cosmétiques → Boss → Événements → Daily → Boutique → Finition. |
| Validés en bloc | Power actuel + Power record ; Forge + matériaux de boss ; Boss Codex ; Void Warden, Forgeheart, Tempest Seraph ; boss secret lié à l'Éclipse ; événements V2 ; harmonisations limitées à 6 reliques ; anti stun-lock ; Sync chaud/froid ; architecture serveur autoritaire. |

---

## 2. Architecture V2 (cible)

```
Shared/Config/  Abilities, Power (✅ phase 1) · Bosses, Loot, Daily, Cosmetics, Store, Music (à venir)
                Events (étendu en phase 7)
Shared/         Power, Status (✅ phase 1)
Server/Core/    Scheduler (✅ phase 1)
Server/Services StatusService, AbilityService (framework) (✅ phase 1)
                WorldDirector, BossService, LootService, ForgeService, CodexService,
                DailyService, BoostService, CosmeticService, MarketService (à venir)
Server/Abilities/<Module>   logique serveur d'une capacité (✅ Dash, Pulse)
Server/Bosses/<Id>          un module par boss (à venir)
Client/Abilities/<Module>   prédiction + ressenti client (✅ Dash, Pulse)
Client/Controllers          MusicDirector, BossFX, Telegraphs, StatusFX, CosmeticFX, EventWorldFX (à venir)
Client/UI/Screens           Loadout, BossPortal, BossHud, Codex, Daily, Premium, Forge (à venir)
```

Principes : le serveur décide (positions, touches, loot, achats), le client affiche ; boss = ancre serveur + visuels
client (même modèle que les reliques) ; un message par attaque de boss (type, position, rayon, heure d'impact) ;
Sync découpé chaud / froid.

---

## 3. Phases

| # | Phase | Contenu | Statut |
|---|---|---|---|
| 1 | Fondations | Schéma v2 + migration, garde anti-écrasement, Scheduler, StatusService, framework de capacités (Dash/Repousser portés), Power + record + HUD, Sync chaud/froid | ✅ |
| 2 | Monde V2 | +35 % de surface (anneau extérieur, grottes, corniche, ruines, landmarks, points de grappin), routes alternatives Faille↔Sanctuaires (trajet direct inchangé : 172 studs), panneaux de Sanctuaire en studs + distance max 150 | ✅ |
| 3 | Audio dynamique | MusicDirector (Boss > Poursuite > Événement > Faille > Exploration), fondus, Sounds v2 documenté, aucun ID inventé | ✅ |
| 4 | Capacités | Blink, Grappin (points dédiés), Onde de givre, Piège runique, Bouclier, Leurre, Phase spectrale ; déblocages par Power record + Essence/matériaux ; UI de loadout (au Sanctuaire) ; harmonisations (Storm Crystal, Void Cube, Magma Heart, Frost Lotus, Chrono Glass, Cosmic Eye) | — |
| 5 | Cosmétiques (moteur) | possession / équipement / rendu (traînées, auras, skins de Sanctuaire, effets de dépôt, titres, emotes) | — |
| 6 | Boss 1 | Portail (toutes les ~10 min, 60 s d'ouverture), écran pré-combat avec probabilités, arène céleste, Void Warden, loot individuel, Codex, Forge, protection Expédition, piédestaux trophées | — |
| 7 | Boss 2 & 3 | Forgeheart, Tempest Seraph | — |
| 8 | Événements V2 | Rift Overload, Void Storm, Golden Surge, Eclipse enrichis + Marée Céleste, Chute d'Étoile ; WorldDirector (pas de chevauchement boss / événement modifiant la carte) | — |
| 9 | Daily | 7 jours sans reset, horloge serveur, boosts en temps de jeu | — |
| 10 | Boutique | MarketplaceService, IDs en config (0 = désactivé), ProcessReceipt idempotent | — |
| 11 | Finition | perf/mobile, simulation d'équilibrage, README V2, rbxl | — |

---

## 4. Données (DataStore)

Store inchangé : `RiftHeist_Player_v1`, clé `u_<UserId>`. Le numéro de **schéma** évolue, pas le nom du store.

| Schéma | Contenu ajouté | Phase |
|---|---|---|
| 1 | lancement (V1) | — |
| **2** | `abilities = { unlocked, loadout }`, `power = { peak }` | **1 ✅** |
| 3+ | `boss`, `materials`, `cosmetics`, `daily`, `boosts`, `receipts` (chacun dans sa phase, avec sa migration) | 5–10 |

Règles :
- les migrations **ajoutent** des champs, ne suppriment jamais de progression ; `normalize` assainit tout ensuite ;
- `normalize` travaille sur une copie : l'enregistrement brut n'est jamais modifié ;
- **garde anti-écrasement** : un enregistrement dont le schéma est plus récent que celui du serveur n'est ni verrouillé,
  ni normalisé, ni réécrit (au chargement *et* dans chaque transformation `UpdateAsync` de sauvegarde) ;
- **déploiement** : un serveur V1 déjà en ligne n'a pas cette garde (elle n'existait pas en V1). À la publication de la V2,
  utiliser *Shut Down All Servers* (ou la migration de serveurs de Roblox) pour qu'aucun serveur V1 ne charge un profil V2.
  À partir de la V2, toutes les versions suivantes sont protégées.

---

## 5. Contenus (rappel du plan validé)

- **Capacités** : 3 emplacements (Mobilité Q/R1, Contrôle F/L1, Utilitaire R/R2) + Sceau (G/Y). Chaque capacité :
  utilité vol/poursuite, cooldown, contre-jeu, validation serveur, clavier/manette/mobile, pas de stun-lock.
- **Anti stun-lock** : contrôle dur (stun/root/knockback) → immunité `max(2,5 s, durée + 1 s)` ; contrôle dur ≤ 2 s ;
  ralentissements non cumulables (le plus fort, max 60 %, ≤ 3 s) ; bouclier bloque tout contrôle.
- **Power** : reliques exposées (rareté ×~1,7 par palier, niveau +30 %/niveau, mutation ×1,2–1,8) + palier du Sanctuaire
  + RiftDex + Résonance (+ Codex en phase 6). Jamais dépensé, jamais utilisé en PvP ; déblocages sur le **record**.
- **Boss** : Void Warden (rang I), Forgeheart (rang II), Tempest Seraph (rang III), Oracle de l'Éclipse (secret) ;
  patterns télégraphiés, phases, PV adaptés au nombre de joueurs, loot individuel avec contribution minimale,
  probabilités affichées, Forge (ex. 30 Éclats du Néant → relique exclusive garantie).
- **Événements V2** : chaque événement change au plus 2 éléments physiques et s'explique en une ligne.
- **Économie** : récompenses d'Essence (boss, daily) exprimées en minutes de production du joueur.

---

## 6. Phase 1 — ce qui a été livré

- **Schéma v2** (`Server/Core/DataSchema`) : `MIGRATIONS[1]` (1 → 2), assainissement des nouveaux champs
  (capacités inconnues retirées, capacités par défaut toujours débloquées, loadout validé emplacement par emplacement,
  Power record borné), `versionOf` / `isNewer`.
- **Garde anti-écrasement** (`Services/DataService`) : statut `"newer"`, notification `n.dataNewer`, sauvegardes refusées.
- **Scheduler** (`Server/Core/Scheduler`) : une seule connexion Heartbeat ; les 11 anciennes boucles `while true`
  (Plot, Economy ×2, Character, Events, Rift ×2, Carry ×2, Movement, autosave) et le Heartbeat de synchronisation
  sont devenus des jobs isolés (13 jobs avec le nouvel audit du Sync) : erreur contenue, job qui yield jamais
  ré-entré, pas de rafale de rattrapage.
- **Status** (`Shared/Status` + `Services/StatusService`) : règles pures + application (stun, root, slow, bouclier,
  phase), vitesse de marche intégrant root/slow, statut remis à zéro au respawn et jamais sauvegardé.
- **Framework de capacités** : `Config/Abilities` (slots, catalogue), `Services/AbilityService` (validation : capacité
  connue, équipée, personnage vivant, statut, cooldown par id, payload assaini), `Server/Abilities/{Dash,Pulse}`,
  `Client/Abilities/{Dash,Pulse}`, remotes `UseAbility` et `SetLoadout` ; `Dash` / `Pulse` V1 conservés comme alias.
- **Power** : `Shared/Power` + `Config/Power`, calcul serveur dans `EconomyService.recompute`, record dans la sauvegarde,
  leaderstat `Power`, ligne Power dans la carte Essence du HUD (record affiché quand il diffère).
- **Sync chaud/froid** (`Server/Core/Snapshot`) : `Sessions.markCold` aux points d'écriture, audit périodique qui
  détecte une écriture non marquée (compteur vérifié par les tests), fusion côté client (`Store`).
- **Tests** : 283 vérifications (148 V1 + 135 nouvelles), dont migration d'une **vraie sauvegarde V1** produite par le
  code V1 (`tests/fixtures/save_v1.json`).

### Écarts au plan (et pourquoi)

1. **Schéma v2 limité aux champs de la phase 1** (`abilities`, `power`). Ajouter dès maintenant boss/daily/cosmétiques
   aurait figé des formats non utilisés et non testés ; chaque phase ajoutera ses champs avec sa propre migration
   (v3, v4…), ce que la garde anti-écrasement rend sûr.
2. **Production collectée immédiatement sur le Noyau.** Le passage au Scheduler a révélé une course déjà présente en
   V1 (la production tombant juste après une collecte restait dans le Noyau jusqu'à 0,4 s, même en se tenant dessus).
   La production d'un joueur qui se tient sur son Noyau est maintenant encaissée immédiatement.
3. **Un seul remote `Sync`** pour les deux moitiés (au lieu de deux remotes) : l'ordre des messages est garanti et
   l'état initial est complet dès le premier message.
4. **Touche manette de l'emplacement Utilitaire : R2** (le plan évoquait « X long », mais X est déjà la touche
   d'interaction des ProximityPrompts).
5. **UI de loadout reportée à la phase 4** (avec les nouvelles capacités) : en phase 1, il n'existe qu'une capacité
   par emplacement ; l'API serveur `SetLoadout` est livrée et testée.
6. **`GameConfig.Abilities.Pulse.SteadyTime` supprimé** au profit de `GameConfig.Status.SteadyTime` (une seule source
   de vérité ; même valeur 2,5 s, comportement V1 identique).

### À vérifier dans Roblox Studio (non vérifiable hors moteur)

- Lisibilité de la ligne Power du HUD sur mobile (carte Essence passée de 76 à 102 px de haut).
- Ressenti du Dash / Repousser (inchangés en théorie : mêmes valeurs, même ordre d'opérations).
- Touche R (Utilitaire) et R2 manette : aucune capacité équipée par défaut, donc sans effet en phase 1.
- Migration réelle : jouer en V1 publiée, publier la V2 avec *Shut Down All Servers*, rejoindre → progression intacte.


---

## 7. Phase 2 — Monde V2 : ce qui a été livré

Toutes les positions sont décrites dans `src/shared/WorldFeatures.luau` (une seule source de vérité pour les
builders, le client et les tests). Le cœur V1 (Faille, prairie, rivière, route circulaire, 8 Sanctuaires à
172 studs) est **inchangé** : la surface gagnée est derrière les Sanctuaires, donc **aucun trajet direct
Faille → Sanctuaire ne s'allonge**.

| Zone / élément | Où | Fonction de gameplay |
|---|---|---|
| **Couronne extérieure** | r 212–276, tout autour | Plateau en relief derrière les Sanctuaires, sentier en boucle éclairé : itinéraire « par l'arrière » pour éviter la route circulaire, bosquets qui cassent la ligne de vue. |
| **Corniche haute** | 72° → 208°, Y +26, derrière les Sanctuaires 5–7 | Verticalité : rampes douces aux deux extrémités, falaise intérieure dont on **saute** (fuite à sens unique), 2 pads de rebond pour y remonter, vue sur trois Sanctuaires (interception). |
| **2 grottes sous la rivière** | Est (67,5°) et Ouest (247,5°) | Raccourci caché prairie de la Faille → ravine → passage en ruines entre deux Sanctuaires. Étroit (10 studs), éclairé par des cristaux : idéal pour semer ou pour une embuscade au Repousser. |
| **Passages en ruines** | crêtes à 22,5°, 67,5°, 247,5°, 337,5° | La crête entre deux Sanctuaires est abaissée en col : **raccourci latéral entre voisins** (sans passer par la route), murs bas, portes, colonnes, estrade et tour ouverte pour couper la ligne de vue. |
| **Route céleste** | 150° → 157,5°, de la prairie à la corniche | Pad de rebond → 4 îles flottantes → ponts runiques **sans rambarde** → corniche. Raccourci visible et risqué : un Repousser là-haut = chute. |
| **Observatoire** (landmark) | 112,5°, sur la corniche | Tour de ~90 studs avec escalier extérieur en spirale jusqu'à un balcon : poste d'observation pour repérer les voleurs ; faisceau lumineux visible de partout. Le sentier le contourne par le bord de la falaise. |
| **Arche brisée** (landmark) | 202,5° | Porte monumentale effondrée enjambant la falaise et le sentier de la corniche ; blocs tombés = couvert dans la ruelle arrière. |
| **Plateau du boss** (landmark) | 292,5°, promontoire au-delà du bord | Chaussée qui monte vers une esplanade en basalte, cercle de rassemblement, obélisques, portail en anneau **dormant** (`PortalState = "Dormant"`), lave aux pieds du portail. Aucune logique de boss (phase 6). |
| **Points de grappin** (préparés) | 14 ancres (`workspace.World.GrapplePoints`) | Bords de corniche, observatoire, arche, îles, tours en ruines, plateau du boss, îles de la Faille. Attributs `GrapplePoint`, `Kind`, `Range` ; visuel unique (gemme cyan dans un anneau). La capacité Grappin n'existe pas encore. |
| **Panneaux des Sanctuaires** | client (`SanctuaryFX`) | Taille en studs (11 × 3,2) au lieu de 340 × 96 px fixes : ils rapetissent avec la distance ; nom seul au-delà de 60 studs ; masqués au-delà de 150 studs (au lieu de 320). |

Budgets mesurés (monde construit, Sanctuaires palier 1, hors reliques/personnages) : **~3 420 parts**
(V1 : ~2 950 ; budget 4 500), **79 PointLights** (budget 130), **16 émetteurs** de particules dans le monde.
Les budgets sont dans `GameConfig.World` et vérifiés par les tests.

### Écarts au plan (Phase 2) et pourquoi

1. **Sanctuaires laissés à 172 studs** (le plan évoquait ~190) : la nouvelle surface est entièrement derrière eux et
   dans les cols ; les trajets directs ne s'allongent pas du tout, ce qui protège la fréquence des rencontres.
2. **La grotte relie la prairie de la Faille à un col en ruines**, pas directement à un Sanctuaire : un tunnel
   menant tout droit à un Sanctuaire aurait avantagé deux joueurs sur huit. Les deux grottes sont symétriques.
3. **L'Arche brisée enjambe la falaise de la corniche** (porte d'entrée de la corniche) au lieu d'être un simple
   décor sur la prairie : c'est plus lisible et elle marque l'accès ouest de la corniche.
4. **Buissons non collisionnables** : ils accrochaient les joueurs en pleine poursuite (détecté par le test des
   routes). Les troncs et les rochers restent solides.
5. **Rambardes des ponts raccourcies** : en V1 elles dépassaient sur la route circulaire et bloquaient le passage
   (détecté par le test des routes).

### Ce que le moteur de rendu des aperçus ne reproduit pas

Les images de `docs/previews/` viennent d'un rastériseur logiciel (`tools/render`), pas de Roblox :
- pas d'éclairage Future (ombres, PointLights, reflets), pas de bloom réel ni de SunRays/DepthOfField ;
- **Beams, ParticleEmitters et ForceField non rendus** : anneaux du portail et des ancres de grappin, faisceau de
  l'observatoire, cascades d'étoiles, particules de la Faille et du monde sont absents des images ;
- terrain affiché en maillage de 4 studs aplati, couleurs de matériau unies (pas de textures, pas d'herbe
  décorative, eau sans transparence ni vagues) ; les grottes sont dessinées comme des boîtes ;
- Atmosphere/brouillard approximés par un brouillard exponentiel simple ; pas de ciel Roblox ni de nuages ;
- BillboardGui (panneaux, jauges) et interface non rendus.
Les vrais rendus (lumières, néons, ambiance) doivent être jugés dans Roblox Studio.

### À vérifier dans Roblox Studio (Phase 2)

- Sensation des **pads de rebond** de la corniche (vitesse verticale 112) et de la route céleste.
- Lisibilité des **ponts runiques** (3 studs de large) sur mobile.
- Rendu réel des **grottes** (taille des voxels de 4 studs : plafond et parois légèrement irréguliers) ; si une
  paroi accroche, élargir `halfWidth` dans `WorldFeatures.Caves`.
- Distance d'affichage et lisibilité des **panneaux** des Sanctuaires.
- Temps de génération du monde au démarrage du serveur (mesuré ~4–6 s dans le simulateur, bien plus rapide dans le
  moteur natif).


---

## 8. Phase 3 — Audio dynamique : ce qui a été livré

Architecture (client, une seule connexion Heartbeat) :

| Module | Rôle |
|---|---|
| `Shared/Config/Music.luau` | Registre de **tous** les emplacements musicaux (id vide = muet) avec type, boucle/one-shot, ambiance, tempo, durée, contexte ; définition des états (priorité, délai d'entrée, maintien, fondus, stinger) ; réglages. |
| `Client/Music/MusicSensors.luau` | Lit l'état répliqué toutes les 0,25 s : attributs `MusicBoss`/`MusicBossPhase` du joueur (réservés au futur service de boss), reliques volées (voleur, victime, ou Légendaire+ volée portée à moins de 70 studs), `EventId` du workspace, distance à la Faille avec hystérésis (entrée 70, sortie 88). |
| `Client/Music/MusicState.luau` | Machine d'état pure : priorités, anti-rebond à l'entrée, maintien après la fin, intervalle minimal avant de redescendre, retour à l'état précédent, repli quand un emplacement est vide. |
| `Client/Music/MusicPlayer.luau` | Lecture : fondu enchaîné à puissance constante, **au plus 2 pistes audibles** (pendant un fondu), pistes mises en pause et reprises là où elles étaient (fenêtre 90 s, 3 pistes max en cache), stingers limités, nettoyage complet. |
| `Client/Controllers/MusicDirector.luau` | Assemble le tout ; `start`/`stop` ; infos de debug. |

États et réglages par défaut :

| État | Priorité | Entrée après | Maintenu après la fin | Fondu entrée / sortie | Pistes (ordre de repli) |
|---|---|---|---|---|---|
| Boss | 5 | immédiat | 1,5 s | 1,2 / 2,5 s | `Boss.<id>.<phase>` → phases inférieures → `Boss.Default.<phase>` |
| Poursuite | 4 | 0,3 s | 6 s | 0,8 / 3 s | `ChaseIntense` (Légendaire+) → `Chase` |
| Événement | 3 | 0,5 s | 2 s | 2,5 / 3 s | `Event.<id>` → `Event.Default` |
| Faille | 2 | 1,5 s | 3 s | 3 / 3 s | `Rift` |
| Exploration | 1 | — | — | 3 / 3 s | `Explore` |

Monter d'un niveau est immédiat (après l'anti-rebond) ; redescendre attend au moins 2,5 s depuis le dernier
changement. Changement de piste au sein d'un état (poursuite → poursuite intense) : 1 s minimum, sauf phases de boss.

Écarts / choix :
1. **Repli quand un emplacement est vide** (`FallThroughWhenSilent`) : une poursuite sans musique fournie ne
   coupe pas la musique d'exploration en cours.
2. **La musique a quitté `Sounds.luau`** (clé `Music` supprimée) pour `Config/Music.luau` ; `Audio.startMusic`
   devient `Audio.startAmbience` (fond sonore `AmbientWorld`, couche séparée de la musique).
3. Les combats de boss et événements V2 n'existent pas encore : leurs **emplacements et la logique de musique
   sont prêts** (attributs `MusicBoss`/`MusicBossPhase` à poser côté serveur en phase 6 ; `EventId` déjà utilisé).

À vérifier dans Roblox Studio : niveaux relatifs des pistes une fois les vraies musiques ajoutées (`volume` par
emplacement), transitions à l'oreille (durées de fondu), boucles sans coupure, et rayon de la zone de la Faille.

Tests : `tests/scenarios/V2Audio.luau` (+75 vérifications, 426 au total) — priorités, anti-rebond, maintien,
retour à l'état précédent, changements rapides, emplacements vides, fondus à puissance constante, 2 pistes
audibles au maximum, reprise, cache borné, stingers, nettoyage, directeur en conditions réelles (zone de la
Faille, poursuite victime / voleur / spectateur, événement, boss via attributs), et vérification qu'aucun ID
n'est fourni dans la configuration livrée.

Patch de configuration (après validation de la phase 3) : 5 emplacements renseignés par l'utilisateur —
`Explore`, `Rift`, `Chase`, `ChaseIntense`, `Stinger.ChaseStart`. Les tests vérifient désormais que ces 5
emplacements portent exactement ces IDs, que tous les autres restent vides, et que les emplacements
Événement / Boss encore vides retombent bien sur la musique inférieure (101 vérifications audio, 452 au total).

Correctif du harnais de test (explique l'échec intermittent signalé en phase 2) : le faux moteur choisissait
la valeur par défaut d'une énumération dans un ordre instable ; `Part.Shape` valait parfois `Ball` au lieu de
`Block` et le test des routes calculait le dessus d'une sphère pour les tabliers de pont. Les valeurs par défaut
sont désormais déterministes et `Part.Shape = Block` comme dans Roblox. Le jeu n'était pas en cause.
