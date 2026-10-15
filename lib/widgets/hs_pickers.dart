import 'package:flutter/material.dart';

import '../theme.dart';

// ==================================================================
// HARD STREET ADMIN - Selectores de FECHA y HORA
//
// Envoltorios de `showDatePicker` / `showTimePicker` con la MISMA piel del
// panel: cabecera en el azul de la marca, esquinas redondeadas y el día de
// hoy marcado con el acento. Los usan el módulo Agendas y la agenda de un
// paquete del cliente, para que los dos se vean igual.
//
// El calendario se abre SOLO en vista de calendario (sin la pestaña de
// "escribir la fecha"): en el celular sobra y confunde.
// ==================================================================

/// Primer día que ofrece el calendario de una agenda (año pasado).
DateTime hsAgendaFirstDay() => DateTime(DateTime.now().year - 1, 1, 1);

/// Último día que ofrece el calendario de una agenda (cinco años adelante).
DateTime hsAgendaLastDay() => DateTime(DateTime.now().year + 5, 12, 31);

/// Calendario con el diseño del panel.
Future<DateTime?> showHsDatePicker(
  BuildContext context, {
  required DateTime initialDate,
  DateTime? firstDate,
  DateTime? lastDate,
  String helpText = 'Fecha del evento',
}) {
  final scheme = Theme.of(context).colorScheme;
  return showDatePicker(
    context: context,
    initialDate: initialDate,
    firstDate: firstDate ?? hsAgendaFirstDay(),
    lastDate: lastDate ?? hsAgendaLastDay(),
    helpText: helpText,
    initialEntryMode: DatePickerEntryMode.calendarOnly,
    builder: (ctx, child) => Theme(
      data: Theme.of(ctx).copyWith(
        datePickerTheme: DatePickerThemeData(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
          headerBackgroundColor: AppColors.brand,
          headerForegroundColor: Colors.white,
          todayBorder: const BorderSide(color: AppColors.brand, width: 1.6),
          dayBackgroundColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.selected)
                ? AppColors.brand
                : null,
          ),
          dayForegroundColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.selected)
                ? Colors.white
                : scheme.onSurface,
          ),
          dayOverlayColor:
              WidgetStatePropertyAll(AppColors.brand.withValues(alpha: .10)),
          yearShape: WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        ),
      ),
      child: child!,
    ),
  );
}

/// Reloj (esfera) con el diseño del panel.
Future<TimeOfDay?> showHsTimePicker(
  BuildContext context, {
  required DateTime initialTime,
  String helpText = 'Hora del evento',
}) {
  final scheme = Theme.of(context).colorScheme;
  return showTimePicker(
    context: context,
    initialTime: TimeOfDay.fromDateTime(initialTime),
    helpText: helpText,
    hourLabelText: 'Hora',
    minuteLabelText: 'Minutos',
    builder: (ctx, child) => Theme(
      data: Theme.of(ctx).copyWith(
        timePickerTheme: TimePickerThemeData(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
          backgroundColor: scheme.surface,
          hourMinuteColor: AppColors.brand.withValues(alpha: .10),
          hourMinuteTextColor: AppColors.brand,
          dayPeriodColor: AppColors.brand.withValues(alpha: .12),
          dayPeriodTextColor: AppColors.brand,
          dialHandColor: AppColors.brand,
          dialBackgroundColor: AppColors.brand.withValues(alpha: .08),
          entryModeIconColor: AppColors.brand,
        ),
      ),
      child: child!,
    ),
  );
}
