// ==================================================================
// HARD STREET — Landing JavaScript (modo estricto: solo backend)
// Si la API no responde, se muestra un error con boton "Reintentar".
// ==================================================================

// ========== LOADER / ERROR ==========
function showLoader() {
  const loader = document.getElementById('loader');
  if (loader) loader.classList.remove('hidden');
}

function hideLoader() {
  const loader = document.getElementById('loader');
  if (loader) loader.classList.add('hidden');
}

// Estado de error: sin datos del backend no se renderiza nada
function showError(message) {
  const section = document.getElementById('packages');
  const grid = document.getElementById('packagesGrid');
  if (!grid) return;
  hideLoader();
  grid.innerHTML = `
    <div class="pkg-error-state" style="grid-column: 1 / -1; text-align:center; padding:4rem 1rem;">
      <h3 style="font-family:'Playfair Display',serif; font-size:1.5rem; margin-bottom:0.75rem;">No pudimos conectar con el servidor</h3>
      <p style="color:var(--text-muted); max-width:480px; margin:0 auto 1.5rem;">
        ${message || 'Verifica tu conexion e intenta de nuevo.'}
      </p>
      <button class="submit-btn" onclick="initLanding()" style="display:inline-flex; align-items:center; gap:0.5rem;">
        Reintentar
        <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" width="16" height="16"><path d="M23 4v6h-6M1 20v-6h6"/><path d="M3.51 9a9 9 0 0 1 14.85-3.36L23 10M1 14l4.64 4.36A9 9 0 0 0 20.49 15"/></svg>
      </button>
    </div>
  `;
  const carousel = document.getElementById('externCarousel');
  if (carousel) carousel.innerHTML = '';
  if (section) section.scrollIntoView({ behavior: 'smooth', block: 'start' });
}

// Error solo para "Lo que ofrecemos" (externos): deja el resto de la pagina funcionando
function showExternError(message) {
  const container = document.getElementById('externCarousel');
  if (!container) return;
  container.innerHTML = `
    <div class="extern-error-state" style="text-align:center; padding:3rem 1rem; border:1px solid rgba(255,255,255,0.08); border-radius:12px;">
      <h3 style="font-family:'Playfair Display',serif; font-size:1.4rem; margin-bottom:0.6rem;">No pudimos conectar con el servidor</h3>
      <p style="color:var(--text-muted); max-width:440px; margin:0 auto 1.25rem;">
        ${message || 'No se pudieron cargar los servicios externos.'}
      </p>
      <button class="submit-btn" onclick="loadExtern()" style="display:inline-flex; align-items:center; gap:0.5rem;">
        Reintentar
        <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" width="16" height="16"><path d="M23 4v6h-6M1 20v-6h6"/><path d="M3.51 9a9 9 0 0 1 14.85-3.36L23 10M1 14l4.64 4.36A9 9 0 0 0 20.49 15"/></svg>
      </button>
    </div>
  `;
  const dots = document.getElementById('externDots');
  if (dots) dots.innerHTML = '';
}

// ========== CUSTOM CURSOR ==========
const dot = document.getElementById('cursorDot');
const ring = document.getElementById('cursorRing');
let mouseX = 0, mouseY = 0, ringX = 0, ringY = 0;
document.addEventListener('mousemove', e => {
  mouseX = e.clientX; mouseY = e.clientY;
  dot.style.left = mouseX - 4 + 'px'; dot.style.top = mouseY - 4 + 'px';
});
function animateCursor() {
  ringX += (mouseX - ringX) * 0.15;
  ringY += (mouseY - ringY) * 0.15;
  ring.style.left = ringX - 20 + 'px'; ring.style.top = ringY - 20 + 'px';
  requestAnimationFrame(animateCursor);
}
animateCursor();
function bindCursorHover() {
  document.querySelectorAll('a, button, .gallery-item, .filter-btn, .service-card, .package-card').forEach(el => {
    el.removeEventListener('mouseenter', el._hsHoverIn || (() => {}));
    el.removeEventListener('mouseleave', el._hsHoverOut || (() => {}));
    el._hsHoverIn = () => ring.classList.add('hover');
    el._hsHoverOut = () => ring.classList.remove('hover');
    el.addEventListener('mouseenter', el._hsHoverIn);
    el.addEventListener('mouseleave', el._hsHoverOut);
  });
}
bindCursorHover();

