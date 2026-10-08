# RIFT HEIST — Plan V2 (validé)

> Statut : **Phases 1 (Fondations), 2 (Monde V2), 3 (Audio dynamique), 4 (Capacités), 5 (Cosmétiques) et 5.5 (Direction artistique cartoon) terminées.** Phases 6 à 11 : non commencées (attente d'autorisation).
> Toute nouvelle phase suit [`ART_DIRECTION.md`](ART_DIRECTION.md).

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
Shared/Config/  Abilities, Power (✅ phase 1), Music (✅ phase 3), Cosmetics (✅ phase 5) · Bosses, Loot, Daily, Store (à venir)
                Events (étendu en phase 7)
Shared/         Power, Status (✅ phase 1)
Server/Core/    Scheduler (✅ phase 1)
Server/Services StatusService, AbilityService (framework) (✅ phase 1)
                WorldDirector, BossService, LootService, ForgeService, CodexService,
                DailyService, BoostService, CosmeticService, MarketService (à venir)
Server/Abilities/<Module>   logique serveur d'une capacité (✅ les 9 + Common)
Server/Bosses/<Id>          un module par boss (à venir)
Client/Abilities/<Module>   prédiction + ressenti client (✅ les 9)
Client/Controllers          MusicDirector (✅ phase 3), AbilityFX + GrappleTargeting (✅ phase 4), CosmeticRenderer (✅ phase 5) · BossFX, Telegraphs, EventWorldFX (à venir)
Client/UI/Screens           Loadout (✅ phase 4), Cosmetics (✅ phase 5) · BossPortal, BossHud, Codex, Daily, Premium, Forge (à venir)
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
| 4 | Capacités | Blink, Grappin (points dédiés), Onde de givre, Piège runique, Bouclier, Leurre, Phase spectrale ; déblocages par Power record + Essence/matériaux ; UI de loadout (au Sanctuaire) ; harmonisations (Storm Crystal, Void Cube, Magma Heart, Frost Lotus, Chrono Glass, Cosmic Eye) | ✅ |
| 5 | Cosmétiques (moteur) | possession / équipement / rendu : 7 catégories (traînées, auras, effets de transport, thèmes de Sanctuaire, arrivée, sécurisation, titres), 26 cosmétiques, déblocages par la progression, écran Style, budgets de rendu | ✅ |
| 5.5 | Direction artistique « Cartoon & Goofy » | jetons UI cartoon, HUD / menus refaits, monde de jour (palette, matériaux jouet, fleurs, champignons, fanions), Faille avec un visage, visages des reliques, présentation des cosmétiques, `ART_DIRECTION.md` (règles + boss) | ✅ |
| 6 | Boss 1 | Portail (toutes les ~10 min, 60 s d'ouverture), écran pré-combat avec probabilités, arène céleste, Void Warden, loot individuel, Codex, matériaux pour la Forge, protection Expédition, piédestaux trophées | ✅ |
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
| **3** | `abilities.harmonyOff` (interrupteurs d'harmonies) | **4 ✅** |
| **4** | `cosmetics = { owned, equipped }` | **5 ✅** |
| 5+ | `boss`, `materials`, `daily`, `boosts`, `receipts` (chacun dans sa phase, avec sa migration) | 6–10 |

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

---

## 9. Phase 4 — Capacités : ce qui a été livré

Le framework de la phase 1 est **étendu, pas réécrit** : `AbilityService` (validation, cooldown par id,
rate limit), `StatusService` (anti stun-lock), `Scheduler` (un seul job `Abilities.tick` à 0,1 s pour toutes
les capacités), Sync chaud/froid, `MovementGuard`. Dash, Repousser, Sceau et les remotes V1 `Dash`/`Pulse`
restent compatibles.

### Loadout

| Emplacement | Clavier | Manette | Capacités |
|---|---|---|---|
| Mobilité | Q | R1 | Dash *(base)*, Blink, Grappin |
| Contrôle | F | L1 | Repousser *(base)*, Onde de givre, Piège runique |
| Utilitaire | R | R2 | Bouclier, Leurre, Phase spectrale (vide au départ) |
| Sceau (hors loadout) | G | Y | inchangé |

Écran **Capacités** (touche L, croix directionnelle haut, ou bouton rond à gauche des boutons de capacités) :
une carte par capacité (description, valeurs effectives harmonies comprises, état Équiper / Équipée /
Retirer / Débloquer) et la liste des 6 harmonies avec leur interrupteur. **Équiper et changer une harmonie
seulement dans son propre Sanctuaire** ; le serveur vérifie : capacité connue et débloquée, bon emplacement,
emplacement valide, personnage vivant **dans** le Sanctuaire dont la session est propriétaire.

### Valeurs définitives (`GameConfig.Abilities` / `GameConfig.Harmonies`)

| Capacité | Recharge | Effet | Contre-jeu |
|---|---|---|---|
| **Dash** | 3,2 s | élan 82 studs/s pendant 0,18 s (appliqué par le client) | direction prévisible |
| **Blink** | 6 s | téléportation de **16 studs** après **0,3 s** de préparation visible ; ×0,5 en portant (8 studs) ; jamais à travers un obstacle (5 rayons : genoux, taille, tête, 2 latéraux ; marge 1,8) ; sol requis à ≤ 14 studs sous l'arrivée, 5,5 studs de hauteur libre ; jamais dans un Sanctuaire scellé d'un autre | un étourdissement ou un enracinement pendant la préparation l'annule |
| **Grappin** | 9 s | uniquement vers les **14 ancres** ; portée 45 (+3 de tolérance réseau), minimum 8 ; ligne de vue depuis la tête ; traction 80 studs/s (×0,8 en portant), arrivée à 5 studs + petit saut | câble visible ; tout contrôle dur le coupe |
| **Repousser** | 7 s | rayon 12, recul 62, étourdit 0,6 s, fait lâcher les reliques | immunité 2,5 s après un contrôle dur |
| **Onde de givre** | 9 s | rayon 14, ralentit **40 % pendant 2,5 s**, bloquée par les murs ; jamais de recul ni de lâcher | contournable, un ralentissement ne se cumule pas |
| **Piège runique** | 12 s | posé **sous le lanceur** (sol trouvé par le serveur), s'arme en **1 s**, rayon 4,5, ralentit **60 % pendant 2 s**, dure 45 s, **1 par joueur** (le nouveau remplace l'ancien) ; interdit dans le Sanctuaire d'un autre | rune visible de tous ; le propriétaire ne le déclenche pas ; un leurre le fait partir |
| **Bouclier** | 16 s | **2 s** d'immunité au **contrôle dur** (étourdissement, enracinement, recul → donc au lâcher du Repousser) ; le porteur est **ralenti de 20 %** ; les ralentissements passent | bulle visible ; attendre 2 s ; geler la cible |
| **Leurre** | 15 s | copie du joueur (avatar + copie visuelle des reliques portées + même marqueur de transport) qui court **4 s** en ligne droite à sa vitesse (60 studs max), s'arrête avant murs et vides | éclate au premier contrôle (Repousser, Onde, piège) ; l'Œil cosmique le révèle |
| **Phase spectrale** | 14 s | **1,5 s** à traverser les **joueurs** uniquement (groupe de collision `Phase<i>`) ; murs, carte et barrières des autres Sanctuaires bloquent toujours | corps fantomatique, relique portée **toujours visible**, contrôle toujours possible ; l'Œil cosmique la révèle et la coupe |

Toutes les durées et intensités respectent l'anti stun-lock (`GameConfig.Status`) : contrôle dur ≤ 2 s puis
immunité, ralentissements non cumulables (le plus fort, ≤ 60 %, ≤ 3 s), bonus ≤ 4 s (vérifié au chargement
de la config et par les tests).

### Les 6 harmonies

Une harmonie est active quand la relique est **posée sur un piédestal de son propre Sanctuaire** (une relique
portée, ou en train d'être volée, ne compte pas) et n'est pas désactivée dans l'écran Capacités. Calculée par le
serveur à chaque changement de collection (`EconomyService.recompute`) ; le client ne peut rien revendiquer.

| Relique | Capacité | Effet exact |
|---|---|---|
| **Storm Crystal** | Dash | traînée statique entre le départ et la position vue par le serveur 0,25 s plus tard (≤ 18 studs, 1,6 s, largeur 3 de chaque côté) : ralentit de 25 % pendant 1,5 s, une fois par traînée |
| **Void Cube** | Blink | portée 20 studs ; en portant ×0,75 (15 studs au lieu de 8) |
| **Magma Heart** | Repousser → **Éruption** | anneau annoncé 0,35 s, puis rayon 15, recul 78, levée 34, étourdit 0,8 s ; recharge 10 s ; sortir de l'anneau l'esquive, étourdir le lanceur l'annule |
| **Frost Lotus** | Onde de givre | rayon 16, ralentit 50 % pendant 3 s |
| **Chrono Glass** | emplacement Utilitaire | recharges ×0,85 (Bouclier 13,6 s, Leurre 12,75 s, Phase 11,9 s) |
| **Cosmic Eye** | passif | révèle à son porteur (et à lui seul) les leurres et les joueurs en Phase spectrale à ≤ 45 studs ; un leurre touché (≤ 4 studs) éclate ; **tout effet de contrôle du porteur met fin à une Phase spectrale** |

### Déblocages

Achat avec de l'Essence une fois le **Power record** atteint (un vol ne reverrouille jamais rien), depuis
l'écran Capacités (n'importe où). Une notification signale chaque capacité qui devient déblocable.

| Capacité | Power record | Essence |
|---|---|---|
| Bouclier | 40 | 400 |
| Onde de givre | 70 | 1 000 |
| Blink | 110 | 2 500 |
| Piège runique | 170 | 6 000 |
| Leurre | 240 | 12 000 |
| Grappin | 320 | 20 000 |
| Phase spectrale | 420 | 35 000 |

`unlock.materials` est prévu pour les matériaux de boss / Forge (phase 6+) : toute exigence non nulle refuse
le déblocage (`materials`) tant que le système n'existe pas ; aucune capacité de lancement n'en demande.
Test en Studio : `/rh abilities` (tout équipable pour la session, **jamais sauvegardé** : le loadout est
re-validé au prochain chargement), `/rh abilities off`, `/rh cooldowns`.

### Sécurité (serveur autoritaire)

- Le client envoie **au plus une direction** (Blink, Leurre ; tout vecteur fini est normalisé, une « position »
  n'est qu'une direction) ou **un index d'ancre** (Grappin). Destinations, raycasts, cibles, placement des
  pièges, ancres (lues dans `WorldFeatures`, jamais dans le workspace), harmonies et cooldowns effectifs : serveur.
- `validate` avant le cooldown : un Blink bloqué, une ancre hors de portée / sans vue, un piège sans sol ou
  dans un Sanctuaire étranger sont refusés **sans coût** ; le client reçoit `AbilityDenied` et annule sa prédiction.
- `MovementGuard` : l'ancienne fenêtre de grâce totale après un Dash est remplacée par un **seuil relevé**
  (160 studs/s pendant 0,6 s) ; le Grappin reste sous le seuil normal (80 < 120) ; le Blink est un déplacement
  serveur signalé au garde. Une téléportation déguisée en Dash ou en Grappin est toujours détectée.
- Nettoyage : mort, réapparition, déconnexion (`AbilityService.release` avant la résolution des reliques),
  déséquipement, expiration, et balayage toutes les secondes (pièges orphelins, effets de capacités non équipées).
- Spam : limites de débit des remotes (`UseAbility` 4/s, `SetLoadout` 2/s, `UnlockAbility` 1/s,
  `SetHarmony` 2/s) + cooldowns ; tout est contenu par `pcall`.

### Données

Schéma **3** : `abilities.harmonyOff` (interrupteurs d'harmonies). Migration 2 → 3 (tout activé), assainissement
(seules les reliques à harmonie connues, seules les valeurs `true`), garde contre les schémas plus récents
inchangée. Sync : `harmonies` (reliques à harmonie exposées) dans la moitié chaude, `harmonyOff` dans la froide.

### Écarts au plan (et pourquoi)

1. **Bouclier = contrôle dur uniquement.** La phase 1 bloquait aussi les ralentissements ; la spec de la phase 4
   (« protection courte contre le hard CC, pas d'invincibilité ») est appliquée dans `Shared/Status` : les
   ralentissements passent. Le test de la phase 1 qui vérifiait l'ancien comportement a été mis à jour.
2. **Schéma 3** pour les interrupteurs d'harmonies (au lieu de les ranger dans un champ existant) ; les tests de
   la phase 1 qui codaient « 2 = actuel / 3 = futur » comparent maintenant à `SchemaVersion` / `SchemaVersion + 1`.
3. **Ancre `ObservatoryRoof` déplacée** : placée en phase 2 sur l'axe de la tour, 70 studs au-dessus du sol, elle
   n'était atteignable de nulle part (hors portée depuis le sol, dôme et tour bloquant la vue depuis le balcon).
   Une coursive (`RoofDeck`, rayon 10) a été ajoutée autour du dôme et l'ancre posée juste à son bord, côté Faille,
   4 studs au-dessus : on la grappine depuis le balcon et on atterrit sur la coursive. Les 13 autres ancres
   sont inchangées ; un test vérifie que les 14 sont atteignables.
4. **Fenêtre de grâce du Dash supprimée** (faille V1 : 0,6 s pendant lesquelles une téléportation n'était pas
   détectée) au profit d'un seuil relevé.
5. **Harmonies désactivables** (écran Capacités) : Éruption a un vrai compromis (recharge 10 s) ; on peut
   préférer le Repousser rapide.
6. **Repousser** : en français, « Repousser » remplace « Onde » pour éviter la confusion avec l'Onde de givre.
7. **Le leurre n'existe que côté client** (aucune instance serveur) : impossible de le voler, de le faire déposer
   ou de dupliquer quoi que ce soit. Un exploit peut toutefois lire le message réseau et savoir qu'il s'agit
   d'un leurre (inévitable pour un affichage client ; sans effet sur le jeu).
8. **Sons des capacités** : 12 emplacements ajoutés dans `Config/Sounds.luau`, sur des sons intégrés à Roblox
   (`rbxasset://`), `id` vide, aucun ID inventé.

### Tests (phase 4)

`tests/scenarios/V2Abilities.luau` : **+289 vérifications, 741 au total, 0 échec** (les 452 précédentes incluses).
Le harnais gagne `workspace:Raycast` (pièces bloc / sphère / cylindre, terrain en voxels issu de `WriteVoxels` et
des remplissages), `RaycastParams`, la matrice des groupes de collision (limite de 32 groupes vérifiée).

### À vérifier dans Roblox Studio (phase 4)

Préparer 2 joueurs (*Test → Clients and Servers*, 2 joueurs), `/rh abilities` et `/rh essence` sur chacun,
`/rh novice` pour pouvoir voler, `/rh spawn <id>` pour obtenir une relique à harmonie.

1. **Écran Capacités** (L / croix haut / bouton rond) : lisible sur PC, manette (navigation) et mobile (cartes,
   boutons ≥ 44 px, défilement) ; « Au Sanctuaire » hors de chez soi ; équiper / retirer / débloquer ; badge « ! ».
2. **Blink** : préparation visible (0,3 s) ; contre un mur, une rambarde, un pilier fin, une porte : jamais au
   travers ; au bord d'une falaise : reste au sol ; depuis la corniche vers le bas (≤ 14 studs) ; en portant
   (8 studs) ; un étourdissement pendant la préparation l'annule ; sensation du déplacement fait par le serveur
   (léger à-coup possible selon la latence).
3. **Grappin** : le cercle cyan suit la caméra ; les 14 points, en particulier `ObservatoryRoof` depuis le balcon
   (atterrissage sur la coursive) ; traction fluide jusqu'au point + petit saut ; câble visible des deux joueurs ;
   un Repousser coupe le câble ; sans point en vue, bouton grisé.
4. **Onde de givre / Piège runique** : lisibilité de l'anneau et de la rune (armement, déclenchement) ; ralenti
   ressenti ; pas de recul ; un piège par joueur ; le piège disparaît à la mort / au départ.
5. **Bouclier** : bulle visible ; Repousser sans effet ; ralenti de 20 % ressenti ; l'Onde de givre ralentit quand même.
6. **Leurre** : crédible à distance (avatar, animation de course issue du script Animate du joueur, relique copiée,
   marqueur de transport, contour rouge pour la victime) ; éclate sur un Repousser ; révélé (contour violet +
   « LEURRE ») avec un Cosmic Eye exposé.
7. **Phase spectrale** : traverser l'autre joueur (dans un couloir / sur un pont) ; impossible de traverser un mur,
   la barrière d'un Sanctuaire scellé ; la relique portée reste bien visible ; fantôme lisible pour l'autre joueur.
8. **Harmonies** : exposer chaque relique, vérifier l'effet et l'interrupteur ; se faire voler la relique → l'effet
   disparaît ; la récupérer → il revient.
9. **Poursuite complète à 2** : vol → Blink/Dash/Grappin → Onde / Repousser → Bouclier / Phase / Leurre →
   récupération ou sécurisation ; surveiller la sortie serveur (aucun avertissement `MovementGuard` en jeu normal).
10. **Mobile** : boutons de capacités + bouton Capacités + puces d'état sans recouvrir le saut ni le panneau de
    transport ; manette : R1/L1/R2/Y et croix haut.
11. **Sons** : les 12 nouveaux emplacements utilisent des sons intégrés provisoires ; remplacer par vos sons
    (`Config/Sounds.luau`, champ `id`).

---

## 10. Phase 5 — Cosmétiques : ce qui a été livré

**Règle absolue : aucun avantage de jeu.** Les cosmétiques ne sont lus que par `CosmeticService` (possession,
équipement, publication), `DataSchema` / `Snapshot` (sauvegarde, Sync) et, côté client, `CosmeticRenderer`, l'écran
Style et le `Store`. Un test analyse tout `src/` et échoue si un autre module charge `Config/Cosmetics` ou
`CosmeticService`. Le rendu est 100 % client et rien n'en revient au serveur. Un test équipe un cosmétique dans
chaque catégorie et vérifie que vitesse, saut, Power, taux d'Essence, multiplicateur, recharges et réglages des
capacités, groupe de collision, capacité de transport et harmonies sont identiques.

### Catégories (`Config/Cosmetics.Categories`)

| Catégorie | Rendu | Visibilité PvP |
|---|---|---|
| **Traînée** (`trail`) | `Trail` natif sur le `HumanoidRootPart` (durée ≤ 0,6 s, largeur ≤ 2) | fine, courte, jamais devant la caméra |
| **Aura** (`aura`) | `ParticleEmitter` léger autour du personnage (≤ 12 particules/s, taille ≤ 1,6) ; lumière seulement pour l'aura Légendaire | plafonds de nombre et de distance |
| **Transport** (`carry`) | particules autour de la relique portée, **seulement pendant le transport** | n'occulte pas le marqueur de transport (petites particules ≤ 0,4, rayon 1,6–2,2 studs, 4 studs au-dessus du personnage, ≤ 9/s) |
| **Thème de Sanctuaire** (`sanctuary`) | recolore les pièces / lumières d'accent du Sanctuaire + particules d'ambiance | ne touche **jamais** la barrière du Sceau ni l'anneau de dépôt |
| **Arrivée** (`arrival`) | effet unique à la réapparition (anneau, pilier, éclat) | ≤ 40 particules, 1,5 s de recharge par joueur |
| **Sécurisation** (`secure`) | effet unique au dépôt ou à la fusion, sur la relique | idem |
| **Titre** (`title`) | `BillboardGui` « « Titre » » au-dessus de la tête (60 studs max) | **masqué pendant le transport** |

Emplacements futurs prévus sans contenu simulé : sources de déblocage `boss`, `event`, `daily`, `premium`
(`UnlockKinds`, `auto = false`), champ `unlock.productId` réservé à la phase 10, `CosmeticService.grant(session, id,
source)` qui n'accepte que la source déclarée par le cosmétique (aucune remote n'y mène).

### Collection de départ (26)

| Catégorie | Commun | Rare | Épique | Légendaire |
|---|---|---|---|---|
| Traînées | Poussière d'étoiles — *offert* | Sillage de la Faille — Power record 150 | Traînée d'orage — 5 casses | Sillage du Néant — Power record 600 |
| Auras | Braises errantes — 10 dépôts | Halo de givre — 3 reliques récupérées | Couronne céleste — 12 reliques au RiftDex | Manteau d'éclipse — 5 dépôts Légendaire+ |
| Transport | Scintillement — *offert* | Orbite — 25 reliques revendiquées | Queue de comète — Power record 300 | — |
| Thèmes | Pierre d'aube — *offert* | Floraison nébulaire — palier 2 | Flèche d'orage — palier 3 | Singularité — Power record 1 000 |
| Arrivée | Étincelle stellaire — *offert* | Porte de la Faille — Power record 80 | Chute d'étoiles — 2 h de jeu | — |
| Sécurisation | Carillon de cristal — *offert* | Éclosion de nova — 25 dépôts | — | Supernova — 10 casses |
| Titres | Vagabond de la Faille — *offert* | Collectionneur — 8 reliques au RiftDex | Cambrioleur — 3 casses · Gardien — 5 reliques récupérées | Né de la Faille — Power record 500 |

Tous les noms sont originaux (FR/EN dans `Locale/Strings`). Textures : uniquement des textures **intégrées** à
Roblox (`rbxasset://textures/particles/...`) ; aucun ID d'asset externe (vérifié au chargement de la config et par
les tests).

### Déblocages

Calculés par le serveur à partir de ses propres données (`power.peak`, `stats`, RiftDex, palier, temps de jeu
cumulé) : au chargement, à chaque nouveau Power record et toutes les 2 s (`Scheduler`, job `Cosmetics.unlocks`).
Un cosmétique débloqué l'est **pour toujours** (un vol ne retire rien). Notification « Nouveau cosmétique : … »,
ou une seule notification groupée au-delà de 3 d'un coup (rattrapage d'un ancien joueur).

### Sauvegarde (schéma 4)

`cosmetics = { owned = { [id] = true }, equipped = { [catégorie] = id } }`. Migration 3 → 4 : ajoute un inventaire
vide ; `normalize` donne ensuite toujours les 6 cosmétiques de départ. Assainissement : seuls les ids connus avec
la valeur `true` sont gardés (un ensemble : pas de doublon possible), un équipement doit être possédé **et** de la
bonne catégorie, toute autre valeur est retirée. Les sauvegardes V1 / phase 4 migrent sans perte ; un schéma plus
récent (5+) n'est jamais réécrit (garde de la phase 1). Le déblocage Studio (`/rh cosmetics`) n'est jamais écrit :
un cosmétique non possédé encore équipé est retiré au prochain chargement.

### Réplication

Le serveur publie l'équipement en attributs : `Cos_<catégorie>` sur le `Player`, `Theme` sur le modèle du Sanctuaire
(remis à vide quand le Sanctuaire est libéré). Inventaire + équipement voyagent dans la moitié **froide** du Sync
(envoyée seulement quand elle change). Aucun message réseau par effet.

### Protections serveur

Remote `EquipCosmetic(catégorie, id | "")` : limiteur 4/s (rafale 8) ; types vérifiés (chaînes ≤ 32 caractères),
catégorie connue, id connu, id de cette catégorie, **possédé** selon l'inventaire serveur ; `""` retire. Le client
ne peut ni ajouter, ni acheter, ni débloquer quoi que ce soit ; un inventaire falsifié dans son `Store` est écrasé
au Sync suivant.

### Budgets et performance (`Config/Cosmetics.Budget`)

Une **seule** connexion `Heartbeat` (mise à jour 4×/s) pour tous les joueurs ; effets natifs (`Trail`,
`ParticleEmitter`) qui s'animent seuls ; distances × réglage Qualité : traînée 160, aura 90, transport 120, thème 220,
titre 60 studs ; au plus **8 auras** et **3 lumières** actives (les plus proches ; la tienne compte dans les lumières) ;
Qualité Basse coupe les auras et effets de transport des autres ; recharge de 1,5 s par joueur sur les effets uniques.
Nettoyage : effets parentés au personnage (disparaissent avec lui), reconstruits une seule fois à la réapparition,
titres détruits au départ du joueur et au changement de cosmétique.

### Écarts au plan (et pourquoi)

1. **Pas d'emotes** (citées dans le plan initial) : elles demandent des animations, donc des IDs d'asset ; interdit
   sans IDs fournis. Les « effets d'arrivée » et « de sécurisation » les remplacent.
2. **Pas de cosmétiques de boss / événement / quotidien / boutique** : les sources sont prêtes mais rien n'est simulé.
3. **Titres** à la place des « nameplates » complètes : le nom Roblox du joueur reste affiché normalement, le titre
   s'ajoute au-dessus.
4. **Thèmes de Sanctuaire = recoloration** des pièces d'accent existantes (+ particules), pas de géométrie ajoutée :
   aucune pièce de plus à collisionner, la lisibilité du Sanctuaire (barrière, anneau, piédestaux) est intacte.
5. Bouton **Essayer** : aperçu local 5 s de n'importe quel cosmétique (même verrouillé), jamais envoyé au serveur.

### Tests (phase 5)

`tests/scenarios/V2Cosmetics.luau` : **+115 vérifications, 856 au total, 0 échec**.

### À vérifier dans Roblox Studio (phase 5)

Préparer 2 joueurs (*Test → Clients and Servers*), `/rh cosmetics` sur chacun.

1. **Écran Style** (C / croix bas / bouton « Style ») : onglets, cartes, états, conditions, progression ; sur
   téléphone (onglets qui défilent, cartes lisibles, boutons ≥ 44 px) et à la manette (navigation).
2. **Traînées** : visibles en courant, en Dash, en Blink (pas de trait parasite à travers un mur), discrètes.
3. **Auras** : ne masquent pas le personnage ni une relique au sol ; Manteau d'éclipse : lumière douce.
4. **Transport** : l'effet s'allume en portant, le titre se masque, le marqueur de transport reste lisible pour
   l'autre joueur ; il s'éteint au dépôt, au lâcher, au vol.
5. **Thèmes** : chaque thème à chaque palier (`/rh tier 1..5`) ; la barrière du Sceau (G) garde sa couleur ; les
   couleurs reviennent en retirant le thème ; le Sanctuaire d'un autre joueur affiche son thème.
6. **Arrivée / sécurisation** : à la réapparition, au dépôt, à la fusion ; pas de répétition en spam.
7. **Titres** : lisibles, à la bonne hauteur, disparaissent au-delà de 60 studs.
8. **Performance** : 8 joueurs avec tout équipé (MicroProfiler, Qualité Basse / Haute) ; mort, réapparition,
   départ d'un joueur : rien ne reste dans `Workspace.CosmeticFX` ni `PlayerGui.CosmeticFX`.
9. **Sauvegarde** : équiper, quitter, revenir ; `/rh cosmetics off` retire ce qui n'est pas possédé.

---

## 11. Phase 5.5 — Direction artistique « Cartoon & Goofy » : ce qui a été livré

**Changement d'apparence, pas de mécanique.** Aucune règle de jeu, valeur de gameplay, remote, sauvegarde ou
condition de déblocage n'a changé (les 856 vérifications précédentes passent sans modification de leurs attentes).
Règles visuelles pour les phases 6 à 11 : [`ART_DIRECTION.md`](ART_DIRECTION.md).

### Interface
- **Jetons** (`Config/Theme`) : panneaux bleu roi opaques, contours encre, texte blanc avec contour, polices
  Fredoka One / Builder Sans / Luckiest Guy (intégrées), 10 familles de boutons colorés, étoiles de rareté.
- **Kit** : `Button` « chunky » (face + lèvre plus sombre, reflet, enfoncement au clic, secousse si refusé, désactivé
  désaturé, `setKind`), `Modal` (ruban de titre coloré avec emoji, ✕ rouge rond qui déborde, ouverture « pop »),
  `Style` (panneau, carte, pilule, badge, reflet, contraste WCAG), `Juice` (confettis, « +250! », étoiles, rayons,
  plafonnés), `Tween.wiggle` / `popIn`.
- **HUD** : bulle d'Essence géante (gemme qui déborde, pilule verte « +x/s », « +250 » flottant à la collecte),
  barre Power orange, **grille 2×2 de gros boutons emoji** (🚀 Améliorations, 📖 RiftDex, 🎨 Style, 🔧 Réglages),
  objectif avec barre de progression qui gigote quand c'est payable, capacités en gros ronds colorés, sac 🎒 du
  loadout, statuts en pilules avec emoji (💪 👻 💫 🌱 🐌), panneau de transport qui devient rouge clignotant en vol.
- **Écrans** : Améliorations (tuiles inclinées, pastilles, « NIVEAU +1 ! » + confettis), RiftDex (cartes avec
  projecteur de rareté, ★), Style (onglets emoji, pastilles de statut), Capacités (couleur du bouton = action :
  débloquer jaune, équiper vert, retirer rouge), Réglages, Inspect, découverte (assiette de rareté, autocollant
  « NOUVEAU ! », confettis, étoiles), notifications (toasts colorés avec emoji), annonces, bannière d'événement,
  écran de chargement ensoleillé (nuages, portail, logo qui rebondit), invites colorées par action, panneaux de
  Sanctuaire à la couleur du propriétaire, étiquettes de reliques avec pastille de rareté, marqueurs de transport,
  « BONK! » quand on se fait repousser.

### Monde
- **Éclairage** de plein jour (`Config/Palette`, `World/Ambience`, recopié dans `default.project.json`), nuages
  blancs, atmosphère bleu ciel, événements recolorés en version lumineuse (jamais plus sombre que le crépuscule).
- **Matériaux** : tous les matériaux réalistes rendus en SmoothPlastic (monde et reliques) ; Neon/Glass/ForceField gardés.
- **Palette** : herbe vert vif, chemins biscuit, falaises lavande, rambardes jaunes, rivière turquoise.
- **Décor** : arbres « barbe à papa », 22 massifs de fleurs géantes, 26 champignons à pois (non collidables, hors
  routes), cascades arc-en-ciel au bord de l'île, planètes-bonbons, lampadaires ronds (lumières réduites de 79 à 58).
- **Sanctuaires** : fondations pastel à la couleur du propriétaire (8 couleurs bonbon distinctes), sol crème,
  fanions sur les poteaux et guirlande au-dessus de l'entrée.
- **La Faille** : intérieur violet bonbon, anneaux jaune / cyan / rose, **visage** (yeux globuleux qui suivent
  chaque joueur, clignements, sourcils levés pendant la charge, bouche qui s'ouvre et « BURP! » à chaque relique).
- Monolithes et Tablette runique : plus de croix (aucune lecture « cimetière »).

### Reliques et cosmétiques
- **14 reliques sur 19 ont un visage** (`Relics/RelicFaces`) avec une humeur ; elles se tournent vers le joueur le
  plus proche, se dandinent, clignent ; les 5 autres (Fragment lunaire, Sablier, Œil cosmique — déjà un œil —,
  Astrolabe, Anomalie prismatique) gardent leur silhouette abstraite.
- **Cosmétiques** : couleurs des 26 effets saturées pour le plein jour (plus de violets presque noirs), cartes
  de l'écran Style refaites. Catégories, déblocages et sauvegarde inchangés.

### Écarts au plan / limites
1. **Les emojis ne sont pas utilisés pour les icônes critiques** (capacités, Essence, Sceau, fermer) : dessinées
   pour s'afficher à coup sûr ; les emojis décorent menus, statuts, toasts, onglets.
2. **Pas d'outline 3D** : Roblox ne trace pas de contour encre autour des objets 3D ; le style cartoon du monde
   repose sur les aplats, les couleurs et les silhouettes.
3. **Musique inchangée** : les 5 pistes configurées en Phase 3 sont conservées (ton plus sombre que la nouvelle
   direction ; à remplacer par des pistes plus joyeuses quand vous en aurez — voir ART_DIRECTION §14).
4. **Aperçus** : le moteur de rendu du dépôt ne dessine pas l'interface ; vérifier l'UI dans Studio.

### Tests (phase 5.5)
`tests/scenarios/V2ArtDirection.luau` : **+238 vérifications, 1094 au total, 0 échec**. Le harnais gagne
`Terrain:GetMaterialColor`.

### À vérifier dans Roblox Studio (phase 5.5)
1. **Premier coup d'œil** (*Play*) : écran de chargement ensoleillé, ciel bleu, île verte, Faille rose avec des
   yeux qui te suivent quand tu tournes autour.
2. **HUD** (PC 1080p, téléphone en mode paysage, manette) : lisibilité de l'Essence, des 4 gros boutons emoji
   (vérifier que les emojis s'affichent **en couleur** sur PC, iOS et Android), objectif, capacités, statuts.
3. **Boutons** : survol (grossit), appui (s'enfonce sur la lèvre), refus (secousse), désactivé (grisé).
4. **Modales** (Améliorations, RiftDex, Style, Capacités, Réglages) : ruban, ✕ rouge, défilement, téléphone.
5. **Récompenses** : achat d'amélioration (confettis + « NIVEAU +1 ! »), découverte RiftDex (autocollant), collecte
   d'Essence (« +250 »), déblocage de capacité.
6. **Reliques** : chaque visage de près, regard vers toi, clignement, mutations (Golden, Void…) — yeux toujours blancs.
7. **Faille** : sourcils pendant la charge, « BURP! » à la sortie d'une relique, lisible depuis chaque Sanctuaire.
8. **Monde** : routes et grottes toujours aussi lisibles (fleurs/champignons traversables), Sanctuaires bien
   distincts, fanions, événements (couleurs lumineuses).
9. **Performance** : MicroProfiler avec 8 joueurs ; Qualité Basse ; téléphone d'entrée de gamme.

## 12. Phase 6 — Premier boss : Void Warden — ce qui a été livré

Un système de boss **générique et extensible** (portail, arène, cœurs, Frappe, attaques par formes, phases,
récompenses, Codex, trophées) et un premier boss complet. Phase 7 (Forgeheart, Tempest Seraph) : non commencée.

### Portail et expédition (`Config/Bosses.Portal`, `Services/BossService`)
- **Toutes les 10 min** (première ouverture 4 min après le démarrage du serveur), **ouvert 60 s**, annoncé 30 s
  avant à tout le serveur. Compte à rebours permanent : barre « Boss » du HUD, panneau au-dessus du portail,
  attributs `PortalState` / `PortalOpensAt` / `PortalClosesAt` / `PortalCount` du modèle `BossPlateau`.
- Une seule expédition à la fois par serveur. On rejoint **devant le portail** (≤ 34 studs) : invite `E` / `X` /
  toucher → carte du boss → **ENTRER !**. Seul ou à plusieurs (jusqu'à 12). Salle d'attente : **Prêt !** de
  tout le monde = début 3 s plus tard ; sinon début à la fermeture du portail. Personne = arène détruite.
- **Reliques en main : entrée refusée** (règle la plus sûre : rien ne peut être perdu ni dupliqué). Aussi refusé :
  portail fermé, combat en cours, Power record < 25, trop loin, déjà dedans.
- **Arène séparée** à 1 600 studs de l'île (`World/ArenaBuilder`, construite à l'ouverture, détruite après) :
  aucune interférence possible avec le PvP de l'île. **Combat limité à 3 min 30** (+ 4 s d'entrée, 7 s de fin).
- **Protection « Expédition »** du Sanctuaire uniquement pendant la participation (`Core/Expeditions`) : elle
  s'arrête à la sortie, au KO, à la mort, à la déconnexion et à la fin du combat. Les voleurs voient « Le
  propriétaire affronte un boss ». Pas d'exploit « se cacher dans l'arène » : AFK 35 s = renvoyé.

### Void Warden (`Server/Bosses/VoidWarden`, `Client/Boss/VoidWardenModel`)
Rang I, difficulté ★★, **1 500 PV +70 % par joueur supplémentaire**, 3 phases. Corps cartoon construit par chaque
client (pièces natives, ~30) qui suit une **ancre serveur invisible** (même modèle que les reliques).

| Attaque | Télégraphe | Comment l'éviter | Phases |
|---|---|---|---|
| Coup de balai (`broom_wave`) | 1,2 s : anneau autour de lui qui se remplit, balai levé | **sauter** quand l'anneau de poussière passe (30 studs/s, +4 par phase ; double en phase 3) | 1-3 |
| Flaques collantes (`goo_puddles`) | 1,2 s : disques jaune → rouge sous les joueurs (+ aléatoires) | sortir du cercle ; la flaque reste 4 s et ralentit de 45 % | 1-3 |
| Moutons de poussière (`dust_bunnies`) | 1,1 s : marques au sol, projectiles en cloche | s'écarter des marques | 1-3 |
| Plat ventre (`belly_flop`) | 1,0 s : ombre qui grossit sous la cible | s'écarter ; intouchable en l'air | 1-3 |
| **Grand Ménage** (`big_cleanup`, spéciale) | **2,0 s** : 3 quarts se remplissent, le quart sûr brille « ✨ SAFE ✨ » | aller dans le quart sûr ; en phase 3, 2e balayage (autre quart) ; finit **étourdi 3,5 s** (dégâts ×1,5) | 2-3 |

Phases : **grognon** 100-60 % (pause 1,6 s entre attaques) · **fâché** 60-25 % (1,3 s, spéciale à l'entrée puis
toutes les 4 attaques) · **rouge comme une tomate** < 25 % (1,0 s, spéciale toutes les 3). Changement de phase :
2,2 s de réaction (intouchable). Plus de joueurs = plus de flaques et de moutons (+1 par joueur, max +3).

### Combat
- **4 cœurs** par joueur, 1,5 s d'invincibilité après un coup, recul + 0,35 s d'étourdissement visuel ;
  0 cœur = KO, retour au plateau (toujours éligible s'il a assez contribué). Mort (reset) = comme un KO.
- **Frappe** : `BossStrike` sans argument ; portée 10 studs depuis le corps du boss, recharge 0,4 s, 10 dégâts ;
  arène uniquement. Contrôles : clic gauche / E (PC), X (manette), gros bouton rond FRAPPE (mobile).
- Capacités dans l'arène : **Dash, Blink, Bouclier, Phase** seulement ; aucune capacité ne touche un autre
  combattant ni ne traverse la frontière (`Common.canAffect`).
- Fin : PV à 0 = victoire ; 3:30 = défaite « temps écoulé » ; plus aucun combattant = défaite « balayés » (KO)
  ou « abandon » (sortis / déconnectés).

### Power
- **Power record** : porte d'entrée (25, un nouveau joueur avec quelques reliques) ; **Power recommandé 150**
  affiché face à ton Power actuel (vert / jaune / rouge).
- **Power actuel** : bonus linéaire de Frappe **contre les boss uniquement**, plafonné à **+25 %** (atteint à 1 500).
  Rien dans le PvP ne lit ce bonus. Un débutant seul peut gagner : 150 frappes ≈ 60 s de frappe sur 210 s.

### Récompenses (`Config/Bosses` → `loot`, tirées par le serveur, individuellement)
| Récompense | Probabilité exacte (par joueur éligible) | Détail |
|---|---|---|
| Essence | 100 % | 5 min de **ta** production (minimum 250) |
| Éclats du Néant | 100 % | ×3 à 6 |
| Catalyseur du Néant | 15 % | ×1 (rare) |
| Relique exclusive **Plumeau du Néant** (Légendaire) | 8 % | sur un socle de trophée ; doublon = +1 niveau ; au niveau max = +8 Éclats |
| Traînée exclusive **Bulles de savon** (Épique) | 5 % | doublon = +5 Éclats |

Éligibilité : avoir infligé ≥ **20 % d'une part équitable** des PV, être encore sur le serveur, ni AFK, ni parti,
ni retiré pour exploit. Anti-double récompense : l'id du combat payé est stocké dans le Codex (`lastFight`) et la
sauvegarde est lancée immédiatement. Les probabilités affichées viennent de la même table que le tirage.

### Trophées (`Services/TrophyService`)
3 socles par Sanctuaire derrière le Noyau, débloqués par le **Power record** (0 / 400 / 900). Une relique de boss
n'a **aucune invite** (état `Trophy`) : impossible à voler, ramasser, porter ou dissoudre ; elle produit et compte
dans le Power comme une relique exposée ; elle part avec son propriétaire et revient à la reconnexion.
Les reliques de boss n'apparaissent **jamais** dans la Faille (`bossOnly`, exclues de `Rolls`).

### Boss Codex et matériaux
Codex extensible (une carte par boss de `Config/Bosses`) : découvert (sinon silhouette « ??? »), tentatives,
victoires, meilleur temps, trouvailles rares. Matériaux (`Config/Materials`) : Éclats et Catalyseur du Néant,
stockés pour la **Forge** (non développée) ; recettes prévues documentées (`Materials.PlannedRecipes` :
30 Éclats → Plumeau garanti ; 1 Catalyseur + 10 Éclats → +1 niveau). Les exigences de matériaux des capacités sont
désormais vérifiées et débitées (aucune capacité n'en demande aujourd'hui).

### Audio
Attributs `MusicBoss = "VoidWarden"` et `MusicBossPhase = 1..3` posés par le serveur pendant le combat :
`MusicDirector` passe en état **Boss** (priorité maximale). Aucun ID musical approprié n'existe : les emplacements
`Boss.VoidWarden.1-3`, `Stinger.BossIntro/Victory/Defeat` restent **vides** → mécanisme de repli existant (la musique
inférieure continue, stingers silencieux). Les briefs de ces emplacements ont été réécrits dans le ton cartoon.

### Données (schéma 5)
`bosses` (Codex), `materials`, `trophies` ; migration 4 → 5 sans perte ; assainissement (boss / ids de butin
inconnus, victoires ≤ tentatives, matériaux entiers et bornés, une seule relique de boss par trophée, aucune
relique de boss sur un piédestal normal). Sync froid : `bosses` (sans `lastFight`), `materials`, `trophies`.

### Écarts au plan (et pourquoi)
1. **Arène « céleste »** → arène flottante cartoon « placard du concierge du Néant », dans la même place (pas de
   TeleportService) : plus simple, aucun temps de chargement, et l'éloignement suffit à isoler le PvP.
2. **Tests existants modifiés (justifiés)** : `V2Cosmetics` attendait 26 cosmétiques tous automatiques, le schéma 4
   et `CosmeticService` utilisé seulement par le bootstrap et les commandes Studio. La phase 6 ajoute exactement
   un cosmétique de source `boss` donné uniquement par `BossService`, et passe au schéma 5 : les vérifications
   comparent désormais au schéma courant et autorisent `BossService` ; tout le reste est inchangé.
3. **Pas d'animation de personnage pour la Frappe** (aucun Animation ID n'est inventé) : un « swoosh » blanc devant
   le joueur + « POW! » sur le boss.
4. **Barre « Boss »** ajoutée sous la grille 2×2 du menu (la grille reste à 4 boutons) ; elle ouvre la carte du
   boss, d'où l'on ouvre le Codex.

### Tests (phase 6)
`tests/scenarios/V2Bosses.luau` : **+260 vérifications, 1355 au total, 0 échec, 0 erreur d'exécution** :
catalogue et formules, schéma 5, cycle du portail, règles d'entrée, protection + isolation PvP, salle d'attente et
mise à l'échelle, Frappe (portée, recharge, spam, payloads falsifiés, en l'air, bouclier de phase), chaque attaque
télégraphiée puis ne touchant que ceux qui restent (anneau / saut, flaques / ralentissement, quarts sûrs),
cœurs / KO / mort / défaite, victoire solo (phases, musique, toutes les récompenses, trophée non volable,
sauvegarde immédiate, jamais deux fois, doublons), victoire en coopération (récompenses individuelles, seuil de
contribution), AFK, hors limites, téléportation, intrus, déconnexion, temps écoulé, socles et reconnexion,
`MovementGuard`, nettoyage complet, interface client (carte avec probabilités exactes, invite, ENTRER, barre du
HUD, Codex, panneau). `ONLY=bosses lune run tests/run.luau` pour itérer (≈ 40 s).

### Limites connues
- Le corps du boss est un assemblage de primitives (pas de modèle sculpté ni d'animation Roblox) ; voir
  ART_DIRECTION §14 pour les vrais assets à prévoir (mesh, animations, musiques, SFX cartoon).
- Positions des joueurs : Roblox laisse la physique du personnage au client ; le serveur juge les coups sur sa
  propre vue (réplication ≈ 100 ms) : télégraphes généreux et 1,5 s d'invincibilité compensent la latence.
- Saut au-dessus de l'anneau : jugé sur la hauteur du personnage au passage du front d'onde (échantillon 20 Hz).
- La Forge, les autres boss et les récompenses quotidiennes ne sont pas commencés.

### À vérifier dans Roblox Studio (phase 6)
1. `/rh boss open` puis marcher jusqu'au portail : panneau + barre « Boss » (compte à rebours), invite **E** / **X**
   / toucher, carte du boss (modèle 3D, pourcentages exacts, Power), **ENTRER !** grisé loin du portail.
2. Entrer avec une relique en main (refus), puis sans ; salle d'attente, **Prêt !** (2 clients avec *Test →
   Clients and Servers*).
3. Combat (PC, manette, téléphone) : lisibilité des 5 attaques, saut au-dessus de l'anneau, quart sûr, cœurs,
   « POW! », étoiles, bouton FRAPPE sur mobile, Dash/Blink dans l'arène, Repousser refusé.
4. Phases : réaction, couleur rouge en phase 3, bannière « ÉTOURDI ! », musique (repli silencieux attendu).
5. Victoire (`/rh boss win`, attendre sa réaction de 2 s, puis une frappe) : il s'enfuit en boudant, confettis, carte de récompenses, trophée sur
   le socle (personne ne peut le voler), Codex mis à jour ; défaite (KO / temps / abandon).
6. Pendant une expédition, un 2ᵉ joueur tente de voler le Sanctuaire du combattant : « affronte un boss ».
7. Déconnexion / reset en plein combat ; publication puis vérification de la sauvegarde (Codex, Éclats, trophée).
8. Performance : MicroProfiler pendant le Grand Ménage à 8 joueurs ; Qualité Basse sur téléphone.
