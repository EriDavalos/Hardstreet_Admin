// ==================================================================
// HARD STREET — Dashboard Core (shared by gallery/* modules)
// Cada página (gallery/home, gallery/package, gallery/photos) define
// window.DASHBOARD_MODULE y este core inicializa solo lo necesario.
// Datos REALES desde la API (backend/). Modo estricto: si no hay
// sesion redirige al login y si el backend falla muestra un error
// con reintentar — nunca datos demo.
// ==================================================================

const DASHBOARD_MODULE = window.DASHBOARD_MODULE || 'home';

// ========== BOOT: autenticacion obligatoria ==========
(async () => {
  try {
    await Store.loadUserData();
    init();
  } catch (e) {
    if (e && e.status === 401) {
      // Sin sesion -> de vuelta al landing (abre el modal de login ahi)
      window.location.href = '../../index.html';
      return;
    }
    showDashboardError(e);
  }
})();

// Error fatal (backend caido / BD caida): pantalla completa con reintentar
function showDashboardError(err) {
  document.body.innerHTML = `
    <div style="min-height:100vh; display:flex; align-items:center; justify-content:center; background:#0a0a0a; color:#fff; font-family:Inter,sans-serif; padding:1.5rem;">
      <div style="max-width:480px; text-align:center;">
        <h1 style="font-family:'Playfair Display',serif; font-size:1.8rem; margin-bottom:0.75rem;">No pudimos conectar con el servidor</h1>
        <p style="color:rgba(255,255,255,0.6); margin-bottom:1.75rem; line-height:1.6;">
          ${err && err.message ? err.message : 'Verifica tu conexion e intenta de nuevo.'}
        </p>
        <div style="display:flex; gap:0.75rem; justify-content:center; flex-wrap:wrap;">
          <button onclick="window.location.reload()" style="padding:0.75rem 1.75rem; background:linear-gradient(135deg,#c9a96e,#f0d48a); color:#0a0a0a; border:none; border-radius:4px; font-weight:600; cursor:pointer;">
            Reintentar
          </button>
          <a href="index.html" style="padding:0.75rem 1.75rem; border:1px solid rgba(255,255,255,0.25); color:#fff; text-decoration:none; border-radius:4px;">
            Volver al inicio
          </a>
        </div>
      </div>
    </div>
  `;
}

// ========== DASHBOARD-SPECIFIC ICONS ==========
const icons = {
  home: `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5"><path d="M3 9l9-7 9 7v11a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2z"/><polyline points="9 22 9 12 15 12 15 22"/></svg>`,
  box: `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5"><path d="M21 16V8a2 2 0 0 0-1-1.73l-7-4a2 2 0 0 0-2 0l-7 4A2 2 0 0 0 3 8v8a2 2 0 0 0 1 1.73l7 4a2 2 0 0 0 2 0l7-4A2 2 0 0 0 21 16z"/><polyline points="3.27 6.96 12 12.01 20.73 6.96"/><line x1="12" y1="22.08" x2="12" y2="12"/></svg>`,
  grid: `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5"><rect x="3" y="3" width="7" height="7"/><rect x="14" y="3" width="7" height="7"/><rect x="14" y="14" width="7" height="7"/><rect x="3" y="14" width="7" height="7"/></svg>`,
  download: `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4"/><polyline points="7 10 12 15 17 10"/><line x1="12" y1="15" x2="12" y2="3"/></svg>`,
  logout: `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5"><path d="M9 21H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h4"/><polyline points="16 17 21 12 16 7"/><line x1="21" y1="12" x2="9" y2="12"/></svg>`,
  menu: `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><line x1="3" y1="12" x2="21" y2="12"/><line x1="3" y1="6" x2="21" y2="6"/><line x1="3" y1="18" x2="21" y2="18"/></svg>`,
  check: `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><polyline points="20 6 9 17 4 12"/></svg>`,
  clock: `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5"><circle cx="12" cy="12" r="10"/><polyline points="12 6 12 12 16 14"/></svg>`,
  checkCircle: `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5"><path d="M22 11.08V12a10 10 0 1 1-5.93-9.14"/><polyline points="22 4 12 14.01 9 11.01"/></svg>`,
  star: `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5"><polygon points="12 2 15.09 8.26 22 9.27 17 14.14 18.18 21.02 12 17.77 5.82 21.02 7 14.14 2 9.27 8.91 8.26 12 2"/></svg>`,
};

