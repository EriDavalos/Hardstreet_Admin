// Verifica que el icono embebido en un PE (exe) coincide con un .ico de disco.
// Parsea el PE a mano (secciones + directorio de recursos), extrae los recursos
// RT_ICON (tipo 3), y para cada uno compara longitud + suma + suma ponderada
// contra cada entrada del .ico. Si alguna entrada coincide cifra a cifra, el
// PE embebe ese .ico (y por tanto el origen: hs_icon.png).
// Uso: node tool/verify_pe_icon.js <exe> [ico]
import fs from 'node:fs';

const exePath = process.argv[2] ?? 'build/windows/x64/runner/Release/HardstreetAdmin.exe';
const icoPath = process.argv[3] ?? 'windows/runner/resources/app_icon.ico';
const b = fs.readFileSync(exePath);

// --- Cabecera PE ---
const peOff = b.readInt32LE(0x3c);
const numSec = b.readUInt16LE(peOff + 6);
const optSize = b.readUInt16LE(peOff + 20);
const magic = b.readUInt16LE(peOff + 24);
const ddOff = magic === 0x20b ? peOff + 24 + 112 : peOff + 24 + 96; // PE32+ vs PE32
const rsrcRva = b.readUInt32LE(ddOff + 2 * 8); // data directory índice 2 = recursos

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
if (rsrcOff < 0) { console.error('No se encontró la sección .rsrc'); process.exit(1); }

// --- Directorio de recursos (3 niveles: tipo -> nombre/id -> lenguaje -> data) ---
// Recorre el árbol y recolecta los data entries cuyo tipo == 3 (RT_ICON).
const dirCount = (off) => b.readUInt16LE(off + 14) & 0xffff; // NumberOfIdEntries
const slot = (off, i) => {
  const o = off + 16 + i * 8;
  const name = b.readUInt32LE(o);
  const ptr = b.readUInt32LE(o + 4);
  return { id: name & 0xffff, isDir: (ptr >>> 31) === 1, off: ptr & 0x7fffffff };
};

const iconRes = [];
const rootN = dirCount(rsrcOff);
for (let i = 0; i < rootN; i++) {
  const type = slot(rsrcOff, i);
  if (type.id !== 3) continue; // solo RT_ICON
  const typeOff = rsrcOff + type.off;
  const imgN = dirCount(typeOff);
  for (let j = 0; j < imgN; j++) {
    const img = slot(typeOff, j);
    const langOff = rsrcOff + img.off;
    const langN = dirCount(langOff);
    const lang = slot(langOff, 0); // primer lenguaje
    const dataEntryOff = rsrcOff + lang.off;
    const dataRva = b.readUInt32LE(dataEntryOff);
    const size = b.readUInt32LE(dataEntryOff + 4);
    const fileOff = rva2off(dataRva);
    iconRes.push(b.subarray(fileOff, fileOff + size));
  }
}
console.log(`RT_ICON en ${exePath}: ${iconRes.length}`);

// --- Agregados de cada recurso ---
const agg = (data) => {
  let sum = 0n, wsum = 0n;
  for (let k = 0; k < data.length; k++) {
    sum += BigInt(data[k]);
    wsum += BigInt(data[k]) * BigInt(k % 251);
  }
  return { size: data.length, sum, wsum };
};

// --- Entradas del .ico de disco ---
const ico = fs.readFileSync(icoPath);
const n = ico.readUInt16LE(4);
const entries = [];
for (let i = 0; i < n; i++) {
  const e = 6 + i * 16;
  const w = ico[e] || 256;
  const size = ico.readUInt32LE(e + 8);
  const off = ico.readUInt32LE(e + 12);
  entries.push({ w, ...agg(ico.subarray(off, off + size)) });
}
console.log(`entradas en ${icoPath}: ${entries.map((e) => `${e.w}x${e.w}(size=${e.size})`).join(', ')}`);

let found = false;
for (const r of iconRes) {
  const a = agg(r);
  for (const e of entries) {
    if (a.size === e.size && a.sum === e.sum && a.wsum === e.wsum) {
      console.log(`  MATCH: recurso size=${a.size} == entrada ${e.w}x${e.w} (mismos bytes)`);
      found = true;
    }
  }
}
console.log(found
  ? `OK: ${exePath} embebe el icono de ${icoPath} (origen hs_icon.png)`
  : `REVISAR: ${exePath} NO coincide con ${icoPath}`);
