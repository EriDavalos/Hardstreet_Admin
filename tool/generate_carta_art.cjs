/* Genera los PNG de la portada Carta.
 * Uso: node tool/generate_carta_art.cjs
 * Requiere `sharp` (ya está instalado en Hardstreet-Backend).
 */
const fs = require('fs');
const path = require('path');
const sharp = require('../../Hardstreet-Backend/node_modules/sharp');

const OUT = path.join(__dirname, '..', 'assets', 'covers');
fs.mkdirSync(OUT, { recursive: true });

const TAU = Math.PI * 2;
const n = (v) => Number(v.toFixed(2));

function defs() {
  return `
  <defs>
    <radialGradient id="ivory" cx="36%" cy="28%" r="78%">
      <stop offset="0" stop-color="#fffdf8"/>
      <stop offset=".48" stop-color="#f4e7d6"/>
      <stop offset=".8" stop-color="#e7d2b8"/>
      <stop offset="1" stop-color="#d8baa0"/>
    </radialGradient>
    <radialGradient id="ivoryInner" cx="42%" cy="38%" r="70%">
      <stop offset="0" stop-color="#fffdfa"/>
      <stop offset=".62" stop-color="#f7ecde"/>
      <stop offset="1" stop-color="#e6cfb4"/>
    </radialGradient>
    <linearGradient id="leaf" x1="0" y1="0" x2="1" y2="1">
      <stop offset="0" stop-color="#8b997b"/>
      <stop offset=".55" stop-color="#5f7055"/>
      <stop offset="1" stop-color="#3e5039"/>
    </linearGradient>
    <linearGradient id="euca" x1="0" y1="0" x2="1" y2="1">
      <stop offset="0" stop-color="#c8d1bd"/>
      <stop offset=".48" stop-color="#91a284"/>
      <stop offset="1" stop-color="#5b7057"/>
    </linearGradient>
    <linearGradient id="gold" x1="0" y1="0" x2="1" y2="1">
      <stop offset="0" stop-color="#fff2bd"/>
      <stop offset=".18" stop-color="#d8b466"/>
      <stop offset=".42" stop-color="#a97c2d"/>
      <stop offset=".62" stop-color="#f6dfa0"/>
      <stop offset=".82" stop-color="#bc8e3e"/>
      <stop offset="1" stop-color="#7c551d"/>
    </linearGradient>
    <linearGradient id="silk" x1="0" y1="0" x2="1" y2="1">
      <stop offset="0" stop-color="#fffaf1" stop-opacity=".94"/>
      <stop offset=".3" stop-color="#f4e2c9" stop-opacity=".86"/>
      <stop offset=".54" stop-color="#d8b98e" stop-opacity=".62"/>
      <stop offset=".78" stop-color="#fff7eb" stop-opacity=".9"/>
      <stop offset="1" stop-color="#caa77c" stop-opacity=".45"/>
    </linearGradient>
    <linearGradient id="seal" x1="0" y1="0" x2="1" y2="1">
      <stop offset="0" stop-color="#fff8e8"/>
      <stop offset=".32" stop-color="#ead6b8"/>
      <stop offset=".68" stop-color="#cbb18d"/>
      <stop offset="1" stop-color="#a88a67"/>
    </linearGradient>
    <radialGradient id="sealLight" cx="34%" cy="25%" r="75%">
      <stop offset="0" stop-color="#fffdf4" stop-opacity=".95"/>
      <stop offset=".55" stop-color="#f0dfc7" stop-opacity=".55"/>
      <stop offset="1" stop-color="#c6a982" stop-opacity=".16"/>
    </radialGradient>
    <filter id="shadow" x="-40%" y="-40%" width="180%" height="180%">
      <feDropShadow dx="0" dy="14" stdDeviation="12" flood-color="#3c2b22" flood-opacity=".28"/>
    </filter>
    <filter id="soft" x="-40%" y="-40%" width="180%" height="180%">
      <feDropShadow dx="0" dy="6" stdDeviation="8" flood-color="#4a352b" flood-opacity=".16"/>
    </filter>
    <filter id="blur"><feGaussianBlur stdDeviation="9"/></filter>
  </defs>`;
}