// ========== NAVBAR ==========
const navbar = document.getElementById('navbar');
window.addEventListener('scroll', () => {
  navbar.classList.toggle('scrolled', window.scrollY > 50);
  document.getElementById('backToTop').classList.toggle('visible', window.scrollY > 500);
});

function toggleNav() {
  document.getElementById('navLinks').classList.toggle('open');
  document.getElementById('navToggle').classList.toggle('active');
}
function closeNav() {
  document.getElementById('navLinks').classList.remove('open');
  document.getElementById('navToggle').classList.remove('active');
}

// ========== SCROLL REVEAL ==========
const revealObserver = new IntersectionObserver((entries) => {
  entries.forEach(entry => {
    if (entry.isIntersecting) {
      entry.target.classList.add('active');
    }
  });
}, { threshold: 0.15, rootMargin: '0px 0px -50px 0px' });

function observeReveals() {
  document.querySelectorAll('.reveal:not(.active), .reveal-left:not(.active), .reveal-right:not(.active)').forEach(el => revealObserver.observe(el));
}
observeReveals();
// site.js los necesita cuando repinta la galería con las fotos del panel.
window.HSRevealObserver = revealObserver;

// ========== PARALLAX ==========
const parallaxBg = document.querySelector('[data-parallax]');
window.addEventListener('scroll', () => {
  if (!parallaxBg) return;
  const rect = parallaxBg.parentElement.getBoundingClientRect();
  if (rect.top < window.innerHeight && rect.bottom > 0) {
    const speed = 0.3;
    const yPos = (rect.top - window.innerHeight / 2) * speed;
    parallaxBg.style.transform = `translateY(${yPos}px)`;
  }
});

// ========== COUNTER ANIMATION ==========
// Los números (Proyectos / Años Exp. / Clientes Felices) los puede cambiar el
// panel: si eso pasa DESPUÉS de registrarlos, se vuelven a registrar (los
// bloques nuevos -clonados- no estarían observados).
const counterObserver = new IntersectionObserver((entries) => {
  entries.forEach(entry => {
    if (entry.isIntersecting) {
      const el = entry.target;
      const target = parseInt(el.getAttribute('data-count'));
      const duration = 2000;
      const step = target / (duration / 16);
      let current = 0;
      const timer = setInterval(() => {
        current += step;
        if (current >= target) { current = target; clearInterval(timer); }
        el.textContent = Math.floor(current) + '+';
      }, 16);
      counterObserver.unobserve(el);
    }
  });
}, { threshold: 0.5 });

function observeStats() {
  document.querySelectorAll('.stat-number').forEach(el => counterObserver.observe(el));
}
window.HSObserveStats = observeStats;

// ========== FOTOS EN DOS TIEMPOS (miniatura → original) ==========
// Las fotos del Drive (las que el panel elige) se piden dos veces: primero la
// miniatura que genera el mismo servidor del Drive (`/thumb/<ruta>?w=N`) y, ya
// que la original bajó, la original. Así la página se ve llena enseguida y las
// fotos van mejorando. El HTML lo arma el módulo del sitio (site.js); si no
// está cargado, la foto se pinta tal cual (la página nunca se queda sin foto).
function galleryImgTag(url, alt) {
  const clean = String(url == null ? '' : url).trim();
  if (!clean) return '';
  if (window.HSSite && typeof window.HSSite.galleryImg === 'function') {
    return window.HSSite.galleryImg(clean, alt);
  }
  const safeAlt = String(alt == null ? '' : alt).replace(/[<>]/g, '');
  return `<img src="${clean.replace(/["<>]/g, '')}" alt="${safeAlt}" loading="lazy" />`;
}

/** Engancha la foto buena a las que arrancaron con su miniatura. */
function scanProgressiveImages(root) {
  if (window.HSSite && typeof window.HSSite.scanImages === 'function') {
    window.HSSite.scanImages(root);
  }
}