// ========== USER STATE ==========
let selectedPhotos = new Set();
let currentFilter = 'all';
let previewPhoto = null;
let currentPkg = null; // PurchasedPackage activo

// ========== INITIALIZATION ==========
document.addEventListener('DOMContentLoaded', async () => {
  // Store.loadUserData() ya corre en el boot de arriba; init() se llama
  // ahi mismo cuando los datos estan listos.
});

// ========== INIT ==========
function init() {
  updateUserInfo();
  // Paquete activo: el mas reciente que no este entregado/cancelado; si no, el ultimo
  const active = Store.purchasedPackages.find(p => !['entregado', 'cancelado'].includes(p.status.key));
  currentPkg = active || Store.purchasedPackages[0] || null;
  // Cada modulo renderiza solo su parte (los containers no presentes se omiten)
  if (document.getElementById('overviewPackage')) renderOverview();
  if (document.getElementById('packageDetail')) renderPackageDetail();
  if (document.getElementById('photosGrid')) renderPhotos();
  setupTabs();
  setupFilters();
}

// ========== UPDATE USER INFO ==========
function updateUserInfo() {
  const u = Store.user;
  if (!u) return;
  document.getElementById('userName').textContent = u.fullName;
  document.getElementById('userEmail').textContent = u.email;
  document.getElementById('userAvatar').textContent = u.initials;
  document.getElementById('mobileUser').textContent = u.initials;
  const ovName = document.getElementById('ovUserName');
  if (ovName) ovName.textContent = u.name;
}

// ========== RENDER OVERVIEW ==========
function renderOverview() {
  const pkg = currentPkg;
  const gallery = Store.gallery.filter(g => g.isImage);
  const readyPhotos = gallery.length;
  const totalServices = pkg ? pkg.totalCount : 0;
  const completedCount = pkg ? pkg.completedCount : 0;
  const catIcon = pkg ? pkg.categoryIcon : '';
  const tierLabel = pkg ? pkg.tierLabel : '';
  const progress = pkg ? pkg.progressPercent : 0;

  // Overview stats
  document.getElementById('statPackage').textContent = pkg ? (pkg.name.split(' - ')[0] || pkg.name) : '-';
  document.getElementById('statPhotos').textContent = Store.gallery.length;
  document.getElementById('statReady').textContent = readyPhotos;
  document.getElementById('statProgress').textContent = `${progress}%`;

  // Render active package card in overview
  const overviewPkg = document.getElementById('overviewPackage');
  if (overviewPkg && pkg) {
    overviewPkg.innerHTML = `
      <div class="ov-pkg-hero tier-${pkg.tier.key}">
        <div class="ov-pkg-glow"></div>
        <div class="ov-pkg-content">
          <div class="ov-pkg-left">
            <div class="ov-pkg-badge">${tierLabel}</div>
            <div class="ov-pkg-cat">
              <span class="ov-pkg-cat-icon">${catIcon}</span>
              <span>${pkg.package.name}</span>
            </div>
            <h3 class="ov-pkg-name">${pkg.name}</h3>
            <p class="ov-pkg-price">${pkg.priceFormatted} <span>${pkg.currency}</span></p>
          </div>
          <div class="ov-pkg-right">
            <div class="ov-pkg-mini-stats">
              <div class="ov-mini-stat">
                <span class="ov-mini-value">${completedCount}/${totalServices}</span>
                <span class="ov-mini-label">Servicios</span>
              </div>
              <div class="ov-mini-stat">
                <span class="ov-mini-value">${readyPhotos}</span>
                <span class="ov-mini-label">Fotos</span>
              </div>
              <div class="ov-mini-stat">
                <span class="ov-mini-value">${pkg.paidFormatted.replace('$', '$')}</span>
                <span class="ov-mini-label">Pagado</span>
              </div>
            </div>
            <button class="ov-pkg-cta" onclick="document.querySelector('.sidebar-item[data-tab=package]').click()">
              Ver Detalles
              <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" width="14" height="14"><path d="M5 12h14M12 5l7 7-7 7"/></svg>
            </button>
          </div>
        </div>
      </div>
    `;
  } else if (overviewPkg) {
    overviewPkg.innerHTML = `
      <div class="ov-pkg-hero">
        <div class="ov-pkg-content">
          <div class="ov-pkg-left">
            <h3 class="ov-pkg-name">Sin paquete activo</h3>
            <p class="ov-pkg-price">Contacta al estudio para contratar tu paquete</p>
          </div>
        </div>
      </div>
    `;
  }

  renderActivity();
}