function rose(cx, cy, r, id, rot = 0) {
  const outer = [];
  const mid = [];
  const inner = [];
  for (let i = 0; i < 9; i++) {
    const a = rot + i * 40 + (i % 2 ? 5 : -4);
    outer.push(`<path d="M0 0 C ${-r * .55} ${-r * .22}, ${-r * .53} ${-r * .78}, 0 ${-r * .9} C ${r * .53} ${-r * .78}, ${r * .55} ${-r * .22}, 0 0 Z" transform="rotate(${n(a)}) translate(0 ${n(r * .05)})" fill="url(#ivory)" stroke="#cfb397" stroke-opacity=".35" stroke-width="1.2"/>`);
  }
  for (let i = 0; i < 7; i++) {
    const a = rot + 24 + i * (360 / 7);
    mid.push(`<path d="M0 0 C ${-r * .42} ${-r * .2}, ${-r * .43} ${-r * .62}, 0 ${-r * .74} C ${r * .43} ${-r * .62}, ${r * .42} ${-r * .2}, 0 0 Z" transform="rotate(${n(a)}) translate(0 ${n(r * .12)})" fill="url(#ivoryInner)" stroke="#d9bfa4" stroke-opacity=".3" stroke-width="1"/>`);
  }
  for (let i = 0; i < 5; i++) {
    const a = rot + 58 + i * 72;
    inner.push(`<path d="M0 0 C ${-r * .3} ${-r * .18}, ${-r * .3} ${-r * .46}, 0 ${-r * .55} C ${r * .3} ${-r * .46}, ${r * .3} ${-r * .18}, 0 0 Z" transform="rotate(${n(a)}) translate(0 ${n(r * .16)})" fill="#fffaf0" stroke="#d8bfa4" stroke-opacity=".32" stroke-width=".8"/>`);
  }
  return `<g transform="translate(${cx} ${cy})" filter="url(#shadow)">
    <ellipse cx="4" cy="${n(r * .12)}" rx="${n(r * .78)}" ry="${n(r * .58)}" fill="#4b3328" opacity=".18" filter="url(#blur)"/>
    ${outer.join('')}
    ${mid.join('')}
    ${inner.join('')}
    <path d="M ${-r * .1} ${-r * .12} C ${-r * .32} ${-r * .24}, ${-r * .2} ${-r * .38}, ${r * .02} ${-r * .32} C ${r * .23} ${-r * .26}, ${r * .18} ${-r * .05}, ${-r * .02} ${-r * .02} C ${r * .2} ${r * .02}, ${r * .12} ${r * .16}, ${-r * .02} ${r * .12} C ${-r * .18} ${r * .08}, ${-r * .18} ${-r * .04}, ${-r * .04} ${-r * .02}" fill="none" stroke="#c9ab8b" stroke-opacity=".7" stroke-width="${n(r * .035)}" stroke-linecap="round"/>
    <ellipse cx="${-r * .16}" cy="${-r * .2}" rx="${r * .28}" ry="${r * .18}" fill="#fffdf7" opacity=".3" transform="rotate(-28 ${-r * .16} ${-r * .2})"/>
  </g>`;
}

function leaf(cx, cy, len, wid, rot, fill = 'url(#leaf)') {
  return `<g transform="translate(${cx} ${cy}) rotate(${rot})" filter="url(#soft)">
    <path d="M0 0 C ${-wid * .5} ${-len * .28}, ${-wid * .48} ${-len * .78}, 0 ${-len} C ${wid * .48} ${-len * .78}, ${wid * .5} ${-len * .28}, 0 0 Z" fill="${fill}" stroke="#384835" stroke-opacity=".18" stroke-width=".8"/>
    <path d="M0 0 C ${wid * .05} ${-len * .3}, ${wid * .03} ${-len * .68}, 0 ${-len * .88}" fill="none" stroke="#f3edda" stroke-opacity=".38" stroke-width="1.1"/>
  </g>`;
}

function baby(cx, cy, s = 1, rot = 0) {
  const blossoms = [];
  for (let i = 0; i < 7; i++) {
    const a = rot + i * 51;
    const rr = i === 0 ? 0 : s * (5 + (i % 3) * 3);
    const x = Math.cos(a * Math.PI / 180) * rr;
    const y = Math.sin(a * Math.PI / 180) * rr * .8;
    blossoms.push(`<g transform="translate(${n(x)} ${n(y)}) scale(${n(.72 + (i % 3) * .13)})"><circle r="3.1" fill="#fffdf7"/><circle cx="-2.5" cy="-1.6" r="1.7" fill="#fffdf7"/><circle cx="2.5" cy="-1.6" r="1.7" fill="#fffdf7"/><circle cx="-1.7" cy="2.2" r="1.7" fill="#fffdf7"/><circle cx="1.7" cy="2.2" r="1.7" fill="#fffdf7"/><circle r="1.2" fill="#d9c7a3"/></g>`);
  }
  return `<g transform="translate(${cx} ${cy}) rotate(${rot})" filter="url(#soft)">${blossoms.join('')}</g>`;
}

