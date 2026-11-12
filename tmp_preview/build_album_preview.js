// Vista previa LOCAL del Álbum digital, sin base de datos ni Drive.
// Extrae la página real de Hardstreet-Backend y la rellena con fotos demo.
const fs = require("fs");
const path = require("path");

const root = path.resolve(__dirname, "../..");
const source = path.join(root, "Hardstreet-Backend/pages/api/albums/page.ts");
const out = path.join(__dirname, "album.html");

const src = fs.readFileSync(source, "utf8");
const start = src.lastIndexOf("return `<!DOCTYPE html>");
const end = src.indexOf("</html>`;", start);
if (start < 0 || end < 0) {
  throw new Error("No se encontró la plantilla del álbum en page.ts");
}

let html = src.slice(start + "return `".length, end) + "</html>";

// Valores de la invitación demo.
html = html
  .replace(/\$\{esc\(title\)\}/g, "Ana &amp; Luis")
  .replace(/\$\{date \? `[^`]*` : ""\}/, '<p class="date">14 de noviembre de 2026</p>')
  .replace(/\$\{theme\}/g, "boda")
  .replace(/\$\{JSON\.stringify\(slug\)\}/g, JSON.stringify("demo2026"));

const seeds = [
  ["f1", 1400, 1800, 900],
  ["f2", 1500, 1100, 550],
  ["f3", 1200, 1600, 760],
  ["f4", 1600, 1200, 560],
  ["f5", 1300, 1900, 940],
  ["f6", 1400, 1400, 640],
  ["f7", 1500, 2000, 980],
  ["f8", 1600, 1000, 480],
  ["f9", 1200, 1500, 700],
  ["f10", 1400, 1750, 860],
  ["f11", 1500, 1200, 570],
  ["f12", 1300, 1700, 820],
];

const items = seeds.map(([seed, w, h], i) => ({
  name: `recuerdo-${seed}.jpg`,
  kind: "image",
  size: 2400000 + i * 130000,
  file: `https://picsum.photos/seed/analuis-${seed}/${w}/${h}`,
  thumb: `https://picsum.photos/seed/analuis-${seed}/${Math.round(w / 2)}/${Math.round(h / 2)}`,
}));

items.splice(3, 0, {
  name: "primer-baile.mp4",
  kind: "video",
  size: 18400000,
  file: "https://interactive-examples.mdn.mozilla.net/media/cc0-videos/flower.mp4",
  thumb: "https://picsum.photos/seed/analuis-video/700/900",
});

const mock = `<script>
window.__ALBUM_DEMO__ = ${JSON.stringify({ items })};
(function () {
  var realFetch = window.fetch;
  window.fetch = function (url, opts) {
    if (String(url).indexOf('/api/albums/public') === 0) {
      return Promise.resolve({
        ok: true,
        json: function () {
          return Promise.resolve({
            ok: true,
            album: { title: 'Ana & Luis', theme: 'boda', eventDate: '14 de noviembre de 2026' },
            items: window.__ALBUM_DEMO__.items
          });
        }
      });
    }
    return realFetch ? realFetch(url, opts) : Promise.reject(new Error('demo'));
  };
})();
</script>
`;

html = html.replace("<script>\n(function () {", mock + "<script>\n(function () {");

fs.writeFileSync(out, html, "utf8");
console.log("Vista previa escrita en " + out + " (" + html.length + " bytes)");
