import 'package:flutter_test/flutter_test.dart';

import 'package:hardstreet_admin/widgets/connection_topology.dart';

// ==================================================================
// DIAGRAMA DE SERVIDORES — ARISTAS DEL GRAFO
// ==================================================================
// El diagrama dibuja una línea por cada DEPENDENCIA entre servidores. Estas
// pruebas fijan las reglas de esas líneas, que es lo que no se puede ver a
// simple vista en una captura:
//
//   · A depende de B          → UNA arista, con flecha hacia B;
//   · A y B se dependen       → UNA sola arista MUTUA (flecha en las dos
//                               puntas), nunca dos líneas encimadas;
//   · ids que ya no existen   → se descartan (una dependencia huérfana no
//                               puede romper el diagrama);
//   · un servidor consigo mismo no es una arista.
// ==================================================================

NodeView _node(
  int id,
  String name, {
  List<int> deps = const [],
  bool online = true,
  bool blocked = false,
}) => NodeView(
  id: id,
  name: name,
  url: 'http://192.168.1.7$id:4000',
  enabled: true,
  online: online,
  blocked: blocked,
  dependsOnIds: deps,
  dependsOnNames: [for (final d in deps) 'nodo $d'],
);

void main() {
  test(
    'una dependencia normal es UNA arista hacia el servidor del que depende',
    () {
      final edges = topologyDependencyEdges([
        _node(1, 'Bodega'),
        _node(2, 'Respaldo', deps: const [1]),
      ]);

      expect(edges, hasLength(1));
      expect(edges.single.from, 2);
      expect(edges.single.to, 1);
      expect(edges.single.mutual, isFalse);
    },
  );

  test('si los dos se dependen, la arista es MUTUA (no dos líneas)', () {
    final edges = topologyDependencyEdges([
      _node(1, 'Bodega', deps: const [2]),
      _node(2, 'Respaldo', deps: const [1]),
    ]);

    expect(edges, hasLength(1), reason: 'dos líneas encimadas no se leerían');
    expect(edges.single.mutual, isTrue);
    expect({edges.single.from, edges.single.to}, {1, 2});
  });

  test('se descartan dependencias huérfanas y de sí mismo', () {
    final edges = topologyDependencyEdges([
      _node(1, 'Bodega', deps: const [1, 9]),
      _node(2, 'Respaldo', deps: const [1, 9]),
    ]);

    expect(edges, hasLength(1));
    expect(edges.single.from, 2);
    expect(edges.single.to, 1);
  });
}