function stem(d, w = 3) {
  return `<path d="${d}" fill="none" stroke="#65755a" stroke-width="${w}" stroke-linecap="round" filter="url(#soft)"/>`;
}

function rosesSvg() {
  const parts = [defs()];
  // Ramos y hojas detrás de las flores.
  parts.push(stem('M 38 820 C 84 690, 120 610, 208 500', 5));
  parts.push(stem('M 110 820 C 145 700, 172 570, 290 432', 5));
  parts.push(stem('M 225 820 C 250 700, 300 590, 383 535', 4));
  parts.push(stem('M 300 820 C 295 704, 324 620, 405 590', 3.4));
  parts.push(leaf(120, 610, 155, 55, -38));
  parts.push(leaf(165, 570, 140, 50, 38, 'url(#euca)'));
  parts.push(leaf(195, 655, 180, 62, 58));
  parts.push(leaf(260, 640, 156, 53, -32, 'url(#euca)'));
  parts.push(leaf(332, 664, 126, 45, 42));
  parts.push(leaf(270, 545, 128, 43, 14, 'url(#euca)'));
  parts.push(leaf(365, 555, 142, 47, -28));
  parts.push(stem('M 96 760 C 82 680, 90 600, 142 535', 1.4));
  parts.push(stem('M 150 790 C 175 700, 198 645, 238 590', 1.4));
  // Baby's breath.
  [
    [128, 538, 1.25, -12], [176, 500, .95, 20], [212, 560, 1.1, -20],
    [250, 518, .9, 18], [292, 590, .9, -8], [74, 585, .9, 30],
    [338, 520, .8, 20], [370, 610, .8, -18], [54, 690, .8, 10],
  ].forEach(([x, y, s, rot]) => parts.push(baby(x, y, s, rot)));
  // Rosas principales.
  parts.push(rose(135, 695, 116, 'a', -18));
  parts.push(rose(285, 720, 94, 'b', 21));
  parts.push(rose(45, 748, 78, 'c', 42));
  parts.push(rose(352, 660, 68, 'd', -36));
  // Capullos.
  parts.push(`<g filter="url(#soft)"><path d="M 335 550 C 322 520, 342 494, 365 504 C 379 512, 372 540, 356 556 Z" fill="url(#ivory)" stroke="#cfb397" stroke-opacity=".3"/><path d="M 350 561 C 350 538, 358 516, 365 504" fill="none" stroke="#75836a" stroke-width="2"/></g>`);
  parts.push(`<g filter="url(#soft)"><path d="M 210 606 C 202 582, 220 562, 238 572 C 248 579, 242 598, 229 610 Z" fill="url(#ivoryInner)" stroke="#cfb397" stroke-opacity=".3"/></g>`);
  return `<svg xmlns="http://www.w3.org/2000/svg" width="640" height="840" viewBox="0 0 640 840">${parts.join('')}</svg>`;
}

function eucalyptusSvg() {
  const parts = [defs()];
  parts.push(stem('M 42 770 C 90 600, 172 390, 302 52', 4));
  parts.push(stem('M 76 700 C 100 590, 116 500, 150 398', 2.5));
  const positions = [];
  for (let i = 0; i < 14; i++) {
    const t = i / 13;
    const x = 42 + t * 260 + Math.sin(i) * 15;
    const y = 770 - t * 700;
    positions.push([x, y, 58 - t * 24, 26 - t * 6, i % 2 ? 58 : -58]);
  }
  for (let i = 0; i < 8; i++) {
    const t = i / 7;
    positions.push([76 + t * 70 + Math.sin(i * 2) * 14, 700 - t * 270, 45 - t * 12, 20 - t * 4, i % 2 ? 46 : -46]);
  }
  positions.forEach(([x, y, len, wid, rot], i) => {
    parts.push(`<g transform="translate(${n(x)} ${n(y)}) rotate(${rot})" filter="url(#soft)">
      <path d="M0 0 C ${-wid * .7} ${-len * .28}, ${-wid * .62} ${-len * .8}, 0 ${-len} C ${wid * .62} ${-len * .8}, ${wid * .7} ${-len * .28}, 0 0 Z" fill="url(#euca)" stroke="#4f624b" stroke-opacity=".22"/>
      <path d="M0 0 C 1 ${-len * .3}, 0 ${-len * .68}, 0 ${-len * .86}" fill="none" stroke="#f1efdf" stroke-opacity=".38"/>
      <ellipse cx="${-wid * .12}" cy="${-len * .45}" rx="${wid * .2}" ry="${len * .25}" fill="#fff" opacity=".12" transform="rotate(-18 ${-wid * .12} ${-len * .45})"/>
    </g>`);
  });
  parts.push(stem('M 42 770 C 100 620, 190 420, 302 52', 1.1));
  return `<svg xmlns="http://www.w3.org/2000/svg" width="420" height="800" viewBox="0 0 420 800">${parts.join('')}</svg>`;
}

