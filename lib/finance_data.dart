// ==================================================================
// HARD STREET ADMIN - Modelo de FINANZAS
//
// Traduce (de forma TOLERANTE) la respuesta de /api/admin/finance a
// objetos que usan el módulo Finanzas y el Dashboard:
//   FinanceData.totals    abonado, gastos, inversión, ahorro, por cobrar,
//                         abono externo, pagos y DINERO ACTUAL
//   FinanceData.packages  el dinero de cada paquete CON MOVIMIENTO
//   FinanceData.months    serie de los últimos meses (para la gráfica)
//   FinanceData.movements los registros individuales
//   FinanceData.payees    lo pagado a cada colaborador/empleado
//   FinanceData.payments  cada pago individual (para desglosar por persona)
//
// DINERO ACTUAL = abonado + abono externo - gastos e inversión de los
//                 PAQUETES - ahorro apartado - pagos. Los movimientos
//                 GENERALES (gasto/inversión) se pagan con el ahorro.
//
// Todo dato que falte viene en cero: la UI nunca revienta por un backend
// viejo o a medias.
// ==================================================================

/// Cuánto dinero hay en cada concepto (global).
class FinanceTotals {
  const FinanceTotals({
    this.facturado = 0,
    this.ganancias = 0,
    this.porCobrar = 0,
    this.disponible = 0,
    this.ahorro = 0,
    this.inversiones = 0,
    this.gastos = 0,
    this.abonoExterno = 0,
    this.pagos = 0,
    this.gananciaEstimada = 0,
    this.gananciaReal = 0,
  });

  /// Suma de los precios de los paquetes activos (con movimiento).
  final num facturado;

  /// ABONADO: todo lo que los clientes han abonado en todos los paquetes.
  final num ganancias;

  /// Falta por cobrar (saldo de los paquetes).
  final num porCobrar;

  /// DINERO ACTUAL: abonado + abono externo - gastos e inversión de los
  /// PAQUETES - ahorro apartado - pagos. Es lo que de verdad se tiene hoy:
  /// los movimientos GENERALES los paga el ahorro.
  final num disponible;

  /// Ahorro apartado (dinero del negocio guardado) MENOS los gastos e
  /// inversiones generales que se pagaron con él.
  final num ahorro;
  final num inversiones;
  final num gastos;

  /// Dinero extra que entra por fuera de los paquetes.
  final num abonoExterno;

  /// Pagos repartidos a colaboradores/empleados: SÍ salen del dinero.
  final num pagos;

  /// Ganancia ESTIMADA: abonado + abono externo − inversión − ahorro (sin
  /// descontar gastos ni pagos).
  final num gananciaEstimada;

  /// Ganancia REAL: la estimada menos gastos y pagos. Coincide con el
  /// disponible (el dinero actual).
  final num gananciaReal;

  /// Alias explícito para la UI: el dinero que se tiene actualmente.
  num get dineroActual => disponible;

  /// Todo lo que salió: gastos + inversiones (sin ahorro ni pagos).
  num get gastado => gastos + inversiones;

  /// Todo lo que salió del negocio con los pagos incluidos.
  num get salidas => gastos + inversiones + pagos;

  static num _num(Object? v) => v is num ? v : 0;

  factory FinanceTotals.fromJson(Map<String, dynamic> json) {
    final gastos = _num(json['gastos'] ?? json['gastado']);
    final ganancias = _num(json['ganancias'] ?? json['abonado']);
    final abonoExterno = _num(json['abonoExterno']);
    final inversiones = _num(json['inversiones'] ?? json['invertido']);
    final ahorro = _num(json['ahorro'] ?? json['ahorrado']);
    final pagos = _num(json['pagos']);
    // Si el backend todavía no manda el dinero actual, se deriva aquí con la
    // misma fórmula (así el módulo funciona con un servidor viejo).
    final estimada = json['gananciaEstimada'] != null
        ? _num(json['gananciaEstimada'])
        : ganancias + abonoExterno - inversiones - ahorro;
    final real = json['gananciaReal'] != null
        ? _num(json['gananciaReal'])
        : estimada - gastos - pagos;
    return FinanceTotals(
      facturado: _num(json['facturado']),
      ganancias: ganancias,
      porCobrar: _num(json['porCobrar']),
      disponible: json['disponible'] != null ? _num(json['disponible']) : real,
      ahorro: ahorro,
      inversiones: inversiones,
      gastos: gastos,
      abonoExterno: abonoExterno,
      pagos: pagos,
      gananciaEstimada: estimada,
      gananciaReal: real,
    );
  }
}

/// Dinero registrado SIN paquete: gastos, inversiones, ahorro y abonos
/// externos del NEGOCIO (los movimientos generales del módulo Finanzas).
class FinanceGeneral {
  const FinanceGeneral({
    this.gastos = 0,
    this.inversiones = 0,
    this.ahorro = 0,
    this.abonoExterno = 0,
    this.pagos = 0,
    this.neto = 0,
  });

