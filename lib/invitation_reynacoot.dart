// GENERADO desde Hardstreet/ReynaCoot (index.html, index.css, index.js).
// No editar a mano: es el documento original, con marcadores en los datos.

const String kReynaCootBody = r'''
<!-- SVG line-art library -->
  <svg width="0" height="0" style="position:absolute" aria-hidden="true">
    <defs>
      <g id="leaf" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round">
        <path d="M 0 0 C 5 -9, 14 -11, 20 -6 C 14 -1, 6 2, 0 0 Z" />
        <path d="M 2 0 L 17 -5" />
      </g>
      <g id="flower" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round">
        <circle cx="0" cy="-7" r="5.5" />
        <circle cx="6.7" cy="-2.2" r="5.5" />
        <circle cx="4.1" cy="5.7" r="5.5" />
        <circle cx="-4.1" cy="5.7" r="5.5" />
        <circle cx="-6.7" cy="-2.2" r="5.5" />
        <circle cx="0" cy="0" r="2" fill="currentColor" stroke="none" />
      </g>
      <g id="rose" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round">
        <path d="M -11 0 C -11 -9, -2 -12, 4 -10 C 11 -8, 13 0, 11 5 C 9 10, 3 12, -3 10 C -9 8, -11 2, -10 -2" />
        <path d="M -6 0 C -6 -5, 0 -7, 4 -5 C 7 -3, 7 1, 5 3 C 2 5, -2 5, -5 3" />
        <circle cx="0" cy="0" r="1.5" fill="currentColor" stroke="none" />
      </g>
      <g id="sparkle" fill="currentColor">
        <path d="M 0 -12 C 2 -5 5 -2 12 0 C 5 2 2 5 0 12 C -2 5 -5 2 -12 0 C -5 -2 -2 -5 0 -12 Z" />
      </g>
      <g id="heart" fill="currentColor">
        <path d="M 12 21 C 5 15 2 11 2 7.5 C 2 4.5 4.5 2 7.5 2 C 9.5 2 11.2 3 12 4.6 C 12.8 3 14.5 2 16.5 2 C 19.5 2 22 4.5 22 7.5 C 22 11 19 15 12 21 Z" />
      </g>
      <!-- corner vine: hugs the top-left corner, viewBox 220x220 -->
      <g id="corner-fl" stroke="currentColor" stroke-width="1.5" fill="none" stroke-linecap="round">
        <path d="M 12 14 C 44 18, 78 26, 102 48 C 120 64, 128 86, 124 110" />
        <path d="M 14 12 C 18 44, 26 78, 48 102 C 64 120, 86 128, 110 124" />
        <path d="M 16 16 C 30 30, 40 48, 44 70" />
        <use href="#leaf" transform="translate(70 30) rotate(15) scale(0.85)" />
        <use href="#leaf" transform="translate(110 60) rotate(55) scale(0.85)" />
        <use href="#leaf" transform="translate(118 95) rotate(80) scale(0.8)" />
        <use href="#leaf" transform="translate(30 70) rotate(75) scale(0.85)" />
        <use href="#leaf" transform="translate(60 110) rotate(115) scale(0.85)" />
        <use href="#leaf" transform="translate(95 118) rotate(140) scale(0.8)" />
        <use href="#leaf" transform="translate(34 44) rotate(45) scale(0.7)" />
        <use href="#rose" transform="translate(16 16) scale(1)" />
        <use href="#flower" transform="translate(124 110) scale(0.85)" />
        <use href="#flower" transform="translate(110 124) scale(0.85)" />
        <use href="#flower" transform="translate(44 70) scale(0.7)" />
      </g>
      <!-- top / bottom spray -->
      <g id="spray" stroke="currentColor" stroke-width="1.5" fill="none" stroke-linecap="round">
        <path d="M 8 24 C 36 16, 64 14, 92 24" />
        <path d="M 34 18 C 30 10, 24 6, 16 6" />
        <path d="M 66 18 C 70 10, 76 6, 84 6" />
        <use href="#rose" transform="translate(8 24) scale(0.9)" />
        <use href="#flower" transform="translate(50 16) scale(0.9)" />
        <use href="#rose" transform="translate(92 24) scale(0.9)" />
        <use href="#flower" transform="translate(16 6) scale(0.65)" />
        <use href="#flower" transform="translate(84 6) scale(0.65)" />
        <use href="#leaf" transform="translate(36 14) rotate(-15) scale(0.7)" />
        <use href="#leaf" transform="translate(64 14) rotate(15) scale(0.7)" />
      </g>
      <!-- hanging floral garland / swag -->
      <g id="garland" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round">
        <path d="M 6 10 Q 105 74 200 38 Q 295 2 394 10" />
        <path d="M 6 10 C 3 5 1 2 2 -2" />
        <path d="M 394 10 C 397 5 399 2 398 -2" />
        <path d="M 60 34 L 60 44" />
        <path d="M 140 50 L 140 60" />
        <path d="M 260 20 L 260 30" />
        <path d="M 340 26 L 340 36" />
        <use href="#rose" transform="translate(14 8) scale(1.1)" />
        <use href="#rose" transform="translate(386 8) scale(1.1)" />
        <use href="#rose" transform="translate(200 38) scale(1.3)" />
        <use href="#flower" transform="translate(100 54) scale(1)" />
        <use href="#flower" transform="translate(296 6) scale(1)" />
        <use href="#flower" transform="translate(60 44) scale(0.85)" />
        <use href="#flower" transform="translate(140 60) scale(0.85)" />
        <use href="#flower" transform="translate(260 30) scale(0.85)" />
        <use href="#flower" transform="translate(340 36) scale(0.85)" />
        <use href="#leaf" transform="translate(80 42) rotate(-25) scale(0.9)" />
        <use href="#leaf" transform="translate(120 52) rotate(20) scale(0.9)" />
        <use href="#leaf" transform="translate(170 44) rotate(-15) scale(0.8)" />
        <use href="#leaf" transform="translate(230 34) rotate(15) scale(0.8)" />
        <use href="#leaf" transform="translate(320 14) rotate(-30) scale(0.8)" />
      </g>
      <!-- center divider flourish -->
      <g id="divider" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round">
        <path d="M 14 16 H 96" />
        <path d="M 164 16 H 246" />
        <path d="M 96 16 C 104 10 116 10 124 16" />
        <path d="M 136 16 C 144 10 156 10 164 16" />
        <rect x="125" y="11" width="10" height="10" transform="rotate(45 130 16)" />
        <circle cx="104" cy="16" r="2" fill="currentColor" stroke="none" />
        <circle cx="156" cy="16" r="2" fill="currentColor" stroke="none" />
        <path d="M 78 16 l -6 -6 M 78 16 l -6 6" />
        <path d="M 182 16 l 6 -6 M 182 16 l 6 6" />
      </g>
      <!-- ribbon bow -->
      <g id="ribbon" stroke="currentColor" stroke-width="1.8" fill="none" stroke-linecap="round" stroke-linejoin="round">
        <path d="M 22 12 C 8 -4, 2 12, 14 20 C 18 23, 21 20, 22 12 Z" />
        <path d="M 22 12 C 36 -4, 42 12, 30 20 C 26 23, 23 20, 22 12 Z" />
        <path d="M 22 12 L 22 30" />
        <path d="M 22 30 C 16 38, 12 42, 8 48" />
        <path d="M 22 30 C 28 38, 32 42, 36 48" />
        <path d="M 22 8 C 21 4, 23 0, 27 -2" />
      </g>
      <!-- tiara -->
      <g id="tiara" stroke="currentColor" stroke-width="2" fill="none" stroke-linecap="round" stroke-linejoin="round">
        <path d="M 12 34 L 12 18 L 22 24 L 30 12 L 38 24 L 48 18 L 48 34 Z" />
        <path d="M 6 34 L 54 34" />
        <circle cx="12" cy="16" r="2.4" fill="currentColor" stroke="none" />
        <circle cx="48" cy="16" r="2.4" fill="currentColor" stroke="none" />
        <circle cx="30" cy="10" r="2.4" fill="currentColor" stroke="none" />
        <path d="M 22 30 C 25 27, 27 27, 30 30" />
      </g>
      <!-- champagne glasses -->
      <g id="champagne" stroke="currentColor" stroke-width="2" fill="none" stroke-linecap="round" stroke-linejoin="round">
        <path d="M 10 12 C 6 20, 14 26, 19 26 C 24 26, 32 20, 28 12 Z" />
        <path d="M 19 26 L 19 40" />
        <path d="M 12 44 L 26 44" />
        <path d="M 32 12 C 28 20, 36 26, 41 26 C 46 26, 54 20, 50 12 Z" />
        <path d="M 41 26 L 41 40" />
        <path d="M 34 44 L 48 44" />
        <circle cx="20" cy="6" r="1.6" />
        <circle cx="26" cy="2.5" r="1.2" />
        <circle cx="14" cy="4" r="1" />
        <circle cx="44" cy="5" r="1.3" />
        <path d="M 30 10 l 3 -3 M 30 10 l -3 -3" />
      </g>
      <!-- church: la misa -->
      <g id="church" stroke="currentColor" stroke-width="2" fill="none" stroke-linecap="round" stroke-linejoin="round">
        <path d="M 30 12 V 4" />
        <path d="M 26.9 7.6 H 33.1" />
        <path d="M 8 34 L 30 12 L 52 34" />
        <path d="M 6 58 V 34 H 54 V 58" />
        <path d="M 26 58 V 49 A 4 4 0 0 1 34 49 V 58" />
        <circle cx="30" cy="40" r="3" />
        <path d="M 12 55 V 51 A 2.6 2.6 0 0 1 17.2 51 V 55" />
        <path d="M 42.8 55 V 51 A 2.6 2.6 0 0 1 48 51 V 55" />
      </g>
      <!-- couple: dress code -->
      <g id="couple" stroke="currentColor" stroke-width="2" fill="none" stroke-linecap="round" stroke-linejoin="round">
        <circle cx="20" cy="12" r="6.5" />
        <path d="M 20 18.5 L 20 26" />
        <path d="M 10 30 C 10 24, 30 24, 30 30 L 28 46 L 12 46 Z" />
        <path d="M 20 30 L 20 46" />
        <path d="M 20 30 L 15 26 M 20 30 L 25 26" />
        <circle cx="50" cy="12" r="6" />
        <path d="M 50 18 L 50 24" />
        <path d="M 50 24 C 46 27, 42 29, 40 32 L 40 40" />
        <path d="M 50 24 C 54 27, 58 29, 60 32 L 60 40" />
        <path d="M 38 40 L 62 40" />
        <path d="M 42 40 L 50 56 L 58 40 Z" />
        <path d="M 44 31 C 40 34, 39 38, 39 42" />
        <path d="M 56 31 C 60 34, 61 38, 61 42" />
      </g>
      <!-- envelope with letter -->
      <g id="env-illu" stroke="currentColor" stroke-width="2" fill="none" stroke-linecap="round" stroke-linejoin="round">
        <rect x="12" y="18" width="56" height="36" rx="4" />
        <path d="M 12 18 L 40 34 L 68 18" />
        <path d="M 40 20 L 40 54" />
        <path d="M 32 42 L 52 42" />
        <path d="M 36 47 L 48 47" />
        <path d="M 40 34 C 32 28, 28 30, 28 36 C 28 40, 33 42, 40 34 Z" />
        <path d="M 40 34 C 48 28, 52 30, 52 36 C 52 40, 47 42, 40 34 Z" />
        <circle cx="40" cy="34" r="1.8" fill="currentColor" stroke="none" />
      </g>
      <!-- small falling envelope (lluvia de sobres) -->
      <g id="env-drop" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round">
        <rect x="-14" y="-10" width="28" height="20" rx="2.5" />
        <path d="M -14 -10 L 0 3 L 14 -10" />
        <use href="#heart" transform="translate(-4.08 1.1) scale(0.34)" />
      </g>
      <!-- rain of envelopes (gift suggestion) -->
      <g id="rain-env" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round">
        <path d="M 15 1 l -4 7 M 55 0.5 l -4 7 M 33 15 l -4 8 M 66 28 l -4 8" />
        <use href="#env-drop" transform="translate(36 40) rotate(-12) scale(1.3)" />
        <use href="#env-drop" transform="translate(16 18) rotate(14) scale(0.82)" />
        <use href="#env-drop" transform="translate(56 16) rotate(-18) scale(0.72)" />
        <use href="#env-drop" transform="translate(10 46) rotate(8) scale(0.62)" />
        <use href="#sparkle" transform="translate(46 47) scale(0.3)" />
        <use href="#sparkle" transform="translate(13 31) scale(0.24)" />
        <use href="#sparkle" transform="translate(64 42) scale(0.22)" />
      </g>
      <!-- butterfly -->
      <g id="butterfly" stroke="currentColor" stroke-width="1.8" fill="none" stroke-linecap="round" stroke-linejoin="round">
        <path d="M 22 24 C 16 16, 8 14, 5 19 C 2 24, 8 29, 15 30 C 18 30.5, 21 29, 22 24 Z" />
        <path d="M 22 27 C 20 33, 16 38, 12 37 C 8 36, 12 31, 17 30.5 C 19 30, 21 29, 22 27 Z" />
        <path d="M 22 24 C 28 16, 36 14, 39 19 C 42 24, 36 29, 29 30 C 26 30.5, 23 29, 22 24 Z" />
        <path d="M 22 27 C 24 33, 28 38, 32 37 C 36 36, 32 31, 27 30.5 C 25 30, 23 29, 22 27 Z" />
        <path d="M 22 22 L 22 36" />
        <path d="M 22 24 C 20 20, 19 17, 20 15 M 22 24 C 24 20, 25 17, 24 15" />
      </g>
    </defs>
  </svg>

  <!-- ENVELOPE COVER -->
  <div class="envelope" id="envelope"{{ENVELOPE_STYLE}} onclick="openInvitation()">
    {{COVER_MEDIA}}
    {{COVER_DESIGN}}
    <svg class="garland top" viewBox="0 0 400 100"><use href="#garland" /></svg>
    <svg class="corner-svg tl" viewBox="0 0 220 220"><use href="#corner-fl" /></svg>
    <svg class="corner-svg tr" viewBox="0 0 220 220"><use href="#corner-fl" transform="translate(220 0) scale(-1 1)" /></svg>
    <svg class="corner-svg bl" viewBox="0 0 220 220"><use href="#corner-fl" transform="translate(0 220) scale(1 -1)" /></svg>
    <svg class="corner-svg br" viewBox="0 0 220 220"><use href="#corner-fl" transform="translate(220 220) scale(-1 -1)" /></svg>
    <svg class="sparkle e1" viewBox="-14 -14 28 28"><use href="#sparkle" /></svg>
    <svg class="sparkle e2" viewBox="-14 -14 28 28"><use href="#sparkle" /></svg>
    <svg class="sparkle e3" viewBox="-14 -14 28 28"><use href="#sparkle" /></svg>
    <svg class="sparkle e4" viewBox="-14 -14 28 28"><use href="#sparkle" /></svg>
    <div class="petal"></div><div class="petal"></div><div class="petal"></div>
    <div class="petal"></div><div class="petal"></div><div class="petal"></div>
    <div class="envelope-content">
      <div class="envelope-icon">💌</div>
      <p class="envelope-text">{{ENVELOPE_TEXT}}</p>
      <p class="envelope-name">{{ENVELOPE_NAME}}</p>
      <p class="envelope-date">{{ENVELOPE_DATE}}</p>
      <p class="envelope-tap">Toca para abrir ✨</p>
    </div>
  </div>

  <!-- INVITATION -->
  <div class="{{INV_CLASS}}" id="invitation">

    <!-- ===== MAIN CARD ===== -->
    <div class="section main-card-section">
      <svg class="garland top" viewBox="0 0 400 100"><use href="#garland" /></svg>
      <div class="main-card">
        <svg class="corner-svg tl" viewBox="0 0 220 220"><use href="#corner-fl" /></svg>
        <svg class="corner-svg tr" viewBox="0 0 220 220"><use href="#corner-fl" transform="translate(220 0) scale(-1 1)" /></svg>
        <svg class="corner-svg bl" viewBox="0 0 220 220"><use href="#corner-fl" transform="translate(0 220) scale(1 -1)" /></svg>
        <svg class="corner-svg br" viewBox="0 0 220 220"><use href="#corner-fl" transform="translate(220 220) scale(-1 -1)" /></svg>
        <svg class="sparkle s1" viewBox="-14 -14 28 28"><use href="#sparkle" /></svg>
        <svg class="sparkle s2" viewBox="-14 -14 28 28"><use href="#sparkle" /></svg>
        <svg class="sparkle s3" viewBox="-14 -14 28 28"><use href="#sparkle" /></svg>
        <svg class="sparkle s4" viewBox="-14 -14 28 28"><use href="#sparkle" /></svg>
        <svg class="sparkle s5" viewBox="-14 -14 28 28"><use href="#sparkle" /></svg>
        <svg class="sparkle s6" viewBox="-14 -14 28 28"><use href="#sparkle" /></svg>

        <div class="vertical-title">{{VERTICAL_TITLE}}</div>

        <div class="invite-frame">
          <div class="invite-frame-inner">
            <svg class="arc-svg" viewBox="0 0 320 70">
              <defs><path id="arcPath" d="M 24 58 Q 160 -8 296 58" fill="none" /></defs>
              <text class="arc-text">
                <textPath href="#arcPath">{{ARC_TEXT}}</textPath>
              </text>
            </svg>
            <h1 class="main-name">{{MAIN_NAME}}</h1>
            <p class="invite-sub">{{INVITE_SUB}}</p>
            {{DATE_CAPSULE}}
          </div>
        </div>

        <svg class="tiara" viewBox="0 0 60 44"><use href="#tiara" /></svg>

        {{POLAROIDS}}

        {{QUOTE}}{{COUNTDOWN}}<svg class="corner-svg bl small" viewBox="0 0 220 220"><use href="#corner-fl" transform="translate(0 220) scale(1 -1)" /></svg>
        <svg class="corner-svg br small" viewBox="0 0 220 220"><use href="#corner-fl" transform="translate(220 220) scale(-1 -1)" /></svg>
      </div>
    </div>

    <!-- ===== SECCIONES (orden del panel de capas) ===== -->
    {{FLOW_SECTIONS}}

  <!-- THANKS OVERLAY (RSVP) -->
  <div class="thanks-overlay" id="thanks-overlay" aria-hidden="true">
    <svg class="corner-svg tl" viewBox="0 0 220 220"><use href="#corner-fl" /></svg>
    <svg class="corner-svg tr" viewBox="0 0 220 220"><use href="#corner-fl" transform="translate(220 0) scale(-1 1)" /></svg>
    <svg class="corner-svg bl" viewBox="0 0 220 220"><use href="#corner-fl" transform="translate(0 220) scale(1 -1)" /></svg>
    <svg class="corner-svg br" viewBox="0 0 220 220"><use href="#corner-fl" transform="translate(220 220) scale(-1 -1)" /></svg>
    <svg class="garland top" viewBox="0 0 400 100"><use href="#garland" /></svg>
    <svg class="sparkle s1" viewBox="-14 -14 28 28"><use href="#sparkle" /></svg>
    <svg class="sparkle s2" viewBox="-14 -14 28 28"><use href="#sparkle" /></svg>
    <svg class="sparkle s4" viewBox="-14 -14 28 28"><use href="#sparkle" /></svg>
    <svg class="sparkle s5" viewBox="-14 -14 28 28"><use href="#sparkle" /></svg>
    <div class="petals-bg">
      <div class="petal"></div><div class="petal"></div><div class="petal"></div>
      <div class="petal"></div><div class="petal"></div>
    </div>
    <div class="thanks-card">
      <svg class="thanks-heart" viewBox="0 0 24 24"><use href="#heart" /></svg>
      <p class="thanks-script">¡Gracias!</p>
      <svg class="thanks-divider" viewBox="0 0 260 32"><use href="#divider" /></svg>
      <p class="thanks-sub">Tu confirmación fue enviada.<br />¡Nos vemos el <b>{{THANKS_DATE}}</b>! 💗</p>
    </div>
  </div>

  {{AUDIO}}
  {{MUSIC_BTN}}
''';

