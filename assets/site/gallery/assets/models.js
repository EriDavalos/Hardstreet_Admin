// ==================================================================
// HARD STREET — Modelos del frontend (compatibles con la BD)
// Campos en ingles, tal como los devuelve la API:
//   Service, Tier, PackageCategory, Status, Package,
//   PurchasedPackageService, PurchasedPackage, User, Gallery
// ==================================================================

// ========== ICONOS SVG DE SERVICIOS ==========
// Clave = nombre del archivo de icono guardado en BD (services.icon),
// ej: "icon/video.svg" -> clave "video"
const ServiceIcons = {
  video: `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5"><polygon points="23 7 16 12 23 17 23 7"/><rect x="1" y="5" width="15" height="14" rx="2" ry="2"/></svg>`,
  videoHighlights: `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5"><rect x="2" y="2" width="20" height="20" rx="2.18" ry="2.18"/><line x1="7" y1="2" x2="7" y2="22"/><line x1="17" y1="2" x2="17" y2="22"/><line x1="2" y1="12" x2="22" y2="12"/></svg>`,
  drone: `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5"><path d="M12 2L2 7l10 5 10-5-10-5z"/><path d="M2 17l10 5 10-5"/><path d="M2 12l10 5 10-5"/></svg>`,
  ring: `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5"><circle cx="12" cy="12" r="10"/><circle cx="12" cy="12" r="4"/></svg>`,
  camera: `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5"><path d="M23 19a2 2 0 0 1-2 2H3a2 2 0 0 1-2-2V8a2 2 0 0 1 2-2h4l2-3h6l2 3h4a2 2 0 0 1 2 2z"/><circle cx="12" cy="13" r="4"/></svg>`,
  photos: `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5"><rect x="3" y="3" width="18" height="18" rx="2" ry="2"/><circle cx="8.5" cy="8.5" r="1.5"/><polyline points="21 15 16 10 5 21"/></svg>`,
  frame: `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5"><rect x="3" y="3" width="18" height="18" rx="2" ry="2"/><line x1="3" y1="9" x2="21" y2="9"/><line x1="9" y1="21" x2="9" y2="9"/></svg>`,
  church: `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5"><path d="M18 22V8l-6-6-6 6v14"/><path d="M9 22v-6h6v6"/><path d="M12 2v4"/></svg>`,
  star: `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5"><polygon points="12 2 15.09 8.26 22 9.27 17 14.14 18.18 21.02 12 17.77 5.82 21.02 7 14.14 2 9.27 8.91 8.26 12 2"/></svg>`,
  print: `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5"><polyline points="6 9 6 2 18 2 18 9"/><path d="M6 18H4a2 2 0 0 1-2-2v-5a2 2 0 0 1 2-2h16a2 2 0 0 1 2 2v5a2 2 0 0 1-2 2h-2"/><rect x="6" y="14" width="12" height="8"/></svg>`,
  studio: `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5"><path d="M3 9l9-7 9 7v11a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2z"/><polyline points="9 22 9 12 15 12 15 22"/></svg>`,
  event: `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5"><rect x="3" y="4" width="18" height="18" rx="2" ry="2"/><line x1="16" y1="2" x2="16" y2="6"/><line x1="8" y1="2" x2="8" y2="6"/><line x1="3" y1="10" x2="21" y2="10"/></svg>`,
  product: `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5"><path d="M21 16V8a2 2 0 0 0-1-1.73l-7-4a2 2 0 0 0-2 0l-7 4A2 2 0 0 0 3 8v8a2 2 0 0 0 1 1.73l7 4a2 2 0 0 0 2 0l7-4A2 2 0 0 0 21 16z"/><polyline points="3.27 6.96 12 12.01 20.73 6.96"/><line x1="12" y1="22.08" x2="12" y2="12"/></svg>`,
  flyer: `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5"><path d="M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8z"/><polyline points="14 2 14 8 20 8"/><line x1="16" y1="13" x2="8" y2="13"/><line x1="16" y1="17" x2="8" y2="17"/></svg>`,
  personal: `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5"><path d="M20 21v-2a4 4 0 0 0-4-4H8a4 4 0 0 0-4 4v2"/><circle cx="12" cy="7" r="4"/></svg>`,
  mic: `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5"><path d="M12 1a3 3 0 0 0-3 3v8a3 3 0 0 0 6 0V4a3 3 0 0 0-3-3z"/><path d="M19 10v2a7 7 0 0 1-14 0v-2"/><line x1="12" y1="19" x2="12" y2="23"/><line x1="8" y1="23" x2="16" y2="23"/></svg>`,
  general: `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5"><rect x="3" y="3" width="18" height="18" rx="2" ry="2"/><circle cx="8.5" cy="8.5" r="1.5"/><polyline points="21 15 16 10 5 21"/></svg>`,
};

