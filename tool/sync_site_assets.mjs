#!/usr/bin/env node
// ==================================================================
// COPIA EL SITIO REAL DENTRO DE LA APP (assets/site)
// ==================================================================
// El editor HTML del módulo "Sitio web" abre el SITIO DE VERDAD en un WebView:
// index.html, el CSS, el JS y las imágenes viajan empaquetados con la app y se
// sirven en loopback (ver `lib/site_preview_server_io.dart`). Así la vista
// previa no es una maqueta de Flutter: es la web, con su CSS y sus fuentes.
//
// Esto copia los archivos que la web necesita (no todo `Hardstreet/`, que
// además trae carpetas de clientes y pruebas):
//
//   ../Hardstreet/index.html      -> assets/site/index.html
//   ../Hardstreet/index.css       -> assets/site/index.css
//   ../Hardstreet/index.js        -> assets/site/index.js
//   ../Hardstreet/gallery/assets/ -> assets/site/gallery/assets/
//   ../Hardstreet/images/         -> assets/site/images/
//
// Uso:  node tool/sync_site_assets.mjs
// Se corre cada vez que cambie la web, antes de compilar el panel.
// ==================================================================
import { cpSync, existsSync, mkdirSync, readdirSync, rmSync, statSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const appRoot = resolve(here, '..');
const siteRoot = resolve(appRoot, '..', 'Hardstreet');
const outRoot = join(appRoot, 'assets', 'site');

/** Carpetas completas que se copian tal cual. */
const folders = ['gallery/assets', 'images'];
/** Archivos sueltos de la raíz del sitio. */
const files = ['index.html', 'index.css', 'index.js'];

if (!existsSync(siteRoot)) {
  console.error(`No encuentro la web en ${siteRoot}`);
  process.exit(1);
}

rmSync(outRoot, { recursive: true, force: true });
mkdirSync(outRoot, { recursive: true });

let total = 0;
for (const name of files) {
  const from = join(siteRoot, name);
  if (!existsSync(from) || !statSync(from).isFile()) {
    console.error(`Falta ${from}`);
    process.exit(1);
  }
  cpSync(from, join(outRoot, name));
  total++;
}

for (const folder of folders) {
  const from = join(siteRoot, folder);
  if (!existsSync(from)) {
    console.error(`Falta ${from}`);
    process.exit(1);
  }
  const to = join(outRoot, folder);
  cpSync(from, to, {
    recursive: true,
    // Basura del sistema / del editor fuera.
    filter: (src) => !/(^|[\\/])(\.DS_Store|Thumbs\.db|__pycache__)$/.test(src),
  });
  total += readdirSync(to).length;
}

console.log(`Sitio copiado a assets/site (${total} entradas de nivel superior).`);
