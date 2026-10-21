import 'package:flutter/material.dart';

import '../hs_api.dart';
import '../widgets/hs_toast.dart';

/// Selector de EMPRESA ACTIVA (solo Superadministrador).
///
/// El Superadministrador ve todas las empresas, pero trabaja dentro de UNA a
/// la vez: agendas, finanzas, archivos, paquetes y demás piden solo los datos
/// de la empresa elegida. Las peticiones viajan con `X-Company-Id`
/// (ver `HsApi._headers`), así el recorte lo hace el servidor.
///
/// Para cualquier otro usuario no dibuja nada: él trabaja siempre en la
/// empresa de SU cuenta.
class CompanySelector extends StatefulWidget {
  const CompanySelector({super.key, this.onChanged});

  /// La empresa activa cambió: el panel vuelve a montar el módulo actual.
  final VoidCallback? onChanged;

  @override
  State<CompanySelector> createState() => _CompanySelectorState();
}

class _CompanySelectorState extends State<CompanySelector> {
  List<Map<String, dynamic>> _companies = const [];
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (HsSession.isSuperAdmin) _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await HsApi.companies();
      if (!mounted) return;
      final active = list.where((c) => c['active'] != false).toList();
      setState(() {
        _companies = active;
        _loading = false;
      });
      // Sin empresa elegida, se arranca en la primera activa: trabajar
      // "en todas" no tiene sentido en Agendas ni en Finanzas.
      if (HsSession.activeCompanyId == null && active.isNotEmpty) {
        HsApi.setActiveCompany((active.first['id'] as num?)?.toInt());
        widget.onChanged?.call();
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '$e';
      });
    }
  }

  void _select(int? id) {
    HsApi.setActiveCompany(id);
    final name = _companies
        .firstWhere(
          (c) => (c['id'] as num?)?.toInt() == id,
          orElse: () => const <String, dynamic>{},
        )['name']
        ?.toString();
    HsToast.info(
      id == null
          ? 'Viendo todas las empresas'
          : 'Ahora trabajas en ${name ?? 'la empresa'}',
    );
    setState(() {});
    widget.onChanged?.call();
  }

  @override
  Widget build(BuildContext context) {
    if (!HsSession.isSuperAdmin) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;

    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(horizontal: 10),
        child: SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }

    if (_error != null) {
      return IconButton(
        tooltip: 'No se pudieron cargar las empresas · Reintentar',
        onPressed: _load,
        icon: Icon(Icons.apartment_outlined, color: scheme.error),
      );
    }

    final activeId = HsSession.activeCompanyId;
    final current = _companies.where(
      (c) => (c['id'] as num?)?.toInt() == activeId,
    );
    final label = current.isEmpty
        ? 'Todas'
        : (current.first['name'] ?? 'Empresa').toString();

    return PopupMenuButton<int?>(
      tooltip: 'Empresa con la que trabajas',
      onSelected: _select,
      itemBuilder: (context) => [
        const PopupMenuItem<int?>(
          value: null,
          child: Text('Todas las empresas'),
        ),
        const PopupMenuDivider(),
        for (final c in _companies)
          PopupMenuItem<int?>(
            value: (c['id'] as num?)?.toInt(),
            child: Row(
              children: [
                Icon(
                  (c['id'] as num?)?.toInt() == activeId
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked,
                  size: 16,
                  color: scheme.primary,
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    (c['name'] ?? '').toString(),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
      ],
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 4),
        padding: const EdgeInsets.fromLTRB(9, 6, 6, 6),
        decoration: BoxDecoration(
          color: scheme.primary.withValues(alpha: .12),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.apartment_rounded, size: 15, color: scheme.primary),
            const SizedBox(width: 6),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 130),
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: scheme.primary,
                ),
              ),
            ),
            Icon(Icons.arrow_drop_down, size: 18, color: scheme.primary),
          ],
        ),
      ),
    );
  }
}