const String kReynaCootCss = r'''
*, *::before, *::after { margin: 0; padding: 0; box-sizing: border-box; }
    html { scroll-behavior: smooth; }
    body {
      font-family: 'Inter', sans-serif;
      background: #e8cfcd;
      color: #5a3f3b;
      overflow-x: hidden;
    }

    /* ===== REUSABLE SVG DECORATION POSITIONING ===== */
    .corner-svg {
      position: absolute;
      width: 150px; height: 150px;
      color: #a05c58;
      opacity: 0.65;
      pointer-events: none;
      z-index: 2;
    }
    .corner-svg.tl { top: 6px; left: 6px; }
    .corner-svg.tr { top: 6px; right: 6px; }
    .corner-svg.bl { bottom: 6px; left: 6px; }
    .corner-svg.br { bottom: 6px; right: 6px; }
    .corner-svg.small { width: 92px; height: 92px; opacity: 0.45; }

    /* Sparkles */
    .sparkle {
      position: absolute;
      color: #d9a95e;
      z-index: 3;
      pointer-events: none;
      animation: twinkle 3.2s ease-in-out infinite;
      opacity: 0.8;
    }
    .sparkle.s1 { top: 5%; left: 11%; width: 22px; animation-delay: 0.3s; }
    .sparkle.s2 { top: 17%; right: 9%; width: 15px; animation-delay: 1.2s; }
    .sparkle.s3 { bottom: 11%; left: 7%; width: 17px; animation-delay: 2s; }
    .sparkle.s4 { bottom: 7%; right: 12%; width: 24px; animation-delay: 0.9s; }
    .sparkle.s5 { top: 46%; right: 5%; width: 12px; animation-delay: 1.7s; }
    .sparkle.s6 { top: 50%; left: 4%; width: 13px; animation-delay: 2.5s; }
    @keyframes twinkle {
      0%, 100% { opacity: 0.12; transform: scale(0.45) rotate(0deg); }
      50% { opacity: 0.95; transform: scale(1.15) rotate(35deg); }
    }

    /* Garland (floral swag) */
    .garland {
      display: block; width: 100%; max-width: 560px;
      margin: 0 auto 1rem;
      color: #a05c58; opacity: 0.8;
      pointer-events: none;
    }
    .garland.top { position: absolute; top: -6px; left: 50%; transform: translateX(-50%); z-index: 3; }

    /* Section divider flourish */
    .section-divider {
      display: block; margin: 0 auto 1.1rem;
      width: 200px; color: #b76e79; opacity: 0.75;
    }

    /* Floating petals inside sections */
    .petals-bg {
      position: absolute; inset: 0;
      overflow: hidden; pointer-events: none; z-index: 0;
    }
    .petals-bg .petal {
      position: absolute;
      width: 15px; height: 15px;
      background: radial-gradient(ellipse, rgba(183,110,121,0.4), rgba(183,110,121,0.08));
      border-radius: 50% 0 50% 50%;
      animation: floatDrift linear infinite;
      opacity: 0;
    }
    @keyframes floatDrift {
      0% { transform: translate(0, 20px) rotate(0deg); opacity: 0; }
      20% { opacity: 0.5; }
      100% { transform: translate(36px, -180px) rotate(320deg); opacity: 0; }
    }
    .petals-bg .petal:nth-of-type(1) { left: 10%; animation-duration: 11s; animation-delay: 0s; }
    .petals-bg .petal:nth-of-type(2) { left: 38%; animation-duration: 14s; animation-delay: 2.5s; }
    .petals-bg .petal:nth-of-type(3) { left: 66%; animation-duration: 12s; animation-delay: 1s; }
    .petals-bg .petal:nth-of-type(4) { left: 86%; animation-duration: 15s; animation-delay: 4s; }
    .petals-bg .petal:nth-of-type(5) { left: 24%; animation-duration: 13s; animation-delay: 5.5s; }

    /* ===== ENVELOPE / COVER ===== */
    .envelope {
      min-height: 100vh;
      display: flex; flex-direction: column;
      align-items: center; justify-content: center;
      background: linear-gradient(170deg, #e8cfcd 0%, #f6e5e2 55%, #dfbfbc 100%);
      position: relative;
      overflow: hidden;
      cursor: pointer;
    }
    .envelope::before {
      content: '';
      position: absolute; inset: 0;
      background: radial-gradient(ellipse at 30% 20%, rgba(184,145,90,0.12) 0%, transparent 60%),
                  radial-gradient(ellipse at 70% 80%, rgba(183,110,121,0.12) 0%, transparent 60%);
      animation: breathe 6s ease-in-out infinite;
    }
    @keyframes breathe {
      0%, 100% { opacity: 0.7; }
      50% { opacity: 1; }
    }
    .envelope .corner-svg { opacity: 0.4; width: 200px; height: 200px; }
    .envelope .garland.top { color: #a05c58; opacity: 0.5; }
    .envelope .sparkle { color: rgba(217,169,94,0.9); }
    .envelope .sparkle.e1 { top: 20%; left: 24%; width: 20px; animation-delay: 0.6s; }
    .envelope .sparkle.e2 { top: 32%; right: 22%; width: 14px; animation-delay: 1.6s; }
    .envelope .sparkle.e3 { bottom: 22%; left: 30%; width: 16px; animation-delay: 2.4s; }
    .envelope .sparkle.e4 { bottom: 30%; right: 28%; width: 22px; animation-delay: 1s; }

    /* Floating petals (cover) */
    .petal {
      position: absolute;
      width: 20px; height: 20px;
      background: radial-gradient(ellipse, rgba(183,110,121,0.45), rgba(183,110,121,0.1));
      border-radius: 50% 0 50% 50%;
      opacity: 0;
    }
    .envelope > .petal { animation: floatPetal linear infinite; }
    @keyframes floatPetal {
      0% { transform: translateY(100vh) rotate(0deg) scale(0.5); opacity: 0; }
      10% { opacity: 0.6; }
      90% { opacity: 0.6; }
      100% { transform: translateY(-10vh) rotate(360deg) scale(1); opacity: 0; }
    }
    .envelope > .petal:nth-of-type(1) { left: 10%; animation-duration: 12s; animation-delay: 0s; width: 15px; height: 15px; }
    .envelope > .petal:nth-of-type(2) { left: 25%; animation-duration: 15s; animation-delay: 2s; width: 18px; height: 18px; }
    .envelope > .petal:nth-of-type(3) { left: 45%; animation-duration: 11s; animation-delay: 4s; width: 12px; height: 12px; }
    .envelope > .petal:nth-of-type(4) { left: 65%; animation-duration: 14s; animation-delay: 1s; width: 20px; height: 20px; }
    .envelope > .petal:nth-of-type(5) { left: 80%; animation-duration: 13s; animation-delay: 3s; width: 16px; height: 16px; }
    .envelope > .petal:nth-of-type(6) { left: 90%; animation-duration: 16s; animation-delay: 5s; width: 14px; height: 14px; }

    .envelope-content { position: relative; z-index: 2; text-align: center; padding: 2rem; }
    .envelope-icon {
      font-size: 3rem; margin-bottom: 1rem;
      animation: pulse 2s ease-in-out infinite;
      filter: drop-shadow(0 8px 18px rgba(183,110,121,0.35));
    }
    @keyframes pulse { 0%, 100% { transform: scale(1) rotate(0deg); } 50% { transform: scale(1.12) rotate(-3deg); } }
    .envelope-text {
      font-family: 'Cormorant Garamond', serif;
      font-size: 1.2rem; font-weight: 600; color: #66443f;
      letter-spacing: 4px; text-transform: uppercase;
      margin-bottom: 0.5rem;
    }
    .envelope-name {
      font-family: 'Great Vibes', cursive;
      font-size: 2.4rem; color: #9c4a55;
      letter-spacing: 1px;
      margin-top: 0.3rem;
      filter: drop-shadow(0 4px 12px rgba(183,110,121,0.25));
    }
    .envelope-date {
      font-family: 'Cormorant Garamond', serif;
      font-weight: 600; font-size: 0.95rem;
      letter-spacing: 4px; text-transform: uppercase;
      color: #85541c; margin-top: 0.9rem;
      animation: fadeInUp 1s ease 0.4s both;
    }
    .envelope-date::before, .envelope-date::after {
      content: '✦'; margin: 0 0.6rem; color: #c98a5e; font-size: 0.6rem;
    }
    .envelope-tap {
      font-family: 'Inter', sans-serif;
      font-size: 1rem; font-weight: 600;
      color: #9c4a55;
      margin-top: 1.6rem;
      animation: fadeInUp 1s ease 1s both;
    }
    @keyframes fadeInUp { from { opacity: 0; transform: translateY(15px); } to { opacity: 1; transform: translateY(0); } }

    /* ===== INVITATION ===== */
    .invitation { display: none; }
    .invitation.open { display: block; }

    .section { padding: 5rem 1.2rem; position: relative; }
    .section.animate { opacity: 0; transform: translateY(40px); }
    .section.visible { opacity: 1; transform: translateY(0); transition: opacity 0.8s ease, transform 0.8s ease; }

    .ornament {
      display: flex; align-items: center; gap: 0.9rem;
      margin-bottom: 1.6rem; justify-content: center;
    }
    .ornament-line { width: 56px; height: 1px; background: linear-gradient(90deg, transparent, #b76e79, transparent); }
    .ornament-diamond { width: 7px; height: 7px; background: #b8915a; transform: rotate(45deg); }

    /* ===== MAIN INVITATION CARD ===== */
    .main-card-section {
      background:
        radial-gradient(ellipse at 20% 10%, rgba(255,255,255,0.35) 0%, transparent 55%),
        linear-gradient(180deg, #e8cfcd 0%, #f4e2df 40%, #e8cfcd 100%);
      padding: 4.5rem 1rem 5rem;
    }
    .main-card {
      position: relative; z-index: 1;
      max-width: 520px;
      margin: 0 auto;
      background: linear-gradient(180deg, #f9ecea 0%, #f3dfdc 100%);
      border: 1px solid rgba(160,92,88,0.45);
      box-shadow: 0 30px 70px rgba(120,60,55,0.20);
      padding: 3.4rem 2.1rem 3.8rem;
      transition: transform 0.25s ease-out, box-shadow 0.25s ease-out;
    }
    .main-card::after {
      content: '';
      position: absolute; inset: 6px;
      border: 1px solid rgba(160,92,88,0.18);
      pointer-events: none;
    }

    /* Vertical title on left edge */
    .vertical-title {
      position: absolute; left: 13px; top: 50%;
      transform: translateY(-50%) rotate(180deg);
      writing-mode: vertical-rl;
      font-family: 'Cormorant Garamond', serif;
      font-weight: 600; font-size: 0.8rem; letter-spacing: 5px;
      color: #8f4946; text-transform: uppercase;
      z-index: 3;
    }
    .vertical-title::before, .vertical-title::after {
      content: '✦'; display: block; color: #c98a5e;
      font-size: 0.55rem; letter-spacing: 0;
    }

    /* Top frame with curved title */
    .invite-frame { border: 1px solid rgba(160,92,88,0.55); border-radius: 18px; padding: 7px; }
    .invite-frame-inner {
      border: 1px solid rgba(160,92,88,0.28);
      border-radius: 12px;
      padding: 2rem 1.3rem 1.9rem;
      text-align: center;
    }
    .arc-svg { width: 100%; height: auto; display: block; }
    .arc-text { font-family: 'Cormorant Garamond', serif; font-weight: 600; font-size: 18px; letter-spacing: 5px; fill: #8f4946; }
    .main-name {
      font-family: 'Great Vibes', cursive;
      font-size: clamp(3.9rem, 15vw, 5.6rem);
      line-height: 1.05;
      margin: 0.5rem 0 0.3rem;
      background: linear-gradient(90deg, #b76e79 0%, #c98a5e 30%, #e0b060 50%, #c98a5e 70%, #b76e79 100%);
      background-size: 200% auto;
      -webkit-background-clip: text; background-clip: text;
      -webkit-text-fill-color: transparent; color: transparent;
      animation: shimmer 5s linear infinite;
      filter: drop-shadow(0 4px 14px rgba(183,110,121,0.35));
      display: flex;
      align-items: center;
      justify-content: center;
      block-size: 110px;
    }
    @keyframes shimmer { to { background-position: -200% center; } }
    .invite-sub {
      font-family: 'Cormorant Garamond', serif;
      font-style: italic; font-weight: 600;
      font-size: 1.22rem;
      color: #66443f;
    }

    /* Date capsule (two-row, never wraps) */
    .date-capsule {
      display: inline-block;
      margin-top: 1.7rem;
      padding: 1rem 2rem 1.1rem;
      border: 1px solid rgba(160,92,88,0.55);
      border-radius: 22px;
      background: rgba(255,255,255,0.5);
      box-shadow: 0 6px 18px rgba(160,92,88,0.12);
      text-align: center;
    }
    .dc-day {
      display: flex; align-items: center; justify-content: center; gap: 0.8rem;
      font-family: 'Cormorant Garamond', serif; font-weight: 600;
      font-size: 1.05rem; letter-spacing: 5px; color: #4e3834;
      white-space: nowrap;
    }
    .dc-flourish { font-size: 0.6rem; color: #c98a5e; letter-spacing: 0; }
    .dc-row {
      display: flex; align-items: center; justify-content: center;
      gap: 0.85rem; margin-top: 0.55rem; white-space: nowrap;
    }
    .dc-circle {
      width: 46px; height: 46px;
      border-radius: 50%;
      background: linear-gradient(135deg, #d9a95e, #b8915a);
      color: #fff;
      font-family: 'Playfair Display', serif;
      font-weight: 700; font-size: 1.35rem;
      line-height: 1;
      display: inline-flex; align-items: center; justify-content: center;
      box-shadow: 0 4px 12px rgba(184,145,90,0.4);
      animation: glowPulse 3s ease-in-out infinite;
    }
    @keyframes glowPulse {
      0%, 100% { box-shadow: 0 4px 12px rgba(184,145,90,0.4); }
      50% { box-shadow: 0 4px 22px rgba(217,169,94,0.75); }
    }
    .dc-rest {
      font-family: 'Cormorant Garamond', serif; font-weight: 600;
      font-size: 1.08rem; letter-spacing: 2.5px; color: #4e3834;
      white-space: nowrap;
    }
    .dc-rest .dc-dot { color: #c98a5e; margin: 0 0.2rem; }

    /* Tiara */
    .tiara { width: 92px; margin: 1.5rem auto 0; color: #b8915a; display: block; animation: floatGentle 3.5s ease-in-out infinite; }
    @keyframes floatGentle {
      0%, 100% { transform: translateY(0) rotate(-2deg); }
      50% { transform: translateY(-5px) rotate(2deg); }
    }

    /* Polaroid photos */
    .polaroids {
      display: flex; justify-content: center; align-items: flex-start;
      gap: 1.1rem;
      margin: 2.2rem auto 0;
      padding: 0 0.4rem;
    }
    .polaroid {
      background: #fff;
      padding: 7px 7px 24px;
      box-shadow: 0 14px 30px rgba(120,60,55,0.20);
      line-height: 0;
      transition: transform 0.45s cubic-bezier(0.2, 0.7, 0.3, 1.15), box-shadow 0.45s ease;
      will-change: transform;
    }
    .polaroid img { width: 100%; aspect-ratio: 3 / 4; object-fit: cover; display: block; }
    .polaroid.p1 { width: 30%; transform: rotate(-7deg); }
    .polaroid.p2 { width: 34%; transform: rotate(3deg) translateY(-14px); z-index: 1; }
    .polaroid.p3 { width: 30%; transform: rotate(6deg); }
    .polaroid:hover {
      transform: rotate(0deg) translateY(-12px) scale(1.06);
      box-shadow: 0 26px 48px rgba(120,60,55,0.30);
      z-index: 5;
    }

    /* Quote box */
    .quote-box {
      position: relative;
      margin: 2.6rem auto 0;
      max-width: 410px;
      border: 1px solid rgba(160,92,88,0.45);
      border-radius: 26px;
      background: rgba(255,255,255,0.5);
      padding: 2rem 1.7rem 1.9rem;
      text-align: center;
    }
    .quote-rose {
      position: absolute; top: -24px; left: 50%;
      transform: translateX(-50%);
      width: 52px; color: #b76e79;
      background: #f3dfdc;
      border-radius: 50%;
      padding: 2px;
    }
    .quote-text {
      font-family: 'Cormorant Garamond', serif;
      font-style: italic; font-size: 1.15rem;
      line-height: 1.9; color: #4e3834;
    }

    /* Countdown */
    .countdown-wrap { margin-top: 2.8rem; text-align: center; }
    .script-faltan { font-family: 'Great Vibes', cursive; font-size: 2.3rem; color: #9c4a55; filter: drop-shadow(0 3px 10px rgba(183,110,121,0.2)); }
    .countdown-box {
      margin-top: 1rem;
      border: 1px solid rgba(160,92,88,0.5);
      border-radius: 16px;
      background: rgba(255,255,255,0.42);
      display: flex; justify-content: center; align-items: flex-start;
      padding: 1.4rem 0.8rem;
      gap: 0.4rem;
    }
    .cd-item { display: flex; flex-direction: column; align-items: center; min-width: 60px; }
    .cd-num {
      font-family: 'Playfair Display', serif; font-size: 2.4rem; font-weight: 700;
      color: #85541c; line-height: 1;
      min-width: 2ch; text-align: center; display: inline-block;
    }
    .cd-num.tick { animation: tickPop 0.45s ease; }
    @keyframes tickPop {
      0% { transform: scale(1); }
      35% { transform: scale(1.22); color: #c98a5e; }
      100% { transform: scale(1); }
    }
    .cd-label { font-size: 0.72rem; font-weight: 600; letter-spacing: 2px; color: #66443f; text-transform: uppercase; margin-top: 0.55rem; }
    .cd-sep { font-family: 'Playfair Display', serif; font-size: 2rem; color: rgba(133,84,28,0.65); margin-top: 0.15rem; animation: sepBlink 1s steps(2, start) infinite; }
    @keyframes sepBlink { 50% { opacity: 0.35; } }

    /* ===== FAMILIES ===== */
    .families-section { background: #f4e2df; overflow: hidden; }
    .families-title {
      font-family: 'Great Vibes', cursive;
      font-size: clamp(2.6rem, 9vw, 3.6rem);
      color: #9c4a55; text-align: center;
      margin-bottom: 2.4rem;
      position: relative; z-index: 1;
    }
    .families-grid { display: grid; grid-template-columns: 1fr 1fr; gap: 1.6rem; max-width: 580px; margin: 0 auto; position: relative; z-index: 1; }
    .family-card {
      position: relative;
      background: #f9ecea;
      border: 1px solid rgba(160,92,88,0.35);
      border-radius: 16px;
      padding: 2.4rem 1.5rem 2rem;
      text-align: center;
      box-shadow: 0 10px 26px rgba(120,60,55,0.10);
      transition: transform 0.35s ease, box-shadow 0.35s ease;
    }
    .family-card:hover { transform: translateY(-6px); box-shadow: 0 18px 36px rgba(120,60,55,0.18); }
    .family-card h3 {
      font-family: 'Cormorant Garamond', serif;
      font-weight: 600; font-size: 0.95rem; letter-spacing: 3px;
      text-transform: uppercase; color: #9c4a55;
      margin-bottom: 0.4rem;
    }
    .family-heart { width: 24px; margin: 0.3rem auto 0.9rem; color: #c98a5e; display: block; animation: heartbeat 1.8s ease-in-out infinite; }
    .family-card .name { font-family: 'Great Vibes', cursive; font-size: 1.75rem; color: #4e3834; line-height: 1.75; }

    /* ===== DETAILS ===== */
    .details-section { background: #e8cfcd; padding: 4.5rem 1.2rem 5.5rem; overflow: hidden; }
    .details-title {
      font-family: 'Great Vibes', cursive;
      font-size: clamp(3.2rem, 11vw, 4.4rem);
      color: #9c4a55; text-align: center;
      margin-bottom: 0.6rem;
      position: relative; z-index: 1;
    }
    .details-sub {
      font-family: 'Cormorant Garamond', serif;
      font-style: italic; font-weight: 600; font-size: 1.22rem;
      color: #66443f; text-align: center;
      margin-bottom: 2.6rem;
      position: relative; z-index: 1;
    }
    .details-list { max-width: 440px; margin: 0 auto; display: flex; flex-direction: column; gap: 2.4rem; position: relative; z-index: 1; }
    .detail-card {
      position: relative;
      background: linear-gradient(180deg, #f9ecea, #f3dfdc);
      border: 1px solid rgba(160,92,88,0.45);
      border-radius: 18px;
      padding: 2.8rem 1.8rem 2.3rem;
      text-align: center;
      box-shadow: 0 14px 34px rgba(120,60,55,0.14);
      transition: transform 0.35s ease, box-shadow 0.35s ease;
    }
    .detail-card:hover { transform: translateY(-6px); box-shadow: 0 22px 44px rgba(120,60,55,0.20); }
    .ribbon { position: absolute; top: -14px; left: 50%; transform: translateX(-50%); width: 66px; color: #b76e79; z-index: 3; }
    .detail-title { font-family: 'Great Vibes', cursive; font-size: 2.35rem; color: #9c4a55; margin-bottom: 0.9rem; }
    .detail-illustration { width: 108px; margin: 0.2rem auto 1rem; color: #b76e79; display: block; }
    .detail-time { font-family: 'Playfair Display', serif; font-weight: 700; font-size: 1.65rem; color: #9c4a55; }
    .detail-place { font-family: 'Cormorant Garamond', serif; font-weight: 600; font-size: 1.2rem; color: #4e3834; margin-top: 0.2rem; }
    .detail-upper {
      font-family: 'Cormorant Garamond', serif;
      font-weight: 600; font-size: 1.05rem;
      letter-spacing: 2.5px; text-transform: uppercase;
      color: #4e3834; margin-bottom: 0.5rem;
    }
    .detail-script { font-family: 'Great Vibes', cursive; font-size: 2.2rem; color: #9c4a55; }
    .detail-text {
      font-family: 'Cormorant Garamond', serif;
      font-style: italic; font-size: 1.15rem;
      line-height: 1.9; color: #4e3834;
      max-width: 340px; margin: 0.2rem auto 1.2rem;
    }
    .detail-note {
      font-family: 'Cormorant Garamond', serif;
      font-style: italic; font-weight: 600;
      font-size: 1.08rem; line-height: 1.5;
      color: #9c4a55;
      max-width: 300px; margin: 1rem auto 0;
    }
    /* Suggested colors swatches */
    .swatch-label {
      display: block; margin-top: 1.1rem;
      font-size: 0.72rem; font-weight: 600; letter-spacing: 2px;
      color: #66443f; text-transform: uppercase;
    }
    .swatches { display: flex; justify-content: center; gap: 0.8rem; margin-top: 0.8rem; }
    .swatch {
      width: 26px; height: 26px; border-radius: 50%;
      border: 2px solid rgba(255,255,255,0.85);
      box-shadow: 0 3px 8px rgba(120,60,55,0.25);
      transition: transform 0.3s ease;
      cursor: default;
    }
    .swatch:hover { transform: scale(1.2); }

    .btn {
      display: inline-block;
      position: relative; overflow: hidden;
      margin-top: 1.3rem;
      padding: 0.85rem 2.4rem;
      border-radius: 999px;
      background: linear-gradient(135deg, #b76e79, #a2555f);
      color: #fff;
      font-size: 0.9rem; font-weight: 600;
      letter-spacing: 2px; text-transform: uppercase;
      text-decoration: none;
      box-shadow: 0 10px 24px rgba(183,110,121,0.4);
      transition: transform 0.3s ease, box-shadow 0.3s ease, background 0.3s ease;
      cursor: pointer; border: none; font-family: 'Inter', sans-serif;
    }
    .btn::after {
      content: '';
      position: absolute; top: 0; left: -130%;
      width: 55%; height: 100%;
      background: linear-gradient(100deg, transparent, rgba(255,255,255,0.45), transparent);
      transform: skewX(-20deg);
      transition: left 0.6s ease;
    }
    .btn:hover { transform: translateY(-3px); box-shadow: 0 14px 30px rgba(183,110,121,0.5); background: linear-gradient(135deg, #a95f6a, #91464f); }
    .btn:hover::after { left: 150%; }
    .btn:active { transform: translateY(0) scale(0.97); }
    .butterfly { position: absolute; bottom: 14px; right: 16px; width: 54px; color: #a05c58; opacity: 0.75; animation: flutter 4s ease-in-out infinite; transform-origin: 50% 60%; }
    @keyframes flutter {
      0%, 100% { transform: rotate(-3deg) translateY(0); }
      50% { transform: rotate(4deg) translateY(-6px); }
    }

    /* ===== HASHTAG BAND ===== */
    .hashtag-section {
      background: linear-gradient(90deg, #b76e79 0%, #c98a5e 50%, #b76e79 100%);
      background-size: 200% auto;
      animation: shimmer 8s linear infinite;
      padding: 2.6rem 1.2rem;
      text-align: center;
      position: relative; overflow: hidden;
    }
    .hashtag-section .sparkle { color: rgba(255,255,255,0.9); }
    .hashtag-script {
      font-family: 'Great Vibes', cursive;
      color: #fff; font-size: 1.9rem;
      text-shadow: 0 2px 8px rgba(120,60,55,0.4);
      display: block; margin-bottom: 0.2rem;
    }
    .hashtag-text {
      font-family: 'Cormorant Garamond', serif;
      font-weight: 600; letter-spacing: 5px;
      color: #fff; font-size: clamp(1.3rem, 4.8vw, 1.7rem);
      text-shadow: 0 2px 8px rgba(120,60,55,0.35);
      text-transform: uppercase;
      position: relative; z-index: 1;
    }

    /* ===== ITINERARY ===== */
    .itinerary-section { background: #f4e2df; padding-bottom: 5.5rem; overflow: hidden; }
    .itinerary-title {
      font-family: 'Playfair Display', serif;
      font-size: clamp(1.7rem, 6vw, 2.3rem);
      color: #5a3f3b; text-align: center;
      margin-bottom: 3rem;
      position: relative; z-index: 1;
    }
    .timeline { max-width: 460px; margin: 0 auto; position: relative; padding-left: 3rem; z-index: 1; }
    .timeline::before {
      content: '';
      position: absolute; left: 13px; top: 6px; bottom: 6px;
      width: 1px;
      background: linear-gradient(180deg, transparent, #b8915a 20%, #b76e79 80%, transparent);
    }
    .timeline-item { position: relative; padding: 1.15rem 0; }
    .timeline-item.animate { opacity: 0; transform: translateX(-20px); }
    .timeline-item.visible { opacity: 1; transform: translateX(0); transition: opacity 0.6s ease, transform 0.6s ease; }
    .timeline-dot {
      position: absolute; left: -3rem; top: 1.4rem;
      width: 9px; height: 9px;
      background: #b8915a; color: #b8915a;
      border-radius: 50%;
      transform: translateX(50%);
      box-shadow: 0 0 0 4px rgba(184,145,90,0.18);
    }
    .timeline-dot::after {
      content: '';
      position: absolute; inset: -3px;
      border-radius: 50%;
      border: 1px solid currentColor;
      animation: pulseRing 2.4s ease-out infinite;
    }
    @keyframes pulseRing {
      0% { transform: scale(0.5); opacity: 0.7; }
      100% { transform: scale(2.3); opacity: 0; }
    }
    .timeline-item:nth-child(even) .timeline-dot { background: #b76e79; color: #b76e79; box-shadow: 0 0 0 4px rgba(183,110,121,0.16); }
    .timeline-time { font-family: 'Playfair Display', serif; font-size: 1.25rem; font-weight: 700; color: #85541c; }
    .timeline-event { font-family: 'Cormorant Garamond', serif; font-weight: 600; font-size: 1.2rem; color: #4e3834; margin-top: 0.2rem; }

    /* ===== FOOTER ===== */
    .footer-section {
      background: linear-gradient(180deg, #e8cfcd 0%, #dfbfbc 100%);
      padding: 4.5rem 1.5rem 4rem;
      text-align: center;
      position: relative;
      overflow: hidden;
    }
    .footer-hearts { font-size: 1.8rem; margin-bottom: 1.2rem; animation: heartbeat 1.5s ease-in-out infinite; }
    @keyframes heartbeat {
      0%, 100% { transform: scale(1); }
      15% { transform: scale(1.15); }
      30% { transform: scale(1); }
      45% { transform: scale(1.1); }
    }
    .footer-names { font-family: 'Great Vibes', cursive; font-size: clamp(2.4rem, 8vw, 3.8rem); color: #9c4a55; }
    .footer-message {
      font-family: 'Cormorant Garamond', serif;
      font-weight: 600;
      font-style: italic; font-size: 1.2rem;
      color: #66443f; max-width: 460px;
      line-height: 1.85; margin: 1rem auto 0;
    }
    .footer-share { margin-top: 2rem; display: flex; gap: 1rem; justify-content: center; }
    .share-btn {
      width: 50px; height: 50px;
      border: 1px solid rgba(183,110,121,0.4);
      background: rgba(255,255,255,0.65);
      border-radius: 50%;
      display: flex; align-items: center; justify-content: center;
      font-size: 1.3rem; cursor: pointer;
      transition: all 0.3s ease;
    }
    .share-btn:hover { background: #b76e79; border-color: #b76e79; transform: translateY(-3px) scale(1.05); }
    .footer-credit {
      display: flex;
      align-items: center;
      justify-content: center;
      flex-wrap: wrap;
      gap: 0.6rem;
      margin: 2.2rem auto 0;
      padding: 1.2rem 1.4rem 0;
      max-width: 460px;
      border-top: 1px solid rgba(183, 110, 121, 0.25);
      font-family: 'Cormorant Garamond', serif;
      font-style: italic;
      font-weight: 600;
      font-size: 1.15rem;
      color: #66443f;
    }
    .footer-credit-heart { font-size: 1rem; animation: heartbeat 1.5s ease-in-out infinite; display: inline-block; }
    .footer-credit-brand {
      font-family: 'Playfair Display', serif;
      font-style: normal;
      font-weight: 600;
      font-size: 1.1rem;
      color: #a05c58;
      text-decoration: none;
      letter-spacing: 0.04em;
      position: relative;
      transition: color 0.3s ease;
      padding: 0.1rem 0.2rem;
    }
    .footer-credit-brand::after {
      content: "";
      position: absolute;
      left: 0.2rem; right: 0.2rem; bottom: 0;
      height: 1px;
      background: linear-gradient(90deg, #d9a95e, #b76e79);
      transform: scaleX(0.6);
      opacity: 0.5;
      transition: transform 0.3s ease, opacity 0.3s ease;
    }
    .footer-credit-brand:hover {
      color: #8b4347;
      transform: translateY(-1px);
    }
    .footer-credit-brand:hover::after {
      transform: scaleX(1);
      opacity: 1;
    }
    .footer-watermark {
      font-family: 'Great Vibes', cursive;
      font-size: clamp(7rem, 34vw, 13rem);
      color: rgba(156,85,82,0.13);
      line-height: 1;
      margin-top: 2.2rem;
      pointer-events: none;
      user-select: none;
    }

    /* ===== MUSIC TOGGLE ===== */
    #bg-music { display: none; }
    .music-btn {
      position: fixed;
      right: 16px; bottom: 16px;
      z-index: 1000;
      width: 50px; height: 50px;
      border-radius: 50%;
      border: 1px solid rgba(183,110,121,0.4);
      background: rgba(255,255,255,0.85);
      color: #b76e79;
      font-size: 1.25rem;
      display: none;
      align-items: center; justify-content: center;
      cursor: pointer;
      box-shadow: 0 8px 22px rgba(120,60,55,0.28);
      transition: transform 0.3s ease, background 0.3s ease;
      backdrop-filter: blur(4px);
    }
    .music-btn:hover { transform: scale(1.1); background: #fff; }
    .music-btn.playing { animation: pulseTone 2.4s ease-in-out infinite; }
    @keyframes pulseTone {
      0%, 100% { box-shadow: 0 8px 22px rgba(120,60,55,0.28); }
      50% { box-shadow: 0 8px 26px rgba(183,110,121,0.5); }
    }

    /* ===== CONFETTI ===== */
    .confetti-piece {
      position: fixed; z-index: 3300;
      pointer-events: none;
      top: 0; left: 0;
      border-radius: 2px;
      animation: confettiFly 1.6s ease-out forwards;
    }
    @keyframes confettiFly {
      0% { transform: translate(0, 0) rotate(0deg); opacity: 1; }
      100% { transform: translate(var(--dx), var(--dy)) rotate(var(--rot)); opacity: 0; }
    }

    /* ===== THANKS OVERLAY (RSVP) ===== */
    body.no-scroll { overflow: hidden; }
    .thanks-overlay {
      position: fixed; inset: 0;
      z-index: 3000;
      display: flex; align-items: center; justify-content: center;
      padding: 1.5rem;
      background:
        radial-gradient(ellipse at 28% 18%, rgba(217,169,94,0.20), transparent 55%),
        radial-gradient(ellipse at 75% 85%, rgba(183,110,121,0.22), transparent 55%),
        linear-gradient(165deg, #dfbfbc 0%, #e8cfcd 40%, #f6e5e2 70%, #e2c4c0 100%);
      opacity: 0; visibility: hidden;
      transition: opacity 0.45s ease, visibility 0.45s ease;
      overflow: hidden;
    }
    .thanks-overlay.show { opacity: 1; visibility: visible; }
    .thanks-overlay .corner-svg { width: 190px; height: 190px; opacity: 0.5; }
    .thanks-overlay .garland.top { color: #a05c58; opacity: 0.55; }
    .thanks-overlay .sparkle { color: rgba(217,169,94,0.95); }
    .thanks-overlay .petals-bg { z-index: 1; }

    .thanks-card {
      position: relative; z-index: 2;
      width: 100%; max-width: 380px;
      background: linear-gradient(180deg, #fdf6f3 0%, #f7e9e6 100%);
      border: 1px solid rgba(160,92,88,0.5);
      border-radius: 26px;
      padding: 3rem 2.2rem 2.8rem;
      text-align: center;
      box-shadow: 0 34px 80px rgba(120,60,55,0.35);
      transform: scale(0.7);
      opacity: 0;
      transition: transform 0.55s cubic-bezier(0.18, 0.9, 0.28, 1.25), opacity 0.4s ease;
    }
    .thanks-card::after {
      content: '';
      position: absolute; inset: 7px;
      border: 1px solid rgba(160,92,88,0.25);
      border-radius: 20px;
      pointer-events: none;
    }
    .thanks-overlay.show .thanks-card { transform: scale(1); opacity: 1; }

    .thanks-heart {
      width: 54px; margin: 0 auto 0.4rem; display: block;
      color: #b76e79;
      filter: drop-shadow(0 6px 14px rgba(183,110,121,0.4));
      opacity: 0; transform: scale(0.3) rotate(-14deg);
    }
    .thanks-overlay.show .thanks-heart {
      opacity: 1; transform: scale(1) rotate(0deg);
      transition: transform 0.5s cubic-bezier(0.18, 0.9, 0.28, 1.3) 0.25s, opacity 0.35s ease 0.25s;
      animation: heartbeat 1.7s ease-in-out 1s infinite;
    }
    .thanks-script {
      font-family: 'Great Vibes', cursive;
      font-size: clamp(3.4rem, 14vw, 4.6rem);
      line-height: 1.1;
      background: linear-gradient(90deg, #b76e79 0%, #c98a5e 30%, #e0b060 50%, #c98a5e 70%, #b76e79 100%);
      background-size: 200% auto;
      -webkit-background-clip: text; background-clip: text;
      -webkit-text-fill-color: transparent; color: transparent;
      filter: drop-shadow(0 5px 16px rgba(183,110,121,0.35));
      opacity: 0; transform: scale(0.5);
    }
    .thanks-overlay.show .thanks-script {
      opacity: 1; transform: scale(1);
      transition: transform 0.55s cubic-bezier(0.18, 0.9, 0.28, 1.3) 0.4s, opacity 0.4s ease 0.4s;
      animation: shimmer 4s linear 0.6s infinite;
    }
    .thanks-divider {
      width: 150px; margin: 0.7rem auto 0.9rem;
      display: block; color: #b8915a;
      opacity: 0;
    }
    .thanks-overlay.show .thanks-divider { opacity: 0.8; transition: opacity 0.5s ease 0.7s; }
    .thanks-sub {
      font-family: 'Cormorant Garamond', serif;
      font-style: italic; font-weight: 600; font-size: 1.22rem;
      line-height: 1.85; color: #4e3834;
      opacity: 0; transform: translateY(10px);
    }
    .thanks-sub b { font-family: 'Playfair Display', serif; font-weight: 700; color: #b76e79; }
    .thanks-overlay.show .thanks-sub {
      opacity: 1; transform: translateY(0);
      transition: opacity 0.6s ease 0.85s, transform 0.6s ease 0.85s;
    }

    /* Pretty burst particles */
    .pretty-piece {
      position: fixed; z-index: 3300;
      pointer-events: none;
      top: 0; left: 0;
      line-height: 1;
      animation: prettyFly var(--dur, 1.8s) cubic-bezier(0.15, 0.6, 0.35, 1) forwards;
      animation-delay: var(--del, 0s);
    }
    @keyframes prettyFly {
      0% { transform: translate(0, 0) rotate(0deg) scale(0.5); opacity: 0; }
      10% { opacity: 1; }
      100% { transform: translate(var(--dx), var(--dy)) rotate(var(--rot)) scale(var(--sc, 1)); opacity: 0; }
    }
    .pretty-heart { color: #b76e79; }
    .pretty-heart.alt { color: #c07d86; }
    .pretty-spark {
      color: #d9a95e;
      text-shadow: 0 0 6px rgba(217,169,94,0.85);
    }
    .pretty-petal {
      background: radial-gradient(ellipse, rgba(183,110,121,0.75), rgba(183,110,121,0.15));
      border-radius: 50% 0 50% 50%;
    }
    .pretty-confetti { border-radius: 2px; }

    /* ===== RESPONSIVE ===== */
    @media (max-width: 520px) {
      .main-card { padding: 3rem 1.5rem 3.4rem; }
      .vertical-title { left: 7px; font-size: 0.72rem; letter-spacing: 4px; }
      .cd-num { font-size: 2rem; }
      .cd-item { min-width: 52px; }
      .corner-svg { width: 120px; height: 120px; }
      .families-grid { grid-template-columns: 1fr; }
    }
    @media (max-width: 380px) {
      .date-capsule { padding: 0.85rem 1.3rem 1rem; }
      .dc-day { font-size: 0.98rem; letter-spacing: 3px; gap: 0.6rem; }
      .dc-rest { font-size: 1.02rem; letter-spacing: 1.5px; }
      .dc-row { gap: 0.6rem; }
      .dc-circle { width: 40px; height: 40px; font-size: 1.15rem; }
      .polaroids { gap: 0.7rem; }
    }
    @media (prefers-reduced-motion: reduce) {
      *, *::before, *::after {
        animation-duration: 0.01ms !important;
        animation-iteration-count: 1 !important;
        transition-duration: 0.01ms !important;
      }
    }''';

