# Arch Linux + Hyprland — Installation automatisée

Projet d'installation Arch Linux en dual-boot avec Windows, environnement Hyprland ricé, démarrage graphique via SDDM, et support gaming DX12 (Vulkan/vkd3d-proton).

## Matériel cible

- **PC** : Honor MagicBook HGE-WX6
- **CPU** : Intel i7-11390H (Tiger Lake)
- **GPU** : Intel Iris Xe (Mesa + vulkan-intel)
- **RAM** : 16 Go
- **Disque** : WD_BLACK SN770 2 To (~314 Go non alloués pour Arch)

## Structure du projet

```
arch/
├── analyze/          # Analyse Windows → hardware-report.json
├── install/          # Installateur Arch (ISO live)
├── configure/        # Post-installation système
├── dotfiles/         # Rice Hyprland complet
└── tests/            # Tests unitaires (Pester + bats)
```

## Prérequis

### Sur Windows (développement / tests)

- PowerShell 5.1+
- Docker Desktop (pour tests bash)
- WSL2 (optionnel, pour dry-run local)

### Avant l'installation

1. **Suspendre BitLocker** si activé sur C: (vérifié par `analyze-windows.ps1`)
2. **Sauvegarder** vos données importantes
3. Créer une **clé USB Arch Linux** (≥ 2 Go)

## Installation rapide (utilitaire automatisé)

### Sous Windows

```powershell
cd C:\Users\flofl\Documents\arch

# 1. Analyse + validation (PowerShell admin recommandé)
.\arch-setup.ps1 prepare

# 2. Copier le projet sur la clé USB (lettre E: par exemple)
.\arch-setup.ps1 copy-usb -DriveLetter E

# Ou tout en une commande :
.\arch-setup.ps1 all -DriveLetter E
```

### Sur l'ISO Arch live (root)

```bash
cd /root/usb/arch          # adaptez le chemin (jamais sous /mnt : install.sh y monte le disque cible)
chmod +x arch-setup
./arch-setup live
```

Le script détecte le projet, vérifie le réseau, valide BitLocker/canInstall, puis lance `install.sh`.

Wi-Fi automatique (optionnel) :
```bash
export WIFI_SSID="MonWiFi"
export WIFI_PASS="motdepasse"
./arch-setup live
```

### Premier boot Arch

```bash
~/arch-setup/arch-setup first-boot
```

Enchaîne automatiquement : `setup.sh` → `deploy.sh` → `verify-dx12.sh`.

---

## Installation manuelle (étapes détaillées)

## Étape 1 — Analyser le PC (Windows)

Lancer dans un **PowerShell administrateur** (nécessaire pour lire le statut BitLocker) :

```powershell
cd C:\Users\flofl\Documents\arch
.\analyze\analyze-windows.ps1
```

Génère `analyze\hardware-report.json` avec l'inventaire complet, dont :
- la résolution **native** du panneau et le facteur d'échelle réel (ex. 2520x1680 @ 90 Hz, scale 1.5) — utilisés pour générer `monitors.conf`
- le statut BitLocker (`security.bitlocker`) — si `Unknown`, relancer en admin ; l'installateur avertit avant de poser GRUB

## Étape 2 — Préparer la clé USB

1. Télécharger l'ISO Arch : https://archlinux.org/download/
2. Flasher avec Rufus/Etcher (mode UEFI/GPT)
3. Copier ce dossier `arch` sur la clé USB ou un second support accessible

## Étape 3 — Installation (ISO Arch live)

1. Démarrer sur la clé USB Arch
2. Connecter au réseau : `iwctl` ou `dhcpcd`
3. Monter le support contenant ce projet **hors de `/mnt`** (ex: `/root/usb`) —
   install.sh monte le disque cible sur `/mnt`, ce qui masquerait le projet
   s'il y était monté
4. Lancer l'installation :

```bash
cd /root/usb/arch
chmod +x install/install.sh configure/setup.sh configure/verify-dx12.sh dotfiles/deploy.sh
./install/install.sh --report analyze/hardware-report.json
```

Options utiles :
- `--dry-run` : simulation sans modification
- `--disk nvme0n1` : forcer le disque cible
- `--root-gib 250` : taille partition root
- `--user archuser` : nom d'utilisateur
- `--bootloader grub` : dual-boot Windows (défaut)

## Étape 4 — Post-installation (premier boot Arch)

```bash
~/arch-setup/configure/setup.sh
~/arch-setup/dotfiles/deploy.sh
~/arch-setup/configure/verify-dx12.sh
```

Redémarrer → SDDM thémé → session Hyprland.

## Étape 5 — Vérification gaming DX12

1. Lancer Steam, installer Proton-GE via ProtonPlus si besoin
2. Activer Proton pour un jeu DX12 dans les propriétés
3. Exécuter `verify-dx12.sh` — doit afficher Vulkan Intel (ANV) + vkd3d

Variables d'environnement gaming configurées dans `~/.config/environment.d/gaming.conf`.

## Raccourcis Hyprland

| Raccourci | Action |
|-----------|--------|
| `Super + Return` | Terminal (kitty) |
| `Super + R` / `Super + Space` | Lanceur (rofi) |
| `Super + E` | Fichiers (thunar) |
| `Super + Q` | Fermer fenêtre |
| `Super + L` | Verrouillage (hyprlock) |
| `Super + S` | Capture écran |
| `Super + 1-5` | Workspaces |

## Tests

Lancer tous les tests avant de tester sur machine réelle :

```powershell
.\tests\run-tests.ps1
```

Inclut :
- Tests Pester (analyse PowerShell)
- shellcheck + bats (conteneur Arch Docker)
- Validation JSON des configs
- Dry-run installateur complet

Options :
- `-SkipDocker` : ignorer tests bash
- `-SkipPester` : ignorer tests PowerShell

## Profils logiciels installés

| Profil | Contenu |
|--------|---------|
| base | Système Arch, GRUB, réseau, PipeWire |
| hyprland | Hyprland, Waybar, rofi, SDDM, kitty |
| dev | VS Code, Docker, Git, Node, Python, Rust |
| gaming | Steam, gamemode, Vulkan, vkd3d, mangohud |
| office | Firefox, LibreOffice, Thunderbird |
| video | OBS, Kdenlive, FFmpeg, GIMP |

## Dépannage

### Pas d'entrée Windows au boot
```bash
sudo grub-mkconfig -o /boot/grub/grub.cfg
```

### Écran mal dimensionné
`monitors.conf` est généré depuis le rapport matériel (résolution native + scale réel,
ex. `monitor = eDP-1, 2520x1680@90, 0x0, 1.5` sur le MagicBook). Si besoin, éditer
`~/.config/hypr/monitors.conf` à la main.

### Vulkan absent
```bash
sudo pacman -S mesa vulkan-intel vulkan-tools
vulkaninfo --summary
```

### SDDM ne démarre pas
```bash
sudo systemctl enable sddm
sudo systemctl start sddm
```

## Licence

Usage personnel — configuration pour Honor MagicBook HGE-WX6.