/**
 * Resuelve el icono de un servicio al HTML que se pinta en la web.
 *
 * Acepta los dos formatos que guarda la columna `services.icon`:
 *   * `material:videocam` → el MISMO icono que elige el panel (Flutter) en el
 *     módulo Servicios. Se dibuja con la tipografía Material Symbols, así el
 *     sitio y la app muestran exactamente el mismo dibujo sin mantener aquí
 *     una lista de SVG que se quedaría corta.
 *   * `icon/photos.svg`  → formato heredado: se resuelve con la tabla de SVG.
 */
function resolveServiceIcon(icon) {
  if (!icon) return ServiceIcons.general;
  const raw = String(icon).trim();
  if (/^material:/i.test(raw)) {
    // Solo el nombre del icono (nada de HTML): se limpia por si llegara basura.
    const name = raw.slice('material:'.length).trim().toLowerCase()
      .replace(/[^a-z0-9_]/g, '');
    if (!name) return ServiceIcons.general;
    return `<span class="material-symbols-outlined" aria-hidden="true">${name}</span>`;
  }
  const key = raw.split('/').pop().replace(/\.svg$/i, '');
  return ServiceIcons[key] || ServiceIcons.general;
}

// ========== ICONOS POR CATEGORIA ==========
const CategoryIcons = {
  boda: `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5"><path d="M20.84 4.61a5.5 5.5 0 0 0-7.78 0L12 5.67l-1.06-1.06a5.5 5.5 0 0 0-7.78 7.78l1.06 1.06L12 21.23l7.78-7.78 1.06-1.06a5.5 5.5 0 0 0 0-7.78z"/></svg>`,
  'xv años': `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5"><path d="M12 2L15.09 8.26L22 9.27L17 14.14L18.18 21.02L12 17.77L5.82 21.02L7 14.14L2 9.27L8.91 8.26L12 2z"/></svg>`,
  bautizo: `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5"><path d="M12 2v6M12 22v-6M4.93 4.93l4.24 4.24M14.83 14.83l4.24 4.24M2 12h6M22 12h-6M4.93 19.07l4.24-4.24M14.83 9.17l4.24-4.24"/></svg>`,
  graduación: `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5"><path d="M22 10v6M2 10l10-5 10 5-10 5z"/><path d="M6 12v5c3 3 6 3 6 3s3 0 6-3v-5"/></svg>`,
  comercial: `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5"><rect x="2" y="7" width="20" height="14" rx="2" ry="2"/><path d="M16 21V5a2 2 0 0 0-2-2h-4a2 2 0 0 0-2 2v16"/></svg>`,
  general: `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5"><rect x="3" y="3" width="18" height="18" rx="2" ry="2"/><circle cx="8.5" cy="8.5" r="1.5"/><polyline points="21 15 16 10 5 21"/></svg>`,
};

/** Clave CSS/SEO de una categoria: "XV Años" -> "xv-anos", "Graduación" -> "graduacion" */
function categoryKey(name) {
  return String(name || 'general')
    .toLowerCase()
    .normalize('NFD')
    .replace(/[\u0300-\u036f]/g, '')
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-|-$/g, '') || 'general';
}

/** Icono de categoria aceptando el nombre ("Boda") o la clave ("boda"). */
function categoryIcon(name) {
  return CategoryIcons[categoryKey(name)] || CategoryIcons.general;
}

// ========== TIER ==========
class Tier {
  constructor({ id = 0, name = 'Basic', tier = 3 } = {}) {
    this.id = id;
    this.name = name;   // 'Premium' | 'Gold' | 'Basic'
    this.tier = tier;   // 1 | 2 | 3 (menor = mejor)
  }
  get key() { return this.name.toLowerCase(); }            // css: tier-premium
  get label() { return this.name; }
  toObject() { return { id: this.id, name: this.name, tier: this.tier }; }
}