// ========== GALERIA DESTACADA (desde la API: fotos publicas) ==========
// Cada foto trae su categoria (packages_categories). Los filtros se generan
// con las categorias que REALLY tienen fotos publicas.
function renderPublicGallery() {
  const grid = document.querySelector('.gallery-grid');
  const filtersWrap = document.querySelector('.gallery-filters');
  if (!grid || !filtersWrap) return;

  const fotos = Store.publicGallery;
  if (!fotos.length) return; // sin datos no renderiza nada (modo estricto)

  // Filtros: "Todos" + las categorias presentes en las fotos publicas
  const cats = [...new Set(fotos.map(f => f.categoryKey))];
  const catName = (key) => fotos.find(f => f.categoryKey === key)?.categoryName || key;
  filtersWrap.innerHTML = [
    `<button class="filter-btn active" data-filter="all">Todos</button>`,
    ...cats.map(k => `<button class="filter-btn" data-filter="${k}">${catName(k)}</button>`),
  ].join('');

  grid.innerHTML = fotos.map((foto, i) => `
    <div class="gallery-item ${i % 3 === 0 ? 'tall' : ''} reveal" data-category="${foto.categoryKey}">
      ${galleryImgTag(foto.url, foto.categoryName)}
      <div class="gallery-item-overlay">
        <h3>${foto.categoryName}</h3>
        <p>${foto.galleryType === 'video' ? 'Video' : 'Fotografía'}</p>
      </div>
      <div class="gallery-item-line"></div>
    </div>
  `).join('');
  // Las fotos que vengan del Drive mejoran solas (miniatura → original).
  scanProgressiveImages(grid);

  // Re-vincular filtros y reveals (el HTML se recreo)
  bindGalleryFilters();
  grid.querySelectorAll('.reveal').forEach(el => revealObserver.observe(el));
  bindCursorHover();
}

function bindGalleryFilters(root) {
  const scope = root && root.querySelectorAll ? root : document;
  scope.querySelectorAll('.filter-btn').forEach(btn => {
    // Un botón se engancha UNA vez: al repintar la galería los botones son
    // nuevos, así que se vuelven a llamar solos.
    if (btn.dataset.hsBound === '1') return;
    btn.dataset.hsBound = '1';
    btn.addEventListener('click', () => {
      // Se filtra la galería del botón: con varias galerías en la página, cada
      // una responde a sus propios filtros.
      const section = btn.closest('section') || scope;
      section.querySelectorAll('.filter-btn').forEach(b => b.classList.remove('active'));
      btn.classList.add('active');
      const filter = btn.getAttribute('data-filter');
      section.querySelectorAll('.gallery-item').forEach(item => {
        if (filter === 'all' || item.getAttribute('data-category') === filter) {
          item.style.opacity = '0'; item.style.transform = 'scale(0.8)';
          setTimeout(() => {
            item.style.display = 'block';
            requestAnimationFrame(() => {
              item.style.transition = 'opacity 0.5s ease, transform 0.5s ease';
              item.style.opacity = '1'; item.style.transform = 'scale(1)';
            });
          }, 100);
        } else {
          item.style.transition = 'opacity 0.3s ease, transform 0.3s ease';
          item.style.opacity = '0'; item.style.transform = 'scale(0.8)';
          setTimeout(() => { item.style.display = 'none'; }, 300);
        }
      });
    });
  });
}

// site.js lo usa cuando pinta la galería con las fotos elegidas en el panel.
window.HSBindGalleryFilters = bindGalleryFilters;

