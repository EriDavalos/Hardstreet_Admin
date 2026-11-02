// PLANTILLA «MARFIL & ORO» — documento propio, generado desde el mismo
// modelo de invitación que ReynaCoot.
//
// Es un HTML aparte (no una variante de color): portada de sobre con sello de
// cera que se abre con animación, nombres en caligrafía, cuenta regresiva,
// programa del día, detalles,
// familias, fotos, hashtag y confirmación por WhatsApp. Los textos, la fecha,
// las fotos, el acento y el fondo salen de los campos del editor; las clases
// `.petals-bg`, `.petal` y `.sparkle` se mantienen para que los efectos de
// ambiente funcionen igual que en la otra plantilla.

const String kMarfilBody = r'''
<div class="envelope" id="envelope"{{ENVELOPE_STYLE}} onclick="openInvitation()" tabindex="0" aria-label="Abrir la invitación" onkeydown="if(event.key==='Enter'||event.key===' '){event.preventDefault();openInvitation();}">
  {{COVER_MEDIA}}
  <div class="petal"></div>
  <div class="petal"></div>
  <div class="petal"></div>
  <div class="petal"></div>
  <div class="petal"></div>
  <div class="petal"></div>
  <svg class="sparkle e1" viewBox="-14 -14 28 28" aria-hidden="true"><use href="#mf-spark" /></svg>
  <svg class="sparkle e2" viewBox="-14 -14 28 28" aria-hidden="true"><use href="#mf-spark" /></svg>
  <svg class="sparkle e3" viewBox="-14 -14 28 28" aria-hidden="true"><use href="#mf-spark" /></svg>

  <svg class="cover-rings" viewBox="0 0 220 160" aria-hidden="true">
    <defs>
      <linearGradient id="mf-ring-gold" x1="0" y1="0" x2="1" y2="1">
        <stop offset="0" stop-color="#EDD8A2" />
        <stop offset=".4" stop-color="#B8945E" />
        <stop offset=".72" stop-color="#8B6B39" />
        <stop offset="1" stop-color="#DCC086" />
      </linearGradient>
    </defs>
    <g fill="none" stroke="url(#mf-ring-gold)" stroke-width="5.5">
      <ellipse cx="76" cy="76" rx="44" ry="38" transform="rotate(-18 76 76)" />
      <ellipse cx="124" cy="68" rx="44" ry="38" transform="rotate(16 124 68)" />
    </g>
    <g fill="none" stroke="#FFF9E7" stroke-width="1.2" opacity=".65">
      <path d="M40 64 A 44 38 -18 0 1 70 42" />
      <path d="M92 58 A 44 38 16 0 1 132 40" />
    </g>
    <g fill="none" stroke="#8F997F" stroke-width="1" opacity=".85">
      <path d="M158 130 C 172 108 182 88 184 64" />
      <path d="M148 138 C 160 126 170 120 184 118" />
    </g>
    <g fill="#FFFDF6" stroke="#CFC3AA" stroke-width=".6">
      <circle cx="184" cy="62" r="3.4" />
      <circle cx="173" cy="54" r="2.6" />
      <circle cx="166" cy="47" r="2" />
      <circle cx="184" cy="118" r="3" />
      <circle cx="171" cy="124" r="2.4" />
      <circle cx="160" cy="131" r="2" />
    </g>
  </svg>

  <div class="cover-copy">
    <h2 class="cover-title">{{ENVELOPE_TEXT}}</h2>

    <div class="env-stage">
      <div class="env-back"></div>
      <div class="env-letter">
        <span class="letter-flourish">&#10022;</span>
        <span class="letter-script">{{ENVELOPE_NAME}}</span>
        <span class="letter-date">{{ENVELOPE_DATE}}</span>
      </div>
      <div class="env-body"></div>
      <div class="env-flap">
        <svg class="env-flap-shape" viewBox="0 0 100 100" preserveAspectRatio="none" aria-hidden="true">
          <defs>
            <linearGradient id="mf-flap-fill" x1="0" y1="0" x2="0" y2="1">
              <stop offset="0" stop-color="#FCF7EA" />
              <stop offset=".55" stop-color="#F5EBDA" />
              <stop offset="1" stop-color="#ECDFC7" />
            </linearGradient>
          </defs>
          <path d="M0 0 H100 L50 100 Z" fill="url(#mf-flap-fill)" />
          <path d="M0 0 L50 100 L100 0" fill="none" stroke="rgba(160,135,95,.28)" stroke-width=".5" vector-effect="non-scaling-stroke" />
        </svg>
        <span class="env-seal"><span class="env-seal-in">{{SEAL}}</span></span>
      </div>
    </div>

    <p class="cover-tap">Toca el sobre para abrir</p>
  </div>

  <!-- Capa de toque: cualquier toque abre el sobre, incluso sobre los SVG
       decorativos o en navegadores móviles. -->
  <div class="cover-hit" aria-hidden="true" onclick="openInvitation()"></div>

  <svg class="cover-flowers" viewBox="0 0 360 360" aria-hidden="true">
    <defs>
      <radialGradient id="mf-rose-fill" cx="34%" cy="28%" r="80%">
        <stop offset="0" stop-color="#FFFEF9" />
        <stop offset=".5" stop-color="#F8EEDD" />
        <stop offset="1" stop-color="#DDC7A7" />
      </radialGradient>
      <linearGradient id="mf-leaf-fill" x1="0" y1="0" x2="1" y2="1">
        <stop offset="0" stop-color="#AEB69B" />
        <stop offset="1" stop-color="#717C62" />
      </linearGradient>
      <g id="mf-rose">
        <g fill="url(#mf-rose-fill)" stroke="#D5BE9C" stroke-width=".8">
          <ellipse cx="0" cy="-21" rx="15" ry="20" />
          <ellipse cx="0" cy="-21" rx="15" ry="20" transform="rotate(60)" />
          <ellipse cx="0" cy="-21" rx="15" ry="20" transform="rotate(120)" />
          <ellipse cx="0" cy="-21" rx="15" ry="20" transform="rotate(180)" />
          <ellipse cx="0" cy="-21" rx="15" ry="20" transform="rotate(240)" />
          <ellipse cx="0" cy="-21" rx="15" ry="20" transform="rotate(300)" />
        </g>
        <g fill="#FCF5E7" stroke="#D8C3A2" stroke-width=".7">
          <ellipse cx="0" cy="-11" rx="9" ry="12" transform="rotate(24)" />
          <ellipse cx="0" cy="-11" rx="9" ry="12" transform="rotate(144)" />
          <ellipse cx="0" cy="-11" rx="9" ry="12" transform="rotate(264)" />
        </g>
        <path d="M-3 2 C 3 -7 13 -1 9 7 C 5 14 -6 12 -7 4 C -7 -5 2 -10 8 -5" fill="none" stroke="#C7AB81" stroke-width="1.1" stroke-linecap="round" />
      </g>
      <g id="mf-bloom">
        <g fill="#FFFDF7" stroke="#E1D3B8" stroke-width=".5">
          <circle cx="0" cy="-3.4" r="2.7" />
          <circle cx="3.2" cy="0" r="2.7" />
          <circle cx="0" cy="3.4" r="2.7" />
          <circle cx="-3.2" cy="0" r="2.7" />
        </g>
        <circle r="1.3" fill="#D9C08D" />
      </g>
    </defs>

    <g fill="none" stroke="#7F8971" stroke-width="2" stroke-linecap="round">
      <path d="M40 356 C 62 286 86 238 146 192" />
      <path d="M30 332 C 48 268 76 220 132 180" />
      <path d="M58 356 C 92 300 118 262 176 230" />
      <path d="M18 300 C 32 262 44 230 72 204" />
      <path d="M96 356 C 120 316 138 284 186 254" />
    </g>
    <g fill="url(#mf-leaf-fill)" opacity=".92">
      <ellipse cx="78" cy="282" rx="21" ry="8" transform="rotate(-36 78 282)" />
      <ellipse cx="96" cy="252" rx="19" ry="7" transform="rotate(-52 96 252)" />
      <ellipse cx="58" cy="306" rx="20" ry="7.5" transform="rotate(-16 58 306)" />
      <ellipse cx="120" cy="212" rx="17" ry="6.5" transform="rotate(-44 120 212)" />
      <ellipse cx="112" cy="298" rx="22" ry="8" transform="rotate(18 112 298)" />
      <ellipse cx="150" cy="264" rx="20" ry="7" transform="rotate(-24 150 264)" />
      <ellipse cx="40" cy="270" rx="17" ry="6.5" transform="rotate(-64 40 270)" />
    </g>

    <use href="#mf-rose" transform="translate(82 278) scale(1.35)" />
    <use href="#mf-rose" transform="translate(152 306) scale(1.1)" />
    <use href="#mf-rose" transform="translate(164 230) scale(.92)" />
    <use href="#mf-rose" transform="translate(56 218) scale(.78)" />

    <g fill="none" stroke="#8A9378" stroke-width="1">
      <path d="M118 206 C 106 168 82 142 48 128" />
      <path d="M126 216 C 138 184 158 162 192 150" />
      <path d="M108 236 C 88 210 62 196 30 194" />
    </g>
    <g>
      <use href="#mf-bloom" transform="translate(48 128) scale(1.2)" />
      <use href="#mf-bloom" transform="translate(64 112) scale(1)" />
      <use href="#mf-bloom" transform="translate(30 146) scale(.9)" />
      <use href="#mf-bloom" transform="translate(192 150) scale(1.1)" />
      <use href="#mf-bloom" transform="translate(178 132) scale(.9)" />
      <use href="#mf-bloom" transform="translate(206 168) scale(.85)" />
      <use href="#mf-bloom" transform="translate(30 194) scale(1)" />
      <use href="#mf-bloom" transform="translate(48 182) scale(.85)" />
    </g>
  </svg>

</div>

<svg width="0" height="0" style="position:absolute" aria-hidden="true">
  <defs>
    <g id="mf-spark" fill="currentColor">
      <path d="M 0 -12 C 2 -5 5 -2 12 0 C 5 2 2 5 0 12 C -2 5 -5 2 -12 0 C -5 -2 -2 -5 0 -12 Z" />
    </g>
  </defs>
</svg>

<div class="{{INV_CLASS}}" id="invitation">

  <section class="mf-hero section">
    <div class="petals-bg"><div class="petal"></div><div class="petal"></div><div class="petal"></div><div class="petal"></div><div class="petal"></div></div>
    <svg class="sparkle s1" viewBox="-14 -14 28 28" aria-hidden="true"><use href="#mf-spark" /></svg>
    <svg class="sparkle s2" viewBox="-14 -14 28 28" aria-hidden="true"><use href="#mf-spark" /></svg>
    <svg class="sparkle s3" viewBox="-14 -14 28 28" aria-hidden="true"><use href="#mf-spark" /></svg>
    <svg class="sparkle s4" viewBox="-14 -14 28 28" aria-hidden="true"><use href="#mf-spark" /></svg>

    <svg class="mf-rings hero" viewBox="0 0 120 64" aria-hidden="true">
      <circle cx="44" cy="34" r="20" fill="none" stroke="currentColor" stroke-width="1.6" />
      <circle cx="76" cy="34" r="20" fill="none" stroke="currentColor" stroke-width="1.6" />
      <path d="M60 8 l4 6 h-8 z" fill="currentColor" />
    </svg>
    <p class="mf-eyebrow">{{ARC_TEXT}}</p>
    <h1 class="mf-names">{{MAIN_NAME}}</h1>
    <p class="mf-sub">{{INVITE_SUB}}</p>
    <p class="mf-hero-date">{{DATE_LINE}}</p>
  </section>

  {{COUNTDOWN}}
  {{ITINERARY}}
  {{QUOTE}}
  {{DETAILS}}
  {{FAMILIES}}
  {{PHOTOS}}
  {{HASHTAG}}
  {{RSVP}}
  {{FOOTER}}

</div>

<div class="thanks-overlay" id="thanks-overlay" aria-hidden="true">
  <div class="thanks-card">
    <p class="thanks-script">¡Gracias!</p>
    <p>Tu confirmación se está abriendo en WhatsApp.<br />¡Nos vemos el <b>{{THANKS_DATE}}</b>!</p>
  </div>
</div>

{{AUDIO}}
{{MUSIC_BTN}}
''';

