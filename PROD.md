# Production Packaging

This resource now has a clean split between source files and runtime files.

## Before Packaging

Run the web build from the repo root:

```sh
npm run check
npm run build
```

Confirm the runtime UI exists after the build:

- `ui/index.html`
- `ui/app.js`
- `ui/style.css`
- `ui/assets/props/fallback.svg`

## Runtime Package

For a production deploy, keep only the files FiveM needs at runtime:

- `client/`
- `server/`
- `shared/`
- `config/`
- `data/`
- `http/`
- `stream/`
- `ui/`
- `fxmanifest.lua`
- `pmms.sql`
- `README.md`

Include these optional persistence files only if you intentionally want to ship preseeded defaults:

- `models.json`
- `defaultMediaPlayers.json`

## Do Not Ship In The Runtime Resource

These are source, tooling, or local operational files and should stay out of the deployed resource folder:

- `.git/`
- `.playwright-cli/`
- `node_modules/`
- `nui/`
- `package.json`
- `package-lock.json`
- `tsconfig.json`
- `vite.config.ts`
- `data/provider_stats.json`
- `data/admin_state.json`

Keep the `data/` folder itself in the runtime package so the resource still has a writable location for generated state.
`data/provider_stats.example.json` can stay in the source repo for reference and is safe to include in runtime packages too.

## What To Keep On GitHub

Keep the full source repository on GitHub so the NUI can be rebuilt and maintained:

- everything in the runtime package list
- `nui/`
- `package.json`
- `package-lock.json`
- `tsconfig.json`
- `vite.config.ts`
- `PROD.md`
- `data/provider_stats.example.json`

Do not commit local noise or generated runtime state:

- `node_modules/`
- `.playwright-cli/`
- `data/provider_stats.json`
- `data/admin_state.json`

## Release Flow

1. Update code and config.
2. Run `npm run check`.
3. Run `npm run build`.
4. Verify `ui/` was regenerated.
5. Prepare a runtime-only folder using the runtime package list above.
6. Import `pmms.sql` if the target server database has not been initialized yet.
7. Ensure `oxmysql` starts before this resource.

## Notes

- `config/permissions.cfg` is no longer part of the release surface. Permissions are configured only through `Config.permissions` in `config/config.lua`.
- `ui/` is the built artifact that FiveM loads. `nui/` is source-only.
- Live provider stats and admin panel state are machine-local operational data, not release assets.