// Error solo para "Galeria Destacada": el resto de la pagina sigue funcionando
function showGalleryError(message) {
  const grid = document.querySelector('.gallery-grid');
  if (!grid) return;
  grid.innerHTML = `
    <div class="gallery-error-state" style="grid-column: 1 / -1; text-align:center; padding:3rem 1rem;">
      <h3 style="font-family:'Playfair Display',serif; font-size:1.4rem; margin-bottom:0.6rem;">No pudimos conectar con el servidor</h3>
      <p style="color:var(--text-muted); max-width:440px; margin:0 auto 1.25rem;">
        ${message || 'No se pudieron cargar las fotos.'}
      </p>
      <button class="submit-btn" onclick="loadGallery()" style="display:inline-flex; align-items:center; gap:0.5rem;">
        Reintentar
        <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" width="16" height="16"><path d="M23 4v6h-6M1 20v-6h6"/><path d="M3.51 9a9 9 0 0 1 14.85-3.36L23 10M1 14l4.64 4.36A9 9 0 0 0 20.49 15"/></svg>
      </button>
    </div>
  `;
  const filtersWrap = document.querySelector('.gallery-filters');
  if (filtersWrap) filtersWrap.innerHTML = '';
}

// Carga independiente de la galeria publica
async function loadGallery() {
  try {
    await Store.loadPublicGallery();
    renderPublicGallery();
  } catch (e) {
    console.error('[HardStreet] No se pudo cargar la galeria publica:', e.message);
    showGalleryError(e.message);
  }
}

// ========== TESTIMONIALS ==========
// Los comentarios pueden venir del panel (Sitio web → Testimonios): cuando
// llegan, site.js reescribe el carrusel y pide que se vuelva a enganchar.
// Por eso esto es una FUNCIÓN y no código de una sola pasada.
let currentTestimonial = 0;
let testimonials = [];
let testimonialDots = [];
let testimonialTimer = null;

function showTestimonial(index) {
  if (!testimonials.length) return;
  testimonials.forEach(t => t.classList.remove('active'));
  testimonialDots.forEach(d => d.classList.remove('active'));
  testimonials[index].classList.add('active');
  if (testimonialDots[index]) testimonialDots[index].classList.add('active');
  currentTestimonial = index;
}

function initTestimonials() {
  testimonials = [...document.querySelectorAll('.testimonial-item')];
  testimonialDots = [...document.querySelectorAll('#testimonialDots .dot')];
  testimonialDots.forEach(dot => {
    dot.addEventListener('click', () => showTestimonial(parseInt(dot.getAttribute('data-index'))));
  });
  if (testimonialTimer) clearInterval(testimonialTimer);
  if (testimonials.length) {
    testimonialTimer = setInterval(() => {
      showTestimonial((currentTestimonial + 1) % testimonials.length);
    }, 5000);
  }
}
window.HSInitTestimonials = initTestimonials;
initTestimonials();

// ========== PACKAGES (desde la API) ==========
const packagesContainer = document.getElementById('packagesGrid');
let currentCategory = 'all';

// Filtros de categorias generados desde la BD (packages_categories via /api/categories)
function renderCategoryFilters() {
  const wrap = document.getElementById('pkgFilters');
  if (!wrap || !Store.categories.length) return;
  const btn = (cat, label) => `<button class="pkg-filter-btn" data-category="${cat}">${label}</button>`;
  wrap.innerHTML = [
    `<button class="pkg-filter-btn active" data-category="all">Todos</button>`,
    ...Store.categories.map(c => btn(c.key, c.name)),
  ].join('');
  // Re-bind: los botones se recrearon
  bindPkgFilters();
}

function bindPkgFilters() {
  document.querySelectorAll('.pkg-filter-btn').forEach(btn => {
    btn.addEventListener('click', () => {
      document.querySelectorAll('.pkg-filter-btn').forEach(b => b.classList.remove('active'));
      btn.classList.add('active');
      currentCategory = btn.getAttribute('data-category');
      filterPackages();
    });
  });
}

