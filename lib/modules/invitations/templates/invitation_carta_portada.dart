import 'package:hardstreet_admin/modules/invitations/assets/invitation_portada_carta_assets.dart';

// ==================================================================
// PORTADA CARTA — sobre clásico sobre mesa de novia
// ==================================================================
// La portada es un sobre horizontal, centrado y cerrado, con solapa
// triangular y sello de cera. La carta vertical vive dentro del sobre: al
// abrirse, la solapa gira y la carta asoma por el borde superior, sin quedar
// nunca por encima del frente. Anillos, flores y listón enmarcan la escena.
//
// Todo se apaga con prefers-reduced-motion.

/// El escenario se inserta dentro de `#envelope`. Recibe textos YA escapados.
String cartaPortadaScene({
  required String invitationText,
  required String name,
  required String date,
  required String place,
  required String initials,
}) =>
    '''
<div class="hs-carta-portada" aria-hidden="true">
  <div class="hs-carta-papel"></div>
  <div class="hs-carta-luz"></div>
  <div class="hs-carta-tinte"></div>
  <div class="hs-carta-grano"></div>
  <div class="hs-carta-vineta"></div>
  <div class="hs-carta-destellos">
    <span class="d1"></span><span class="d2"></span>
    <span class="d3"></span><span class="d4"></span>
  </div>
  <div class="hs-carta-anillos">
    <img src="https://i.imgur.com/kHfHXdk.png" alt="" referrerpolicy="no-referrer" />
  </div>
  <div class="hs-carta-flor-esquina">
    <img src="https://i.imgur.com/EjgjsxW.png" alt="" referrerpolicy="no-referrer" />
  </div>
  <div class="hs-carta-cinta">
    <img src="https://i.imgur.com/zuk8cKV.png" alt="" referrerpolicy="no-referrer" />
  </div>
  <span class="hs-carta-petalo p1"></span>
  <span class="hs-carta-petalo p2"></span>
  <span class="hs-carta-petalo p3"></span>
  <span class="hs-carta-petalo p4"></span>
  <span class="hs-carta-petalo p5"></span>
</div>
<div class="hs-carta-contenido">
  <p class="hs-kicker hs-carta-invite">$invitationText</p>
  <div class="hs-carta-tilt">
    <div class="hs-carta-rotor">
      <div class="hs-carta-flap-open" aria-hidden="true"></div>
      <div class="hs-carta-stage">
      <div class="hs-carta-back"></div>
      <div class="hs-carta-liner" aria-hidden="true"></div>
      <div class="hs-carta-letter">
        <span class="hs-carta-letter-sprig" aria-hidden="true">
          <img src="https://i.imgur.com/EjgjsxW.png" alt="" referrerpolicy="no-referrer" />
        </span>
        <span class="hs-carta-letter-wm" aria-hidden="true">$initials</span>
        <span class="hs-kicker hs-carta-letter-kicker">Para ti</span>
        <p class="hs-script hs-carta-name">$name</p>
        <p class="hs-carta-message">Acompáñanos a celebrar este día tan especial</p>
        <span class="hs-carta-rule" aria-hidden="true"></span>
        <p class="hs-date">$date</p>
        ${place.isEmpty ? '' : '<p class="hs-carta-place">$place</p>'}
      </div>
      <div class="hs-carta-envelope">
        <div class="hs-carta-body"></div>
        <span class="hs-carta-fold" aria-hidden="true"></span>
        <div class="hs-carta-foil" aria-hidden="true"></div>
        <div class="hs-carta-flap">
          <svg class="hs-carta-flap-art" viewBox="0 0 100 58" preserveAspectRatio="none" aria-hidden="true">
            <defs>
              <linearGradient id="hs-carta-flap-fill" x1="0" y1="0" x2="0" y2="1">
                <stop offset="0" style="stop-color: var(--hs-cover-light)" />
                <stop offset=".72" style="stop-color: var(--hs-cover-pale)" />
                <stop offset="1" style="stop-color: var(--hs-cover-panel)" />
              </linearGradient>
            </defs>
            <path d="M0 0 H100 L50 58 Z" fill="url(#hs-carta-flap-fill)" vector-effect="non-scaling-stroke" />
            <path class="hs-carta-flap-inner" d="M2.6 1.8 H97.4 L50 54.4 Z" fill="none" vector-effect="non-scaling-stroke" />
          </svg>
          <span class="hs-carta-flap-mark">$initials</span>
        </div>
        <span class="hs-carta-lazada" aria-hidden="true"></span>
        <span class="hs-carta-seal">$initials</span>
      </div>
      </div>
    </div>
  </div>
  <p class="hs-carta-tap"><span class="hs-carta-tap-line" aria-hidden="true"></span>Toca el sobre para abrir<span class="hs-carta-tap-line" aria-hidden="true"></span></p>
</div>''';