// ========== RENDER ACTIVITY ==========
function renderActivity() {
  const container = document.getElementById('activityList');
  if (!container) return;

  // Actividad generada de los datos reales de la BD
  const actividad = [];
  if (currentPkg) {
    actividad.push({ tipo: 'package', texto: `Paquete: ${currentPkg.name} — ${currentPkg.status.name}`, tiempo: 'Estado actual' });
    actividad.push({ tipo: 'progress', texto: `Pago registrados: ${currentPkg.paidFormatted} de ${currentPkg.priceFormatted}`, tiempo: 'Pagos' });
    const inProgress = currentPkg.services.find(s => s.inProgress);
    if (inProgress) {
      actividad.push({ tipo: 'progress', texto: `${inProgress.name}: ${inProgress.description || 'En proceso'}`, tiempo: inProgress.status.name });
    }
  }
  const photos = Store.gallery.length;
  if (photos > 0) {
    actividad.push({ tipo: 'photo', texto: `${photos} elemento(s) disponibles en tu galería`, tiempo: 'Galería' });
  }
  if (actividad.length === 0) {
    actividad.push({ tipo: 'package', texto: 'Bienvenido a Hard Street', tiempo: 'Hoy' });
  }

  const activityConfig = {
    photo: { icon: ServiceIcons.photos, class: 'blue' },
    progress: { icon: icons.clock, class: 'gold' },
    package: { icon: ServiceIcons.product, class: 'green' },
  };

  container.innerHTML = actividad.map(item => {
    const config = activityConfig[item.tipo] || activityConfig.package;
    return `
      <div class="activity-item">
        <div class="activity-icon ${config.class}">${config.icon}</div>
        <div class="activity-content">
          <div class="activity-text">${item.texto}</div>
          <div class="activity-time">${item.tiempo}</div>
        </div>
      </div>
    `;
  }).join('');
}

