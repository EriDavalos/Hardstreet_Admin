// Generador de iconos de "Hardstreet Admin".
// Produce: Android (mipmaps), Web (favicon + PWA), Windows (app_icon.ico).
// Uso:  node tool/generate_icons.mjs
// Requiere sharp (usa el node_modules del backend hermano si hace falta).
import { createRequire } from 'node:module';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const require = createRequire(import.meta.url);
let sharp;
try {
  sharp = require('sharp');
} catch {
  // Fallback: node_modules del backend hermano (los binarios son por plataforma).
  const alt = path.resolve(
    path.dirname(fileURLToPath(import.meta.url)),
    '../../Hardstreet-Backend-Drive/node_modules/sharp',
  );
  sharp = require(alt);
}

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');

// ===== Marca: cuadrado azul con "H" blanca (colores de AppColors.brand) =====
const BRAND = '#2F6BFF';
const svg = (size) => `
<svg xmlns="http://www.w3.org/2000/svg" width="${size}" height="${size}" viewBox="0 0 512 512">
  <rect width="512" height="512" rx="${Math.round(512 * 0.18)}" fill="${BRAND}"/>
  <path d="M150 128 h72 v112 h68 V128 h72 v256 h-72 V304 h-68 v80 h-72 Z"
        fill="#FFFFFF"/>
</svg>`;

// Instancia sharp del SVG en el tamaño dado (densidad alta para nitidez).
const png = (px) => sharp(Buffer.from(svg(px)), { density: 300 });

// ===== Android: mipmaps ic_launcher =====
const androidSizes = {
  'mipmap-mdpi': 48,
  'mipmap-hdpi': 72,
  'mipmap-xhdpi': 96,
  'mipmap-xxhdpi': 144,
  'mipmap-xxxhdpi': 192,
};
for (const [dir, px] of Object.entries(androidSizes)) {
  const out = path.join(
    root, 'android', 'app', 'src', 'main', 'res', dir, 'ic_launcher.png',
  );
  await png(px).png().toFile(out);
  console.log('✔', path.relative(root, out));
}

// ===== Web: favicon + PWA =====
await png(64).png().toFile(path.join(root, 'web', 'favicon.png'));
console.log('✔ web/favicon.png');
await png(192).png().toFile(path.join(root, 'web', 'icons', 'Icon-192.png'));
console.log('✔ web/icons/Icon-192.png');
await png(512).png().toFile(path.join(root, 'web', 'icons', 'Icon-512.png'));
console.log('✔ web/icons/Icon-512.png');
await png(512)
  .png()
  .toFile(path.join(root, 'web', 'icons', 'Icon-maskable-192.png'));
await png(512)
  .png()
  .toFile(path.join(root, 'web', 'icons', 'Icon-maskable-512.png'));

// ===== Windows: app_icon.ico (contiene 16/32/48/256) =====
const icoSizes = [16, 32, 48, 256];
const bmps = [];
for (const px of icoSizes) {
  const raw = await png(px).raw().toBuffer();
  bmps.push({ px, raw });
}
// Formato ICO: cabecera + entradas BITMAPINFOHEADER + píxeles RGBA.
const headerSize = 6 + bmps.length * 16;
let imageSize = 0;
for (const b of bmps) imageSize += 40 + b.raw.length;
const buf = Buffer.alloc(headerSize + imageSize);
buf.writeUInt16LE(0, 0); // reservado
buf.writeUInt16LE(1, 2); // tipo ICO
buf.writeUInt16LE(bmps.length, 4);
let offset = headerSize;
bmps.forEach((b, i) => {
  const e = 6 + i * 16;
  buf[e] = b.px === 256 ? 0 : b.px; // ancho
  buf[e + 1] = b.px === 256 ? 0 : b.px; // alto
  buf[e + 2] = 0; // paleta
  buf[e + 3] = 0; // reservado
  buf.writeUInt16LE(1, e + 4); // planos
  buf.writeUInt16LE(32, e + 6); // bits por píxel
  buf.writeUInt32LE(40 + b.raw.length, e + 8);
  buf.writeUInt32LE(offset, e + 12);
  // BITMAPINFOHEADER (altura doble: imagen + máscara)
  const h = offset;
  buf.writeUInt32LE(40, h);
  buf.writeInt32LE(b.px, h + 4);
  buf.writeInt32LE(b.px * 2, h + 8);
  buf.writeUInt16LE(1, h + 12);
  buf.writeUInt16LE(32, h + 14);
  buf.writeUInt32LE(0, h + 20);
  buf.writeUInt32LE(b.raw.length, h + 20 + 8);
  b.raw.copy(buf, offset + 40);
  offset += 40 + b.raw.length;
});
fs.writeFileSync(
  path.join(root, 'windows', 'runner', 'resources', 'app_icon.ico'),
  buf,
);
console.log('✔ windows/runner/resources/app_icon.ico');
console.log('\nIconos generados correctamente.');