  final num gastos;
  final num inversiones;
  final num ahorro;
  final num abonoExterno;

  /// Pagos a colaboradores/empleados registrados SIN paquete.
  final num pagos;

  /// Efecto neto en el dinero del negocio: abonos externos − gastado −
  /// ahorro − pagos (puede ser negativo).
  final num neto;

  /// Todo lo que salió: gastos + inversión.
  num get salidas => gastos + inversiones;

  bool get isEmpty =>
      gastos == 0 &&
      inversiones == 0 &&
      ahorro == 0 &&
      abonoExterno == 0 &&
      pagos == 0;

  factory FinanceGeneral.fromJson(Map<String, dynamic> json) {
    num n(Object? v) => v is num ? v : 0;
    final gastos = n(json['gastos']);
    final inversiones = n(json['inversiones']);
    final ahorro = n(json['ahorro']);
    final abonoExterno = n(json['abonoExterno']);
    final pagos = n(json['pagos']);
    return FinanceGeneral(
      gastos: gastos,
      inversiones: inversiones,
      ahorro: ahorro,
      abonoExterno: abonoExterno,
      pagos: pagos,
      neto: json['neto'] != null
          ? n(json['neto'])
          : abonoExterno - gastos - inversiones - ahorro - pagos,
    );
  }
}

/// Dinero de UN paquete activo (con su cliente).
class FinancePackage {
  const FinancePackage({
    required this.id,
    this.name = '',
    this.clientName = '',
    this.price = 0,
    this.paid = 0,
    this.balance = 0,
    this.disponible = 0,
    this.ahorro = 0,
    this.gastos = 0,
    this.inversiones = 0,
    this.abonoExterno = 0,
    this.pagos = 0,
    this.gananciaEstimada = 0,
  });

  final int id;
  final String name;
  final String clientName;
  final num price;
  final num paid;
  final num balance;
  final num disponible;
  final num ahorro;
  final num gastos;
  final num inversiones;
  final num abonoExterno;

  /// Pagos del paquete a colaboradores/empleados: sí salen del dinero.
  final num pagos;

  /// Ganancia estimada del paquete (sin contar gastos ni pagos).
  final num gananciaEstimada;

  /// Etiqueta corta para los selectores: "Boda - Premium · Ana Ruiz".
  String get label => clientName.isEmpty ? name : '$name · $clientName';

  /// Todo lo que SALIÓ del paquete: gastos + inversión.
  num get salidas => gastos + inversiones;

  /// ¿Tiene algún movimiento de dinero? (un paquete gratis sin nada no
  /// aparece en Finanzas).
  bool get hasActivity =>
      price > 0 ||
      paid > 0 ||
      gastos > 0 ||
      inversiones > 0 ||
      ahorro > 0 ||
      abonoExterno > 0 ||
      pagos > 0;

  factory FinancePackage.fromJson(Map<String, dynamic> json) {
    num n(Object? v) => v is num ? v : 0;
    final gastos = n(json['gastos']);
    final inversiones = n(json['inversiones']);
    final ahorro = n(json['ahorro']);
    final abonoExterno = n(json['abonoExterno']);
    final pagos = n(json['pagos']);
    final paid = n(json['paid']);
    return FinancePackage(
      id: (json['id'] as num?)?.toInt() ?? 0,
      name: (json['name'] ?? '').toString(),
      clientName: (json['clientName'] ?? '').toString(),
      price: n(json['price']),
      paid: paid,
      balance: n(json['balance']),
      disponible: json['disponible'] != null
          ? n(json['disponible'])
          : paid + abonoExterno - gastos - inversiones - ahorro - pagos,
      ahorro: ahorro,
      gastos: gastos,
      inversiones: inversiones,
      abonoExterno: abonoExterno,
      pagos: pagos,
      gananciaEstimada: json['gananciaEstimada'] != null
          ? n(json['gananciaEstimada'])
          : paid + abonoExterno - inversiones - ahorro,
    );
  }
}

/// Un mes de la serie (para las barras de la gráfica).
class FinanceMonth {
  const FinanceMonth({
    required this.month,
    required this.label,
    this.ganancias = 0,
    this.gastos = 0,
    this.inversiones = 0,
    this.ahorro = 0,
    this.abonoExterno = 0,
  });

  /// `YYYY-MM`.
  final String month;

  /// Etiqueta corta: "oct".
  final String label;

  final num ganancias;
  final num gastos;
  final num inversiones;
  final num ahorro;
  final num abonoExterno;

  /// Todo lo que salió ese mes.
  num get gastado => gastos + inversiones;

