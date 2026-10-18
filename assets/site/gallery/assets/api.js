// ==================================================================
// HARD STREET — Cliente de API + Store (modo estricto, SIN fallback)
// Toda la pagina se alimenta del backend. Si el backend no responde,
// la pagina muestra un error con boton "Reintentar" — nunca datos
// viejos ni demo.
// ==================================================================

// ---------- CONFIG ----------
const API_CONFIG = {
  // En produccion define window.HARDSTREET_API_URL (ej: 'https://tu-proyecto.vercel.app')
  baseUrl: (window.HARDSTREET_API_URL || '').replace(/\/$/, ''),
};

// ---------- HELPERS ----------

// Token JWT en memoria + localStorage. Al loguearse se guarda y de ahi
// en adelante se manda en cada peticion via header Authorization (Bearer).
const TOKEN_KEY = 'hs_token';
let authToken = localStorage.getItem(TOKEN_KEY) || '';

function saveToken(token) {
  authToken = token || '';
  try {
    if (authToken) localStorage.setItem(TOKEN_KEY, authToken);
    else localStorage.removeItem(TOKEN_KEY);
  } catch (_) {}
}

async function apiFetch(path, options = {}) {
  const url = API_CONFIG.baseUrl + path;
  const headers = { 'Content-Type': 'application/json', ...options.headers };
  if (authToken) headers['Authorization'] = 'Bearer ' + authToken;
  const res = await fetch(url, {
    headers,
    ...options,
  });
  if (!res.ok) {
    let msg = `HTTP ${res.status}`;
    try { const j = await res.json(); if (j.error) msg = j.error; } catch (_) {}
    const err = new Error(msg);
    err.status = res.status;
    // Token invalido/expirado -> limpiarlo para no seguir mandando basura
    if (res.status === 401 && authToken) saveToken('');
    throw err;
  }
  return res.json();
}

// Normaliza cualquier objeto crudo de la API a instancias de modelo
function hydratePackage(p) { return new Package(p); }
function hydratePurchasedPackage(p) { return new PurchasedPackage(p); }

// ==================================================================
// STORE — estado global de la app
// ==================================================================
const Store = {
  packages: [],          // Package[] (catalogo publico, is_extern = 0)
  externServices: [],    // Package[] ("Nuestros servicios", is_extern = 1)
  categories: [],        // PackageCategory[]
  publicGallery: [],     // Gallery[] (galeria publica, is_public = 1, landing)
  purchasedPackages: [], // PurchasedPackage[] (del usuario logueado)
  gallery: [],           // Gallery[] (del usuario logueado)
  user: null,            // User | null

  // Catalogo publico de la landing (paquetes + categorias).
  // Lanza excepcion si el backend no responde.
  async loadCatalog() {
    const [pkgs, cats] = await Promise.all([
      apiFetch('/api/packages'),
      apiFetch('/api/categories'),
    ]);
    this.packages = (pkgs.packages || []).map(hydratePackage);
    // Categorias desde la BD (packages_categories): alimentan los filtros
    this.categories = (cats.categories || []).map(c => new PackageCategory(c));
    return this;
  },

  // "Lo que ofrecemos": paquetes con is_extern = 1, endpoint propio.
  // Independiente de loadCatalog para poder reintentarlo por separado.
  async loadExternServices() {
    const ext = await apiFetch('/api/extern-services');
    this.externServices = (ext.externServices || []).map(hydratePackage);
    return this;
  },

  // "Galeria Destacada": fotos publicas (is_public = 1) con su categoria.
  // Tambien independiente para reintentarlo por separado.
  async loadPublicGallery() {
    const res = await apiFetch('/api/public/gallery');
    this.publicGallery = (res.gallery || []).map(g => new Gallery(g));
    return this;
  },

  // Datos del usuario logueado (dashboard). 401 = no hay sesion.
  async loadUserData() {
    const me = await apiFetch('/api/auth/me');
    this.user = new User(me.user);
    const [pp, gal] = await Promise.all([
      apiFetch('/api/my/packages'),
      apiFetch('/api/my/gallery'),
    ]);
    this.purchasedPackages = (pp.purchasedPackages || []).map(hydratePurchasedPackage);
    this.gallery = (gal.gallery || []).map(g => new Gallery(g));
    return this;
  },

  async login(email, password) {
    const res = await apiFetch('/api/auth/login', {
      method: 'POST',
      body: JSON.stringify({ email, password }),
    });
    saveToken(res.token); // el token viaja ahora en el header Authorization
    this.user = new User(res.user);
    await this.loadUserData();
    return this.user;
  },

  async logout() {
    saveToken('');
    try { await apiFetch('/api/auth/logout', { method: 'POST' }); } catch (_) {}
    this.user = null;
    this.purchasedPackages = [];
    this.gallery = [];
  },
};