const String kMarfilCss = r'''
*, *::before, *::after { margin: 0; padding: 0; box-sizing: border-box; }

:root {
  --gold: #B99A63;
  --gold-deep: #9A7C48;
  --paper: #F8F3E7;
  --paper-2: #F1E8D7;
  --ink: #3B352C;
  --soft: #7D7263;
  --line: rgba(185, 154, 99, .45);
  --white: #FFFDF8;
}

html { scroll-behavior: smooth; }

body {
  font-family: 'Cormorant Garamond', Georgia, 'Times New Roman', serif;
  color: var(--ink);
  background-color: var(--paper);
  background-image:
    radial-gradient(circle at 18% 6%, rgba(255, 255, 255, .55), transparent 40%),
    repeating-linear-gradient(0deg, rgba(120, 100, 70, .022) 0 1px, transparent 1px 4px);
  overflow-x: hidden;
  -webkit-font-smoothing: antialiased;
}

body.no-scroll { overflow: hidden; }
img { max-width: 100%; }
a { color: inherit; }

/* ===== AMBIENTE (pétalos / destellos; los efectos los retoca el editor) ===== */
.petals-bg {
  position: absolute;
  inset: 0;
  overflow: hidden;
  pointer-events: none;
  z-index: 0;
}

.petal {
  position: absolute;
  width: 13px;
  height: 13px;
  border-radius: 50% 0 50% 50%;
  background: radial-gradient(ellipse, rgba(185, 154, 99, .35), rgba(185, 154, 99, .06));
  opacity: 0;
}

.petals-bg .petal { animation: mfDrift linear infinite; }
.envelope > .petal { animation: mfRise linear infinite; }

.petals-bg .petal:nth-of-type(1) { left: 8%; animation-duration: 12s; }
.petals-bg .petal:nth-of-type(2) { left: 32%; animation-duration: 15s; animation-delay: 2.4s; }
.petals-bg .petal:nth-of-type(3) { left: 58%; animation-duration: 13s; animation-delay: 1s; }
.petals-bg .petal:nth-of-type(4) { left: 78%; animation-duration: 16s; animation-delay: 4s; }
.petals-bg .petal:nth-of-type(5) { left: 92%; animation-duration: 14s; animation-delay: 5.2s; }

.envelope > .petal:nth-of-type(1) { left: 8%; animation-duration: 15s; }
.envelope > .petal:nth-of-type(2) { left: 26%; animation-duration: 18s; animation-delay: 2s; }
.envelope > .petal:nth-of-type(3) { left: 46%; animation-duration: 13s; animation-delay: 4.5s; }
.envelope > .petal:nth-of-type(4) { left: 64%; animation-duration: 17s; animation-delay: 1.2s; }
.envelope > .petal:nth-of-type(5) { left: 82%; animation-duration: 16s; animation-delay: 3.4s; }
.envelope > .petal:nth-of-type(6) { left: 93%; animation-duration: 19s; animation-delay: 5.6s; }

@keyframes mfDrift {
  0% { transform: translate(0, 26px) rotate(0deg); opacity: 0; }
  18% { opacity: .5; }
  100% { transform: translate(38px, -210px) rotate(300deg); opacity: 0; }
}

@keyframes mfRise {
  0% { transform: translateY(100vh) rotate(0deg) scale(.55); opacity: 0; }
  12% { opacity: .55; }
  88% { opacity: .55; }
  100% { transform: translateY(-12vh) rotate(340deg) scale(1); opacity: 0; }
}

.sparkle {
  position: absolute;
  width: 16px;
  height: auto;
  color: var(--gold);
  opacity: .85;
  z-index: 3;
  pointer-events: none;
  animation: mfTwinkle 4s ease-in-out infinite;
}

.sparkle.e1 { top: 15%; left: 12%; animation-delay: .4s; }
.sparkle.e2 { top: 26%; right: 11%; width: 12px; animation-delay: 1.6s; }
.sparkle.e3 { bottom: 16%; left: 18%; width: 13px; animation-delay: 2.5s; }
.sparkle.s1 { top: 8%; left: 10%; }
.sparkle.s2 { top: 20%; right: 9%; width: 12px; animation-delay: 1.3s; }
.sparkle.s3 { bottom: 12%; left: 8%; width: 14px; animation-delay: 2.2s; }
.sparkle.s4 { bottom: 8%; right: 12%; animation-delay: .8s; }

@keyframes mfTwinkle {
  0%, 100% { opacity: .12; transform: scale(.5) rotate(0deg); }
  50% { opacity: .9; transform: scale(1.1) rotate(35deg); }
}

/* ===== PORTADA: SOBRE CON SELLO ===== */
.mf-rings {
  width: 84px;
  height: auto;
  display: block;
  margin: 0 auto 1rem;
  color: var(--gold);
}

.mf-rings.hero { width: 74px; margin-bottom: 1.2rem; }

.envelope {
  position: relative;
  min-height: 100svh;
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  padding: clamp(76px, 15vh, 132px) 20px clamp(108px, 17vh, 150px);
  text-align: center;
  overflow: hidden;
  cursor: pointer;
  -webkit-tap-highlight-color: transparent;
  background:
    radial-gradient(ellipse at 20% 6%, rgba(255, 255, 255, .82), transparent 52%),
    radial-gradient(ellipse at 84% 94%, rgba(196, 170, 124, .16), transparent 58%),
    repeating-linear-gradient(112deg, rgba(120, 100, 70, .026) 0 1px, transparent 1px 7px),
    linear-gradient(165deg, var(--paper) 0%, var(--paper-2) 58%, #E9DCC5 100%);
}

.envelope::after {
  content: '';
  position: absolute;
  inset: 0;
  box-shadow: inset 0 0 80px rgba(140, 115, 75, .12);
  pointer-events: none;
  z-index: 8;
}

.envelope.opening {
  position: fixed;
  inset: 0;
  z-index: 40;
  cursor: default;
}

.envelope.opened {
  opacity: 0;
  transform: scale(1.03);
  pointer-events: none;
  transition: opacity .65s ease, transform .9s ease;
}

.mf-cover-media {
  position: absolute;
  inset: 0;
  z-index: 0;
}

.mf-cover-media img,
.mf-cover-media video {
  width: 100%;
  height: 100%;
  object-fit: cover;
}

.mf-cover-media::after {
  content: '';
  position: absolute;
  inset: 0;
  background: linear-gradient(180deg, rgba(248, 243, 231, .8), rgba(248, 243, 231, .9));
}

.cover-copy {
  position: relative;
  z-index: 4;
  width: 100%;
  max-width: 480px;
  display: flex;
  flex-direction: column;
  align-items: center;
}

.cover-title {
  font-family: 'Cormorant Garamond', Georgia, serif;
  font-weight: 500;
  font-size: clamp(1.5rem, 7.2vw, 2.3rem);
  line-height: 1.3;
  letter-spacing: .075em;
  text-transform: uppercase;
  color: var(--gold-deep);
  max-width: 22ch;
  text-wrap: balance;
}

.cover-rings {
  position: absolute;
  top: -16px;
  left: -20px;
  z-index: 3;
  width: min(200px, 42vw);
  height: auto;
  pointer-events: none;
  transform: rotate(-7deg);
  filter: drop-shadow(0 8px 14px rgba(90, 68, 32, .12));
}

.cover-flowers {
  position: absolute;
  left: -36px;
  bottom: -30px;
  z-index: 2;
  width: min(300px, 70vw);
  height: auto;
  pointer-events: none;
  filter: drop-shadow(0 10px 18px rgba(90, 68, 32, .08));
}

.env-stage {
  position: relative;
  width: min(340px, 80vw);
  aspect-ratio: 1.34;
  margin-top: clamp(1.5rem, 5vh, 2.8rem);
  perspective: 1200px;
  filter: drop-shadow(0 26px 34px rgba(90, 68, 32, .16));
}

.env-back {
  position: absolute;
  inset: 0;
  background: linear-gradient(180deg, #F1E6D3, #E5D5BB);
  border: 1px solid rgba(170, 145, 105, .4);
  border-radius: 3px;
}

.env-letter {
  position: absolute;
  left: 7%;
  right: 7%;
  top: 5%;
  height: 86%;
  z-index: 2;
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  gap: .55rem;
  padding: 1.4rem 1rem;
  background:
    radial-gradient(circle at 50% 0%, rgba(255, 255, 255, .9), transparent 65%),
    #FFFDF7;
  border: 1px solid rgba(190, 165, 125, .55);
  box-shadow: 0 2px 6px rgba(90, 68, 32, .1);
  transition: transform 1.15s cubic-bezier(.33, .78, .32, 1) .28s;
}

.envelope.opening .env-letter { transform: translateY(-70%); }

.letter-flourish {
  color: var(--gold);
  font-size: .72rem;
  letter-spacing: .32em;
}

.letter-script {
  font-family: 'Great Vibes', cursive;
  font-size: clamp(1.8rem, 9vw, 2.6rem);
  line-height: 1.05;
  color: var(--gold-deep);
  overflow-wrap: anywhere;
}

.letter-date {
  font-family: 'Italiana', 'Cormorant Garamond', serif;
  font-size: .66rem;
  letter-spacing: .22em;
  text-transform: uppercase;
  color: var(--soft);
}

.env-body {
  position: absolute;
  inset: 0;
  z-index: 3;
  background:
    linear-gradient(118deg, rgba(255, 255, 255, .55), transparent 42%),
    linear-gradient(180deg, #F8F1E2 0%, #F2E7D3 55%, #E9DCC4 100%);
  border: 1px solid rgba(170, 145, 105, .45);
  border-radius: 3px;
  overflow: hidden;
}

.env-body::before,
.env-body::after {
  content: '';
  position: absolute;
  bottom: 0;
  width: 53%;
  height: 1px;
  background: linear-gradient(90deg, rgba(150, 125, 85, .3), rgba(150, 125, 85, .04));
}

.env-body::before { left: 0; transform-origin: bottom left; transform: rotate(24deg); }
.env-body::after {
  right: 0;
  transform-origin: bottom right;
  transform: rotate(-24deg);
  background: linear-gradient(270deg, rgba(150, 125, 85, .3), rgba(150, 125, 85, .04));
}

.env-flap {
  position: absolute;
  inset: 0 0 auto;
  height: 54%;
  z-index: 5;
  transform-origin: top center;
  transform-style: preserve-3d;
  backface-visibility: hidden;
  transition: transform 1.05s cubic-bezier(.55, .05, .25, 1);
  filter: drop-shadow(0 2px 2px rgba(120, 95, 55, .14));
}

.env-flap-shape {
  display: block;
  width: 100%;
  height: 100%;
  pointer-events: none;
}

.envelope.opening .env-flap { transform: rotateX(176deg); }

.env-seal {
  position: absolute;
  left: 50%;
  bottom: 0;
  width: clamp(58px, 17vw, 72px);
  aspect-ratio: 1;
  transform: translate(-50%, 46%);
  display: grid;
  place-items: center;
  border-radius: 47% 53% 49% 51% / 52% 47% 53% 48%;
  background: radial-gradient(circle at 34% 26%, #FFF9EA 0%, #F2E3C4 38%, #DCC49C 72%, #BFA274 100%);
  border: 1px solid rgba(150, 120, 75, .45);
  box-shadow:
    0 6px 12px rgba(90, 68, 32, .22),
    inset 0 2px 3px rgba(255, 255, 255, .85),
    inset 0 -3px 6px rgba(120, 95, 55, .22);
  color: #8A6C3D;
  transition: opacity .35s ease .32s;
}

.env-seal::before {
  content: '';
  position: absolute;
  inset: 9%;
  border: 1px solid rgba(138, 105, 58, .4);
  border-radius: 50%;
}

.env-seal-in {
  position: relative;
  z-index: 1;
  font-family: 'Cormorant Garamond', serif;
  font-size: clamp(.9rem, 3.2vw, 1.15rem);
  font-weight: 600;
  letter-spacing: .12em;
}

.envelope.opening .env-seal { opacity: 0; }

.cover-tap {
  margin-top: clamp(1.2rem, 3.5vh, 1.9rem);
  font-family: 'Great Vibes', cursive;
  font-size: clamp(1.5rem, 6.6vw, 2rem);
  line-height: 1.2;
  color: var(--gold-deep);
  opacity: .92;
}

.cover-hit {
  position: absolute;
  inset: 0;
  z-index: 6;
  cursor: pointer;
  -webkit-tap-highlight-color: transparent;
}

/* ===== INVITACIÓN ===== */
.invitation { display: none; }
.invitation.open { display: block; }

.section {
  position: relative;
  padding: 4rem 1.35rem;
  z-index: 1;
}

.section.animate { opacity: 0; transform: translateY(26px); }
.section.visible { opacity: 1; transform: translateY(0); transition: opacity .9s ease, transform .9s ease; }

.mf-eyebrow {
  font-family: 'Inter', sans-serif;
  font-size: .58rem;
  font-weight: 500;
  letter-spacing: .4em;
  text-transform: uppercase;
  color: var(--soft);
}

.mf-names {
  font-family: 'Great Vibes', cursive;
  font-weight: 400;
  font-size: clamp(3.5rem, 17vw, 5.6rem);
  line-height: 1;
  color: var(--gold-deep);
  margin: .45rem 0 .3rem;
  overflow-wrap: anywhere;
}

.mf-sub {
  font-family: 'Italiana', 'Cormorant Garamond', serif;
  font-size: 1rem;
  letter-spacing: .22em;
  text-transform: uppercase;
  color: var(--ink);
}

.mf-hero {
  text-align: center;
  background:
    radial-gradient(ellipse at 50% 0%, rgba(255, 255, 255, .85), transparent 62%),
    linear-gradient(180deg, var(--paper-2) 0%, var(--paper) 72%);
  overflow: hidden;
  padding: 4.4rem 1.35rem 3.4rem;
}

.mf-hero-date {
  display: inline-block;
  margin-top: 1.35rem;
  padding-top: .95rem;
  border-top: 1px solid var(--line);
  font-family: 'Inter', sans-serif;
  font-size: .6rem;
  letter-spacing: .26em;
  text-transform: uppercase;
  color: var(--soft);
}

/* ===== ENCABEZADOS DE SECCIÓN ===== */
.mf-head {
  text-align: center;
  margin-bottom: 2.1rem;
}

.mf-script {
  display: block;
  font-family: 'Great Vibes', cursive;
  font-size: 2.6rem;
  line-height: 1.1;
  color: var(--gold-deep);
}

.mf-kicker {
  display: block;
  margin-top: .35rem;
  font-family: 'Inter', sans-serif;
  font-size: .55rem;
  letter-spacing: .32em;
  text-transform: uppercase;
  color: var(--soft);
}

.mf-rule {
  display: block;
  position: relative;
  width: 66px;
  height: 1px;
  margin: 1rem auto 0;
  background: var(--line);
}

.mf-rule::after {
  content: '';
  position: absolute;
  left: 50%;
  top: 50%;
  width: 5px;
  height: 5px;
  background: var(--gold);
  transform: translate(-50%, -50%) rotate(45deg);
}

/* ===== CUENTA REGRESIVA ===== */
.mf-countdown {
  text-align: center;
  background: var(--paper-2);
  border-top: 1px solid var(--line);
  border-bottom: 1px solid var(--line);
  padding: 2.9rem 1.2rem 3.1rem;
}

.mf-count-script {
  font-family: 'Great Vibes', cursive;
  font-size: 2.15rem;
  color: var(--gold-deep);
}

.mf-count-row {
  display: flex;
  justify-content: center;
  gap: clamp(.6rem, 4vw, 2rem);
  margin-top: 1.2rem;
}

.mf-count-box { min-width: 54px; }

.mf-count-num {
  display: block;
  font-family: 'Italiana', 'Cormorant Garamond', serif;
  font-size: 2.15rem;
  line-height: 1;
  color: var(--ink);
  font-variant-numeric: tabular-nums;
}

.mf-count-lab {
  display: block;
  margin-top: .5rem;
  font-family: 'Inter', sans-serif;
  font-size: .52rem;
  letter-spacing: .22em;
  text-transform: uppercase;
  color: var(--soft);
}

/* ===== PROGRAMA DEL DÍA ===== */
.mf-day {
  position: relative;
  max-width: 400px;
  margin: 0 auto;
}

.mf-day::before {
  content: '';
  position: absolute;
  top: 8px;
  bottom: 8px;
  left: 50%;
  width: 1px;
  background: linear-gradient(180deg, transparent, var(--line) 10%, var(--line) 90%, transparent);
}

.mf-stop {
  position: relative;
  text-align: center;
  padding-bottom: 1.6rem;
}

.mf-stop:last-child { padding-bottom: 0; }

.mf-dot {
  display: block;
  width: 8px;
  height: 8px;
  margin: 0 auto .6rem;
  background: var(--paper);
  border: 1px solid var(--gold);
  transform: rotate(45deg);
}

.mf-stop-time {
  display: block;
  font-family: 'Italiana', 'Cormorant Garamond', serif;
  font-size: 1.08rem;
  letter-spacing: .14em;
  color: var(--gold-deep);
}

.mf-stop-title {
  display: block;
  margin-top: .18rem;
  font-size: 1rem;
  letter-spacing: .18em;
  text-transform: uppercase;
}

/* ===== DETALLES ===== */
.mf-details-section {
  position: relative;
  overflow: hidden;
}

.mf-details-content {
  position: relative;
  z-index: 1;
}

.mf-details-media {
  position: absolute;
  inset: 0;
  z-index: 0;
  overflow: hidden;
  pointer-events: none;
}

.mf-details-media img,
.mf-details-media video {
  width: 100%;
  height: 100%;
  object-fit: cover;
}

.mf-details-media::after {
  content: '';
  position: absolute;
  inset: 0;
  background: var(--paper);
  opacity: .86;
}

.mf-details {
  display: grid;
  grid-template-columns: 1fr;
  gap: 1rem;
  max-width: 760px;
  margin: 0 auto;
}

.mf-card {
  position: relative;
  text-align: center;
  padding: 1.9rem 1.4rem 1.7rem;
  background: var(--white);
  border: 1px solid var(--line);
}

.mf-card::before {
  content: '';
  position: absolute;
  inset: 6px;
  border: 1px solid rgba(185, 154, 99, .18);
  pointer-events: none;
}

.mf-mark {
  display: block;
  width: 16px;
  margin: 0 auto .75rem;
  color: var(--gold);
}

.mf-card h3 {
  font-family: 'Cormorant Garamond', serif;
  font-weight: 600;
  font-size: 1rem;
  letter-spacing: .2em;
  text-transform: uppercase;
}

.mf-time {
  margin-top: .35rem;
  font-family: 'Italiana', 'Cormorant Garamond', serif;
  font-size: 1.05rem;
  letter-spacing: .1em;
  color: var(--gold-deep);
}

.mf-place { margin-top: .2rem; font-size: 1.02rem; }

.mf-note {
  margin-top: .55rem;
  font-size: .98rem;
  font-style: italic;
  line-height: 1.6;
  color: var(--soft);
}

.mf-link {
  display: inline-block;
  margin-top: 1rem;
  padding-bottom: 2px;
  border-bottom: 1px solid var(--line);
  font-family: 'Inter', sans-serif;
  font-size: .56rem;
  font-weight: 500;
  letter-spacing: .24em;
  text-transform: uppercase;
  color: var(--gold-deep);
  text-decoration: none;
}

/* ===== FAMILIAS ===== */
.mf-families {
  display: grid;
  gap: 1.5rem;
  max-width: 560px;
  margin: 0 auto;
  text-align: center;
}

.mf-family h3 {
  font-family: 'Italiana', 'Cormorant Garamond', serif;
  font-weight: 400;
  font-size: 1.1rem;
  letter-spacing: .18em;
  text-transform: uppercase;
  color: var(--gold-deep);
}

.mf-family p {
  margin-top: .4rem;
  font-size: 1.06rem;
  line-height: 1.7;
}

/* ===== FOTOS ===== */
.mf-photos {
  display: flex;
  justify-content: center;
  align-items: flex-start;
  gap: clamp(.55rem, 3vw, 1.2rem);
  max-width: 720px;
  margin: 0 auto;
  padding: 0 1.2rem 3.8rem;
}

.mf-photo {
  width: 30%;
  max-width: 200px;
  padding: 6px 6px 14px;
  background: var(--white);
  border: 1px solid var(--line);
  box-shadow: 0 16px 30px rgba(80, 60, 30, .12);
}

.mf-photo:nth-child(1) { transform: rotate(-2.4deg); }
.mf-photo:nth-child(2) { transform: translateY(-10px); }
.mf-photo:nth-child(3) { transform: rotate(2.2deg); }

.mf-photo img {
  width: 100%;
  aspect-ratio: 3 / 4;
  object-fit: cover;
  display: block;
  filter: saturate(.94);
}

/* ===== FRASE ===== */
.mf-quote-section {
  text-align: center;
  max-width: 620px;
  margin: 0 auto;
  padding-top: 2.2rem;
  padding-bottom: 3.2rem;
}

.mf-quote-mark {
  display: block;
  font-family: 'Great Vibes', cursive;
  font-size: 3.2rem;
  line-height: .5;
  color: var(--gold);
}

.mf-quote-section p {
  margin-top: 1rem;
  font-size: 1.32rem;
  font-style: italic;
  line-height: 1.75;
}

/* ===== HASHTAG ===== */
.mf-hashtag {
  text-align: center;
  background: var(--paper-2);
  border-top: 1px solid var(--line);
  border-bottom: 1px solid var(--line);
  padding: 2.9rem 1.2rem;
}

.mf-hashtag-script {
  font-family: 'Great Vibes', cursive;
  font-size: 2rem;
  color: var(--soft);
}

.mf-tag {
  margin-top: .3rem;
  font-family: 'Italiana', 'Cormorant Garamond', serif;
  font-size: 1.9rem;
  letter-spacing: .06em;
  color: var(--gold-deep);
}

/* ===== RSVP ===== */
.mf-rsvp {
  text-align: center;
  padding: 3.6rem 1.4rem 4rem;
}

.mf-rsvp-text {
  max-width: 460px;
  margin: 0 auto;
  font-size: 1.05rem;
  line-height: 1.7;
  color: var(--soft);
}

.mf-cta {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  margin-top: 1.6rem;
  padding: 1rem 2.2rem;
  border: 0;
  background: var(--gold-deep);
  color: #FFFDF8;
  font-family: 'Inter', sans-serif;
  font-size: .64rem;
  font-weight: 500;
  letter-spacing: .26em;
  text-transform: uppercase;
  cursor: pointer;
  box-shadow: 0 14px 26px rgba(154, 124, 72, .26);
  transition: transform .2s ease, box-shadow .2s ease;
}

.mf-cta:hover {
  transform: translateY(-2px);
  box-shadow: 0 18px 32px rgba(154, 124, 72, .32);
}

/* ===== PIE ===== */
.mf-footer {
  position: relative;
  overflow: hidden;
  text-align: center;
  padding: 3.4rem 1.4rem 2.6rem;
  background: #EFE5D3;
  border-top: 1px solid var(--line);
}

.mf-footer-names {
  position: relative;
  z-index: 1;
  font-family: 'Great Vibes', cursive;
  font-size: 2.9rem;
  line-height: 1.1;
  color: var(--gold-deep);
}

.mf-footer-msg {
  position: relative;
  z-index: 1;
  max-width: 440px;
  margin: .8rem auto 0;
  font-size: 1.04rem;
  line-height: 1.75;
}

.mf-credit {
  position: relative;
  z-index: 1;
  margin-top: 2.1rem;
  font-family: 'Inter', sans-serif;
  font-size: .54rem;
  letter-spacing: .2em;
  text-transform: uppercase;
  color: var(--soft);
}

.mf-credit a { color: var(--gold-deep); text-decoration: none; }

/* ===== GRACIAS (RSVP) ===== */
.thanks-overlay {
  position: fixed;
  inset: 0;
  z-index: 60;
  display: flex;
  align-items: center;
  justify-content: center;
  padding: 1.4rem;
  background: rgba(59, 53, 44, .55);
  opacity: 0;
  pointer-events: none;
  transition: opacity .35s ease;
}

.thanks-overlay.show { opacity: 1; pointer-events: auto; }

.thanks-card {
  max-width: 330px;
  padding: 2.6rem 2rem;
  text-align: center;
  background: var(--paper);
  border: 1px solid var(--gold);
}

.thanks-script {
  font-family: 'Great Vibes', cursive;
  font-size: 2.5rem;
  color: var(--gold-deep);
}

.thanks-card p { margin-top: .5rem; font-size: 1rem; line-height: 1.6; }

/* ===== MÚSICA ===== */
.music-btn {
  position: fixed;
  right: 15px;
  bottom: 15px;
  z-index: 50;
  width: 54px;
  height: 54px;
  display: flex;
  align-items: center;
  justify-content: center;
  border: 2px solid rgba(255, 250, 235, .8);
  border-radius: 50%;
  background: radial-gradient(circle at 32% 26%, #FFF3C9 0%, #F0D28C 26%, #D2A95E 64%, #A47A39 100%);
  color: #513D1E;
  cursor: pointer;
  box-shadow:
    0 10px 22px rgba(80, 58, 24, .26),
    inset 0 2px 3px rgba(255, 255, 255, .85),
    inset 0 -4px 8px rgba(120, 86, 35, .25);
  transition: bottom .4s ease, width .3s ease, height .3s ease;
}

.music-btn svg { width: 23px; height: 23px; }

body.at-cover .music-btn {
  right: 14px;
  bottom: 88px;
  width: 62px;
  height: 62px;
}

body.at-cover .music-btn svg { width: 26px; height: 26px; }

.music-btn.playing {
  background: radial-gradient(circle at 32% 26%, #E8CD92 0%, #C9A45F 42%, #997334 100%);
  color: #FFFDF8;
}

/* ===== PANTALLAS ANCHAS ===== */
@media (min-width: 640px) {
  .mf-details { grid-template-columns: 1fr 1fr; }
  .mf-families { grid-template-columns: 1fr 1fr; }
  .section { padding-left: 2.4rem; padding-right: 2.4rem; }
  .mf-cover-media::after { background: linear-gradient(180deg, rgba(248, 243, 231, .72), rgba(248, 243, 231, .86)); }
}

@media (prefers-reduced-motion: reduce) {
  *, *::before, *::after {
    animation-duration: .01ms !important;
    animation-iteration-count: 1 !important;
    transition-duration: .01ms !important;
  }
  /* La apertura del sobre es la acción principal: se mantiene completa,
     igual que en el admin. Solo se apagan los efectos ambientales. */
  .env-flap { transition-duration: 1.05s !important; }
  .env-letter { transition-duration: 1.15s !important; transition-delay: .28s !important; }
  .env-seal { transition-duration: .35s !important; transition-delay: .32s !important; }
  .envelope.opened { transition-duration: .65s, .9s !important; }
  .section.visible { transition-duration: .45s !important; }
}
''';

