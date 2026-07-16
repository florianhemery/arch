# Plan d'action — audit du 15/07/2026

État des lieux après relecture complète du projet (libs d'installation, configs
Hyprland, listes de paquets, schéma, tests). Cinq problèmes feraient échouer ou
casseraient l'installation réelle ; les tests actuels ne peuvent pas les attraper.

## Problèmes critiques identifiés

### C1. Paquets inexistants → pacstrap avorte
`pacstrap` s'arrête si un seul paquet est introuvable. Paquets concernés :

| Paquet | Fichier | Problème |
|--------|---------|----------|
| `bibata-cursor-theme` | hyprland.txt | AUR uniquement |
| `protonplus` | gaming.txt | AUR uniquement |
| `davinci-resolve` | video.txt | AUR uniquement |
| `calculator` | office.txt | N'existe pas (doublon de `gnome-calculator`) |
| `vainfo` | video.txt | Le paquet s'appelle `libva-utils` |

Inverse : `wlogout` est bindé (`SUPER+SHIFT+Q` dans hyprland.conf) mais installé nulle part.

### C2. `verify-dx12.sh` meurt au premier PASS
`((PASS++))` retourne le code 1 quand `PASS` vaut 0, et le script est en `set -e` :
il affiche le premier `[PASS]` puis sort en exit 1. Aucun test ne couvre ce script.
Fix : `PASS=$((PASS+1))` (idem WARN/FAIL) + test de couverture.

### C3. Multilib cassé dans `setup.sh`
- `Include = /etc/pacman.mirrorlist` → chemin faux, le bon est `/etc/pacman.d/mirrorlist`
- Multilib n'est jamais activé dans le système **cible** : les `lib32-*` installés
  par pacstrap ne se mettraient plus à jour après le premier boot

### C4. `disk.sh` peut choisir un trou d'alignement de 1 MiB
`find_unallocated_region` prend la **première** région libre (souvent un trou
d'alignement GPT) au lieu de la **plus grande**, et `calculate_partition_layout`
rétrécit silencieusement la root à la taille de la région sans minimum.
Scénario : partition root de 1 MiB. Fix : plus grande région + refus si < 50 GiB.

### C5. Option `systemd-boot` structurellement cassée
Les entrées pointent vers `/vmlinuz-linux` à la racine de l'ESP, mais le noyau
vit dans `/boot` (btrfs) et l'ESP Windows (200 Mo) est montée sur `/boot/efi`.
systemd-boot ne lit pas le btrfs → système non bootable. GRUB (défaut) est sain.
Fix : retirer l'option ou la bloquer avec un message explicite.

## Améliorations souhaitables

- **Swap absent** : ajouter zram (`zram-generator` + config) — 16 GiB RAM, gaming
- **`hypridle` installé mais ni configuré ni lancé** : pas de verrouillage auto ni
  DPMS → `hypridle.conf` + `exec-once = hypridle`
- **`@snapshots` créé mais aucun outil** : ajouter `snapper` + `snap-pac`
- **`reflector` jamais exécuté** : rafraîchir les miroirs avant pacstrap + `reflector.timer`
- **Wallpaper fantôme** : hyprpaper précharge `wallpaper.jpg` créé seulement si
  ImageMagick est présent (installé nulle part) → embarquer un wallpaper dans `dotfiles/`
- **AUR non géré** : bootstrap `paru` dans `setup.sh` + `packages/aur.txt`
  (protonplus, bibata-cursor-theme, davinci-resolve)
- **zsh + starship installés mais non configurés**, user créé avec bash →
  `.zshrc` + `starship.toml` dans dotfiles, `useradd -s /bin/zsh`
- **`sudoers` modifié par sed sans validation** → `visudo -c` après modification
- **Schéma JSON jamais appliqué** : les tests vérifient que le schéma est du JSON
  valide, pas que le rapport s'y conforme ; `display`/`storage`/`security`/`network`
  absents de `properties` → compléter (refreshHz, logicalWidth…) + validation
  `jsonschema` dans les deux harnais

## Phases

### Phase 1 — Bloquants d'installation
- [x] 1.1 Nettoyer les listes de paquets : retirer `bibata-cursor-theme`,
      `protonplus`, `davinci-resolve`, `calculator` ; remplacer `vainfo` par
      `libva-utils` ; ajouter `wlogout` à hyprland.txt
- [x] 1.2 Créer `install/packages/aur.txt` (protonplus, bibata-cursor-theme,
      davinci-resolve) — installé en post-install, jamais par pacstrap
- [x] 1.3 Test de validation des noms de paquets contre les dépôts réels
      (`pacman -Sp` dans le conteneur Docker archlinux) — le filet qui manquait
- [x] 1.4 `disk.sh` : sélectionner la plus grande région libre, erreur si < 50 GiB
      + tests bats des deux cas
- [x] 1.5 `setup.sh` : corriger le chemin mirrorlist + activer multilib dans le
      système cible pendant l'installation (install.sh)
- [x] 1.6 `verify-dx12.sh` : remplacer `((X++))` par `X=$((X+1))` + test dry-run
- [x] 1.7 Bloquer `--bootloader systemd-boot` avec un message expliquant pourquoi
- [x] 1.8 Suite de tests complète au vert

### Phase 2 — Système complet au premier boot
- [x] 2.1 zram : `zram-generator` dans base.txt + config déployée par install.sh
- [x] 2.2 snapper + snap-pac dans base.txt, config initiale dans setup.sh
- [x] 2.3 reflector avant pacstrap (install.sh) + `reflector.timer` activé (setup.sh)
- [x] 2.4 `hypridle.conf` (lock 5 min, DPMS off 10 min, suspend 30 min) +
      `exec-once = hypridle` dans hyprland.conf
- [x] 2.5 Wallpaper par défaut embarqué dans `dotfiles/hypr/` + suppression du
      placeholder ImageMagick dans deploy.sh
- [x] 2.6 Config wlogout dans dotfiles
- [x] 2.7 Bootstrap `paru` + installation de `aur.txt` dans setup.sh
- [x] 2.8 `.zshrc` + `starship.toml` dans dotfiles, shell par défaut zsh,
      déploiement dans deploy.sh
- [x] 2.9 `visudo -c` après le sed sudoers dans users.sh
- [x] 2.10 Suite de tests complète au vert

### Phase 3 — Robustesse de l'outillage
- [x] 3.1 Compléter `hardware-report.schema.json` (display avec refreshHz et
      logicalWidth/Height, storage, security, network, keyboard, locale)
- [x] 3.2 Valider le rapport contre le schéma : `jsonschema` côté bash
      (run-bash-tests.sh) et Pester côté Windows
- [x] 3.3 (Optionnel) CI GitHub Actions : shellcheck + bats + Pester, si le repo
      est poussé sur GitHub

Chaque phase se termine par `.\tests\run-tests.ps1` au vert avant de passer à la
suivante. La phase 1 est prioritaire : sans elle, l'installation réelle échoue à
l'étape pacstrap.
