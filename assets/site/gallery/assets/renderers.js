// ==================================================================
// HARD STREET — Renderers (HTML desde los modelos nuevos)
// ==================================================================

// Pool de imagenes para el carousel de servicios externos.
// Prioridad: packages.url_image de la BD; si viene vacio, pool local.
// (solo archivos que existen en images/)
const ExternImagesPool = [
  'images/boungle.jpg',
  'images/review.jpg',
  'images/banner.jpg',
  'images/banner1.jpg',
  'images/after_p.jpg',
  'images/before_p.jpg',
];

function imageForPackage(pkg, idx = 0) {
  if (pkg.urlImage) return pkg.urlImage;
  return ExternImagesPool[pkg.id % ExternImagesPool.length] || ExternImagesPool[idx % ExternImagesPool.length];
}

// ========== TEXTOS DEL DISEÑO (los edita el panel) ==========
// El diseñador de tarjetas del panel puede cambiar estos rótulos; si no hay
// diseño cargado, se usan los de siempre.
function designCard() {
  const d = window.HS_SITE_DESIGN;
  return (d && d.card) || {};
}
function designPriceLabel() {
  return designCard().priceLabel || 'Desde';
}
function designCtaLabel() {
  return designCard().ctaLabel || 'Cotizar';
}

/**
 * FOTO del paquete dentro de su tarjeta, si el diseño la pide.
 *
 *   'top' → banda arriba (el alto lo fija el CSS con `imageHeight`)
 *   'bg'  → de fondo: la foto se ve y encima va el degradado del CSS, con el
 *           color de la tarjeta y la fuerza de `imageFade`
 *   'fade'→ fondo con degradado de desaparición: la foto se funde con el color
 *           (o el degradado) de fondo de la tarjeta
 *
 * La foto es la del paquete (`url_image`) y, si no tiene, una del pool: es la
 * misma que ya usan los carruseles, así que no hay otra fuente que mantener.
 */
function designImageMode() {
  const mode = String(designCard().imageMode || 'none');
  return mode === 'top' || mode === 'bg' || mode === 'fade' ? mode : 'none';
}

/**
 * La foto de un paquete, ya lista para meter en la tarjeta.
 *
 * Es SOLO la foto del paquete (`url_image`). Si no tiene, la tarjeta se ve
 * limpia, igual que la del panel: antes se ponía una del pool del sitio y la
 * misma tarjeta cambiaba de foto sin que nadie la hubiera elegido.
 */