const String kMarfilJs = r'''
// ===== ABRIR LA INVITACIÓN =====
function openInvitation(target) {
  var cover = document.getElementById('envelope');
  var invitation = document.getElementById('invitation');
  if (!cover || !invitation) return;
  if (cover.classList.contains('opening') || cover.classList.contains('opened')) return;

  var reduce = window.matchMedia && window.matchMedia('(prefers-reduced-motion: reduce)').matches;
  cover.classList.add('opening');
  document.body.classList.remove('at-cover');
  document.body.classList.add('no-scroll');
  startMusic();

  setTimeout(function () {
    cover.classList.add('opened');
    invitation.classList.add('open');
    window.scrollTo(0, 0);
    observeSections();
    startCountdown();
  // La apertura es la misma con o sin movimiento reducido: solo se apagan
  // los efectos ambientales, no el gesto de abrir el sobre.
  }, 1450);

  setTimeout(function () {
    cover.style.display = 'none';
    document.body.classList.remove('no-scroll');
    if (target === 'rsvp') {
      setTimeout(function () {
        var rsvp = document.getElementById('rsvp');
        if (rsvp) rsvp.scrollIntoView({ behavior: reduce ? 'auto' : 'smooth', block: 'start' });
      }, 60);
    }
  }, 2350);
}

// ===== MÚSICA =====
function startMusic() {
  var audio = document.getElementById('bg-music');
  var btn = document.getElementById('music-btn');
  if (btn) btn.style.display = 'flex';
  if (!audio) return;
  audio.volume = .5;
  audio.play().then(function () {
    if (btn) btn.classList.add('playing');
  }).catch(function () {});
}

function toggleMusic() {
  var audio = document.getElementById('bg-music');
  var btn = document.getElementById('music-btn');
  if (!audio) return;
  if (audio.paused) {
    audio.play().then(function () {
      if (btn) btn.classList.add('playing');
    }).catch(function () {});
  } else {
    audio.pause();
    if (btn) btn.classList.remove('playing');
  }
}

// ===== APARICIÓN AL DESLIZAR =====
function observeSections() {
  var sections = document.querySelectorAll('.section');
  sections.forEach(function (s) { s.classList.add('animate'); });
  var observer = new IntersectionObserver(function (entries) {
    entries.forEach(function (entry) {
      if (entry.isIntersecting) entry.target.classList.add('visible');
    });
  }, { threshold: .12 });
  sections.forEach(function (s) { observer.observe(s); });
}

// ===== CUENTA REGRESIVA =====
function startCountdown() {
  var target = new Date((window.__HS_INV && window.__HS_INV.event) || '2026-10-10T19:30:00').getTime();
  function setNum(id, value) {
    var el = document.getElementById(id);
    if (!el) return;
    el.textContent = String(value).padStart(2, '0');
  }
  function update() {
    var diff = target - Date.now();
    if (diff <= 0) {
      setNum('days', 0); setNum('hours', 0); setNum('minutes', 0); setNum('seconds', 0);
      return;
    }
    var d = Math.floor(diff / 86400000); diff %= 86400000;
    var h = Math.floor(diff / 3600000); diff %= 3600000;
    var m = Math.floor(diff / 60000); diff %= 60000;
    var s = Math.floor(diff / 1000);
    setNum('days', d); setNum('hours', h); setNum('minutes', m); setNum('seconds', s);
  }
  update();
  setInterval(update, 1000);
}

// ===== CONFIRMAR POR WHATSAPP =====
function confirmarAsistencia(event) {
  if (window.__rsvpBusy) return;
  window.__rsvpBusy = true;

  var info = window.__HS_INV || {};
  var overlay = document.getElementById('thanks-overlay');
  if (overlay) {
    overlay.classList.add('show');
    document.body.classList.add('no-scroll');
  }

  setTimeout(function () {
    if (overlay) {
      overlay.classList.remove('show');
      document.body.classList.remove('no-scroll');
    }
  }, 2600);

  setTimeout(function () {
    window.__rsvpBusy = false;
    if (!info.wa) return;
    var msg = encodeURIComponent(info.rsvp || '¡Hola! Quiero confirmar mi asistencia.');
    var url = 'https://wa.me/' + info.wa + '?text=' + msg;
    var win = null;
    try { win = window.open(url, '_blank'); } catch (e) { win = null; }
    if (!win || win.closed) window.location.href = url;
  }, 2300);
}
''';