const TierLabels = { premium: 'Premium', gold: 'Gold', basic: 'Essentials' };

// ========== PACKAGE CATEGORY ==========
class PackageCategory {
  constructor({ id = 0, name = 'General', icon = '', urlImage = '' } = {}) {
    this.id = id;
    this.name = name;   // 'Boda', 'XV Años'...
    this.icon = icon;   // 'icon/heart.svg' (reservado en BD)
    // Foto que representa a la categoría (la elige el panel; puede ser del
    // Drive). Vacía = la categoría usa la foto de su primer paquete.
    this.urlImage = urlImage;
  }
  get key() { return categoryKey(this.name); }
  get iconSvg() { return categoryIcon(this.name); }
  toObject() {
    return { id: this.id, name: this.name, icon: this.icon, urlImage: this.urlImage };
  }
}

// ========== STATUS ==========
class Status {
  constructor({ id = 0, name = 'Pendiente' } = {}) {
    this.id = id;
    this.name = name;   // 'Pendiente' | 'En proceso' | 'Entregado'
  }
  get key() { return categoryKey(this.name); }   // 'pendiente' | 'en-proceso' | 'entregado'
  toObject() { return { id: this.id, name: this.name }; }
}

// ========== SERVICE ==========
class Service {
  constructor({ id = 0, name = '', description = '', icon = '' } = {}) {
    this.id = id;
    this.name = name;
    this.description = description;
    this.icon = icon;        // string crudo de BD: 'icon/video.svg'
    this.iconSvg = resolveServiceIcon(icon); // SVG listo para render
  }
  toObject() { return { id: this.id, name: this.name, description: this.description, icon: this.icon }; }
}

// ========== PACKAGE ==========
// name, subtitle, description: string
// price: number | currency: string
// tier: Tier | packageCategory: PackageCategory
// isExtern: bool | services: Service[] | urlImage: string
class Package {
  constructor({
    id = 0, name = '', subtitle = '', description = '',
    price = 0, currency = 'MXN',
    tier = null, packageCategory = null,
    isExtern = false, urlImage = '', services = [],
  } = {}) {
    this.id = id;
    this.name = name;
    this.subtitle = subtitle;
    this.description = description;
    this.price = Number(price) || 0;
    this.currency = currency || 'MXN';
    this.tier = tier instanceof Tier ? tier : new Tier(tier || {});
    this.packageCategory = packageCategory instanceof PackageCategory ? packageCategory : new PackageCategory(packageCategory || {});
    this.isExtern = !!isExtern;
    this.urlImage = urlImage || '';   // url_image de BD (imagen del carousel)
    this.services = (services || []).map(s => (s instanceof Service ? s : new Service(s)));
  }

  get priceFormatted() {
    return '$' + this.price.toLocaleString('es-MX');
  }
  get tierLabel() { return TierLabels[this.tier.key] || this.tier.name; }
  get categoryKey() { return this.packageCategory.key; }
  get categoryIcon() { return this.packageCategory.iconSvg; }

  toObject() {
    return {
      id: this.id, name: this.name, subtitle: this.subtitle, description: this.description,
      price: this.price, currency: this.currency,
      tier: this.tier.toObject(), packageCategory: this.packageCategory.toObject(),
      isExtern: this.isExtern, urlImage: this.urlImage, services: this.services.map(s => s.toObject()),
    };
  }
}

// ========== PURCHASED PACKAGE SERVICE ==========
class PurchasedPackageService {
  constructor({
    id = 0, description = '', deliveryDate = null,
    status = null, service = null,
  } = {}) {
    this.id = id;
    this.description = description;         // nota de avance escrita por el admin
    this.deliveryDate = deliveryDate;       // dias de entrega (integer en BD)
    this.status = status instanceof Status ? status : new Status(status || {});
    this.service = service instanceof Service ? service : new Service(service || {});
  }
  get name() { return this.service.name; }             // atajo para render
  get iconSvg() { return this.service.iconSvg; }
  get serviceDescription() { return this.service.description; }
  get isDone() { return this.status.key === 'entregado'; }
  get inProgress() { return this.status.key === 'en-proceso'; }
  get isPending() { return !this.isDone && !this.inProgress; }