function ringsSvg() {
  const ring = (cx, cy, rx, ry, rot, opacity = 1) => `<g transform="translate(${cx} ${cy}) rotate(${rot})" filter="url(#shadow)">
    <ellipse rx="${rx}" ry="${ry}" fill="none" stroke="#6d4d21" stroke-width="14" opacity=".3" transform="translate(0 5)"/>
    <ellipse rx="${rx}" ry="${ry}" fill="none" stroke="url(#gold)" stroke-width="12"/>
    <ellipse rx="${rx}" ry="${ry}" fill="none" stroke="#fff4c8" stroke-opacity=".7" stroke-width="3" stroke-dasharray="42 115" transform="rotate(18)"/>
    <ellipse rx="${rx - 5}" ry="${ry - 5}" fill="none" stroke="#8a5d20" stroke-opacity=".45" stroke-width="1.2"/>
    <ellipse rx="${rx + 5}" ry="${ry + 5}" fill="none" stroke="#fff0b5" stroke-opacity=".4" stroke-width="1.2"/>
  </g>`;
  return `<svg xmlns="http://www.w3.org/2000/svg" width="420" height="280" viewBox="0 0 420 280">${defs()}
    <g filter="url(#shadow)"><ellipse cx="220" cy="152" rx="86" ry="56" fill="#66451d" opacity=".12" filter="url(#blur)"/></g>
    ${ring(235, 138, 82, 53, -15)}
    ${ring(168, 154, 82, 53, -15)}
    <path d="M 198 103 C 222 88, 250 92, 268 109" fill="none" stroke="#fff7d1" stroke-opacity=".55" stroke-width="2" stroke-linecap="round"/>
  </svg>`;
}

function stationerySvg() {
  return `<svg xmlns="http://www.w3.org/2000/svg" width="460" height="660" viewBox="0 0 460 660">${defs()}
    <g transform="translate(250 120) rotate(7)" filter="url(#shadow)">
      <rect width="190" height="250" rx="3" fill="#d8c7b2" opacity=".28" transform="translate(10 14)"/>
      <rect width="190" height="250" rx="2" fill="#fffaf0" stroke="#d8c3a6"/>
      <rect x="14" y="14" width="162" height="130" fill="#d9c3a8"/>
      <rect x="14" y="14" width="162" height="130" fill="url(#silk)" opacity=".5"/>
      <circle cx="95" cy="78" r="30" fill="#f6ead8" opacity=".55"/>
      <path d="M 41 158 C 88 150, 131 166, 163 190" fill="none" stroke="#c6ad8e" stroke-width="1"/>
      <path d="M 41 173 C 80 166, 119 177, 151 199" fill="none" stroke="#c6ad8e" stroke-width="1"/>
    </g>
    <g transform="translate(56 96) rotate(-9)" filter="url(#shadow)">
      <rect width="200" height="280" rx="3" fill="#cbb69b" opacity=".22" transform="translate(9 13)"/>
      <rect width="200" height="280" rx="2" fill="#fffdf7" stroke="#dcc9ae"/>
      <path d="M 22 52 C 70 40, 136 40, 178 53" fill="none" stroke="#c7ad8b" stroke-width=".9"/>
      <path d="M 42 83 C 88 74, 132 78, 164 94" fill="none" stroke="#d6c2a6" stroke-width="1.2"/>
      <path d="M 42 103 C 85 96, 124 101, 151 112" fill="none" stroke="#d6c2a6" stroke-width="1.2"/>
      <path d="M 42 123 C 80 117, 103 121, 127 130" fill="none" stroke="#d6c2a6" stroke-width="1.2"/>
      <path d="M 70 190 C 95 175, 122 178, 140 194" fill="none" stroke="#b59b7c" stroke-width="1"/>
    </g>
  </svg>`;
}

