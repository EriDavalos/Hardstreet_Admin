// Extrae el icono embebido en un PE (exe) y lo guarda como PNG para
// inspeccion visual. Usa el mismo fallback de sharp que generate_icons.mjs.
// Uso: node tool/extract_pe_icon.js <exe> <out.png> [size]
import { createRequire } from 'node:module';
import fs from 'node:fs';
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

const [exePath, outPath, sizeArg] = process.argv.slice(2);
const size = Number(sizeArg || 128);
const b = fs.readFileSync(exePath);

// --- Cabecera PE ---
const peOff = b.readInt32LE(0x3c);
const numSec = b.readUInt16LE(peOff + 6);
const optSize = b.readUInt16LE(peOff + 20);
const magic = b.readUInt16LE(peOff + 24);
const ddOff = magic === 0x20b ? peOff + 24 + 112 : peOff + 24 + 96;
const rsrcRva = b.readUInt32LE(ddOff + 2 * 8);

// --- Secciones ---
const secOff = peOff + 24 + optSize;
const secs = [];
for (let i = 0; i < numSec; i++) {
  const o = secOff + i * 40;
  secs.push({
    va: b.readUInt32LE(o + 12), vs: b.readUInt32LE(o + 8),
    rp: b.readUInt32LE(o + 20), rs: b.readUInt32LE(o + 16),
  });
}
const rva2off = (rva) => {
  for (const s of secs) {
    if (rva >= s.va && rva < s.va + Math.max(s.vs, s.rs)) return s.rp + (rva - s.va);
  }
  return -1;
};
const rsrcOff = rva2off(rsrcRva);
const dirCount = (off) => b.readUInt16LE(off + 14) & 0xffff;
const slot = (off, i) => {
  const o = off + 16 + i * 8;
  const name = b.readUInt32LE(o);
  const ptr = b.readUInt32LE(o + 4);
  return { id: name & 0xffff, off: ptr & 0x7fffffff };
};

// Recolecta los recursos RT_ICON (tipo 3).
const iconRes = [];
const rootN = dirCount(rsrcOff);
for (let i = 0; i < rootN; i++) {
  const type = slot(rsrcOff, i);
  if (type.id !== 3) continue;
  const typeOff = rsrcOff + type.off;
  const imgN = dirCount(typeOff);
  for (let j = 0; j < imgN; j++) {
    const img = slot(typeOff, j);
    const lang = slot(rsrcOff + img.off, 0);
    const dataOff = rva2off(rsrcOff + lang.off);
    const dataRva = b.readUInt32LE(dataOff);
    const sz = b.readUInt32LE(dataOff + 4);
    iconRes.push(b.subarray(rva2off(dataRva), rva2off(dataRva) + sz));
  }
}
console.log(`RT_ICON en ${exePath}: ${iconRes.length}`);

// Elige el recurso mas grande (el de mayor resolucion) y conviértelo a PNG.
const best = iconRes.reduce((a, c) => (c.length > a.length ? c : a), iconRes[0]);
const w = best.readInt32LE(4);
const h = Math.abs(best.readInt32LE(8)) / 2; // altura doble (XOR + AND)
const bpp = best.readUInt16LE(14);
console.log(`recurso elegido: ${w}x${h} ${bpp}bpp size=${best.length}`);

if (bpp === 32) {
  const px = w * h * 4;
  const dib = best.subarray(40, 40 + px); // BGRA bottom-up
  const rgba = Buffer.alloc(px);
  for (let y = 0; y < h; y++) {
    const srcRow = h - 1 - y;
    for (let x = 0; x < w; x++) {
      const s = (srcRow * w + x) * 4;
      const d = (y * w + x) * 4;
      rgba[d] = dib[s + 2];
      rgba[d + 1] = dib[s + 1];
      rgba[d + 2] = dib[s];
      rgba[d + 3] = dib[s + 3];
    }
  }
  await sharp(rgba, { raw: { width: w, height: h, channels: 4 } })
    .resize(size, size, { kernel: 'nearest' })
    .png()
    .toFile(outPath);
  console.log(`guardado ${outPath} (${w}x${h} -> ${size}x${size})`);
} else {
  console.log(`bpp=${bpp}: conversión no soportada aqui; usa extract_setup_icon.ps1`);
  process.exit(1);
}