// ========== RENDER PACKAGE DETAIL ==========
function renderPackageDetail() {
  const container = document.getElementById('packageDetail');
  if (!container) return;

  if (!currentPkg) {
    container.innerHTML = `
      <div class="pkg-section">
        <div class="pkg-section-header">
          <div class="pkg-section-title">${icons.box}<h3>Sin paquetes contratados</h3></div>
        </div>
        <div class="delivery-timeline">
          <p style="color:var(--text-muted)">Cuando contrates un paquete, aquí verás el estado de entrega de cada servicio.</p>
        </div>
      </div>
    `;
    return;
  }

  const pkg = currentPkg;
  const completedCount = pkg.completedCount;
  const totalServices = pkg.totalCount;
  const progressPercent = pkg.progressPercent;
  const catIcon = pkg.categoryIcon;
  const tierLabel = pkg.tierLabel;

  // Otros paquetes comprados por el usuario (excluyendo el activo)
  const otherPackages = Store.purchasedPackages.filter(p => p.id !== pkg.id).slice(0, 3);

  container.innerHTML = `
    <!-- Package Hero -->
    <div class="pkg-hero tier-${pkg.tier.key}">
      <div class="pkg-hero-bg"></div>
      <div class="pkg-hero-content">
        <span class="pkg-tier-badge">${tierLabel}</span>
        <div class="pkg-hero-category">
          <span class="pkg-category-icon">${catIcon}</span>
          <span>${pkg.package.packageCategory.name}</span>
        </div>
        <h2 class="pkg-hero-name">${pkg.name}</h2>
        <p class="pkg-hero-subtitle">${pkg.subtitle}</p>
        <div class="pkg-hero-bottom">
          <div class="pkg-hero-price">
            <span class="pkg-hero-price-label">Inversión</span>
            <span class="pkg-hero-price-value">${pkg.priceFormatted}</span>
            <span class="pkg-hero-price-note">${pkg.currency}</span>
          </div>
          <div class="pkg-hero-progress-pill">
            <span>${progressPercent}% completado</span>
            <div class="pkg-hero-mini-bar"><div class="pkg-hero-mini-fill" style="width:${progressPercent}%"></div></div>
          </div>
        </div>
      </div>
    </div>

    <!-- Service Delivery Timeline -->
    <div class="pkg-section">
      <div class="pkg-section-header">
        <div class="pkg-section-title">
          ${icons.checkCircle}
          <h3>Estado de Entrega</h3>
        </div>
        <div class="pkg-section-stats">
          <span class="stat-pill done">${completedCount} Entregados</span>
          <span class="stat-pill active">${totalServices - completedCount} Pendientes</span>
        </div>
      </div>
      <div class="delivery-timeline">
        ${pkg.services.map((svc, index) => {
          const isDone = svc.isDone;
          const isActive = svc.inProgress;
          const statusClass = isDone ? 'done' : isActive ? 'active' : 'pending';
          const statusLabel = svc.status.name;
          const delivery = svc.deliveryDate !== null && svc.deliveryDate !== undefined
            ? `${svc.deliveryDate} día(s) de entrega`
            : '';

          return `
            <div class="timeline-item ${statusClass}" style="animation-delay: ${index * 0.08}s">
              <div class="timeline-connector">
                <div class="timeline-dot">
                  ${isDone ? icons.check : isActive ? icons.clock : '<span class="dot-inner"></span>'}
                </div>
                ${index < totalServices - 1 ? '<div class="timeline-line"></div>' : ''}
              </div>
              <div class="timeline-card">
                <div class="timeline-card-header">
                  <div class="timeline-service-icon">${svc.iconSvg}</div>
                  <div class="timeline-service-info">
                    <h4>${svc.name}</h4>
                    <p>${svc.serviceDescription}</p>
                  </div>
                  <span class="timeline-status-badge ${statusClass}">${statusLabel}</span>
                </div>
                ${(svc.description || delivery) ? `<div class="timeline-delivery-info">
                  ${delivery ? `<div class="delivery-date">
                    ${icons.clock}
                    <span>${delivery}</span>
                  </div>` : ''}
                  ${svc.description ? `<p class="delivery-notes">${svc.description}</p>` : ''}
                </div>` : ''}
              </div>
            </div>
          `;
        }).join('')}
      </div>
    </div>

    <!-- Otros paquetes comprados -->
    ${otherPackages.length ? `
    <div class="pkg-section">
      <div class="pkg-section-header">
        <div class="pkg-section-title">
          ${icons.box}
          <h3>Paquetes anteriormente elegidos</h3>
        </div>
      </div>
      <div class="past-packages-grid">
        ${otherPackages.map(p => {
          const pProgress = p.progressPercent;
          return `
            <div class="past-pkg-card tier-${p.tier.key}">
              <div class="past-pkg-badge">${p.tierLabel}</div>
              <div class="past-pkg-top">
                <div class="past-pkg-category">
                  <span class="past-pkg-cat-icon">${p.categoryIcon}</span>
                  <span>${p.package.packageCategory.name}</span>
                </div>
                <h4 class="past-pkg-name">${p.name}</h4>
                <p class="past-pkg-subtitle">${p.subtitle}</p>
              </div>
              <div class="past-pkg-divider"></div>
              <div class="past-pkg-services">
                <div class="past-pkg-progress-header">
                  <span class="past-pkg-count">${p.completedCount} de ${p.totalCount} servicios entregados</span>
                  <span class="past-pkg-progress-text">${pProgress}%</span>
                </div>
                <div class="past-pkg-mini-timeline">
                  ${p.services.slice(0, 5).map(s => {
                    const statusClass = s.isDone ? 'done' : s.inProgress ? 'active' : 'pending';
                    return `
                      <div class="past-pkg-timeline-item ${statusClass}">
                        <div class="past-pkg-timeline-dot">
                          ${s.isDone ? icons.check : s.inProgress ? icons.clock : '<span class="past-pkg-dot-inner"></span>'}
                        </div>
                        <div class="past-pkg-timeline-info">
                          <span class="past-pkg-timeline-name">${s.name}</span>
                          <span class="past-pkg-timeline-status">${s.status.name}</span>
                        </div>
                      </div>
                    `;
                  }).join('')}
                </div>
              </div>
              <div class="past-pkg-footer">
                <div class="past-pkg-price">
                  <span>Inversión</span>
                  <strong>${p.priceFormatted}</strong>
                </div>
                <div class="past-pkg-progress-bar">
                  <div class="past-pkg-progress-fill" style="width:${pProgress}%"></div>
                </div>
              </div>
            </div>
          `;
        }).join('')}
      </div>
    </div>
    ` : ''}
  `;
}

