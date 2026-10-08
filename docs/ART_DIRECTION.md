# RIFT HEIST — Direction artistique « Cartoon & Goofy »

> Référence visuelle obligatoire pour les Phases 6 à 11. Introduite en Phase 5.5.
> Les valeurs exactes vivent dans le code ; ce document explique **quoi** utiliser et **pourquoi**.
>
> | Domaine | Source de vérité |
> |---|---|
> | Couleurs, polices, rayons, contours, boutons UI | `src/shared/Config/Theme.luau` |
> | Palette du monde, terrain, matériaux, éclairage | `src/shared/Config/Palette.luau` |
> | Emojis autorisés (et interdits) | `src/shared/Config/Emoji.luau` |
> | Composants UI | `src/client/UI/Kit/` (`Style`, `Button`, `Modal`, `Juice`, `Icons`, `Tween`) |
> | Visages des reliques | `src/shared/Relics/RelicFaces.luau` |
> | Tests qui font respecter ces règles | `tests/scenarios/V2ArtDirection.luau` |

---

## 0. Le pitch visuel

*Une île-bonbon flotte dans un ciel d'été. Au centre, la Faille — un gros portail rose avec des yeux
globuleux — rote des reliques qui ont toutes une petite tête rigolote. Tout le monde court, vole,
rigole, se pique des trucs et repart en dérapant.*

Références d'**accessibilité** et de **ton** (sans rien copier de leurs assets, noms ou identité) :
la lisibilité immédiate de *Grow a Garden*, l'humour absurde de *Steal a Brainrot*.

Ce que Rift Heist n'est **plus** : nuit violette, dark fantasy, matériaux réalistes, interface en verre fumé.

## 1. Les 4 piliers

1. **Lisible en 1 seconde** — un enfant de 8 ans comprend ce qu'est un objet, s'il peut le prendre et
   à qui il appartient, sans lire. Silhouettes simples, couleurs franches, contours encre.
2. **Drôle** — chaque objet important a une personnalité (visage, rebond, réaction). L'absurde est
   bienvenu, la moquerie et la peur non.
3. **Généreux** — chaque action récompensée a un retour exagéré : pop, confettis, « +250! », son.
4. **Léger** — le style cartoon coûte *moins* cher que le réalisme : aplats, peu de lumières, effets
   courts et plafonnés. Jamais au détriment du framerate mobile.

## 2. Palette

### Couleurs de marque (`Palette.Core`)

| Nom | RGB | Usage |
|---|---|---|
| Sky | 110, 200, 255 | ciel, eau, informations neutres |
| Grass | 98, 214, 92 | herbe, succès, « acheter », « équiper » |
| Sunny | 255, 210, 63 | or, récompenses, objectifs, rambardes |
| Bubblegum | 255, 111, 181 | la Faille, le style, l'accent principal |
| Grape | 155, 107, 255 | magie, capacités, rareté Épique |
| Tangerine | 255, 154, 60 | Power, énergie, avertissements doux |
| Mint | 95, 227, 192 | fraîcheur, statut Phase |
| Cherry | 255, 79, 94 | danger, vol, fermer |
| Cream | 255, 246, 229 | sols, pierres claires, puces de touches |
| **Ink** | 30, 27, 75 | **tous les contours et ombres** (jamais de noir pur) |

### Interface (`Theme.Colors`)

- Panneaux : **bleu roi opaque** `60,110,235` avec un léger dégradé vers le bas, contour encre 3 px.
- Puits / cartes dans un panneau : `40,78,196` (plus sombre → texte blanc ≥ 7:1).
- Texte : **blanc**, contour encre pour tout texte ≥ 15 px ou posé sur une couleur vive.
- Contraste minimal : 4,5:1 pour le texte courant sur panneau, 3:1 pour les légendes (testé).

### Boutons (`Theme.Buttons`)

| Famille | Sens | Exemples |
|---|---|---|
| green | faire / valider / acheter / équiper | Acheter, Équiper, Débloquer |
| yellow | récompense, objectif, mise en avant | Réclamer, Prochain objectif |
| orange | action secondaire importante | Dissoudre |
| red | fermer, retirer, danger | ✕, Retirer |
| blue | navigation / information | RiftDex, onglets |
| pink | style, cosmétiques | Style, Essayer |
| purple | capacités, réglages | Capacités, Réglages |
| neutral / gray | secondaire, désactivé | onglet inactif |