const String kReynaCootJs = r'''
// ===== OPEN INVITATION =====
    function openInvitation() {
      const envelope = document.getElementById('envelope');
      const invitation = document.getElementById('invitation');
      if (!envelope || envelope.classList.contains('opening')) return;
      const isCarta = document.body.classList.contains('hs-cover-carta');
      const revealAt = isCarta ? 2000 : 1750;
      const hideAt = isCarta ? 2900 : 2650;
      envelope.classList.add('opening');
      startMusic();
      // La portada de Carta necesita tiempo para abrir la solapa y sacar la
      // carta. Las demás portadas también respiran antes de despedirse.
      let contentOpen = false;
      const revealContent = () => {
        if (contentOpen) return;
        contentOpen = true;
        invitation.classList.add('open');
        window.scrollTo(0, 0);
        observeSections();
        startCountdown();
      };
      envelope.style.transition = 'opacity 0.7s ease, transform 0.7s ease';
      setTimeout(() => {
        // Carta: la invitación ya está detrás cuando el sobre se desvanece.
        if (isCarta) revealContent();
        envelope.style.opacity = '0';
        envelope.style.transform = isCarta ? 'none' : 'scale(0.96)';
      }, revealAt);
      setTimeout(() => {
        envelope.style.display = 'none';
        if (!isCarta) revealContent();
        burstConfetti();
      }, hideAt);
    }

    // ===== MUSIC =====
    function startMusic() {
      const audio = document.getElementById('bg-music');
      const btn = document.getElementById('music-btn');
      if (btn) btn.style.display = 'flex';
      if (!audio) return;
      audio.volume = 0.55;
      audio.play().then(() => {
        if (btn) btn.classList.add('playing');
      }).catch(() => {});
    }
    function toggleMusic() {
      const audio = document.getElementById('bg-music');
      const btn = document.getElementById('music-btn');
      if (!audio) return;
      if (audio.paused) {
        audio.play().then(() => {
          if (btn) { btn.classList.add('playing'); btn.textContent = '🎵'; }
        }).catch(() => {});
      } else {
        audio.pause();
        if (btn) { btn.classList.remove('playing'); btn.textContent = '🔇'; }
      }
    }

    // ===== SCROLL REVEAL =====
    function observeSections() {
      document.querySelectorAll('.section').forEach(s => s.classList.add('animate'));
      document.querySelectorAll('.timeline-item').forEach(s => s.classList.add('animate'));

      const observer = new IntersectionObserver((entries) => {
        entries.forEach(entry => {
          if (entry.isIntersecting) entry.target.classList.add('visible');
        });
      }, { threshold: 0.12 });
      document.querySelectorAll('.section').forEach(s => observer.observe(s));

      const tlObserver = new IntersectionObserver((entries) => {
        entries.forEach(entry => {
          if (entry.isIntersecting) entry.target.classList.add('visible');
        });
      }, { threshold: 0.2 });
      document.querySelectorAll('.timeline-item').forEach((item, i) => {
        item.style.transitionDelay = (i * 0.12) + 's';
        tlObserver.observe(item);
      });
    }

    // ===== COUNTDOWN =====
    function startCountdown() {
      const target = new Date((window.__HS_INV && window.__HS_INV.event) || '2026-10-10T19:30:00').getTime();
      function setNum(id, val) {
        const el = document.getElementById(id);
        const pad = String(val).padStart(2, '0');
        if (el.textContent !== pad) {
          el.textContent = pad;
          el.classList.remove('tick');
          void el.offsetWidth; // restart animation
          el.classList.add('tick');
        }
      }
      function update() {
        const now = Date.now();
        let diff = target - now;
        if (diff <= 0) {
          setNum('days', 0);
          setNum('hours', 0);
          setNum('minutes', 0);
          setNum('seconds', 0);
          return;
        }
        const d = Math.floor(diff / 86400000); diff %= 86400000;
        const h = Math.floor(diff / 3600000); diff %= 3600000;
        const m = Math.floor(diff / 60000); diff %= 60000;
        const s = Math.floor(diff / 1000);
        setNum('days', d);
        setNum('hours', h);
        setNum('minutes', m);
        setNum('seconds', s);
      }
      update();
      setInterval(update, 1000);
    }

    // ===== CONFETTI =====
    function burstConfetti(origin) {
      const colors = ['#b76e79', '#d9a95e', '#e8cfcd', '#8b5a5b', '#f6e5e2', '#ffffff'];
      const cx = origin ? origin.x : window.innerWidth / 2;
      const cy = origin ? origin.y : window.innerHeight * 0.4;
      for (let i = 0; i < 70; i++) {
        const el = document.createElement('div');
        el.className = 'confetti-piece';
        el.style.left = cx + 'px';
        el.style.top = cy + 'px';
        el.style.background = colors[i % colors.length];
        const angle = Math.random() * Math.PI * 2;
        const dist = 120 + Math.random() * 260;
        const dx = Math.cos(angle) * dist;
        const dy = Math.sin(angle) * dist - 130;
        el.style.setProperty('--dx', dx + 'px');
        el.style.setProperty('--dy', dy + 'px');
        el.style.setProperty('--rot', (Math.random() * 720 - 360) + 'deg');
        el.style.width = el.style.height = (6 + Math.random() * 6) + 'px';
        el.style.animationDuration = (0.9 + Math.random() * 0.9) + 's';
        document.body.appendChild(el);
        setTimeout(() => el.remove(), 2200);
      }
    }

    // ===== PARALLAX TILT (desktop) =====
    const cardSection = document.querySelector('.main-card-section');
    const card = document.querySelector('.main-card');
    if (window.matchMedia('(hover:hover) and (pointer:fine)').matches) {
      cardSection.addEventListener('mousemove', (e) => {
        const r = cardSection.getBoundingClientRect();
        const x = (e.clientX - r.left) / r.width - 0.5;
        const y = (e.clientY - r.top) / r.height - 0.5;
        card.style.transform = 'translate(' + (x * 14) + 'px, ' + (y * 10) + 'px) rotate(' + (x * 1.2) + 'deg)';
      });
      cardSection.addEventListener('mouseleave', () => {
        card.style.transform = '';
      });
    }

    // ===== RSVP VIA WHATSAPP =====
    function confirmarAsistencia(event) {
      if (window.__rsvpBusy) return;
      window.__rsvpBusy = true;

      const info = window.__HS_INV || {};
      if (!info.wa) { window.__rsvpBusy = false; return; }
      const msg = encodeURIComponent(info.rsvp || '¡Hola! Quiero confirmar mi asistencia.');
      const url = 'https://wa.me/' + info.wa + '?text=' + msg;
      const rect = event && event.currentTarget ? event.currentTarget.getBoundingClientRect() : null;
      burstConfetti(rect ? { x: rect.left + rect.width / 2, y: rect.top + rect.height / 2 } : null);
      prettyBurst(window.innerWidth / 2, window.innerHeight * 0.42);

      const overlay = document.getElementById('thanks-overlay');
      if (overlay) {
        overlay.classList.remove('show');
        void overlay.offsetWidth;
        overlay.classList.add('show');
        document.body.classList.add('no-scroll');
      }

      setTimeout(() => {
        if (overlay) {
          overlay.classList.remove('show');
          document.body.classList.remove('no-scroll');
        }
      }, 2500);

      setTimeout(() => {
        window.__rsvpBusy = false;
        // Intentar en pestaña nueva; si el navegador bloquea el popup, abrir WhatsApp en esta misma pestaña
        let win = null;
        try { win = window.open(url, '_blank'); } catch (e) { win = null; }
        if (!win || win.closed) {
          window.location.href = url;
        }
      }, 3100);
    }

    // Pretty celebratory burst (hearts, sparkles, petals, confetti)
    function prettyBurst(x, y) {
      const colors = ['#d9a95e', '#b76e79', '#e0b060', '#c98a5e', '#8b5a5b', '#f0d9d5'];
      const fly = (el) => {
        const angle = Math.random() * Math.PI * 2;
        const dist = 140 + Math.random() * 230;
        el.style.left = x + 'px';
        el.style.top = y + 'px';
        el.style.setProperty('--dx', Math.cos(angle) * dist + 'px');
        el.style.setProperty('--dy', (Math.sin(angle) * dist - 70) + 'px');
        el.style.setProperty('--rot', (Math.random() * 540 - 270) + 'deg');
        el.style.setProperty('--sc', (0.8 + Math.random() * 0.7).toFixed(2));
        el.style.setProperty('--dur', (1.5 + Math.random() * 0.9) + 's');
        el.style.setProperty('--del', (Math.random() * 0.18).toFixed(2) + 's');
        document.body.appendChild(el);
        setTimeout(() => el.remove(), 3200);
      };
      // rose hearts
      for (let i = 0; i < 14; i++) {
        const s = document.createElement('span');
        s.className = 'pretty-piece pretty-heart' + (i % 2 ? ' alt' : '');
        s.textContent = '♥';
        s.style.fontSize = (14 + Math.random() * 14) + 'px';
        fly(s);
      }
      // golden sparkles
      for (let i = 0; i < 16; i++) {
        const s = document.createElement('span');
        s.className = 'pretty-piece pretty-spark';
        s.textContent = '✦';
        s.style.fontSize = (13 + Math.random() * 13) + 'px';
        fly(s);
      }
      // petals
      for (let i = 0; i < 10; i++) {
        const s = document.createElement('span');
        s.className = 'pretty-piece pretty-petal';
        s.style.width = s.style.height = (11 + Math.random() * 11) + 'px';
        fly(s);
      }
      // confetti rects
      for (let i = 0; i < 16; i++) {
        const s = document.createElement('span');
        s.className = 'pretty-piece pretty-confetti';
        s.style.background = colors[i % colors.length];
        s.style.width = (6 + Math.random() * 6) + 'px';
        s.style.height = (4 + Math.random() * 5) + 'px';
        fly(s);
      }
    }

    // ===== SHARE =====
    function shareWhatsApp() {
      const text = encodeURIComponent('¡Estás invitad@ a los XV años de Reyna! 🎀\nSábado 10 de Octubre 2026\nAbre la invitación para más detalles.');
      window.open('https://wa.me/529994124233?text=' + text, '_blank');
    }
    function shareCopy() {
      navigator.clipboard.writeText(window.location.href).then(() => {
        alert('¡Enlace copiado!');
      });
    }''';
