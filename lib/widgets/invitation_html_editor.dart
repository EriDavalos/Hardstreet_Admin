// ==================================================================
// CAPA DE EDICIÓN SOBRE EL HTML REAL
// ==================================================================
// El lienzo del editor NO puede ser una maqueta de Flutter: tiene que ser
// exactamente el documento que se publica. Para poder editar sin tocar el
// diseño, se inyectan dos cosas pequeñas en el propio HTML:
//
//   1. CSS de editor (contorno al pasar el ratón y una barra flotante).
//   2. Un script que crea esa barra, permite reordenar los bloques y avisa
//      a Flutter con `callHandler('hsEditor', ...)`.
//
// El documento original no se reescribe: la barra vive fuera del flujo
// (`position: fixed`) y los bloques conservan su `display: contents`.
// ==================================================================

/// Inyecta la capa de edición en un documento de invitación ya generado.
///
/// [openAtStart] oculta el sobre y abre la invitación, que es lo que necesita
/// el panel derecho del editor. La portada tiene su propio WebView.
String injectInvitationEditor(String html, {required bool openAtStart}) {
  if (html.isEmpty) return html;
  final script = _kInvitationEditorJs.replaceAll(
    '__HS_OPEN_AT_START__',
    openAtStart ? 'true' : 'false',
  );
  var out = html;
  if (out.contains('</head>')) {
    out = out.replaceFirst(
      '</head>',
      '<style>$_kInvitationEditorCss</style></head>',
    );
  }
  if (out.contains('</body>')) {
    out = out.replaceFirst('</body>', '<script>$script</script></body>');
  }
  return out;
}

/// Se expone para las pruebas y para el editor de estilos.
String get invitationEditorCss => _kInvitationEditorCss;

/// Se expone para las pruebas del puente JS.
String get invitationEditorJs => _kInvitationEditorJs;

const String _kInvitationEditorCss = r'''
/* ===== SOLO EDITOR: no altera el diseño de la invitación ===== */
html.hs-editor {
  scroll-behavior: auto;
}
html.hs-editor .hs-edit-host {
  position: relative !important;
}
html.hs-editor .hs-edit-host.hs-edit-hover {
  outline: 1.5px dashed var(--hs-comp-accent, #b76e79) !important;
  outline-offset: 4px;
}
html.hs-editor .hs-edit-host.hs-edit-dragover {
  outline: 2px solid var(--hs-comp-accent, #b76e79) !important;
  outline-offset: 5px;
}
html.hs-editor.hs-editor-open #envelope {
  display: none !important;
}
html.hs-editor.hs-editor-open #invitation {
  opacity: 1 !important;
  transform: none !important;
}
html.hs-editor .hs-edit-drop-end {
  display: none;
  margin: 12px 20px 22px;
  padding: 12px;
  border: 1.5px dashed var(--hs-comp-accent, #b76e79);
  border-radius: 10px;
  color: var(--hs-comp-accent, #b76e79);
  font: 700 11px/1.3 Inter, Arial, sans-serif;
  letter-spacing: .02em;
  text-align: center;
  background: rgba(255, 255, 255, .76);
}
html.hs-editor.hs-dragging .hs-edit-drop-end {
  display: block;
}
html.hs-editor .hs-editbar {
  position: fixed;
  z-index: 2147483000;
  display: none;
  align-items: center;
  gap: 2px;
  max-width: min(260px, calc(100vw - 16px));
  padding: 3px 4px 3px 8px;
  border-radius: 8px;
  background: #201b18;
  color: #fff;
  box-shadow: 0 7px 22px rgba(0, 0, 0, .26);
  font: 600 10px/1.2 Inter, Arial, sans-serif;
  user-select: none;
}
html.hs-editor .hs-editbar.on {
  display: flex;
}
html.hs-editor .hs-editbar-label {
  max-width: 104px;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
  color: rgba(255, 255, 255, .88);
}
html.hs-editor .hs-editbar-grip {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  width: 20px;
  height: 20px;
  margin-left: 2px;
  border-radius: 5px;
  color: rgba(255, 255, 255, .72);
  cursor: grab;
  letter-spacing: 1px;
}
html.hs-editor .hs-editbar-grip:hover {
  background: rgba(255, 255, 255, .14);
  color: #fff;
}
html.hs-editor .hs-editbar-grip:active {
  cursor: grabbing;
}
html.hs-editor .hs-editbar button {
  appearance: none;
  border: 0;
  border-radius: 5px;
  padding: 5px 7px;
  background: transparent;
  color: #fff;
  font: 600 10px/1.1 Inter, Arial, sans-serif;
  cursor: pointer;
}
html.hs-editor .hs-editbar button:hover {
  background: rgba(255, 255, 255, .15);
}
html.hs-editor .hs-editbar button[data-action="remove"] {
  color: #ffb4ae;
}
html.hs-editor .hs-editbar button[data-action="remove"]:hover {
  background: rgba(255, 120, 110, .20);
}
''';

