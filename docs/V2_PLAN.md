# RIFT HEIST — Plan V2 (validé)

> Statut : **Phase 1 — Fondations : terminée.** Phases 2 à 11 : non commencées (attente d'autorisation).

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
| 2 | Monde V2 | +35 % de surface (anneau extérieur, grottes, corniche, ruines, landmarks, points de grappin), routes alternatives Faille↔Sanctuaires (trajet direct ~172 → ~190 studs), panneaux de Sanctuaire en studs + distance max ~140 | — |
| 3 | Audio dynamique | MusicDirector (Boss > Poursuite > Événement > Faille > Exploration), fondus, Sounds v2 documenté, aucun ID inventé | — |
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