function silkSvg() {
  return `<svg xmlns="http://www.w3.org/2000/svg" width="760" height="1100" viewBox="0 0 760 1100">${defs()}
    <g filter="url(#shadow)">
      <path d="M 760 40 C 590 80, 565 214, 612 330 C 660 447, 617 612, 760 708 L 760 40 Z" fill="url(#silk)"/>
      <path d="M 760 62 C 612 108, 598 242, 642 374 C 690 507, 666 637, 760 766 L 760 62 Z" fill="none" stroke="#fff9ee" stroke-opacity=".55" stroke-width="2"/>
      <path d="M 760 150 C 664 184, 650 271, 688 380 C 720 476, 710 570, 760 660" fill="none" stroke="#b6956d" stroke-opacity=".3" stroke-width="10" filter="url(#blur)"/>
    </g>
  </svg>`;
}

function sealSvg() {
  const pts = [];
  const count = 28;
  for (let i = 0; i < count; i++) {
    const a = (i / count) * TAU;
    const r = 86 + Math.sin(i * 2.3) * 4.5 + Math.cos(i * 1.7) * 3;
    pts.push(`${n(120 + Math.cos(a) * r)} ${n(118 + Math.sin(a) * r * .96)}`);
  }
  return `<svg xmlns="http://www.w3.org/2000/svg" width="240" height="240" viewBox="0 0 240 240">${defs()}
    <g filter="url(#shadow)">
      <path d="M ${pts.join(' L ')} Z" fill="url(#seal)" stroke="#b0906a" stroke-opacity=".5" stroke-width="1.4"/>
      <path d="M ${pts.join(' L ')} Z" fill="url(#sealLight)"/>
      <circle cx="120" cy="118" r="62" fill="none" stroke="#a8875f" stroke-opacity=".55" stroke-width="2"/>
      <circle cx="120" cy="118" r="53" fill="none" stroke="#fff8e8" stroke-opacity=".45" stroke-width="1.2"/>
      <path d="M 78 96 C 100 83, 138 84, 160 99" fill="none" stroke="#fffdf4" stroke-opacity=".38" stroke-width="3" stroke-linecap="round"/>
      <ellipse cx="88" cy="80" rx="18" ry="8" fill="#fff" opacity=".22" transform="rotate(-24 88 80)"/>
    </g>
  </svg>`;
}

function petalSvg() {
  return `<svg xmlns="http://www.w3.org/2000/svg" width="96" height="64" viewBox="0 0 96 64">${defs()}
    <g filter="url(#soft)">
      <path d="M 8 34 C 18 8, 62 -8, 87 13 C 98 30, 62 59, 29 53 C 18 50, 11 44, 8 34 Z" fill="url(#ivory)" stroke="#d6bea2" stroke-opacity=".35"/>
      <path d="M 15 33 C 30 19, 57 11, 78 19" fill="none" stroke="#fffdf7" stroke-opacity=".55" stroke-width="2"/>
    </g>
  </svg>`;
}

async function render(name, svg, width, { quality = 90, colors = 160 } = {}) {
  const png = await sharp(Buffer.from(svg), { density: 144 })
    .resize({ width, withoutEnlargement: false })
    .png({ compressionLevel: 9, palette: true, quality, colours: colors, effort: 10 })
    .toBuffer();
  fs.writeFileSync(path.join(OUT, `${name}.png`), png);
  console.log(`${name}.png ${(png.length / 1024).toFixed(1)} KB`);
}

(async () => {
  await render('roses', rosesSvg(), 720, { quality: 92, colors: 160 });
  await render('eucalyptus', eucalyptusSvg(), 480, { quality: 88, colors: 96 });
  await render('rings', ringsSvg(), 460, { quality: 92, colors: 128 });
  await render('stationery', stationerySvg(), 520, { quality: 88, colors: 96 });
  await render('silk', silkSvg(), 760, { quality: 82, colors: 64 });
  await render('seal', sealSvg(), 300, { quality: 90, colors: 96 });
  await render('petal', petalSvg(), 128, { quality: 90, colors: 64 });
})().catch((e) => {
  console.error(e);
  process.exit(1);
});
