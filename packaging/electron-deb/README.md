# packaging/electron-deb

Debian packaging templates for the Electron-primary desktop bootstrap package.

Important:

- this `.deb` installs the Electron desktop launcher and bootstrap tooling
- this `.deb` also installs a rollback helper for switching back to the previous
  local release
- this `.deb` does **not** ship the upstream desktop payload itself
- users run `codex-desktop-bootstrap` after install to build and install the
  local desktop payload for their own account