Une même famille garde le même sens dans tout le jeu (Phases 6-11 comprises).

### Monde (`Palette.World`, `Palette.Terrain`)

- Herbe vert vif, chemins sable/biscuit, falaises et dessous de l'île **lavande** (pas de gris sale).
- Structures : biscuit (`Stone`), pervenche (`StoneDark`), crème (`StoneLight`), rambardes **jaunes** (`Trim`).
- La Faille et tout ce qui est « magique » : **bubblegum** (`Rift`) + blanc.
- Chaque Sanctuaire a sa couleur bonbon (`Theme.PlotColors`) sur ses anneaux, lanternes et fanions.
- Arbres « sucettes » et buissons aux couleurs de `Palette.Canopies`, fleurs `Palette.Flowers`.

## 3. Typographie

| Rôle | Police (intégrée à Roblox) | Taille mini (avant mise à l'échelle) |
|---|---|---|
| Titres, boutons, nombres, légendes | **Fredoka One** (`Theme.Fonts.Display` / `Heavy`) | 13 px |
| Texte courant, descriptions | **Builder Sans Bold/Heavy** (`Body` / `BodyBold`) | 14 px |
| Cris courts : « +250 », « NEW! », « BURP! » | **Luckiest Guy** (`Burst`) — latin, **pas d'accents** | 24 px |

- Pas de police téléversée : uniquement `rbxasset://fonts/families/...` (testé).
- Gros nombres partout : compteur d'Essence 38 px, recharges ≈ 1/3 du bouton.
- Texte en majuscules réservé aux étiquettes courtes (rareté, ÉQUIPÉ).

## 4. Icônes et emojis

**Règle :** un emoji n'est utilisé que s'il est dans `Config/Emoji.Glyphs` — un seul point de code,
présentation emoji par défaut, Unicode ≤ 10. Sinon on **dessine** l'icône avec des Frames (`Kit/Icons`).

| Emoji (autorisés) | Usage |
|---|---|
| 🚀 📖 🎨 🔧 🎒 | Améliorations, RiftDex, Style, Réglages, Capacités |
| 💎 ⚡ 🎯 🏠 🚨 | Essence (texte), Power, objectif, maison, vol |
| 🔒 ✅ 🆕 ✨ ⏳ ❌ | verrouillé, équipé, nouveau, prêt, temps, refusé |
| ⭐ 🎉 🏆 👑 🎁 🔥 💥 🌀 🌈 | récompenses, découvertes, événements |
| 💪 👻 💫 🐌 🌱 | statuts Bouclier, Phase, étourdi, enraciné, ralenti |

**Interdits** (rendu monochrome ou absent sur certains appareils) : ⚙ 🛡 ❄ ☀ ☁ ❤ ⚔ ✏ ⬆ ✔ ⚠ 🌪 —
la liste complète est `Emoji.Unreliable`. Les icônes critiques en jeu (capacités, Essence, Sceau,
fermer) restent **dessinées** : elles doivent s'afficher à coup sûr et prendre la couleur voulue.

Les étoiles de rareté utilisent le caractère texte `★` (pas un emoji) : 1 ★ Commun … 7 ★ Secret.

## 5. Formes et composants

- **Tout est arrondi** : panneaux 22 px, cartes 14 px, boutons 14 px ou pilule, badges ronds.
- **Contour encre partout** : panneaux 3 px (modales 4 px), boutons et cartes 2–2,5 px, texte 1,5–3 px.
- **Bouton « chunky »** (`Kit/Button`) : face colorée + **lèvre** plus sombre de 4 px dessous + reflet
  brillant en haut. Survol : grossit (×1,06, easing Back). Appui : la face descend sur la lèvre.
  Désactivé : face désaturée (pas transparente). Refus : petite secousse.
- **Modale** (`Kit/Modal`) : panneau bleu, **ruban de titre** coloré qui déborde en haut (emoji + titre
  avec contour), bouton ✕ rouge rond qui déborde en haut à droite, ouverture « pop » avec léger tilt.
- **Pilule** (`Style.pill`) : rareté, taux « +12/s », statuts. **Badge** (`Style.badge`) : « ! » rouge.
- Cibles tactiles ≥ 44 px (boutons de menu 131×62, capacités 60–88 px).
- Un écran = une action principale (le bouton le plus gros et le plus vert).

### Disposition du HUD (hiérarchie)

1. **Essence** (haut de colonne, la plus grosse) — gemme qui déborde, nombre 38 px, pilule verte « +x/s ».
2. **Power** — barre orange.
3. **Menu** — grille 2×2 de gros boutons emoji colorés.
4. **Prochain objectif** — barre de progression jaune→orange, devient verte et gigote quand c'est payable.
5. À droite : capacités (gros ronds colorés), sac 🎒 du loadout, statuts en pilules au-dessus.
6. En bas : panneau de transport (devient rouge clignotant quand c'est volé).

## 6. Animation

| Situation | Durée | Easing |
|---|---|---|
| Apparition (pop) | 0,3–0,45 s | Back Out (dépassement) |
| Survol / appui | 0,25 s / 0,05 s | Back / Quad |
| Secousse « wiggle » | 0,55 s | Elastic Out |
| Disparition | 0,15 s | Back In |
| Texte flottant « +250 » | 0,35 s pop + 0,8 s montée | Back / Quad In |
| Confettis | 0,35 s éclatement + 0,75 s chute | Quad |

- Principes cartoon : anticipation, **squash & stretch**, dépassement, rebond.
- Pas de boucle par élément : tweens ponctuels, ou **un** tween en boucle (rayons de récompense).
- `Kit/Juice` plafonne : 60 confettis vivants, 4 explosions / seconde maximum.
- Rien ne clignote plus de 3 fois par seconde (photosensibilité).

## 7. Effets visuels

- Particules : textures intégrées `rbxasset://textures/particles/...` uniquement (sparkles, fire, forcefield).
- Effets courts (≤ 1,5 s), couleurs de la palette, `LightEmission` modéré en plein jour.
- Les effets ne masquent jamais : un joueur qui porte une relique, une barrière de Sceau, un
  télégraphe d'attaque. Budgets cosmétiques inchangés (`Config/Cosmetics.Budget`).
- En plein jour, les lumières (PointLight) servent peu : en ajouter le moins possible.

## 8. Monde

- **Éclairage** (`Palette.Lighting`) : après-midi ensoleillé (ClockTime 14,3), ombres douces, nuages
  blancs bien ronds, atmosphère bleu ciel légère, saturation +0,28. Appliqué par le serveur au démarrage
  (`World/Ambience`) et recopié dans `default.project.json` (testé : les deux doivent concorder).
- **Matériaux** : les matériaux réalistes (Slate, Marble, Cobblestone, Metal, Wood…) sont rendus en
  **SmoothPlastic** (`Palette.Stylize`) — aplats propres façon jouet. On garde Neon (lueurs), Glass,
  ForceField.
- **Silhouettes** : arbres sucettes (tronc + 2–3 boules), champignons, fleurs géantes, fanions. Pas de
  détail fin illisible de loin.
- **Lisibilité des déplacements** : rien de décoratif sur les routes, rampes, grottes, points de grappin,
  pads de rebond ; les décorations sont non collidables et non « raycastables » (testé).
- Budgets monde : `GameConfig.World` (parts, lumières, émetteurs) — testés.

## 9. Reliques

- **Visage** quand c'est pertinent (`Relics/RelicFaces`, 14 reliques sur 19) : gros yeux blancs, pupilles encre
  qui se baladent, reflet, clignements, bouche, joues roses. Humeurs : joyeux, grognon, endormi, timide, surpris,
  coquin (clin d'œil), farceur (langue), loufoque (yeux qui louchent), frimeur (lunettes de soleil), malin.
- Les reliques à visage **se tournent vers le joueur le plus proche** (ou la caméra) et se dandinent au lieu de
  tourner sur elles-mêmes. La Faille, elle, suit ton personnage des yeux.
- Échelle de rareté (inchangée en gameplay) : Commun sobre → Secret avec aura, pilier de lumière et
  orbiteurs. L'étiquette au-dessus de la relique affiche des **★** + couleur de rareté.
- Silhouette d'abord : une relique doit être reconnaissable en ombre chinoise.

## 10. Cosmétiques

- Cartes de l'écran Style : grande pastille de couleur, emoji de catégorie, ★ de rareté, statut en pilule
  (🔒 / ✅). Les conditions de déblocage, catégories et sauvegarde ne changent pas.
- Couleurs des effets : saturées, lisibles de jour ; jamais d'effet sombre « gothique ».
- Titres : police Fredoka, couleur du titre, contour encre.

## 11. Boss (Phases 6-7) — direction, pas encore de système

**Créatures géantes, rondes, expressives, un peu ridicules. Jamais de gore, de sang, de cadavre ni
d'horreur.** La défaite d'un boss : étoiles qui tournent autour de la tête, « pouf » de confettis, il
s'enfuit en boudant.

| Boss (ids prévus) | Concept | Attaques lisibles (exemples) |
|---|---|---|
| Void Warden | gros cube-gelée violet, concierge grognon de la Faille, balai géant | coup de balai circulaire (zone qui se remplit), flaques collantes, « ménage » qui repousse |
| Forgeheart | escargot-forgeron de lave, joues rondes, rote des boulets | boulets en cloche (cercle au sol 1 s avant), coup de marteau-onde, rot de flammes en cône |
| Tempest Seraph | oiseau-nuage diva qui chante l'opéra | notes aiguës = éclairs (colonnes marquées), tourbillon qui aspire, plumes rebondissantes |
| Eclipse Oracle | hibou-lune somnolent en pyjama de sorcier | bâillements = bulles de gravité, oreiller qui tombe (ombre au sol), « dodo » qui ralentit |

Règles de télégraphes : zone colorée **jaune → rouge** qui se remplit, contour encre, au moins **0,8 s**
d'avance (1,2 s pour les gros coups), anticipation exagérée du boss (squash avant de frapper), son
dédié. Une attaque = une forme = une couleur. Barres de vie : grosse pilule avec la tête du boss, pas de
chiffres de dégâts rouges sanglants (étoiles et « POW! » à la place).

## 12. Interfaces des Phases 6 à 11

- **Boss** : écran pré-combat = carte « affiche de catch » (portrait, nom, 3 icônes d'attaques, butin
  possible avec ★ et pourcentages lisibles).
- **Quotidien** : 7 cadeaux 🎁 en ligne, le jour actuel rebondit, réclamer = confettis + rayons.
- **Boutique Robux (Phase 10)** : prix toujours visibles, aucun compte à rebours artificiel, aucune
  « boîte mystère » payante opaque, bouton d'achat vert identique partout, conforme aux règles Roblox
  pour les jeunes publics. Les cosmétiques payants restent purement visuels.
- **Codex / Forge** : grilles de cartes avec ★ de rareté et silhouettes noires pour l'inconnu (« ??? »).
- **Événements** : bannière avec emoji, couleur de l'événement, ambiance qui reste lumineuse (jamais
  plus sombre que le crépuscule).

## 13. Accessibilité

- Contrastes testés (texte blanc / panneaux). Rareté = couleur **et** nombre d'étoiles.
- Le réglage Qualité Basse coupe les effets coûteux ; « secousses » désactivables (réglage existant).
- Textes FR et EN ; prévoir +30 % de longueur pour le français (TextScaled + contraintes de taille).

## 14. Ce qui demande de vrais assets (non fournis, rien n'a été inventé)

Le jeu est 100 % construit avec des primitives Roblox, des polices et textures intégrées. Pour aller
plus loin, il faudra de vrais fichiers créés ou achetés par l'équipe :

- **Modèles 3D / MeshParts** : reliques sculptées, boss, arbres et props stylisés plus organiques,
  personnage-mascotte de la Faille.
- **Illustrations 2D** : logo du jeu, icône et miniatures de la page Roblox, portraits de boss,
  icônes dessinées des menus (remplaçant les emojis), fonds de cartes.
- **Animations** : animations de boss et de PNJ (Animation IDs), emotes.
- **Audio** : musique plus légère et joyeuse, SFX cartoon (boing, pop, rot de la Faille). Les 5 pistes
  configurées en Phase 3 sont conservées telles quelles.
- **Décalques / textures** : motifs (rayures, pois) sur les Sanctuaires, visages dessinés.

## 15. Checklist pour toute nouvelle fonctionnalité

- [ ] Couleurs prises dans `Theme` / `Palette` (pas de `Color3.fromRGB` sombre isolé).
- [ ] Contour encre + coins arrondis ; bouton d'action principal = famille correcte.
- [ ] Emojis uniquement depuis `Config/Emoji` ; icônes critiques dessinées.
- [ ] Texte ≥ tailles minimales, FR + EN, lisible sur téléphone.
- [ ] Une animation d'apparition et un retour de récompense, sans boucle par élément.
- [ ] Effets dans les budgets, rien qui masque un joueur porteur ou un télégraphe.
- [ ] Rien d'effrayant, de gore, de moqueur ou de trompeur pour un enfant.
- [ ] Aucun asset ID inventé.
