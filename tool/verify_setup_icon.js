// Verifica que el instalador de Inno Setup embebe el icono de wizard
// (SetupIconFile) comparando los recursos RT_ICON del .exe del setup contra
// las entradas del .ico de disco. Parsea el PE (secciones + directorio de
// recursos) a mano, igual que tool/verify_pe_icon.js.
// Uso: node tool/verify_setup_icon.js <setup.exe> <setup_icon.ico>
import fs from 'node:fs';

const [setupPath, icoPath] = process.argv.slice(2);
if (!setupPath || !icoPath) {
  console.error('Uso: node tool/verify_setup_icon.js <setup.exe> <setup_icon.ico>');
  process.exit(2);
}
const b = fs.readFileSync(setupPath);

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
    va: b.readUInt32LE(o + 12),
    vs: b.readUInt32LE(o + 8),
    rp: b.readUInt32LE(o + 20),
    rs: b.readUInt32LE(o + 16),
  });
}
const rva2off = (rva) => {
  for (const s of secs) {
    if (rva >= s.va && rva < s.va + Math.max(s.vs, s.rs)) return s.rp + (rva - s.va);
  }
  return -1;
};

const rsrcOff = rva2off(rsrcRva);
if (rsrcOff < 0) {
  console.log(`No hay seccion .rsrc en ${setupPath} (¿icono no embebido?)`);
  process.exit(1);
}

// --- Recursos RT_ICON (tipo 3) ---
const dirCount = (off) => b.readUInt16LE(off + 14) & 0xffff;
const slot = (off, i) => {
  const o = off + 16 + i * 8;
  const name = b.readUInt32LE(o);
  const ptr = b.readUInt32LE(o + 4);
  return { id: name & 0xffff, off: ptr & 0x7fffffff };
};

const iconRes = [];
const rootN = dirCount(rsrcOff);
for (let i = 0; i < rootN; i++) {
  const type = slot(rsrcOff, i);
  if (type.id !== 3) continue; // RT_ICON
  const typeOff = rsrcOff + type.off;
  const imgN = dirCount(typeOff);
  for (let j = 0; j < imgN; j++) {
    const img = slot(typeOff, j);
    const langOff = rsrcOff + img.off;
    const lang = slot(langOff, 0);
    const dataOff = rva2off(rsrcOff + lang.off);
    const dataRva = b.readUInt32LE(dataOff);
    const size = b.readUInt32LE(dataOff + 4);
    iconRes.push(b.subarray(rva2off(dataRva), rva2off(dataRva) + size));
  }
}
console.log(`RT_ICON en el setup: ${iconRes.length}`);

// --- Entradas del .ico de disco (incluyen el DIB header de 40 bytes) ---
const ico = fs.readFileSync(icoPath);
const n = ico.readUInt16LE(4);
const entries = [];
for (let i = 0; i < n; i++) {
  const e = 6 + i * 16;
  const w = ico[e] || 256;
  const size = ico.readUInt32LE(e + 8);
  const off = ico.readUInt32LE(e + 12);
  entries.push({ w, size, bytes: ico.subarray(off, off + size) });
}
console.log(`entradas en ${icoPath}: ${entries.map((e) => `${e.w}x${e.w}(size=${e.size})`).join(', ')}`);

let found = 0;
for (const r of iconRes) {
  for (const e of entries) {
    if (r.length !== e.size) continue;
    let same = true;
    for (let k = 0; k < r.length; k++) {
      if (r[k] !== e.bytes[k]) { same = false; break; }
    }
    if (same) {
      console.log(`  MATCH: recurso size=${e.size} == entrada ${e.w}x${e.w} (mismos bytes)`);
      found++;
    }
  }
}
console.log(found > 0
  ? `OK: ${setupPath} embebe ${icoPath} (origen hs_icon.png)`
  : `REVISAR: ${setupPath} NO coincide con ${icoPath}`);