  toObject() {
    return {
      id: this.id, description: this.description, deliveryDate: this.deliveryDate,
      status: this.status.toObject(), service: this.service.toObject(),
    };
  }
}

// ========== PURCHASED PACKAGE ==========
// Paquete comprado por un cliente. Hereda del paquete principal
// (name/subtitle/price...) y agrega paid, status y sus propios servicios.
class PurchasedPackage {
  constructor({
    id = 0, name = '', subtitle = '', description = '',
    price = 0, paid = 0, currency = 'MXN',
    status = null,
    package: pkg = null, // la API manda 'package'; 'pkg' se acepta por compatibilidad
    services = [],
  } = {}) {
    this.id = id;
    this.name = name;
    this.subtitle = subtitle;
    this.description = description;
    this.price = Number(price) || 0;   // precio total acordado
    this.paid = Number(paid) || 0;     // monto ya pagado
    this.currency = currency || 'MXN';
    this.status = status instanceof Status ? status : new Status(status || {});
    this.package = pkg instanceof Package ? pkg : new Package(pkg || {});
    this.services = (services || []).map(s => (s instanceof PurchasedPackageService ? s : new PurchasedPackageService(s)));
  }

  get priceFormatted() { return '$' + this.price.toLocaleString('es-MX'); }
  get paidFormatted() { return '$' + this.paid.toLocaleString('es-MX'); }
  get pendingAmount() { return Math.max(this.price - this.paid, 0); }
  get tier() { return this.package.tier; }               // para clases tier-premium etc.
  get tierLabel() { return TierLabels[this.tier.key] || this.tier.name; }
  get categoryKey() { return this.package.categoryKey; }
  get categoryIcon() { return this.package.categoryIcon; }
  get completedCount() { return this.services.filter(s => s.isDone).length; }
  get totalCount() { return this.services.length; }
  get progressPercent() { return this.totalCount ? Math.round((this.completedCount / this.totalCount) * 100) : 0; }

  toObject() {
    return {
      id: this.id, name: this.name, subtitle: this.subtitle, description: this.description,
      price: this.price, paid: this.paid, currency: this.currency,
      status: this.status.toObject(), package: this.package.toObject(),
      services: this.services.map(s => s.toObject()),
    };
  }
}

// ========== USER ==========
class User {
  constructor({ id = 0, name = '', lastname = '', number = '', email = '', role = '' } = {}) {
    this.id = id;
    this.name = name;
    this.lastname = lastname;
    this.number = number;
    this.email = email;
    this.role = role;   // 'Admin' | 'Client'
  }
  get fullName() { return [this.name, this.lastname].filter(Boolean).join(' '); }
  get initials() { return this.fullName.split(' ').map(n => n[0]).join('').toUpperCase().slice(0, 2); }
  isAdmin() { return this.role.toLowerCase() === 'admin'; }
  toObject() { return { id: this.id, name: this.name, lastname: this.lastname, number: this.number, email: this.email, role: this.role }; }
}

// ========== GALLERY ==========
class Gallery {
  constructor({
    id = 0, url = '', user = 0, galleryType = 'image',
    purchasedPackage = null, packageCategory = null,
    packageCategoryName = '', isPublic = false,
  } = {}) {
    this.id = id;
    this.url = url;
    this.user = user;                            // id_user (dueno)
    this.galleryType = galleryType;              // 'image' | 'video' | 'pdf'
    this.purchasedPackage = purchasedPackage;    // id_purchased_package
    this.packageCategory = packageCategory;      // id_package_category
    this.packageCategoryName = packageCategoryName || ''; // nombre de packages_categories
    this.isPublic = !!isPublic;
  }
  get isImage() { return this.galleryType === 'image'; }
  get isVideo() { return this.galleryType === 'video'; }
  get isPdf() { return this.galleryType === 'pdf'; }
  get categoryKey() { return categoryKey(this.packageCategoryName || 'general'); } // para filtros CSS
  get categoryName() { return this.packageCategoryName || 'General'; }

  toObject() {
    return {
      id: this.id, url: this.url, user: this.user, galleryType: this.galleryType,
      purchasedPackage: this.purchasedPackage, packageCategory: this.packageCategory,
      packageCategoryName: this.packageCategoryName, isPublic: this.isPublic,
    };
  }
}

// ========== ALIAS DE COMPATIBILIDAD (codigo viejo en espanol) ==========
const ExternService = Package;
