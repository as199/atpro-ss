# Canal auto-update ATPRO-SS

L’application lit ce manifeste (fallback) :

`https://raw.githubusercontent.com/as199/atpro-ss/master/updates/latest.json`

Endpoint principal (après chaque release signée) :

`https://github.com/as199/atpro-ss/releases/latest/download/latest.json`

## Contenu de `latest.json`

| Champ | Rôle |
|-------|------|
| `version` | SemVer de la dernière version |
| `notes` | Affiché dans Settings → Updates |
| `pub_date` | RFC 3339 |
| `platforms.windows-x86_64.url` | URL HTTPS de l’installeur NSIS |
| `platforms.windows-x86_64.signature` | Contenu du fichier `.sig` (Ed25519 / minisign Tauri) |

## Publier une nouvelle version

1. Builder + signer côté app (`TAURI_SIGNING_PRIVATE_KEY`, `createUpdaterArtifacts`).
2. Créer/mettre à jour la GitHub Release **publiée** (pas en brouillon) avec :
   - `ATPRO-SS_*_x64-setup.exe` (+ `.sig`)
   - `latest.json` (généré par `tauri-action` / `includeUpdaterJson`)
3. Copier aussi `updates/latest.json` dans ce dépôt (fallback raw) et pousser `master`.

Script d’upload release (token requis) : [`publish-latest-json.ps1`](./publish-latest-json.ps1)