// ========== RENDER PHOTOS (desde la galeria real) ==========
function renderPhotos() {
  const container = document.getElementById('photosGrid');
  if (!container) return;
  const emptyState = document.getElementById('emptyState');
  const countLabel = document.getElementById('photoCount');
  const readyLabel = document.getElementById('photoReadyCount');
  const fotos = getFilteredPhotos();
  const allFotos = Store.gallery || [];
  const readyFotos = allFotos.filter(f => f.isPublic).length;

  if (countLabel) countLabel.textContent = allFotos.length;
  if (readyLabel) readyLabel.textContent = readyFotos;

  if (fotos.length === 0) {
    container.style.display = 'none';
    emptyState.style.display = 'block';
    return;
  }

  container.style.display = 'grid';
  emptyState.style.display = 'none';

  container.innerHTML = fotos.map((foto, idx) => {
    const typeBadge = foto.isVideo ? 'Video' : foto.isPdf ? 'PDF' : 'Imagen';
    return `
      <div class="photo-card ${selectedPhotos.has(foto.id) ? 'selected' : ''}"
           data-id="${foto.id}" data-idx="${idx}"
           style="animation-delay: ${idx * 0.05}s">
        <img src="${foto.url}" alt="Foto ${foto.id}" loading="lazy" />
        <div class="photo-overlay">
          <div class="photo-overlay-top">
            <span class="photo-session-badge ${foto.isPublic ? 'previa' : 'fiesta'}">${typeBadge}${foto.isPublic ? ' · Pública' : ''}</span>
          </div>
          <div class="photo-overlay-bottom">
            <span class="photo-title">Ítem #${foto.id}</span>
          </div>
        </div>
        <div class="photo-check">
          <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><polyline points="20 6 9 17 4 12"/></svg>
        </div>
        <button class="photo-preview-btn" onclick="event.stopPropagation(); openPhotoPreview(${foto.id})">
          <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M15 3h6v6M9 21H3v-6M21 3l-7 7M3 21l7-7"/></svg>
        </button>
      </div>
    `;
  }).join('');

  container.querySelectorAll('.photo-card').forEach(card => {
    card.addEventListener('click', () => {
      const id = parseInt(card.dataset.id);
      togglePhoto(id);
    });
  });

  updateSelectionCount();
}

// ========== PHOTO PREVIEW ==========
function openPhotoPreview(photoId) {
  const allFotos = Store.gallery || [];
  const foto = allFotos.find(f => f.id === photoId);
  if (!foto) return;

  const idx = allFotos.indexOf(foto);
  previewPhoto = { foto, idx, all: allFotos };

  const modal = document.getElementById('photoPreviewModal');
  renderPreviewContent();
  modal.classList.add('active');
  document.body.style.overflow = 'hidden';
}

function renderPreviewContent() {
  if (!previewPhoto) return;
  const { foto, idx, all } = previewPhoto;
  const content = document.getElementById('previewContent');

  content.innerHTML = `
    <div class="preview-image-wrap">
      <img src="${foto.url}" alt="Galería ${foto.id}" />
    </div>
    <div class="preview-info">
      <span class="preview-session-badge ${foto.isPublic ? 'previa' : 'fiesta'}">${foto.galleryType}</span>
      <h3>Ítem #${foto.id}</h3>
      <p class="preview-counter">${idx + 1} / ${all.length}</p>
      <div class="preview-nav">
        <button onclick="previewNavigate(-1)" ${idx === 0 ? 'disabled' : ''}>
          <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M15 18l-6-6 6-6"/></svg>
          Anterior
        </button>
        <button onclick="previewNavigate(1)" ${idx === all.length - 1 ? 'disabled' : ''}>
          Siguiente
          <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M9 18l6-6-6-6"/></svg>
        </button>
      </div>
    </div>
  `;
}