// Los paquetes del catálogo (is_extern = 0), separados por su CATEGORÍA cuando
// el módulo del sitio lo pide (es lo que trae la página por defecto).
function renderAllPackages() {
  if (!packagesContainer) return;
  const plan = window.HS_SITE_CONTENT || (window.HSSite && window.HSSite.plan(null));
  const groups = window.HSSite
    ? window.HSSite.groupPackages(Store.packages, plan)
    : [{ key: '', name: '', packages: Store.packages.filter(p => !p.isExtern) }];
  const total = groups.reduce((n, g) => n + g.packages.length, 0);
  if (!total) return; // sin datos no renderiza nada (modo estricto)
  const grouped = groups.length > 1 || (groups[0] && groups[0].name);
  packagesContainer.classList.toggle('grouped', !!grouped);
  packagesContainer.innerHTML = groups.map(group => {
    const cards = group.packages.map(pkg => renderPackageCard(pkg)).join('');
    if (!grouped) return cards;
    return `
      <div class="pkg-group" data-group="${group.key}">
        <div class="pkg-group-head">
          <h3 class="pkg-group-title">${group.name || 'Paquetes'}</h3>
          <span class="pkg-group-line"></span>
          <span class="pkg-group-count">${group.packages.length} paquete${group.packages.length === 1 ? '' : 's'}</span>
        </div>
        <div class="packages-grid">${cards}</div>
      </div>`;
  }).join('');
  packagesContainer.querySelectorAll('.reveal').forEach(el => revealObserver.observe(el));
  bindCursorHover();
  filterPackages();
}

function filterPackages() {
  const cards = document.querySelectorAll('#packagesGrid .package-card');
  cards.forEach((card, index) => {
    const cat = card.getAttribute('data-category');
    const show = currentCategory === 'all' || cat === currentCategory;
    if (show) {
      card.style.display = 'block';
      card.style.animation = 'none';
      card.offsetHeight; // Trigger reflow
      // La entrada la manda el DISEÑO de las tarjetas (panel → sitio): así
      // filtrar por categoría se ve igual que cargar la página.
      const anim = window.HSSite && window.HSSite.cardAnim
        ? window.HSSite.cardAnim(index + 1)
        : { animation: 'pkgFadeIn 0.5s ease forwards', delay: `${index * 0.05}s` };
      card.style.animation = anim.animation;
      card.style.animationDelay = anim.delay;
    } else {
      // Sin retardo: el retardo escalonado de la entrada no debe retrasar la
      // salida de las que se van.
      card.style.animationDelay = '0ms';
      card.style.animation = 'pkgFadeOut 0.3s ease forwards';
      setTimeout(() => { card.style.display = 'none'; }, 300);
    }
  });
  // Al agrupar por categoría, el grupo se va con sus tarjetas: sin esto
  // quedaría un título de categoría sin nada debajo.
  document.querySelectorAll('#packagesGrid .pkg-group').forEach(group => {
    const any = [...group.querySelectorAll('.package-card')].some(card =>
      currentCategory === 'all' || card.getAttribute('data-category') === currentCategory
    );
    setTimeout(() => { group.style.display = any ? '' : 'none'; }, any ? 0 : 300);
  });
}

// Bind inicial de los botones estaticos del HTML; cuando lleguen las
// categorias de la BD, renderCategoryFilters() los recrea y re-vincula.
bindPkgFilters();


// ========== EXTERN SERVICES CAROUSEL ("Lo que ofrecemos") ==========
// La imagen de cada slide viene de packages.url_image (BD) via imageForPackage()
let currentExternSlide = 0;

function renderExternCarousel() {
  const container = document.getElementById('externCarousel');
  const dotsContainer = document.getElementById('externDots');
  if (!container || !dotsContainer) return;

  // "Nuestros servicios" = paquetes con is_extern = 1, desde su endpoint /api/extern-services
  const services = Store.externServices;
  if (!services.length) return; // sin datos no renderiza nada (modo estricto)

  container.innerHTML = services.map((service, index) => `
    <div class="extern-slide ${index === 0 ? 'active' : ''}">
      <div class="extern-slide-media">
        <div class="extern-slide-image">
          ${galleryImgTag(imageForPackage(service, index), service.name)}
        </div>
        <div class="extern-slide-medal">${service.categoryIcon}</div>
      </div>
      <div class="extern-slide-content">
        <p class="extern-slide-subtitle">${service.subtitle}</p>
        <h3 class="extern-slide-title">${service.name}</h3>
        <p class="extern-slide-desc">${service.description}</p>
        <ul class="extern-slide-features">
          ${service.services.slice(0, 4).map(s => `<li><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><polyline points="20 6 9 17 4 12"/></svg>${s.name}</li>`).join('')}
        </ul>
        <div class="extern-slide-actions">
          <div class="extern-slide-price">
            <span class="extern-slide-price-label">Inversión</span>
            <span class="extern-slide-price-value">Desde ${service.priceFormatted}</span>
          </div>
          <a class="extern-slide-cta" href="#contact">
            Consultar
            <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M5 12h14M12 5l7 7-7 7"/></svg>
          </a>
        </div>
      </div>
    </div>
  `).join('');

  dotsContainer.innerHTML = services.map((_, index) => `
    <span class="extern-dot ${index === 0 ? 'active' : ''}" onclick="goToExternSlide(${index})"></span>
  `).join('');

  // Las imágenes del panel que vengan del Drive (url_image) también mejoran
  // solas: miniatura primero, original después.
  scanProgressiveImages(container);

  const counter = document.getElementById('externCounter');
  if (counter) counter.innerHTML = `<span>01</span> / ${String(services.length).padStart(2, '0')}`;
}