  /// Escala de la barra: el mayor entre lo que entró y lo que salió.
  num get peak {
    final inTop = ganancias + abonoExterno;
    final outTop = gastado + ahorro;
    return inTop > outTop ? inTop : outTop;
  }

  factory FinanceMonth.fromJson(Map<String, dynamic> json) {
    num n(Object? v) => v is num ? v : 0;
    return FinanceMonth(
      month: (json['month'] ?? '').toString(),
      label: (json['label'] ?? '').toString(),
      ganancias: n(json['ganancias']),
      gastos: n(json['gastos']),
      inversiones: n(json['inversiones']),
      ahorro: n(json['ahorro']),
      abonoExterno: n(json['abonoExterno']),
    );
  }
}

/// Un movimiento INDIVIDUAL del negocio.
/// Los abonos llegan con [kind] = `abono`.
class FinanceMovement {
  const FinanceMovement({
    required this.id,
    required this.kind,
    this.packageId = 0,
    this.packageName = '',
    this.clientName = '',
    this.amount = 0,
    this.description = '',
    this.created = '',
    this.userId = 0,
    this.userName = '',
  });

  final int id;
  final String kind;

  /// Quién recibió un PAGO (colaborador/empleado); vacío en el resto.
  final int userId;
  final String userName;

  /// 0 = movimiento GENERAL (del negocio, sin paquete).
  final int packageId;
  final String packageName;
  final String clientName;
  final num amount;
  final String description;

  /// Fecha tal cual la manda la API (`yyyy-MM-ddTHH:mm:ss`).
  final String created;

  factory FinanceMovement.fromJson(Map<String, dynamic> json) {
    num n(Object? v) => v is num ? v : 0;
    return FinanceMovement(
      id: (json['id'] as num?)?.toInt() ?? 0,
      kind: (json['kind'] ?? 'gasto').toString(),
      packageId: (json['packageId'] as num?)?.toInt() ?? 0,
      packageName: (json['packageName'] ?? '').toString(),
      clientName: (json['clientName'] ?? '').toString(),
      amount: n(json['amount']),
      description: (json['description'] ?? '').toString(),
      created: (json['created'] ?? '').toString(),
      userId: (json['userId'] as num?)?.toInt() ?? 0,
      userName: (json['userName'] ?? '').toString(),
    );
  }
}

/// Lo que se le ha pagado a UNA persona (colaborador o empleado).
class FinancePayee {
  const FinancePayee({
    this.userId = 0,
    this.name = '',
    this.roleName = '',
    this.total = 0,
    this.count = 0,
    this.packageCount = 0,
    this.lastPaid = '',
  });

  final int userId;
  final String name;
  final String roleName;

  /// Total histórico pagado a esta persona.
  final num total;

  /// Cuántos pagos recibió.
  final int count;

  /// En cuántos paquetes se le pagó.
  final int packageCount;

  /// Fecha del último pago (`yyyy-MM-ddTHH:mm:ss`).
  final String lastPaid;

  String get label => name.isEmpty ? 'Sin destinatario' : name;

  factory FinancePayee.fromJson(Map<String, dynamic> json) {
    num n(Object? v) => v is num ? v : 0;
    return FinancePayee(
      userId: (json['userId'] as num?)?.toInt() ?? 0,
      name: (json['name'] ?? '').toString(),
      roleName: (json['roleName'] ?? '').toString(),
      total: n(json['total']),
      count: (json['count'] as num?)?.toInt() ?? 0,
      packageCount: (json['packageCount'] as num?)?.toInt() ?? 0,
      lastPaid: (json['lastPaid'] ?? '').toString(),
    );
  }
}

/// UN pago repartido a una persona.
class FinancePayment {
  const FinancePayment({
    required this.id,
    this.userId = 0,
    this.userName = '',
    this.roleName = '',
    this.packageId = 0,
    this.packageName = '',
    this.clientName = '',
    this.amount = 0,
    this.description = '',
    this.created = '',
  });

  final int id;
  final int userId;
  final String userName;
  final String roleName;
  final int packageId;
  final String packageName;
  final String clientName;
  final num amount;
  final String description;
  final String created;

  factory FinancePayment.fromJson(Map<String, dynamic> json) {
    num n(Object? v) => v is num ? v : 0;
    return FinancePayment(
      id: (json['id'] as num?)?.toInt() ?? 0,
      userId: (json['userId'] as num?)?.toInt() ?? 0,
      userName: (json['userName'] ?? '').toString(),
      roleName: (json['roleName'] ?? '').toString(),
      packageId: (json['packageId'] as num?)?.toInt() ?? 0,
      packageName: (json['packageName'] ?? '').toString(),
      clientName: (json['clientName'] ?? '').toString(),
      amount: n(json['amount']),
      description: (json['description'] ?? '').toString(),
      created: (json['created'] ?? '').toString(),
    );
  }
}

