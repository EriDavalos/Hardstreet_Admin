/* Genera los recursos optimizados de la nueva portada Carta.
 *
 * Fuente: tool/portada_carta_src
 * Destino: assets/covers (para la vista previa Flutter) y
 *          lib/invitation_portada_carta_assets.dart (HTML autocontenido).
 *
 * Uso: node tool/build_portada_carta_assets.cjs
 * Requiere `sharp`, que ya vive en Hardstreet-Backend.
 */
const fs = require('fs');
const path = require('path');
const sharp = require('../../Hardstreet-Backend/node_modules/sharp');

const ROOT = path.resolve(__dirname, '..');
const SRC = path.join(__dirname, 'portada_carta_src');
const OUT = path.join(ROOT, 'assets', 'covers');
const DART = path.join(ROOT, 'lib', 'invitation_portada_carta_assets.dart');

const transparent = { r: 0, g: 0, b: 0, alpha: 0 };

async function saveWebp(input, name, { width, quality, trim = false }) {
  let img = sharp(input).rotate();
  if (trim) img = img.trim({ background: transparent, threshold: 8 });
  img = img.resize({ width, withoutEnlargement: true });
  const file = path.join(OUT, name);
  await img.webp({ quality, effort: 6, smartSubsample: true }).toFile(file);
  return file;
}

function dartString(file) {
  const b64 = fs.readFileSync(file).toString('base64');
  const lines = [];
  for (let i = 0; i < b64.length; i += 96) {
    lines.push(`    '${b64.slice(i, i + 96)}'`);
  }
  return ["    'data:image/webp;base64,'", ...lines].join('\n');
}

async function main() {
  fs.mkdirSync(OUT, { recursive: true });

  const assets = [
    {
      name: 'pc_fondo_desktop.webp',
      constName: 'kPortadaCartaFondoDesktop',
      run: () =>
        saveWebp(path.join(SRC, 'Fondo_Desktop.jpg'), 'pc_fondo_desktop.webp', {
          width: 1600,
          quality: 80,
        }),
    },
    {
      name: 'pc_fondo_movil.webp',
      constName: 'kPortadaCartaFondoMovil',
      run: () =>
        saveWebp(path.join(SRC, 'Fondo_Movil.jpg'), 'pc_fondo_movil.webp', {
          width: 900,
          quality: 80,
        }),
    },
    {
      name: 'pc_flores.webp',
      run: async () => {
        const rotated = path.join(OUT, 'pc_flores_rotada.png');
        // La foto completa se gira 90° para que las rosas queden en la
        // esquina inferior izquierda, como en la referencia.
        await sharp(path.join(SRC, 'Flores.png'))
          .rotate(-90)
          .png()
          .toFile(rotated);
        const file = await saveWebp(rotated, 'pc_flores.webp', {
          width: 760,
          quality: 86,
          trim: true,
        });
        fs.rmSync(rotated, { force: true });
        return file;
      },
    },
    {
      name: 'pc_cinta.webp',
      run: () =>
        saveWebp(path.join(SRC, 'Cinta.png'), 'pc_cinta.webp', {
          width: 520,
          quality: 86,
          trim: true,
        }),
    },
    {
      name: 'pc_anillos.webp',
      run: () =>
        saveWebp(path.join(SRC, 'Anillos.png'), 'pc_anillos.webp', {
          width: 560,
          quality: 86,
          trim: true,
        }),
    },
  ];

  const generated = [];
  for (const asset of assets) {
    const file = await asset.run();
    generated.push({ ...asset, file, bytes: fs.statSync(file).size });
    console.log(
      `${path.basename(file)}: ${(generated.at(-1).bytes / 1024).toFixed(0)} KB`,
    );
  }

  const out = [
    '// GENERADO por tool/build_portada_carta_assets.cjs.',
    '// Fondos de Portada_Carta incrustados; flores, cinta y anillos por URL.',
    '',
    ...generated
        .filter((asset) => asset.constName != null)
        .map(
          (asset) =>
              `const String ${asset.constName} =\n${dartString(asset.file)};\n`,
        ),
  ].join('\n');
  fs.writeFileSync(DART, out);
  console.log(
    `HTML assets: ${(generated.reduce((n, a) => n + a.bytes, 0) / 1024).toFixed(0)} KB`,
  );
  console.log(path.relative(ROOT, DART));
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