String cartaPortadaCss() =>
    '''
/* ===== CARTA · PORTADA FLORAL ===== */
.hs-scene-carta {
  --hs-carta-card-w: min(480px, 77vw);
  isolation: isolate;
  flex-direction: column;
  gap: 0;
  overflow: hidden;
  background: #f4ecdf;
}
.hs-scene-carta .hs-cover-media { display: none; }

.hs-carta-portada {
  position: absolute;
  inset: 0;
  z-index: 0;
  overflow: hidden;
  pointer-events: none;
}
.hs-carta-papel {
  position: absolute;
  inset: -4%;
  background: url("$kPortadaCartaFondoDesktop") center / cover no-repeat;
  filter: saturate(.94) brightness(1.035);
  transform: translate3d(0, 0, 0) scale(1.02);
  animation: hsCartaPaperDrift 26s ease-in-out infinite alternate;
  will-change: transform;
}
.hs-carta-luz {
  position: absolute;
  inset: -10%;
  background:
    radial-gradient(circle at 50% 40%, rgba(255, 253, 247, .62), transparent 42%),
    radial-gradient(circle at 84% 12%, rgba(255, 250, 239, .34), transparent 30%),
    radial-gradient(circle at 4% 96%, rgba(255, 249, 239, .34), transparent 34%);
  opacity: .86;
  animation: hsCartaLightBreathe 9s ease-in-out infinite;
  will-change: opacity;
}
.hs-carta-tinte {
  position: absolute;
  inset: 0;
  opacity: 0;
  transition: opacity .9s ease;
  pointer-events: none;
}
.hs-carta-bg-jardin .hs-carta-tinte {
  opacity: 1;
  background:
    radial-gradient(circle at 8% 88%, rgba(104, 126, 92, .22), transparent 40%),
    linear-gradient(160deg, rgba(232, 240, 226, .34), transparent 52%, rgba(206, 220, 197, .18));
}
.hs-carta-bg-seda .hs-carta-tinte {
  opacity: 1;
  background:
    linear-gradient(132deg, rgba(203, 165, 119, .22), transparent 43%, rgba(255, 249, 240, .2)),
    radial-gradient(circle at 92% 8%, rgba(255, 246, 230, .34), transparent 36%);
}
.hs-carta-bg-corte .hs-carta-tinte {
  opacity: 1;
  background:
    radial-gradient(ellipse at 50% 44%, rgba(255, 252, 244, .5), transparent 58%),
    linear-gradient(180deg, rgba(185, 154, 99, .12), transparent 30%, rgba(154, 124, 72, .14));
}
.hs-carta-bg-perla .hs-carta-tinte {
  opacity: 1;
  background:
    linear-gradient(120deg, rgba(214, 216, 220, .20), transparent 46%, rgba(255, 253, 249, .30)),
    radial-gradient(circle at 20% 14%, rgba(255, 255, 255, .42), transparent 34%);
}
/* Marco doble y filigrana de esquina: solo para los fondos formales. */
.hs-carta-bg-corte .hs-carta-portada::after,
.hs-carta-bg-perla .hs-carta-portada::after {
  content: "";
  position: absolute;
  inset: 3.5%;
  z-index: 4;
  pointer-events: none;
  border: 1px solid rgba(154, 124, 72, .55);
  box-shadow:
    inset 0 0 0 4px rgba(248, 243, 231, .5),
    inset 0 0 0 5px rgba(185, 154, 99, .45);
  background:
    linear-gradient(var(--hs-cover-accent), var(--hs-cover-accent)) top left / 26px 1px no-repeat,
    linear-gradient(var(--hs-cover-accent), var(--hs-cover-accent)) top left / 1px 26px no-repeat,
    linear-gradient(var(--hs-cover-accent), var(--hs-cover-accent)) top right / 26px 1px no-repeat,
    linear-gradient(var(--hs-cover-accent), var(--hs-cover-accent)) top right / 1px 26px no-repeat,
    linear-gradient(var(--hs-cover-accent), var(--hs-cover-accent)) bottom left / 26px 1px no-repeat,
    linear-gradient(var(--hs-cover-accent), var(--hs-cover-accent)) bottom left / 1px 26px no-repeat,
    linear-gradient(var(--hs-cover-accent), var(--hs-cover-accent)) bottom right / 26px 1px no-repeat,
    linear-gradient(var(--hs-cover-accent), var(--hs-cover-accent)) bottom right / 1px 26px no-repeat;
}
.hs-carta-bg-perla .hs-carta-portada::after {
  border-color: rgba(138, 146, 156, .5);
  box-shadow:
    inset 0 0 0 4px rgba(255, 255, 255, .4),
    inset 0 0 0 5px rgba(160, 166, 174, .4);
}
.hs-carta-grano {
  position: absolute;
  inset: 0;
  opacity: .28;
  background:
    repeating-linear-gradient(112deg, rgba(106, 80, 57, .035) 0 1px, transparent 1px 8px),
    repeating-linear-gradient(28deg, rgba(255, 255, 255, .20) 0 1px, transparent 1px 11px);
  mix-blend-mode: multiply;
  pointer-events: none;
}
.hs-carta-vineta {
  position: absolute;
  inset: 0;
  z-index: 3;
  background: radial-gradient(ellipse at 50% 46%, transparent 36%, rgba(83, 61, 31, .08) 72%, rgba(83, 61, 31, .20) 100%);
  pointer-events: none;
}
.hs-carta-destellos {
  position: absolute;
  inset: 0;
  z-index: 3;
  pointer-events: none;
}
.hs-carta-destellos span {
  position: absolute;
  width: 9px;
  height: 9px;
  opacity: 0;
  background:
    linear-gradient(90deg, transparent 47%, rgba(255, 251, 238, .95) 50%, transparent 53%),
    linear-gradient(0deg, transparent 47%, rgba(255, 251, 238, .95) 50%, transparent 53%);
  filter: drop-shadow(0 0 5px rgba(255, 236, 190, .78));
  animation: hsCartaTwinkle 6.5s ease-in-out infinite;
  will-change: transform, opacity;
}
.hs-carta-destellos .d1 { left: 17%; top: 26%; animation-delay: -1.4s; }
.hs-carta-destellos .d2 { left: 82%; top: 19%; width: 7px; height: 7px; animation-delay: -4.1s; }
.hs-carta-destellos .d3 { left: 74%; top: 64%; width: 6px; height: 6px; animation-delay: -2.7s; }
.hs-carta-destellos .d4 { left: 12%; top: 58%; width: 5px; height: 5px; animation-delay: -5.5s; }
.hs-carta-anillos,
.hs-carta-flor-esquina,
.hs-carta-cinta {
  position: absolute;
  display: block;
  background-repeat: no-repeat;
  background-position: center;
  background-size: contain;
  user-select: none;
  pointer-events: none;
}
.hs-carta-anillos {
  left: clamp(26px, 12vw, 160px);
  top: clamp(54px, 9vh, 116px);
  width: clamp(100px, 19vw, 190px);
  z-index: 2;
  aspect-ratio: 560 / 442;
  filter: drop-shadow(0 14px 15px rgba(83, 61, 31, .23));
  transform-origin: 50% 68%;
  animation: hsCartaFloatSoft 7.5s ease-in-out infinite;
  will-change: transform;
}
.hs-carta-anillos img {
  position: absolute;
  top: -22.4%;
  left: -11.3%;
  display: block;
  width: 116.68%;
  height: auto;
  pointer-events: none;
}
.hs-carta-flor-esquina {
  left: -7%;
  bottom: -8%;
  top: auto;
  height: min(52vh, 600px);
  width: auto;
  aspect-ratio: 760 / 1153;
  z-index: 1;
  background: none;
  filter: drop-shadow(0 20px 28px rgba(71, 56, 37, .21));
  transform: rotate(-4deg);
  transform-origin: 0 100%;
  animation: hsCartaSprigSway 10s ease-in-out infinite;
  will-change: transform;
}
.hs-carta-flor-esquina img {
  position: absolute;
  top: 50%;
  left: 50%;
  display: block;
  width: 172%;
  height: 75.58%;
  object-fit: contain;
  transform: translate(-50%, -50%) translate(4.264%, -3.76%) rotate(-90deg);
  transform-origin: 50% 50%;
  pointer-events: none;
}
.hs-carta-cinta {
  right: -8%;
  top: -5%;
  height: min(88vh, 940px);
  aspect-ratio: 368 / 1536;
  opacity: .88;
  filter: drop-shadow(-11px 14px 18px rgba(91, 69, 42, .14));
  transform-origin: 70% 20%;
  animation: hsCartaRibbonSway 11s ease-in-out infinite;
  will-change: transform;
}
.hs-carta-cinta img {
  position: absolute;
  inset: 0;
  display: block;
  width: 100%;
  height: 100%;
  object-fit: cover;
  object-position: 48% center;
  pointer-events: none;
}
.hs-carta-flap-open {
  position: absolute;
  left: 0;
  right: 0;
  bottom: 100%;
  z-index: 0;
  height: 47%;
  opacity: 0;
  pointer-events: none;
  clip-path: polygon(0 100%, 50% 0, 100% 100%);
  background: rgba(var(--hs-cover-accent-rgb), .40);
  filter: drop-shadow(0 -12px 18px rgba(var(--hs-cover-deep-rgb), .24));
  transform: scaleY(.12);
  transform-origin: 50% 100%;
  transition: opacity .42s ease .38s, transform .72s cubic-bezier(.2, .8, .2, 1) .3s;
}
.hs-carta-flap-open::before {
  content: '';
  position: absolute;
  inset: 1px;
  clip-path: inherit;
  background:
    linear-gradient(180deg, rgba(var(--hs-cover-deep-rgb), .10), transparent 38%),
    linear-gradient(180deg, var(--hs-cover-mid), var(--hs-cover-panel) 68%, var(--hs-cover-light));
  box-shadow:
    inset 0 0 0 1px rgba(var(--hs-cover-accent-rgb), .48),
    inset 0 -18px 26px rgba(var(--hs-cover-deep-rgb), .12);
}
.hs-carta-flap-open::after {
  content: '';
  position: absolute;
  left: 0;
  right: 0;
  bottom: 0;
  height: 1px;
  background: rgba(var(--hs-cover-accent-rgb), .42);
}
.envelope.opening .hs-carta-flap-open { opacity: 1; transform: scaleY(1); }
.hs-carta-petalo {
  position: absolute;
  z-index: 2;
  width: 10px;
  height: 7px;
  border-radius: 64% 36% 58% 42%;
  background: radial-gradient(circle at 30% 24%, #fffdf8, #efdcc3 58%, #d6b99c);
  box-shadow: 0 3px 7px rgba(93, 68, 43, .13);
  opacity: 0;
  animation: hsCartaPetalo 12s linear infinite;
  will-change: transform, opacity;
}
.hs-carta-petalo.p1 { left: 23%; top: 21%; animation-delay: -2.4s; }
.hs-carta-petalo.p2 { left: 78%; top: 31%; width: 8px; height: 6px; animation-delay: -7.2s; }
.hs-carta-petalo.p3 { left: 30%; top: 69%; width: 7px; height: 5px; animation-delay: -10.5s; }
.hs-carta-petalo.p4 { left: 69%; top: 73%; width: 11px; height: 8px; animation-delay: -4.8s; }
.hs-carta-petalo.p5 { left: 52%; top: 12%; width: 7px; height: 5px; animation-delay: -8.6s; }

.hs-carta-contenido {
  position: relative;
  z-index: 4;
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  width: 100%;
  min-height: 100%;
  padding: clamp(1rem, 3vw, 2rem);
  text-align: center;
}
.hs-carta-invite {
  position: absolute;
  left: 0;
  right: 0;
  top: clamp(1.5rem, 7vh, 4rem);
  z-index: 5;
  margin: 0;
  padding: 0 1rem;
  color: var(--hs-cover-soft) !important;
  font-family: 'Cormorant Garamond', serif !important;
  font-size: clamp(.78rem, 2.5vw, 1rem) !important;
  font-style: italic;
  font-weight: 600;
  letter-spacing: .12em !important;
  opacity: 1;
  pointer-events: none;
  animation: hsCartaFadeUp .9s .12s cubic-bezier(.2, .8, .2, 1) backwards;
}
.hs-carta-tilt {
  position: relative;
  display: flex;
  align-items: center;
  justify-content: center;
  width: calc(var(--hs-carta-card-w) * 1.17);
  height: calc(var(--hs-carta-card-w) * 1.17);
  margin: .2rem 0 1rem;
  transform: rotate(0deg);
  translate: 0 0;
  transform-origin: 50% 50%;
  animation: hsCartaCardIn 1.05s cubic-bezier(.18, .82, .22, 1) backwards;
  transition: transform .55s cubic-bezier(.2, .8, .2, 1);
  will-change: transform;
}
.hs-carta-rotor {
  position: relative;
  display: flex;
  align-items: center;
  justify-content: center;
  transform: rotate(-45deg);
  transform-origin: 50% 50%;
  transition: transform .55s cubic-bezier(.2, .8, .2, 1);
  will-change: transform;
}
.hs-presentation:hover .hs-carta-rotor { transform: rotate(-45deg) translateY(-3px); }

.hs-carta-stage {
  position: relative;
  width: var(--hs-carta-card-w);
  aspect-ratio: 1.55;
  margin: 0;
  perspective: 1200px;
  filter: drop-shadow(0 18px 34px rgba(var(--hs-cover-deep-rgb), .16)) drop-shadow(0 4px 9px rgba(var(--hs-cover-deep-rgb), .10));
  animation: hsCartaCardFloat 7s 1.05s ease-in-out infinite;
  will-change: transform;
}
.hs-carta-back {
  position: absolute;
  inset: 0;
  z-index: 1;
  overflow: hidden;
  border: 1px solid rgba(var(--hs-cover-accent-rgb), .38);
  border-radius: 2px;
  background:
    linear-gradient(180deg, rgba(255, 255, 255, .45), transparent 32%),
    repeating-linear-gradient(112deg, rgba(98, 72, 53, .022) 0 1px, transparent 1px 7px),
    linear-gradient(160deg, var(--hs-cover-light), var(--hs-cover-pale));
  box-shadow:
    0 18px 28px rgba(var(--hs-cover-deep-rgb), .16),
    inset 0 0 0 1px rgba(255, 255, 255, .38);
}
.hs-carta-liner {
  position: absolute;
  inset: 0;
  z-index: 1;
  opacity: 0;
  pointer-events: none;
  background:
    radial-gradient(circle at 50% 18%, rgba(255, 255, 255, .62), transparent 55%),
    repeating-linear-gradient(45deg, rgba(var(--hs-cover-accent-rgb), .05) 0 1px, transparent 1px 15px),
    repeating-linear-gradient(-45deg, rgba(var(--hs-cover-accent-rgb), .032) 0 1px, transparent 1px 21px),
    linear-gradient(160deg, var(--hs-cover-pale), var(--hs-cover-mid));
  box-shadow:
    inset 0 0 0 1px rgba(var(--hs-cover-accent-rgb), .22),
    inset 0 0 44px rgba(var(--hs-cover-deep-rgb), .07);
  transition: opacity .55s ease .1s;
}
.envelope.opening .hs-carta-liner { opacity: 1; }
.hs-carta-letter {
  position: absolute;
  left: 20%;
  right: 20%;
  top: 8%;
  height: 84%;
  z-index: 2;
  overflow: hidden;
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: flex-start;
  gap: .16rem;
  padding: .78rem .82rem;
  border: 1px solid rgba(var(--hs-cover-accent-rgb), .34);
  border-top: 2px solid rgba(var(--hs-cover-accent-rgb), .48);
  border-radius: 1px;
  background:
    radial-gradient(circle at 50% 0%, rgba(255, 255, 255, .98), transparent 60%),
    repeating-linear-gradient(112deg, rgba(98, 72, 53, .018) 0 1px, transparent 1px 8px),
    linear-gradient(145deg, var(--hs-cover-light), var(--hs-cover-panel));
  box-shadow:
    inset 0 0 0 1px rgba(255, 255, 255, .45),
    0 10px 22px rgba(var(--hs-cover-deep-rgb), .08);
  transform: translateY(0);
  transition: transform 1.08s cubic-bezier(.18, .78, .22, 1) .24s;
}
.hs-carta-letter::before {
  content: '';
  position: absolute;
  inset: 7px;
  border: 1px solid rgba(var(--hs-cover-accent-rgb), .18);
  pointer-events: none;
}
.hs-carta-letter-wm {
  position: absolute;
  left: 50%;
  top: 44%;
  z-index: 0;
  transform: translate(-50%, -50%);
  color: rgba(var(--hs-cover-accent-rgb), .09);
  font-family: 'Cormorant Garamond', serif;
  font-size: clamp(2.5rem, 8.6vw, 3.5rem);
  font-weight: 600;
  letter-spacing: .16em;
  text-indent: .16em;
  white-space: nowrap;
  pointer-events: none;
}
.hs-carta-letter-sprig {
  position: absolute;
  right: -8px;
  top: -10px;
  z-index: 0;
  width: 48%;
  height: 58%;
  overflow: hidden;
  transform: rotate(15deg);
  opacity: .34;
  filter: saturate(.84) brightness(1.03);
  -webkit-mask-image: linear-gradient(205deg, #000 0 42%, transparent 76%);
  mask-image: linear-gradient(205deg, #000 0 42%, transparent 76%);
  pointer-events: none;
}
.hs-carta-letter-sprig img {
  display: block;
  width: 100%;
  height: 100%;
  object-fit: cover;
  object-position: left top;
  pointer-events: none;
}
.hs-carta-letter > .hs-kicker,
.hs-carta-letter > .hs-carta-name,
.hs-carta-letter > .hs-carta-message,
.hs-carta-letter > .hs-carta-rule,
.hs-carta-letter > .hs-date,
.hs-carta-letter > .hs-carta-place {
  position: relative;
  z-index: 1;
}
.hs-carta-letter-kicker { margin-top: .1rem; color: var(--hs-cover-accent) !important; font-size: clamp(.46rem, 1.35vw, .58rem) !important; letter-spacing: .24em !important; }
.hs-carta-name {
  max-width: 100%;
  margin: .14rem 0 .05rem;
  font-size: clamp(2.3rem, 8.8vw, 3.5rem);
  line-height: .98;
  text-align: center;
  overflow-wrap: anywhere;
}
.hs-carta-message {
  max-width: 94%;
  margin: .12rem 0 0;
  color: var(--hs-cover-deep);
  font-family: 'Cormorant Garamond', serif;
  font-size: clamp(.86rem, 2.5vw, 1.02rem);
  font-weight: 600;
  font-style: italic;
  line-height: 1.3;
  letter-spacing: .01em;
}
.hs-carta-rule {
  display: block;
  position: relative;
  width: 66%;
  height: 7px;
  margin: .2rem auto .14rem;
}
.hs-carta-rule::before {
  content: '';
  position: absolute;
  left: 0;
  right: 0;
  top: 50%;
  height: 1px;
  background: linear-gradient(90deg, transparent, rgba(var(--hs-cover-accent-rgb), .52) 24%, rgba(var(--hs-cover-accent-rgb), .52) 76%, transparent);
}
.hs-carta-rule::after {
  content: '';
  position: absolute;
  left: 50%;
  top: 50%;
  width: 5px;
  height: 5px;
  margin: -2.5px 0 0 -2.5px;
  transform: rotate(45deg);
  background: var(--hs-cover-accent);
  opacity: .8;
}
.hs-carta-letter .hs-date { font-size: clamp(.74rem, 2.1vw, .9rem); font-weight: 600; letter-spacing: .12em; }
.hs-carta-place {
  max-width: 94%;
  margin: .08rem 0 0;
  color: var(--hs-cover-deep);
  font-family: 'Inter', sans-serif;
  font-size: clamp(.56rem, 1.6vw, .68rem);
  font-weight: 600;
  letter-spacing: .08em;
  line-height: 1.35;
  text-transform: uppercase;
  opacity: 1;
}
.hs-carta-envelope {
  position: absolute;
  inset: 0;
  z-index: 3;
  transform-style: preserve-3d;
}
.hs-carta-envelope::before {
  content: '';
  position: absolute;
  inset: 8px;
  z-index: 4;
  border: 1px solid rgba(var(--hs-cover-accent-rgb), .12);
  border-radius: 1px;
  box-shadow:
    inset 0 0 0 3px rgba(255, 255, 255, .16),
    inset 0 0 0 4px rgba(var(--hs-cover-accent-rgb), .10);
  pointer-events: none;
}
/* Esquinas doradas del sobre: cuatro ángulos de hilo fino. */
.hs-carta-envelope::after {
  content: '';
  position: absolute;
  inset: 14px;
  z-index: 4;
  pointer-events: none;
  opacity: .2;
  background:
    linear-gradient(rgba(var(--hs-cover-accent-rgb), .62), rgba(var(--hs-cover-accent-rgb), .62)) left top / 14px 1px no-repeat,
    linear-gradient(rgba(var(--hs-cover-accent-rgb), .62), rgba(var(--hs-cover-accent-rgb), .62)) left top / 1px 14px no-repeat,
    linear-gradient(rgba(var(--hs-cover-accent-rgb), .62), rgba(var(--hs-cover-accent-rgb), .62)) right top / 14px 1px no-repeat,
    linear-gradient(rgba(var(--hs-cover-accent-rgb), .62), rgba(var(--hs-cover-accent-rgb), .62)) right top / 1px 14px no-repeat,
    linear-gradient(rgba(var(--hs-cover-accent-rgb), .62), rgba(var(--hs-cover-accent-rgb), .62)) left bottom / 14px 1px no-repeat,
    linear-gradient(rgba(var(--hs-cover-accent-rgb), .62), rgba(var(--hs-cover-accent-rgb), .62)) left bottom / 1px 14px no-repeat,
    linear-gradient(rgba(var(--hs-cover-accent-rgb), .62), rgba(var(--hs-cover-accent-rgb), .62)) right bottom / 14px 1px no-repeat,
    linear-gradient(rgba(var(--hs-cover-accent-rgb), .62), rgba(var(--hs-cover-accent-rgb), .62)) right bottom / 1px 14px no-repeat;
}
.hs-carta-body {
  position: absolute;
  inset: 0;
  z-index: 1;
  clip-path: inset(0 0 0 0);
  overflow: hidden;
  border: 1px solid rgba(var(--hs-cover-accent-rgb), .22);
  border-radius: 2px;
  background:
    linear-gradient(118deg, rgba(255, 255, 255, .72), transparent 44%),
    linear-gradient(64deg, rgba(var(--hs-cover-accent-rgb), .03), transparent 38%),
    linear-gradient(296deg, rgba(var(--hs-cover-accent-rgb), .03), transparent 38%),
    repeating-linear-gradient(108deg, rgba(91, 66, 48, .02) 0 1px, transparent 1px 7px),
    radial-gradient(circle at 30% 20%, rgba(255, 255, 255, .5), transparent 55%),
    linear-gradient(180deg, #fbf7ef 0%, #f4ede1 58%, #efe6d6 100%);
  box-shadow:
    0 -5px 12px rgba(var(--hs-cover-deep-rgb), .12),
    0 18px 26px rgba(var(--hs-cover-deep-rgb), .1),
    inset 0 0 0 1px rgba(255, 255, 255, .32),
    inset 0 -10px 20px rgba(var(--hs-cover-deep-rgb), .05);
  transition: none;
  transform-origin: top center;
}
.hs-carta-body::before,
.hs-carta-body::after {
  content: '';
  position: absolute;
  bottom: 0;
  width: 55%;
  height: 1px;
  background: linear-gradient(90deg, rgba(var(--hs-cover-accent-rgb), .46), rgba(var(--hs-cover-accent-rgb), .04));
  box-shadow: 0 1px 0 rgba(255, 255, 255, .76);
}
.hs-carta-body::before { left: 0; transform-origin: bottom left; transform: rotate(24deg); }
.hs-carta-body::after {
  right: 0;
  transform-origin: bottom right;
  transform: rotate(-24deg);
  background: linear-gradient(270deg, rgba(var(--hs-cover-accent-rgb), .34), rgba(var(--hs-cover-accent-rgb), .03));
}
/* Juntura central del sobre: une la punta de la solapa con el borde. */
.hs-carta-fold {
  position: absolute;
  left: 50%;
  top: 46%;
  bottom: 5%;
  z-index: 3;
  width: 1px;
  height: auto;
  transform: translateX(-50%);
  background: linear-gradient(180deg, transparent, rgba(var(--hs-cover-accent-rgb), .24) 36%, rgba(var(--hs-cover-accent-rgb), .07));
  pointer-events: none;
}
/* Brillo de hoja: una pasada de luz muy lenta sobre el papel. */
.hs-carta-foil {
  position: absolute;
  inset: 0;
  z-index: 2;
  overflow: hidden;
  border-radius: 1px;
  background: linear-gradient(102deg, transparent 36%, rgba(255, 255, 255, .38) 47%, rgba(255, 255, 255, .10) 54%, transparent 64%);
  background-size: 240% 100%;
  background-position: 128% 0;
  mix-blend-mode: screen;
  animation: hsCartaFoilSweep 11s cubic-bezier(.4, 0, .2, 1) infinite;
  pointer-events: none;
  will-change: background-position;
}
.hs-carta-flap {
  position: absolute;
  left: 0;
  right: 0;
  top: 0;
  height: 46%;
  z-index: 5;
  transform-origin: top center;
  transform-style: preserve-3d;
  backface-visibility: hidden;
  transition: transform 1.15s cubic-bezier(.48, .02, .2, 1), opacity .4s ease .55s;
  filter: drop-shadow(0 10px 10px rgba(var(--hs-cover-deep-rgb), .26)) drop-shadow(0 1px 0 rgba(255, 255, 255, .45));
}
.hs-carta-flap-art {
  display: block;
  width: 100%;
  height: 100%;
}
.hs-carta-flap-art path {
  stroke: rgba(var(--hs-cover-accent-rgb), .42);
  stroke-width: .7;
  vector-effect: non-scaling-stroke;
}
.hs-carta-flap-art path.hs-carta-flap-inner {
  fill: none;
  stroke: rgba(var(--hs-cover-accent-rgb), .3);
  stroke-width: .5;
}
.hs-carta-flap-mark {
  position: absolute;
  top: 13%;
  left: 50%;
  z-index: 2;
  transform: translateX(-50%);
  color: var(--hs-cover-accent);
  font-family: 'Cormorant Garamond', serif;
  font-size: clamp(.66rem, 1.8vw, .88rem);
  font-weight: 600;
  letter-spacing: .3em;
  text-indent: .3em;
  opacity: .4;
  pointer-events: none;
}
.hs-carta-flap-mark::after {
  content: '';
  display: block;
  width: 18px;
  height: 1px;
  margin: .22rem auto 0;
  background: rgba(var(--hs-cover-accent-rgb), .38);
}
/* Lazada de seda bajo el sello de cera. */
.hs-carta-lazada {
  position: absolute;
  left: 50%;
  top: 46%;
  z-index: 5;
  width: 0;
  height: 0;
  pointer-events: none;
}
.hs-carta-lazada::before,
.hs-carta-lazada::after {
  content: '';
  position: absolute;
  top: -3px;
  width: 11px;
  height: 36px;
  background: linear-gradient(180deg, rgba(246, 240, 228, .95), rgba(214, 202, 180, .5));
  clip-path: polygon(0 0, 100% 0, 100% 84%, 50% 100%, 0 84%);
  transform-origin: 50% 0;
  box-shadow: 0 4px 7px rgba(var(--hs-cover-deep-rgb), .12);
}
.hs-carta-lazada::before { left: -11px; transform: rotate(14deg); }
.hs-carta-lazada::after { left: 0; transform: rotate(-14deg); }
.hs-carta-seal {
  position: absolute;
  left: 50%;
  top: 46%;
  z-index: 6;
  display: grid;
  place-items: center;
  width: clamp(58px, 15vw, 84px);
  aspect-ratio: 1;
  transform: translate(-50%, -50%);
  border: 1px solid rgba(255, 255, 255, .55);
  border-radius: 47% 53% 49% 51% / 52% 47% 53% 48%;
  background:
    radial-gradient(circle at 32% 26%, #fffdf8, #ece4d5 55%, #cdbfa6);
  color: rgba(120, 104, 78, .34);
  font-family: 'Cormorant Garamond', serif;
  font-size: clamp(.58rem, 1.55vw, .74rem);
  font-weight: 600;
  letter-spacing: .06em;
  box-shadow:
    0 8px 14px rgba(var(--hs-cover-deep-rgb), .22),
    inset 0 1px 2px rgba(255, 255, 255, .8),
    inset 0 -3px 5px rgba(160, 138, 104, .22);
  text-shadow:
    0 1px 1px rgba(255, 255, 255, .55),
    0 -1px 1px rgba(120, 100, 70, .2);
  transition: opacity .42s ease .16s, transform .58s cubic-bezier(.22, .8, .25, 1) .12s;
}
.hs-carta-seal::before {
  content: '';
  position: absolute;
  inset: 10%;
  border: 1px solid rgba(var(--hs-cover-deep-rgb), .28);
  border-radius: 50%;
}
.hs-carta-seal::after {
  content: '';
  position: absolute;
  inset: -5px;
  border: 1px solid rgba(var(--hs-cover-accent-rgb), .36);
  border-radius: 43% 57% 52% 48% / 55% 44% 56% 45%;
  transform: rotate(12deg);
  opacity: .6;
}
.hs-carta-tap {
  position: relative;
  z-index: 4;
  display: flex;
  align-items: center;
  justify-content: center;
  gap: .55rem;
  margin: 1.15rem 0 1.1rem;
  color: var(--hs-cover-ink);
  font-family: 'Cormorant Garamond', serif;
  font-size: clamp(.8rem, 2.4vw, .95rem);
  font-style: italic;
  font-weight: 600;
  letter-spacing: .05em;
  line-height: 1.2;
  opacity: .78;
  text-shadow: 0 1px 0 rgba(255, 255, 255, .42);
  animation: hsCartaFadeUp .9s .38s cubic-bezier(.2, .8, .2, 1) backwards;
}
.hs-carta-tap-line {
  display: block;
  width: 20px;
  height: 1px;
  background: linear-gradient(90deg, transparent, rgba(var(--hs-cover-accent-rgb), .62));
}
.hs-carta-tap-line:last-child { transform: scaleX(-1); }
.envelope.opening .hs-carta-invite { animation: none; opacity: 0; transform: translateY(-5px); transition: opacity .3s ease, transform .4s ease; }
.envelope.opening .hs-carta-tap { animation: none; opacity: 0; transform: translateY(4px); transition: opacity .3s ease, transform .4s ease; }
.envelope.opening .hs-carta-petalo { opacity: 0; transition: opacity .35s ease; }
.envelope.opening .hs-carta-destellos { opacity: 0; transition: opacity .5s ease; }
.envelope.opening .hs-carta-foil { opacity: 0; transition: opacity .55s ease; }
.envelope.opening .hs-carta-lazada { opacity: 0; transition: opacity .3s ease .06s; }
.envelope.opening .hs-carta-tilt {
  animation: none;
  transform: translateY(-8px) scale(1.01);
  transition: transform .95s cubic-bezier(.2, .8, .2, 1);
}
.envelope.opening .hs-carta-stage { animation-play-state: paused; }
.envelope.opening .hs-carta-flap { transform: rotateX(178deg); opacity: .3; }
.envelope.opening .hs-carta-letter { transform: translateY(-72%); }
.envelope.opening .hs-carta-letter > *:not(.hs-carta-letter-wm):not(.hs-carta-letter-sprig) { animation: hsCartaLetterContent .68s ease both; }
.envelope.opening .hs-carta-letter > .hs-kicker { animation-delay: .3s; }
.envelope.opening .hs-carta-letter > .hs-carta-name { animation-delay: .38s; }
.envelope.opening .hs-carta-letter > .hs-carta-rule { animation-delay: .46s; }
.envelope.opening .hs-carta-letter > .hs-line { animation-delay: .5s; }
.envelope.opening .hs-carta-letter > .hs-date { animation-delay: .56s; }
.envelope.opening .hs-carta-seal { opacity: 0; transform: translate(-50%, -50%) scale(.7) rotate(18deg); }
body.hs-cover-carta .envelope.opening {
  position: fixed;
  inset: 0;
  z-index: 40;
  cursor: default;
}
body.hs-cover-carta .envelope.opened { transform: none; }
/* Al abrir, la carta queda bajo flor, cinta y anillos: la portada deja de
   crear contexto de apilamiento para que sus objetos suban por encima. */
.envelope.opening .hs-carta-portada { z-index: auto; }
.envelope.opening .hs-carta-anillos,
.envelope.opening .hs-carta-flor-esquina,
.envelope.opening .hs-carta-cinta { z-index: 5; }

@keyframes hsCartaCardIn {
  from { opacity: 0; transform: scale(.94) translateY(18px); }
  to { opacity: 1; transform: scale(1) translateY(0); }
}
@keyframes hsCartaCardFloat {
  0%, 100% { transform: translateY(0); }
  50% { transform: translateY(-7px); }
}
@keyframes hsCartaPaperDrift {
  0% { transform: scale(1.02) translate3d(0, 0, 0); }
  100% { transform: scale(1.035) translate3d(-1.1%, -.7%, 0); }
}
@keyframes hsCartaLightBreathe {
  0%, 100% { opacity: .76; }
  50% { opacity: .98; }
}
@keyframes hsCartaFloatSoft {
  0%, 100% { transform: translateY(0) rotate(-9deg); }
  50% { transform: translateY(-7px) rotate(-6deg); }
}
@keyframes hsCartaSprigSway {
  0%, 100% { transform: rotate(-4deg) translateY(0); }
  50% { transform: rotate(-4.7deg) translateY(-4px); }
}
@keyframes hsCartaBloomSway {
  0%, 100% { transform: translateY(0) rotate(.5deg); }
  50% { transform: translateY(-4px) rotate(-.9deg); }
}
@keyframes hsCartaRibbonSway {
  0%, 100% { transform: rotate(-.5deg) translateY(0); }
  50% { transform: rotate(1.1deg) translateY(-5px); }
}
@keyframes hsCartaFoilSweep {
  0%, 58% { background-position: 128% 0; }
  100% { background-position: -36% 0; }
}
@keyframes hsCartaTwinkle {
  0%, 100% { opacity: 0; transform: scale(.55); }
  42% { opacity: .92; transform: scale(1); }
  62% { opacity: .28; transform: scale(.82); }
}
@keyframes hsCartaPetalo {
  0% { transform: translate3d(0, -14px, 0) rotate(0deg); opacity: 0; }
  12% { opacity: .72; }
  82% { opacity: .42; }
  100% { transform: translate3d(24px, 86vh, 0) rotate(155deg); opacity: 0; }
}
@keyframes hsCartaLetterContent {
  from { opacity: .35; transform: translateY(7px); }
  to { opacity: 1; transform: translateY(0); }
}
@keyframes hsCartaFadeUp {
  from { opacity: 0; transform: translateY(8px); }
  to { opacity: 1; transform: translateY(0); }
}

@media (max-width: 600px), (max-aspect-ratio: 4/5) {
  .hs-carta-papel { background-image: url("$kPortadaCartaFondoMovil"); }
  .hs-carta-anillos { left: 8%; top: 9%; width: clamp(96px, 26vw, 132px); }
  .hs-carta-flor-esquina { left: -20%; bottom: -22%; height: min(90vh, 680px); }
  .hs-carta-cinta { right: -12%; height: min(78vh, 760px); }
  .hs-carta-contenido { padding: 1.1rem .8rem; }
  .hs-carta-invite { top: clamp(1.2rem, 5.2vh, 2.5rem); }
  .hs-carta-letter-sprig { width: 54%; height: 50%; opacity: .30; }
  .hs-carta-destellos .d2, .hs-carta-destellos .d4 { display: none; }
}
@media (min-width: 601px) {
  .hs-scene-carta { --hs-carta-card-w: min(470px, 46vw); }
  .hs-carta-anillos {
    left: clamp(24px, 3.5vw, 80px);
    top: clamp(44px, 7vh, 96px);
    width: clamp(108px, 13vw, 166px);
  }
  .hs-carta-flor-esquina { left: -9%; bottom: -25%; height: min(102vh, 960px); }
  .hs-carta-cinta { right: -.5%; top: -2%; height: min(84vh, 860px); opacity: .92; }
}
@media (max-height: 700px) {
  .hs-carta-invite { margin-bottom: .4rem; }
  .hs-carta-tap { margin: .75rem 0 .7rem; }
  .hs-carta-cinta { height: 72vh; }
  .hs-carta-letter-wm { font-size: 2.4rem; }
}
@media (prefers-reduced-motion: reduce) {
  .hs-carta-papel,
  .hs-carta-luz,
  .hs-carta-anillos,
  .hs-carta-flor-esquina,
  .hs-carta-cinta,
  .hs-carta-petalo,
  .hs-carta-destellos span,
  .hs-carta-foil,
  .hs-carta-tilt,
  .hs-carta-stage,
  .hs-carta-invite,
  .hs-carta-tap { animation: none !important; }
  .envelope.opening .hs-carta-flap { transition-duration: 1.15s !important; }
  .envelope.opening .hs-carta-letter { transition-duration: 1.08s !important; }
}
''';
