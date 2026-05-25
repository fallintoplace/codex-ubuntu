# packaging/deb

Debian packaging templates for the Ubuntu app.

Today the packaged implementation is still the browser fallback preview utility.

Important:

- this `.deb` does **not** install the Electron desktop app yet
- this `.deb` does install the fallback/recovery launcher
- the main packaging direction is now the separate Electron bootstrap package
  built by `make build-electron-deb`

The local Electron build/install bridge exists now, and the Electron-primary
package installs that launcher/bootstrap tooling without shipping the payload
itself.