/// Respuesta completa de /api/admin/finance.
class FinanceData {
  const FinanceData({
    this.currency = 'MXN',
    this.totals = const FinanceTotals(),
    this.general = const FinanceGeneral(),
    this.packages = const [],
    this.months = const [],
    this.movements = const [],
    this.payees = const [],
    this.payments = const [],
  });

  final String currency;
  final FinanceTotals totals;

  /// Movimientos GENERALES (sin paquete): el dinero del negocio que no se
  /// atribuye a ningún paquete del cliente.
  final FinanceGeneral general;

  /// Paquetes con dinero o movimientos (los gratis vacíos se omiten).
  final List<FinancePackage> packages;
  final List<FinanceMonth> months;
  final List<FinanceMovement> movements;

  /// Pagos agrupados por persona (colaboradores y empleados).
  final List<FinancePayee> payees;

  /// Cada pago individual, del más reciente al más viejo.
  final List<FinancePayment> payments;

  /// Los movimientos de UN paquete (los más recientes primero).
  List<FinanceMovement> movementsOf(int packageId) =>
      movements.where((m) => m.packageId == packageId).toList(growable: false);

  /// Los movimientos GENERALES (los que no pertenecen a ningún paquete).
  List<FinanceMovement> get generalMovements =>
      movements.where((m) => m.packageId == 0).toList(growable: false);

  /// Los movimientos de UN tipo (`abono`, `gasto`, `inversion`, `ahorro`,
  /// `abono_externo`, `pago`).
  List<FinanceMovement> movementsOfKind(String kind) =>
      movements.where((m) => m.kind == kind).toList(growable: false);

  /// Los pagos hechos a UNA persona (por id; 0 = los que no tienen
  /// destinatario).
  List<FinancePayment> paymentsOf(int userId) => payments
      .where((p) => p.userId == (userId > 0 ? userId : 0))
      .toList(growable: false);

  /// El paquete con ese id (o null).
  FinancePackage? packageOf(int id) {
    for (final p in packages) {
      if (p.id == id) return p;
    }
    return null;
  }

  /// Total pagado a colaboradores y empleados.
  num get totalPagos => payees.fold<num>(0, (sum, p) => sum + p.total);

  static List<T> _list<T>(Object? raw, T Function(Map<String, dynamic>) parse) {
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((e) => parse(e.cast<String, dynamic>()))
        .toList();
  }

  factory FinanceData.fromJson(Map<String, dynamic> json) {
    final packages = _list(
      json['packages'],
      FinancePackage.fromJson,
    ).where((p) => p.hasActivity).toList(growable: false);
    final movements = _list(json['movements'], FinanceMovement.fromJson);
    // Pagos: la API los manda aparte; con un backend viejo se derivan de los
    // movimientos de tipo `pago` que sí traen destinatario.
    var payments = _list(json['payments'], FinancePayment.fromJson);
    if (payments.isEmpty) {
      payments = movements
          .where((m) => m.kind == 'pago' && m.userName.trim().isNotEmpty)
          .map(
            (m) => FinancePayment(
              id: m.id,
              userId: m.userId,
              userName: m.userName,
              packageId: m.packageId,
              packageName: m.packageName,
              clientName: m.clientName,
              amount: m.amount,
              description: m.description,
              created: m.created,
            ),
          )
          .toList(growable: false);
    }
    var payees = _list(json['payees'], FinancePayee.fromJson);
    if (payees.isEmpty && payments.isNotEmpty) {
      final map = <int, List<FinancePayment>>{};
      for (final p in payments) {
        map.putIfAbsent(p.userId, () => []).add(p);
      }
      payees = map.entries.map((e) {
        final rows = e.value;
        final last = rows
            .map((p) => p.created)
            .reduce((a, b) => a.compareTo(b) >= 0 ? a : b);
        return FinancePayee(
          userId: e.key,
          name: rows.first.userName,
          roleName: rows.first.roleName,
          total: rows.fold<num>(0, (s, p) => s + p.amount),
          count: rows.length,
          packageCount: rows.map((p) => p.packageId).toSet().length,
          lastPaid: last,
        );
      }).toList()..sort((a, b) => b.total.compareTo(a.total));
    }
    return FinanceData(
      currency: (json['currency'] ?? 'MXN').toString(),
      totals: FinanceTotals.fromJson(
        ((json['totals'] as Map?) ?? const {}).cast<String, dynamic>(),
      ),
      general: FinanceGeneral.fromJson(
        ((json['general'] as Map?) ?? const {}).cast<String, dynamic>(),
      ),
      packages: packages,
      months: _list(json['months'], FinanceMonth.fromJson),
      movements: movements,
      payees: payees,
      payments: payments,
    );
  }
}
