// ==================================================================
// HARD STREET ADMIN - Modelo de FINANZAS
//
// Traduce (de forma TOLERANTE) la respuesta de /api/admin/finance a
// objetos que usan el módulo Finanzas y el Dashboard:
//   FinanceData.totals    ganancias, por cobrar, disponible, ahorro…
//   FinanceData.packages  el dinero de cada paquete activo
//   FinanceData.months    serie de los últimos meses (para la gráfica)
//   FinanceData.movements los registros individuales (para DESGLOSAR la tabla)
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

  /// Suma de los precios de los paquetes activos.
  final num facturado;

  /// Abonos cobrados (dinero que YA entró).
  final num ganancias;

  /// Falta por cobrar (saldo de los paquetes).
  final num porCobrar;

  /// GANANCIA REAL / dinero libre: ganancias - gastado (gasto + inversión)
  /// - ahorro + abono externo. El ahorro se APARTA y el abono externo entra
  /// por fuera, igual que en el administrador del paquete.
  final num disponible;

  /// Apartado en el ahorro.
  final num ahorro;
  final num inversiones;
  final num gastos;
  final num abonoExterno;

  /// Pagos repartidos a colaboradores/empleados: SOLO registro, no son una
  /// salida (un "gasto invisible").
  final num pagos;

  /// Ganancia ESTIMADA: cobrado + abono externo − inversión − ahorro (el
  /// ahorro y la inversión se cuentan como salida, el gasto NO).
  final num gananciaEstimada;

  /// Ganancia REAL: la estimada menos los gastos. Coincide con el disponible.
  final num gananciaReal;

  /// Todo lo que salió del paquete: gastos + inversiones (los pagos no).
  num get gastado => gastos + inversiones;

  static num _num(Object? v) => v is num ? v : 0;

  factory FinanceTotals.fromJson(Map<String, dynamic> json) {
    final gastos = _num(json['gastos'] ?? json['gastado']);
    final ganancias = _num(json['ganancias'] ?? json['abonado']);
    final abonoExterno = _num(json['abonoExterno']);
    final inversiones = _num(json['inversiones'] ?? json['invertido']);
    final ahorro = _num(json['ahorro'] ?? json['ahorrado']);
    // Si el backend todavía no manda las ganancias, se derivan aquí con la
    // misma fórmula (así el módulo funciona con un servidor viejo).
    final estimada = json['gananciaEstimada'] != null
        ? _num(json['gananciaEstimada'])
        : ganancias + abonoExterno - inversiones - ahorro;
    return FinanceTotals(
      facturado: _num(json['facturado']),
      ganancias: ganancias,
      porCobrar: _num(json['porCobrar']),
      disponible: _num(json['disponible']),
      ahorro: ahorro,
      inversiones: inversiones,
      gastos: gastos,
      abonoExterno: abonoExterno,
      pagos: _num(json['pagos']),
      gananciaEstimada: estimada,
      gananciaReal: json['gananciaReal'] != null
          ? _num(json['gananciaReal'])
          : estimada - gastos,
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

  /// Pagos a colaboradores/empleados registrados SIN paquete (solo registro).
  final num pagos;

  /// Efecto neto en el dinero del negocio: abonos externos − gastado −
  /// ahorro (puede ser negativo).
  final num neto;

  /// Todo lo que salió: gastos + inversión.
  num get salidas => gastos + inversiones;

  bool get isEmpty =>
      gastos == 0 && inversiones == 0 && ahorro == 0 && abonoExterno == 0;

  factory FinanceGeneral.fromJson(Map<String, dynamic> json) {
    num n(Object? v) => v is num ? v : 0;
    return FinanceGeneral(
      gastos: n(json['gastos']),
      inversiones: n(json['inversiones']),
      ahorro: n(json['ahorro']),
      abonoExterno: n(json['abonoExterno']),
      pagos: n(json['pagos']),
      neto: n(json['neto']),
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

  /// Pagos del paquete a colaboradores/empleados (solo registro).
  final num pagos;

  /// Ganancia estimada del paquete (sin contar los gastos).
  final num gananciaEstimada;

  /// Etiqueta corta para los selectores: "Boda - Premium · Ana Ruiz".
  String get label => clientName.isEmpty ? name : '$name · $clientName';

  /// Todo lo que SALIÓ del paquete: gastos + inversión.
  num get salidas => gastos + inversiones;

  factory FinancePackage.fromJson(Map<String, dynamic> json) {
    num n(Object? v) => v is num ? v : 0;
    return FinancePackage(
      id: (json['id'] as num?)?.toInt() ?? 0,
      name: (json['name'] ?? '').toString(),
      clientName: (json['clientName'] ?? '').toString(),
      price: n(json['price']),
      paid: n(json['paid']),
      balance: n(json['balance']),
      disponible: n(json['disponible']),
      ahorro: n(json['ahorro']),
      gastos: n(json['gastos']),
      inversiones: n(json['inversiones']),
      abonoExterno: n(json['abonoExterno']),
      pagos: n(json['pagos']),
      gananciaEstimada: json['gananciaEstimada'] != null
          ? n(json['gananciaEstimada'])
          : n(json['paid']) -
              n(json['inversiones']) -
              n(json['ahorro']) +
              n(json['abonoExterno']),
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

/// Un movimiento INDIVIDUAL del negocio (para desglosar la tabla).
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
    this.userName = '',
  });

  final int id;
  final String kind;

  /// Quién recibió un PAGO (colaborador/empleado); vacío en el resto.
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
      userName: (json['userName'] ?? '').toString(),
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
  });

  final String currency;
  final FinanceTotals totals;

  /// Movimientos GENERALES (sin paquete): el dinero del negocio que no se
  /// atribuye a ningún paquete del cliente.
  final FinanceGeneral general;
  final List<FinancePackage> packages;
  final List<FinanceMonth> months;
  final List<FinanceMovement> movements;

  /// Los movimientos de UN paquete (los más recientes primero).
  List<FinanceMovement> movementsOf(int packageId) =>
      movements.where((m) => m.packageId == packageId).toList(growable: false);

  /// Los movimientos GENERALES (los que no pertenecen a ningún paquete).
  List<FinanceMovement> get generalMovements => movements
      .where((m) => m.packageId == 0)
      .toList(growable: false);

  /// Los movimientos de UN tipo (`abono`, `gasto`, `inversion`, `ahorro`,
  /// `abono_externo`).
  List<FinanceMovement> movementsOfKind(String kind) =>
      movements.where((m) => m.kind == kind).toList(growable: false);

  /// El paquete con ese id (o null).
  FinancePackage? packageOf(int id) {
    for (final p in packages) {
      if (p.id == id) return p;
    }
    return null;
  }

  static List<T> _list<T>(Object? raw, T Function(Map<String, dynamic>) parse) {
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((e) => parse(e.cast<String, dynamic>()))
        .toList();
  }

  factory FinanceData.fromJson(Map<String, dynamic> json) => FinanceData(
        currency: (json['currency'] ?? 'MXN').toString(),
        totals: FinanceTotals.fromJson(
            ((json['totals'] as Map?) ?? const {}).cast<String, dynamic>()),
        general: FinanceGeneral.fromJson(
            ((json['general'] as Map?) ?? const {}).cast<String, dynamic>()),
        packages: _list(json['packages'], FinancePackage.fromJson),
        months: _list(json['months'], FinanceMonth.fromJson),
        movements: _list(json['movements'], FinanceMovement.fromJson),
      );
}