function packagePhotoUrl(pkg) {
  return String((pkg && pkg.urlImage) || '').replace(/"/g, '&quot;');
}

/** HTML de la foto del paquete según dónde la ponga el diseño. */
function packagePhotoHtml(mode, url) {
  if (mode !== 'top' && mode !== 'bg' && mode !== 'fade') return '';
  if (mode === 'top') {
    return url ? `<img class="pkg-photo" src="${url}" alt="" loading="lazy">` : '';
  }
  // De FONDO la capa va SIEMPRE: la foto si el paquete tiene, y si no el
  // degradado del diseño (`pkg-photo-empty`), que es el mismo hueco que enseña
  // el diseñador. Así una tarjeta sin foto no se ve como un bloque plano.
  return url
    ? `<div class="pkg-photo-bg" style="background-image:url('${url}')" aria-hidden="true"></div>`
    : '<div class="pkg-photo-bg pkg-photo-empty" aria-hidden="true"></div>';
}

function designCardPhoto(pkg) {
  return packagePhotoHtml(designImageMode(), packagePhotoUrl(pkg));
}

/**
 * Pone —o quita— la foto de las tarjetas YA PINTADAS.
 *
 * El diseño lo aplica `site.js` cuando responde la API y las tarjetas se pintan
 * cuando responde la suya: si la tarjeta se pintó antes de saber el diseño, se
 * corrige aquí (igual que los textos del precio). Es IDEMPOTENTE: repetirla no
 * duplica la foto ni la vuelve a pedir si ya está la correcta.
 *
 * La foto se recuerda en la tarjeta (`data-hs-photo`), así que no hace falta
 * volver a tener el paquete delante.
 */
function refreshPackagePhotos(root) {
  const mode = designImageMode();
  (root || document).querySelectorAll('.package-card').forEach((card) => {
    const url = card.dataset.hsPhoto || '';
    const html = packagePhotoHtml(mode, url);
    const current = card.querySelector('.pkg-photo, .pkg-photo-bg');
    // Ojo: en modo 'bg' la capa existe con foto y sin ella, así que no basta
    // con comparar "bg": hay que ver si la que está es la del hueco y si toca
    // cambiarla por la foto (el paquete pudo ganar su foto después).
    const want = html.includes('pkg-photo-empty')
      ? 'bg-empty'
      : html.includes('pkg-photo-bg')
        ? 'bg-photo'
        : html ? 'top' : 'none';
    const has = current
      ? (current.classList.contains('pkg-photo')
          ? 'top'
          : current.classList.contains('pkg-photo-empty')
            ? 'bg-empty'
            : 'bg-photo')
      : 'none';
    if (want === has) return; // ya está como el diseño pide
    if (current) current.remove();
    if (html) card.insertAdjacentHTML('afterbegin', html);
  });
}

// ========== CARD DE PAQUETE (landing) ==========
//
// El orden de las piezas es el MISMO que el de la tarjeta del panel
// (`WebPackageCard`): foto → badge del tier (EN FLUJO, arriba a la izquierda) →
// categoría → nombre → subtítulo → descripción → línea → cuántos servicios →
// lista → pie con precio y botón. Así las dos tarjetas son la misma tarjeta.
// Check con el que el PANEL marca cada servicio incluido (15 px). Es el
// MISMO símbolo en la web y en la tarjeta del admin; antes la web dibujaba
// el icono propio de cada servicio y las dos tarjetas no se parecían.
const PkgCheckSvg =
  '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" ' +
  'stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round" ' +
  'width="14" height="14"><path d="M20 6 9 17l-5-5"/></svg>';

function renderPackageCard(pkg) {
  const serviciosHTML = pkg.services.map(s =>
    `<li>
      <span class="pkg-icon-svg">${PkgCheckSvg}</span>
      <span class="pkg-service-text">${s.name}</span>
    </li>`
  ).join('');

  return `
    <div class="package-card tier-${pkg.tier.key} cat-${pkg.categoryKey} reveal" data-category="${pkg.categoryKey}" data-hs-photo="${packagePhotoUrl(pkg)}">
      ${designCardPhoto(pkg)}
      <div class="pkg-flyer-inner">
        <div class="pkg-tier-badge tier-${pkg.tier.key}">${pkg.tierLabel}</div>
        <div class="pkg-category">
          <span class="pkg-category-icon">${pkg.categoryIcon}</span>
          <span class="pkg-category-name">${pkg.packageCategory.name}</span>
        </div>
        <div class="pkg-header">
          <h3 class="pkg-name">${pkg.name}</h3>
          <p class="pkg-subtitle">${pkg.subtitle}</p>
          ${pkg.description ? `<p class="pkg-description">${pkg.description}</p>` : ''}
        </div>
        <div class="pkg-divider"></div>
        <div class="pkg-services-header">
          <span class="pkg-services-count">${pkg.services.length} servicios incluidos</span>
        </div>
        <ul class="pkg-services">${serviciosHTML}</ul>
        <div class="pkg-footer">
          <div class="pkg-price">
            <span class="pkg-price-label">${designPriceLabel()}</span>
            <span class="pkg-price-value">${pkg.priceFormatted}</span>
          </div>
          <a href="#contact" class="pkg-cta">
            <span>${designCtaLabel()}</span>
          </a>
        </div>
      </div>
    </div>
  `;
}

// ========== CARD DE PAQUETE (dashboard, compatibilidad) ==========
function renderPackageCardDashboard(pkg, showServices = true) {
  const serviciosHTML = showServices
    ? pkg.services.map(s =>
        `<li><span class="pkg-icon-svg">${s.iconSvg}</span><span class="pkg-service-text">${s.name}</span></li>`
      ).join('')
    : '';

  return `
    <div class="package-card tier-${pkg.tier.key} cat-${pkg.categoryKey}" data-category="${pkg.categoryKey}" data-hs-photo="${packagePhotoUrl(pkg)}">
      ${designCardPhoto(pkg)}
      <div class="pkg-flyer-inner">
        <div class="pkg-tier-badge tier-${pkg.tier.key}">${pkg.tierLabel}</div>
        <div class="pkg-category">
          <span class="pkg-category-icon">${pkg.categoryIcon}</span>
          <span class="pkg-category-name">${pkg.packageCategory.name}</span>
        </div>
        <div class="pkg-header">
          <h3 class="pkg-name">${pkg.name}</h3>
          <p class="pkg-subtitle">${pkg.subtitle}</p>
        </div>
        <div class="pkg-divider"></div>
        <div class="pkg-services-header">
          <span class="pkg-services-count">${pkg.services.length} servicios incluidos</span>
        </div>
        ${showServices ? `<ul class="pkg-services">${serviciosHTML}</ul>` : ''}
        <div class="pkg-footer">
          <div class="pkg-price">
            <span class="pkg-price-label">Precio</span>
            <span class="pkg-price-value">${pkg.priceFormatted}</span>
            <span class="pkg-price-note">${pkg.currency}</span>
          </div>
        </div>
      </div>
    </div>
  `;
}
