import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hardstreet_admin/modules/drive/widgets/connection_topology.dart';

// ==================================================================
// COLORES DEL DIAGRAMA DE CONEXIÓN
// ==================================================================
// La regla de la pantalla se lee de un vistazo:
//
//   · ROJO    → el servidor no responde (encendido en el Drive);
//   · NARANJA → bloqueado: sigue en funcionamiento, pero el Drive no lo usa
//               porque el servidor con el que está enlazado no responde o está
//               apagado;
//   · GRIS    → apagado en el Drive;
//   · AZUL    → no se pudo comprobar;
//   · VERDE   → en línea.
//
// El rojo manda sobre el naranja: si además de bloqueado no contesta, lo que
// hay que mirar es que está caído.
// ==================================================================

const _red = Color(0xFFDC2626);
const _orange = Color(0xFFEA580C);
const _grey = Color(0xFF6B7280);
const _blue = Color(0xFF2F6BFF);
const _green = Color(0xFF2F9E5B);

NodeView _node({bool enabled = true, bool? online, bool blocked = false}) {
  return NodeView(
    id: 1,
    name: 'Bodega',
    url: 'http://127.0.0.1:4100',
    enabled: enabled,
    online: online,
    blocked: blocked,
  );
}

void main() {
  test('sin respuesta va en ROJO (ya no comparte color con el bloqueo)', () {
    final node = _node(online: false);
    expect(node.color, _red);
    expect(node.noteColor, _red);
    expect(node.stateLabel, 'Sin respuesta');
  });

  test('bloqueado va en NARANJA aunque el servidor responda', () {
    final node = _node(online: true, blocked: true);
    expect(node.color, _orange);
    expect(node.noteColor, _orange);
    // Sigue en funcionamiento: solo el Drive lo da por no disponible.
    expect(node.online, true);
    expect(node.stateLabel, 'Mantenimiento');
  });

  test(
    'sin respuesta manda sobre bloqueado (está caído, no solo bloqueado)',
    () {
      expect(_node(online: false, blocked: true).color, _red);
    },
  );

  test('apagado en el Drive va en GRIS', () {
    expect(_node(enabled: false, online: true).color, _grey);
  });

  test('sin comprobar va en AZUL y en línea en VERDE', () {
    expect(_node(online: null).color, _blue);
    expect(_node(online: true).color, _green);
  });

  test('la card del HUB solo es roja si el HUB no contesta', () {
    // Un servidor caído no pinta de rojo al hub que sí responde.
    const up = HubView(
      url: 'http://oriongo.ddns.net:4000',
      online: true,
      onlineCount: 1,
      totalCount: 2,
    );
    expect(up.color, _green);

    // Con servidores bloqueados el Drive va a medias: naranja.
    const partial = HubView(
      url: 'http://oriongo.ddns.net:4000',
      online: true,
      onlineCount: 2,
      totalCount: 2,
      blocked: 1,
    );
    expect(partial.color, _orange);

    const down = HubView(url: 'http://oriongo.ddns.net:4000', online: false);
    expect(down.color, _red);
  });
}