const String _kInvitationEditorJs = r'''
(function () {
  var OPEN_AT_START = __HS_OPEN_AT_START__;
  var dragged = null;
  var active = null;
  var bar = null;
  var hideTimer = null;

  function send(action, key, before) {
    try {
      var bridge = window.flutter_inappwebview;
      if (bridge && bridge.callHandler) {
        bridge.callHandler('hsEditor', {
          action: action,
          key: key,
          before: before || null
        });
      }
    } catch (e) {}
  }

  function esc(value) {
    return String(value).replace(/[&<>"']/g, function (ch) {
      return {'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[ch];
    });
  }

  function positionBar() {
    if (!bar || !active || !bar.classList.contains('on')) return;
    var rect = active.getBoundingClientRect();
    if (rect.bottom < 0 || rect.top > window.innerHeight) {
      bar.classList.remove('on');
      return;
    }
    var width = bar.offsetWidth || 150;
    var height = bar.offsetHeight || 28;
    var left = Math.max(8, Math.min(window.innerWidth - width - 8, rect.right - width - 8));
    var top = Math.max(8, Math.min(window.innerHeight - height - 8, rect.top + 8));
    bar.style.left = left + 'px';
    bar.style.top = top + 'px';
  }

  function showBar(host) {
    active = host;
    if (hideTimer) { clearTimeout(hideTimer); hideTimer = null; }
    if (!bar) return;
    bar.querySelector('.hs-editbar-label').textContent =
      host.getAttribute('data-hs-label') || 'Componente';
    var grip = bar.querySelector('.hs-editbar-grip');
    var flow = host.getAttribute('data-hs-flow') === 'true';
    grip.style.display = flow ? 'inline-flex' : 'none';
    bar.classList.add('on');
    positionBar();
  }

  function scheduleHide() {
    if (hideTimer) clearTimeout(hideTimer);
    hideTimer = setTimeout(function () {
      hideTimer = null;
      if (bar) bar.classList.remove('on');
      active = null;
    }, 180);
  }

  function installBar() {
    if (bar) return bar;
    bar = document.createElement('div');
    bar.className = 'hs-editbar';
    bar.innerHTML =
      '<span class="hs-editbar-label"></span>' +
      '<span class="hs-editbar-grip" draggable="true" title="Arrastrar">&#10495;</span>' +
      '<button type="button" data-action="edit">Editar</button>' +
      '<button type="button" data-action="remove">Quitar</button>';
    document.body.appendChild(bar);

    bar.addEventListener('mouseenter', function () {
      if (hideTimer) { clearTimeout(hideTimer); hideTimer = null; }
    });
    bar.addEventListener('mouseleave', scheduleHide);
    bar.addEventListener('click', function (event) {
      var button = event.target.closest('button[data-action]');
      if (!button || !active) return;
      event.preventDefault();
      event.stopPropagation();
      var key = active.getAttribute('data-hs-key');
      var action = button.getAttribute('data-action');
      send(action, key, null);
      bar.classList.remove('on');
    });

    var grip = bar.querySelector('.hs-editbar-grip');
    grip.addEventListener('dragstart', function (event) {
      if (!active) { event.preventDefault(); return; }
      var flow = active.getAttribute('data-hs-flow') === 'true';
      if (!flow) { event.preventDefault(); return; }
      dragged = active.getAttribute('data-hs-key');
      event.dataTransfer.effectAllowed = 'move';
      event.dataTransfer.setData('text/plain', dragged);
      document.documentElement.classList.add('hs-dragging');
      bar.classList.remove('on');
    });
    grip.addEventListener('dragend', function () {
      dragged = null;
      document.documentElement.classList.remove('hs-dragging');
      document.querySelectorAll('.hs-edit-dragover').forEach(function (el) {
        el.classList.remove('hs-edit-dragover');
      });
    });
    return bar;
  }

  function installEndDrop() {
    var invitation = document.getElementById('invitation');
    if (!invitation || document.getElementById('hs-edit-drop-end')) return;
    var end = document.createElement('div');
    end.id = 'hs-edit-drop-end';
    end.className = 'hs-edit-drop-end';
    end.textContent = 'Suelta aquí para mover al final';
    end.addEventListener('dragover', function (event) {
      if (!dragged) return;
      event.preventDefault();
      event.dataTransfer.dropEffect = 'move';
      end.style.background = 'rgba(255, 255, 255, .96)';
    });
    end.addEventListener('dragleave', function () {
      end.style.background = '';
    });
    end.addEventListener('drop', function (event) {
      event.preventDefault();
      event.stopPropagation();
      end.style.background = '';
      if (!dragged) return;
      var moved = dragged;
      dragged = null;
      document.documentElement.classList.remove('hs-dragging');
      send('move', moved, null);
    });
    invitation.appendChild(end);
  }

  function installComponent(wrapper) {
    if (!wrapper || wrapper.getAttribute('data-hs-ready') === '1') return;
    var key = wrapper.getAttribute('data-component');
    if (!key || key === 'music') return;
    var host = wrapper.firstElementChild;
    if (!host) return;
    var flow = wrapper.getAttribute('data-flow') === 'true';
    wrapper.setAttribute('data-hs-ready', '1');
    host.classList.add('hs-edit-host');
    host.setAttribute('data-hs-key', key);
    host.setAttribute('data-hs-label', wrapper.getAttribute('data-label') || key);
    host.setAttribute('data-hs-flow', flow ? 'true' : 'false');
    host.addEventListener('mouseenter', function () {
      host.classList.add('hs-edit-hover');
      showBar(host);
    });
    host.addEventListener('mouseleave', function () {
      host.classList.remove('hs-edit-hover');
      scheduleHide();
    });
    if (flow) {
      host.addEventListener('dragover', function (event) {
        if (!dragged || dragged === key) return;
        event.preventDefault();
        event.dataTransfer.dropEffect = 'move';
        host.classList.add('hs-edit-dragover');
      });
      host.addEventListener('dragleave', function () {
        host.classList.remove('hs-edit-dragover');
      });
      host.addEventListener('drop', function (event) {
        event.preventDefault();
        event.stopPropagation();
        host.classList.remove('hs-edit-dragover');
        if (!dragged || dragged === key) return;
        var moved = dragged;
        dragged = null;
        document.documentElement.classList.remove('hs-dragging');
        send('move', moved, key);
      });
    }
  }

  function install() {
    document.documentElement.classList.add('hs-editor');
    if (OPEN_AT_START) {
      document.documentElement.classList.add('hs-editor-open');
      var cover = document.getElementById('envelope');
      var invitation = document.getElementById('invitation');
      if (cover) {
        cover.classList.add('opened');
        cover.style.setProperty('display', 'none', 'important');
      }
      if (invitation) invitation.classList.add('open');
      document.body.classList.remove('at-cover');
      document.body.classList.remove('no-scroll');
      setTimeout(function () {
        if (typeof observeSections === 'function') observeSections();
        if (typeof startCountdown === 'function') startCountdown();
      }, 40);
    }
    installBar();
    installEndDrop();
    document.querySelectorAll('.hs-comp[data-component]').forEach(installComponent);
    window.addEventListener('scroll', positionBar, true);
    window.addEventListener('resize', positionBar);
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', install);
  } else {
    install();
  }
})();
''';