function previewNavigate(dir) {
  if (!previewPhoto) return;
  const newIdx = previewPhoto.idx + dir;
  if (newIdx < 0 || newIdx >= previewPhoto.all.length) return;
  previewPhoto.idx = newIdx;
  previewPhoto.foto = previewPhoto.all[newIdx];
  renderPreviewContent();
}

function closePhotoPreview() {
  const modal = document.getElementById('photoPreviewModal');
  modal.classList.remove('active');
  document.body.style.overflow = '';
  previewPhoto = null;
}

// ========== GET FILTERED PHOTOS ==========
function getFilteredPhotos() {
  const fotos = Store.gallery || [];
  if (currentFilter === 'all') return fotos;
  if (currentFilter === 'public') return fotos.filter(f => f.isPublic);
  if (currentFilter === 'private') return fotos.filter(f => !f.isPublic);
  if (currentFilter === 'video') return fotos.filter(f => f.isVideo || f.isPdf);
  return fotos;
}

// ========== TOGGLE PHOTO ==========
function togglePhoto(id) {
  if (selectedPhotos.has(id)) {
    selectedPhotos.delete(id);
  } else {
    selectedPhotos.add(id);
  }
  const card = document.querySelector(`.photo-card[data-id="${id}"]`);
  if (card) {
    card.classList.toggle('selected', selectedPhotos.has(id));
  }
  updateSelectionCount();
}

// ========== UPDATE SELECTION COUNT ==========
function updateSelectionCount() {
  const count = selectedPhotos.size;
  document.getElementById('selectionCount').textContent = `${count} seleccionada${count !== 1 ? 's' : ''}`;
  const downloadBtn = document.getElementById('downloadBtn');
  downloadBtn.disabled = count === 0;
}

// ========== SETUP NAV (navegacion entre modulos) ==========
function setupTabs() {
  const routes = { home: '../home/', package: '../package/', photos: '../photos/' };
  const tabs = document.querySelectorAll('.sidebar-item[data-tab]');
  tabs.forEach(tab => {
    // Estado activo coherente con el modulo actual
    tab.classList.toggle('active', tab.dataset.tab === DASHBOARD_MODULE);
    tab.addEventListener('click', () => {
      const target = tab.dataset.tab;
      if (target === DASHBOARD_MODULE) return;
      if (routes[target]) window.location.href = routes[target];
    });
  });
}

// ========== SETUP FILTERS ==========
function setupFilters() {
  const filters = document.querySelectorAll('.filter-btn');
  filters.forEach(filter => {
    filter.addEventListener('click', () => {
      filters.forEach(f => f.classList.remove('active'));
      filter.classList.add('active');
      currentFilter = filter.dataset.filter;
      renderPhotos();
    });
  });
}

// ========== SIDEBAR TOGGLE ==========
function toggleSidebar() {
  const sidebar = document.getElementById('sidebar');
  const overlay = document.getElementById('sidebarOverlay');
  sidebar.classList.toggle('open');
  overlay.classList.toggle('active');
  document.body.style.overflow = sidebar.classList.contains('open') ? 'hidden' : '';
}

function closeSidebar() {
  const sidebar = document.getElementById('sidebar');
  const overlay = document.getElementById('sidebarOverlay');
  sidebar.classList.remove('open');
  overlay.classList.remove('active');
  document.body.style.overflow = '';
}

// Escape cierra el menu lateral (movil)
document.addEventListener('keydown', (e) => {
  if (e.key === 'Escape') closeSidebar();
});

// ========== DOWNLOAD ==========
const downloadBtnEl = document.getElementById('downloadBtn');
if (downloadBtnEl) {
  downloadBtnEl.addEventListener('click', () => {
    if (selectedPhotos.size === 0) return;
    const count = selectedPhotos.size;
    alert(`Descargando ${count} archivo(s)...\n\nEn producción, esto descargaría un ZIP con los archivos seleccionados.`);
    selectedPhotos.clear();
    document.querySelectorAll('.photo-card.selected').forEach(card => {
      card.classList.remove('selected');
    });
    updateSelectionCount();
  });
}

// ========== LOGOUT ==========
async function handleLogout() {
  await Store.logout();
  window.location.href = '../../index.html';
}