function showExternSlide(index) {
  const slides = document.querySelectorAll('.extern-slide');
  const dotsEls = document.querySelectorAll('.extern-dot');
  if (!slides.length) return;
  slides.forEach(s => s.classList.remove('active'));
  dotsEls.forEach(d => d.classList.remove('active'));
  slides[index].classList.add('active');
  if (dotsEls[index]) dotsEls[index].classList.add('active');
  const counter = document.getElementById('externCounter');
  if (counter) counter.innerHTML = `<span>${String(index + 1).padStart(2, '0')}</span> / ${String(slides.length).padStart(2, '0')}`;
  currentExternSlide = index;
}

function nextExternSlide() {
  const total = document.querySelectorAll('.extern-slide').length;
  if (!total) return;
  showExternSlide((currentExternSlide + 1) % total);
}
function prevExternSlide() {
  const total = document.querySelectorAll('.extern-slide').length;
  if (!total) return;
  showExternSlide((currentExternSlide - 1 + total) % total);
}
function goToExternSlide(index) { showExternSlide(index); }

// Auto-advance carousel (solo si hay slides)
setInterval(() => {
  if (document.querySelectorAll('.extern-slide').length > 1) nextExternSlide();
}, 6000);

// Swipe tactil en el carrusel de servicios (movil)
(() => {
  const carousel = document.querySelector('.extern-carousel');
  if (!carousel) return;
  let startX = null;
  carousel.addEventListener('touchstart', (e) => { startX = e.touches[0].clientX; }, { passive: true });
  carousel.addEventListener('touchend', (e) => {
    if (startX === null) return;
    const dx = e.changedTouches[0].clientX - startX;
    if (Math.abs(dx) > 50) (dx < 0 ? nextExternSlide() : prevExternSlide());
    startX = null;
  }, { passive: true });
})();

// Carga independiente de los externos: si falla, muestra el error SOLO en esta seccion
async function loadExtern() {
  try {
    await Store.loadExternServices();
    renderExternCarousel();
  } catch (e) {
    console.error('[HardStreet] No se pudieron cargar los servicios externos:', e.message);
    showExternError(e.message);
  }
}

// ========== MODAL SYSTEM ==========
function openModal(modalId) {
  document.getElementById(modalId).classList.add('active');
  document.body.style.overflow = 'hidden';
}
function closeModal(modalId) {
  document.getElementById(modalId).classList.remove('active');
  document.body.style.overflow = '';
}
document.querySelectorAll('.modal-overlay').forEach(overlay => {
  overlay.addEventListener('click', (e) => {
    if (e.target === overlay) {
      overlay.classList.remove('active');
      document.body.style.overflow = '';
    }
  });
});

// ========== LOGIN (real via API) ==========
function showLoginError(message) {
  const form = document.querySelector('#loginModal form');
  if (!form) return;
  let el = document.getElementById('loginError');
  if (!el) {
    el = document.createElement('p');
    el.id = 'loginError';
    el.style.cssText = 'color:#e05a5a; font-size:0.85rem; margin:0.5rem 0 0; text-align:center;';
    form.appendChild(el);
  }
  el.textContent = message;
}

