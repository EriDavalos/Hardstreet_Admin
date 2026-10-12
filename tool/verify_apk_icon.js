// Compara el icono embebido en el APK (res/*.png) contra el mipmap fuente
// generado desde hs_icon.png. Si los pixeles son identicos, el APK lleva el
// icono actual. Requiere sharp (usa el node_modules del backend hermano).
// Uso: node tool/verify_apk_icon.js <apk_png_extraido> <mipmap_fuente>
import { createRequire } from 'node:module';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const require = createRequire(import.meta.url);
let sharp;
try {
  sharp = require('sharp');
} catch {
  const alt = path.resolve(
    path.dirname(fileURLToPath(import.meta.url)),
    '../../Hardstreet-Backend/node_modules/sharp',
  );
  sharp = require(alt);
}

const [apkPng, srcPng] = process.argv.slice(2);
if (!apkPng || !srcPng) {
  console.error('Uso: node tool/verify_apk_icon.js <apk_png> <mipmap_fuente>');
  process.exit(2);
}

const a = await sharp(apkPng).ensureAlpha().raw().toBuffer({ resolveWithObject: true });
const b = await sharp(srcPng).ensureAlpha().raw().toBuffer({ resolveWithObject: true });
console.log('APK   ', `${a.info.width}x${a.info.height}`);
console.log('mipmap', `${b.info.width}x${b.info.height}`);

if (a.data.length !== b.data.length) {
  console.log('DIFIEREN: tamanio de pixel distinto');
  process.exit(1);
}
let diff = 0;
for (let i = 0; i < a.data.length; i++) if (a.data[i] !== b.data[i]) diff++;
console.log(`bytes de canal distintos: ${diff}/${a.data.length}`);
if (diff === 0) {
  console.log('PIXELES IDENTICOS: el APK embebe el mipmap de hs_icon.png');
} else {
  console.log('DIFIEREN EN PIXELES (revisar)');
  process.exit(1);
}
