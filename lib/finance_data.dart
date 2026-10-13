// ==================================================================
// HARD STREET ADMIN - Modelo de FINANZAS
//
// Traduce (de forma TOLERANTE) la respuesta de /api/admin/finance a
// objetos que usan el módulo Finanzas y el Dashboard:
//   FinanceData.totals    ganancias, por cobrar, disponible, ahorro…
//   FinanceData.packages  el dinero de cada paquete activo
//   FinanceData.months    serie de los últimos meses (para la gráfica)
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
  });

  /// Suma de los precios de los paquetes activos.
  final num facturado;

  /// Abonos cobrados (dinero que YA entró).
  final num ganancias;

  /// Falta por cobrar (saldo de los paquetes).
  final num porCobrar;

  /// Dinero libre: ganancias - gastado (gasto + inversión).
  final num disponible;

  /// Apartado en el ahorro.
  final num ahorro;
  final num inversiones;
  final num gastos;
  final num abonoExterno;

  /// Todo lo que salió del paquete: gastos + inversiones.
  num get gastado => gastos + inversiones;

  static num _num(Object? v) => v is num ? v : 0;

  factory FinanceTotals.fromJson(Map<String, dynamic> json) => FinanceTotals(
        facturado: _num(json['facturado']),
        ganancias: _num(json['ganancias'] ?? json['abonado']),
        porCobrar: _num(json['porCobrar']),
        disponible: _num(json['disponible']),
        ahorro: _num(json['ahorro'] ?? json['ahorrado']),
        inversiones: _num(json['inversiones'] ?? json['invertido']),
        gastos: _num(json['gastos'] ?? json['gastado']),
        abonoExterno: _num(json['abonoExterno']),
      );
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

  /// Etiqueta corta para los selectores: "Boda - Premium · Ana Ruiz".
  String get label => clientName.isEmpty ? name : '$name · $clientName';

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

/// Respuesta completa de /api/admin/finance.
class FinanceData {
  const FinanceData({
    this.currency = 'MXN',
    this.totals = const FinanceTotals(),
    this.packages = const [],
    this.months = const [],
  });

  final String currency;
  final FinanceTotals totals;
  final List<FinancePackage> packages;
  final List<FinanceMonth> months;

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
        packages: _list(json['packages'], FinancePackage.fromJson),
        months: _list(json['months'], FinanceMonth.fromJson),
      );
}