async function handleLogin(e) {
  e.preventDefault();
  const email = document.getElementById('loginEmail').value;
  const password = document.getElementById('loginPassword').value;
  const btn = e.target.querySelector('.submit-btn');
  const original = btn.innerHTML;
  btn.innerHTML = 'Verificando...';
  btn.disabled = true;

  try {
    await Store.login(email, password);
    // Al entrar, se va a la APP (el panel en /me/), igual que el botón del menú.
    window.location.href = APP_DIR;
  } catch (err) {
    const msg = err.status === 401
      ? 'Correo o contraseña incorrectos'
      : (err.message || 'No se pudo conectar con el servidor');
    showLoginError(msg);
    btn.innerHTML = original;
    btn.disabled = false;
  }
  return false;
}

/**
 * Directorio de la APLICACIÓN (el panel, compilado como web en /me/).
 *
 * "Iniciar Sesión" NO abre un formulario en la página: entra a la app, que ya
 * tiene su propio acceso. Así hay un solo lugar donde se inicia sesión y no dos
 * que se puedan desincronizar.
 */
const APP_DIR = '/me/';

function handleLogout() {
  Store.logout();
  updateAuthUI();
}

function updateAuthUI() {
  const authBtn = document.getElementById('authBtn');
  if (!authBtn) return;
  if (Store.user) {
    authBtn.textContent = 'Mi Paquete';
    authBtn.setAttribute('href', 'gallery/home/');
  } else {
    authBtn.textContent = 'Iniciar Sesión';
    // Entrar = ir al directorio de la APP.
    authBtn.setAttribute('href', APP_DIR);
  }
}

// ========== FORM ==========
function handleSubmit(e) {
  e.preventDefault();
  const btn = e.target.querySelector('.submit-btn');
  const original = btn.innerHTML;
  btn.innerHTML = '✓ Mensaje Enviado';
  btn.style.background = '#c9a96e'; btn.style.color = '#0a0a0a';
  setTimeout(() => { btn.innerHTML = original; btn.style.background = ''; btn.style.color = ''; e.target.reset(); }, 2500);
}

// ========== SMOOTH ANCHOR SCROLLING ==========
document.querySelectorAll('a[href^="#"]').forEach(anchor => {
  anchor.addEventListener('click', function(e) {
    const href = this.getAttribute('href');
    if (!href || href === '#' || href.length < 2) return;
    e.preventDefault();
    const target = document.querySelector(href);
    if (target) target.scrollIntoView({ behavior: 'smooth', block: 'start' });
  });
});

// ========== INIT: todo viene del backend ==========
async function initLanding() {
  showLoader();
  updateAuthUI();

  // Los contadores no dependen de la API: se registran siempre
  observeStats();

  // Catalogo + filtros (packages_grid). Si falla, error global con Reintentar.
  try {
    // El DISEÑO del sitio (lo que se edita en el panel) se aplica ANTES de
    // pintar las tarjetas: así aparecen ya con el diseño elegido, sin un
    // parpadeo con el look viejo.
    if (window.HSSite) await window.HSSite.load();
    await Store.loadCatalog();
    renderCategoryFilters();
    renderAllPackages();
    // Recorta los servicios al tope del diseño ("+N más…").
    if (window.HSSite) window.HSSite.trimServices(document);
  } catch (e) {
    console.error('[HardStreet] El backend no respondio:', e.message);
    showError(e.message);
  }

  // Secciones independientes: el error de una no tira las demas.
  //
  // La galería ya puede venir pintada por site.js si el panel eligió fotos POR
  // CATEGORÍA: en ese caso no se pisan las públicas.
  const customGallery = !!(window.HS_SITE_CONTENT && window.HS_SITE_CONTENT.gallery.custom);
  if (!customGallery) await loadGallery();
  await loadExtern();
  // Los comentarios del panel se engancharon al repintar el carrusel: se
  // vuelve a llamar por si llegaron DESPUÉS de la primera pasada.
  initTestimonials();

  hideLoader();
}

initLanding();
