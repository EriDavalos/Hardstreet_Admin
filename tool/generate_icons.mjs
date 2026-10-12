// Generador de iconos de "Hardstreet Admin".
// ORIGEN ÚNICO: hs_icon.png (raíz del repo). Produce:
//   - Android: mipmap ic_launcher (PNG con fondo azul de marca, ya que
//     Android recorta el icono a círculo/cuadrado y el alfa se pierde).
//   - Web: favicon + iconos PWA (PNG con alfa, y los maskables con fondo).
//   - Windows: app_icon.ico (16/32/48/256 con capa alfa).
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
    '../../Hardstreet-Backend/node_modules/sharp',
  );
  sharp = require(alt);
}

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const srcIcon = path.join(root, '..', 'hs_icon.png');
if (!fs.existsSync(srcIcon)) {
  console.error('No se encontro hs_icon.png en la raiz del proyecto:', srcIcon);
  process.exit(1);
}

// Fondo de marca (azul de AppColors.brand) para los destinos que NO admiten
// transparencia (launcher de Android) o que van recortados (icono maskable).
const BRAND = '#2F6BFF';

// Devuelve los píxeles RGBA del icono reescalado a px x px (fit contain).
const iconRaw = (px) =>
  sharp(srcIcon).resize(px, px, { fit: 'contain' }).ensureAlpha().raw().toBuffer();

// Liendo cuadrado final. withBrandBg pinta TODO el fondo del color de marca y
// el icono centrado encima (se pegan los píxeles RGBA a mano, sin composite,
// que falla con algunas versiones de sharp). Asi el launcher de Android (que
// recorta el alfa) siempre ve el azul de marca alrededor del icono.
const compose = async (px, withBrandBg) => {
  const raw = await iconRaw(px);
  if (!withBrandBg) {
    return sharp(raw, { raw: { width: px, height: px, channels: 4 } }).png().toBuffer();
  }
  // Fondo solido RGBA del color de marca.
  const [r, g, b] = [1, 3, 5].map((i) => parseInt(BRAND.slice(i, i + 2), 16));
  const out = Buffer.alloc(px * px * 4);
  for (let i = 0; i < out.length; i += 4) {
    out[i] = r;
    out[i + 1] = g;
    out[i + 2] = b;
    out[i + 3] = 255;
  }
  // Pega el icono centrado respetando su alfa (src-over sobre el fondo).
  for (let y = 0; y < px; y++) {
    for (let x = 0; x < px; x++) {
      const si = (y * px + x) * 4;
      const a = raw[si + 3];
      if (a === 0) continue;
      const di = si;
      const na = a / 255;
      out[di] = Math.round(raw[si] * na + out[di] * (1 - na));
      out[di + 1] = Math.round(raw[si + 1] * na + out[di + 1] * (1 - na));
      out[di + 2] = Math.round(raw[si + 2] * na + out[di + 2] * (1 - na));
      out[di + 3] = 255;
    }
  }
  return sharp(out, { raw: { width: px, height: px, channels: 4 } }).png().toBuffer();
};

// ===== Android: mipmaps ic_launcher (con fondo de marca) =====
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
  fs.writeFileSync(out, await compose(px, true));
  console.log('✔', path.relative(root, out));
}

// ===== Web: favicon + PWA =====
// Favicon e iconos normales conservan la transparencia del origen.
await sharp(srcIcon).resize(64, 64, { fit: 'contain' })
  .png().toFile(path.join(root, 'web', 'favicon.png'));
console.log('✔ web/favicon.png');
await sharp(srcIcon).resize(192, 192, { fit: 'contain' })
  .png().toFile(path.join(root, 'web', 'icons', 'Icon-192.png'));
console.log('✔ web/icons/Icon-192.png');
await sharp(srcIcon).resize(512, 512, { fit: 'contain' })
  .png().toFile(path.join(root, 'web', 'icons', 'Icon-512.png'));
console.log('✔ web/icons/Icon-512.png');
// Los iconos maskable se recortan en círculo: llevan fondo de marca.
fs.writeFileSync(
  path.join(root, 'web', 'icons', 'Icon-maskable-192.png'),
  await compose(192, true),
);
fs.writeFileSync(
  path.join(root, 'web', 'icons', 'Icon-maskable-512.png'),
  await compose(512, true),
);
console.log('✔ web/icons/Icon-maskable-*.png');

// Construye un buffer .ico a partir de [{px, raw}] (píxeles RGBA de sharp,
// top-down). Windows ICO/BMP de 32 bits espera BGRA bottom-up, así que hay// que invertir los canales (R<->B) y el orden de filas; sin esto el icono
// sale azul y del revés.
const buildIco = (bmps) => {
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
    // Píxeles: convierte RGBA top-down -> BGRA bottom-up.
    const px = b.px;
    const rowSize = px * 4;
    for (let y = 0; y < px; y++) {
      const srcRow = y * rowSize; // sharp: fila 0 = arriba
      const dstRow = offset + 40 + (px - 1 - y) * rowSize; // BMP: fila 0 = abajo
      for (let x = 0; x < px; x++) {
        const s = srcRow + x * 4;
        const d = dstRow + x * 4;
        buf[d] = b.raw[s + 2]; // B
        buf[d + 1] = b.raw[s + 1]; // G
        buf[d + 2] = b.raw[s]; // R
        buf[d + 3] = b.raw[s + 3]; // A
      }
    }
    offset += 40 + b.raw.length;
  });
  return buf;
};

// ===== Windows: app_icon.ico (16/32/48/256, con capa alfa) =====
const icoSizes = [16, 32, 48, 256];
const bmps = [];
for (const px of icoSizes) {
  const raw = await sharp(srcIcon)
    .resize(px, px, { fit: 'contain' })
    .ensureAlpha()
    .raw()
    .toBuffer();
  bmps.push({ px, raw });
}
fs.writeFileSync(
  path.join(root, 'windows', 'runner', 'resources', 'app_icon.ico'),
  buildIco(bmps),
);
console.log('✔ windows/runner/resources/app_icon.ico');

// ===== Windows: setup_icon.ico (para Inno Setup) =====
// Mismo origen (hs_icon.png) pero SIN la entrada 256x256 sin comprimir, que
// excede el limite de recursos del instalador. Solo 16/32/48.
const setupSizes = [16, 32, 48];
const setupBmps = [];
for (const px of setupSizes) {
  const raw = await sharp(srcIcon)
    .resize(px, px, { fit: 'contain' })
    .ensureAlpha()
    .raw()
    .toBuffer();
  setupBmps.push({ px, raw });
}
fs.writeFileSync(
  path.join(root, 'windows', 'runner', 'resources', 'setup_icon.ico'),
  buildIco(setupBmps),
);
console.log('✔ windows/runner/resources/setup_icon.ico');

console.log('\nIconos generados desde hs_icon.png correctamente.');
