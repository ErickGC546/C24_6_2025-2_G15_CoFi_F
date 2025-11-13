import 'package:flutter/material.dart';
import '../../../core/services/report_service.dart';
import '../../../core/services/home_service.dart';
import 'package:fl_chart/fl_chart.dart';

class ReportesView extends StatefulWidget {
  const ReportesView({super.key});

  @override
  State<ReportesView> createState() => _ReportesViewState();
}

class _ReportesViewState extends State<ReportesView> {
  // Estado para los toggles
  bool isPersonal = true;
  int periodo = 0; // 0: Semana, 1: Mes, 2: Año
  // ReportService
  final ReportService _reportService = ReportService();
  bool _loading = true;
  String? _error;
  Map<String, dynamic>? _generalReport;
  List<Map<String, dynamic>> _categories = [];
  List<Map<String, dynamic>> _weeklyReport = [];
  List<Map<String, dynamic>> _monthlyReport = [];
  List<Map<String, dynamic>> _yearlyReport = [];
  List<Map<String, dynamic>> _transactions = [];
  // Paleta de colores usada consistentemente para categorías (leyenda, pie, filas)
  final List<Color> _categoryColors = [
    Colors.orange,
    Colors.green,
    Colors.red,
    Colors.blue,
    Colors.purple,
    Colors.teal,
    Colors.amber,
  ];

  @override
  void initState() {
    super.initState();
    _loadReports();
  }

  Future<void> _loadReports() async {
    // Set loading state early if widget still mounted
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });

    // Fetch reports in parallel to speed up loading
    final futures = <String, Future>{
      'general': _reportService.getGeneralReport(),
      'categories': _reportService.getCategoryReport(),
      'weekly': _reportService.getWeeklyReport(),
      'monthly': _reportService.getMonthlyReport(),
      'yearly': _reportService.getYearlyReport(),
      'home': HomeService.getHomeData(),
    };

    // Await all and process results individually so a single failure doesn't
    // block the rest.
    final results = await Future.wait(
      futures.values.map((f) => f.catchError((e) => e)),
      eagerError: false,
    );

    // Use local variables to accumulate state changes so we call setState once
    String? localError = _error;
    Map<String, dynamic>? localGeneral = _generalReport;
    List<Map<String, dynamic>> localCategories = List.from(_categories);
    List<Map<String, dynamic>> localWeekly = List.from(_weeklyReport);
    List<Map<String, dynamic>> localMonthly = List.from(_monthlyReport);
    List<Map<String, dynamic>> localYearly = List.from(_yearlyReport);
    List<Map<String, dynamic>> localTransactions = List.from(_transactions);

    // Map results back to keys in the same order
    final keys = futures.keys.toList();
    for (int i = 0; i < results.length; i++) {
      final key = keys[i];
      final res = results[i];
      if (res is Exception || res is Error) {
        localError = (localError == null)
            ? 'Error cargando $key: $res'
            : '$localError; $key: $res';
        continue;
      }

      try {
        if (key == 'general') {
          localGeneral = (res as Map<String, dynamic>?) ?? localGeneral;
        } else if (key == 'categories') {
          final cats = (res as List<dynamic>?) ?? [];
          localCategories = cats
              .map((e) => Map<String, dynamic>.from(e))
              .toList();
        } else if (key == 'weekly') {
          final w = (res as List<dynamic>?) ?? [];
          localWeekly = w.map((e) => Map<String, dynamic>.from(e)).toList();
        } else if (key == 'monthly') {
          final m = (res as List<dynamic>?) ?? [];
          localMonthly = m.map((e) => Map<String, dynamic>.from(e)).toList();
        } else if (key == 'yearly') {
          final y = (res as List<dynamic>?) ?? [];
          localYearly = y.map((e) => Map<String, dynamic>.from(e)).toList();
        } else if (key == 'home') {
          final h = (res as Map<String, dynamic>?) ?? {};
          final tx = (h['transactions'] as List<dynamic>?) ?? [];
          localTransactions = tx
              .map((e) => Map<String, dynamic>.from(e))
              .toList();
        }
      } catch (e) {
        localError = (localError == null)
            ? 'Error procesando $key: $e'
            : '$localError; $key proceso: $e';
      }
    }

    // Finally commit changes if widget still mounted
    if (!mounted) return;
    setState(() {
      _error = localError;
      _generalReport = localGeneral;
      _categories = localCategories;
      _weeklyReport = localWeekly;
      _monthlyReport = localMonthly;
      _yearlyReport = localYearly;
      _transactions = localTransactions;
      _loading = false;
    });
  }

  // Sum incomes from cached transactions for the selected periodo.
  double _computeIncomeFromTransactionsForPeriod() {
    if (_transactions.isEmpty) return 0.0;
    final now = DateTime.now();
    double sum = 0.0;

    for (final t in _transactions) {
      try {
        final rawDate = t['occurredAt'] ?? t['createdAt'] ?? t['date'];
        DateTime dt;
        if (rawDate is DateTime)
          dt = rawDate;
        else if (rawDate is int)
          dt = DateTime.fromMillisecondsSinceEpoch(rawDate);
        else
          dt = DateTime.tryParse(rawDate?.toString() ?? '') ?? now;

        bool inPeriod = false;
        if (periodo == 0) {
          // last 7 days (including today)
          final diff = now.difference(dt).inDays;
          inPeriod = diff >= 0 && diff <= 6;
        } else if (periodo == 1) {
          inPeriod = (dt.year == now.year && dt.month == now.month);
        } else if (periodo == 2) {
          inPeriod = (dt.year == now.year);
        }

        if (!inPeriod) continue;

        // Amount extraction (numeric or parseable string)
        final rawAmount = t['amount'] ?? t['monto'] ?? 0;
        final amount = rawAmount is num
            ? rawAmount.toDouble()
            : double.tryParse(rawAmount?.toString() ?? '0') ?? 0.0;

        // Prefer explicit transaction type if provided. Many backends
        // use 'type' or 'tipo' and values like 'income' / 'expense' or
        // spanish 'ingreso' / 'gasto'. If type is present, rely on it.
        final dynamic typeRaw = t['type'] ?? t['tipo'] ?? '';
        final String typeStr = typeRaw?.toString().toLowerCase() ?? '';
        final bool hasType = typeStr.isNotEmpty;

        bool isIncome;
        if (hasType) {
          // match common variants for income
          isIncome =
              typeStr.contains('income') ||
              typeStr.contains('ingres') ||
              typeStr.contains('inflow') ||
              typeStr.contains('deposit');
        } else {
          // no explicit type: fall back to the sign of the amount
          // (positive -> income, negative -> expense)
          isIncome = amount > 0;
        }

        if (isIncome) sum += amount.abs();
      } catch (_) {}
    }

    return sum;
  }

  String _formatCurrency(dynamic value) {
    try {
      final numVal = (value ?? 0) as num;
      return 'S/ ${numVal.toStringAsFixed(0)}';
    } catch (_) {
      return 'S/ 0';
    }
  }

  // Sum a numeric field (or common fallbacks) from a list of maps
  double _sumFieldFromList(List<Map<String, dynamic>> list, String key) {
    double sum = 0.0;
    for (final item in list) {
      try {
        final raw =
            item[key] ?? item['amount'] ?? item['expenses'] ?? item['value'];
        final numVal = raw is num
            ? raw.toDouble()
            : double.tryParse(raw?.toString() ?? '0') ?? 0.0;
        sum += numVal.abs();
      } catch (_) {}
    }
    return sum;
  }

  // Compute display metrics (expenses, income, balance) considering selected period
  Map<String, double> _computeDisplayMetrics() {
    double expenses = 0.0;
    double income = 0.0;

    // Get period-specific expenses when available
    try {
      if (periodo == 0 && _weeklyReport.isNotEmpty) {
        expenses = _sumFieldFromList(_weeklyReport, 'expenses');
        // try to sum income if backend provided it in weekly items
        income = _sumFieldFromList(_weeklyReport, 'income');
      } else if (periodo == 1 && _monthlyReport.isNotEmpty) {
        expenses = _sumFieldFromList(_monthlyReport, 'expenses');
        income = _sumFieldFromList(_monthlyReport, 'income');
      } else if (periodo == 2 && _yearlyReport.isNotEmpty) {
        expenses = _sumFieldFromList(_yearlyReport, 'expenses');
        income = _sumFieldFromList(_yearlyReport, 'income');
      }
    } catch (_) {}

    // If income is zero, try general report fallback
    // If income is zero, try computing it from cached transactions for the period,
    // otherwise fallback to the general report values.
    try {
      if (income <= 0) {
        final txIncome = _computeIncomeFromTransactionsForPeriod();
        if (txIncome > 0) {
          income = txIncome;
        }
      }

      final gIncome =
          (_generalReport != null && _generalReport!['income'] != null)
          ? ((_generalReport!['income'] as num).toDouble())
          : 0.0;
      final gExpenses =
          (_generalReport != null && _generalReport!['expenses'] != null)
          ? ((_generalReport!['expenses'] as num).toDouble())
          : 0.0;

      if (income <= 0) income = gIncome;
      if (expenses <= 0) expenses = gExpenses;
    } catch (_) {}

    final balance = income - expenses;
    return {'expenses': expenses, 'income': income, 'balance': balance};
  }

  @override
  Widget build(BuildContext context) {
    // Local shortcuts
    final isLoading = _loading;
    final error = _error;
    final categories = _categories;

    if (isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    // We always render the main UI; if there are backend errors, show a compact banner
    final banner = (error != null)
        ? MaterialBanner(
            content: const Text('Hubo problemas cargando algunos reportes.'),
            leading: const Icon(Icons.error_outline, color: Colors.red),
            actions: [
              TextButton(
                onPressed: () {
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(SnackBar(content: Text(error)));
                },
                child: const Text('Detalles'),
              ),
              TextButton(
                onPressed: () {
                  setState(() {
                    _error = null; // dismiss banner
                  });
                },
                child: const Text('Cerrar'),
              ),
            ],
          )
        : null;

    return RefreshIndicator(
      onRefresh: _loadReports,
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Banner de error si existe
              if (banner != null) banner,

              // Encabezado y botón de Categorias
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Reportes',
                        style: TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        'Financieros',
                        style: TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 22),
              const Text(
                'Análisis detallado de tus finanzas',
                style: TextStyle(fontSize: 16, color: Colors.black54),
              ),
              const SizedBox(height: 32),
              // Selector de Vista: Personal / Grupos
              Row(
                children: [
                  const Text(
                    'Vista:',
                    style: TextStyle(fontSize: 16, color: Colors.black87),
                  ),
                  const SizedBox(width: 18),
                  // Reemplazado ToggleButtons por un botón único "Personal".
                  // Esto evita el error de aserción cuando solo queda una opción.
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(22),
                      ),
                      backgroundColor: isPersonal ? Colors.green : Colors.white,
                      foregroundColor: isPersonal
                          ? Colors.white
                          : Colors.black87,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      minimumSize: const Size(100, 38),
                      side: BorderSide(color: Colors.green),
                      elevation: 0,
                    ),
                    onPressed: () {
                      setState(() {
                        isPersonal = true;
                      });
                    },
                    icon: const Icon(Icons.person, size: 20),
                    label: const Text(
                      'Personal',
                      style: TextStyle(fontWeight: FontWeight.w500),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 28),
              // Selector de Periodo: Semana / Mes / Año
              Row(
                children: [
                  const Text(
                    'Periodo:',
                    style: TextStyle(fontSize: 16, color: Colors.black87),
                  ),
                  const SizedBox(width: 18),
                  ToggleButtons(
                    isSelected: [periodo == 0, periodo == 1, periodo == 2],
                    borderRadius: BorderRadius.circular(22),
                    selectedColor: Colors.white,
                    color: Colors.black87,
                    fillColor: Colors.green,
                    borderColor: Colors.green,
                    selectedBorderColor: Colors.green,
                    constraints: const BoxConstraints(
                      minHeight: 38,
                      minWidth: 76,
                    ),
                    onPressed: (index) {
                      setState(() {
                        periodo = index;
                      });
                    },
                    children: const [
                      Text(
                        'Semana',
                        style: TextStyle(fontWeight: FontWeight.w500),
                      ),
                      Text(
                        'Mes',
                        style: TextStyle(fontWeight: FontWeight.w500),
                      ),
                      Text(
                        'Año',
                        style: TextStyle(fontWeight: FontWeight.w500),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 32),
              // Mock estático de reportes: métricas, gráfico de barras, pie chart y resumen
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Row de métricas (calculadas desde datos cargados)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Builder(
                        builder: (context) {
                          final metrics = _computeDisplayMetrics();
                          return _metricCard(
                            'Gastos',
                            _formatCurrency(metrics['expenses']),
                            Colors.redAccent,
                          );
                        },
                      ),
                      Builder(
                        builder: (context) {
                          // Show only the user's income when in Personal view (from transactions
                          // filtered by periodo). For Groups view, keep previous behavior.
                          final double incomeValue = isPersonal
                              ? _computeIncomeFromTransactionsForPeriod()
                              : (_computeDisplayMetrics()['income'] ?? 0.0);
                          return _metricCard(
                            'Ingresos',
                            _formatCurrency(incomeValue),
                            Colors.green,
                          );
                        },
                      ),
                      Builder(
                        builder: (context) {
                          final metrics = _computeDisplayMetrics();
                          return _metricCard(
                            'Balance',
                            _formatCurrency(metrics['balance']),
                            Colors.green.shade700,
                          );
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),

                  // Card: Evolución (Bar chart) según periodo seleccionado
                  Card(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Evolución - Gastos',
                            style: TextStyle(fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 12),
                          SizedBox(height: 140, child: _periodicBarChart()),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),

                  // Card: Distribución por Categorías (Pie chart)
                  Card(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Distribución por Categorías',
                            style: TextStyle(fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 12),
                          SizedBox(
                            height: 160,
                            child: Row(
                              children: [
                                Expanded(child: _categoriesPieChart()),
                                const SizedBox(width: 12),
                                // Legend column
                                Expanded(
                                  child: SingleChildScrollView(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        for (
                                          var i = 0;
                                          i <
                                              (categories.isNotEmpty
                                                  ? categories.length
                                                  : 4);
                                          i++
                                        )
                                          () {
                                            final c = categories.isNotEmpty
                                                ? categories[i]
                                                : {
                                                    'name': i == 0
                                                        ? 'Alimentación'
                                                        : i == 1
                                                        ? 'Suministros'
                                                        : i == 2
                                                        ? 'Decoración'
                                                        : 'Tecnología',
                                                    'amount': i == 0
                                                        ? 120
                                                        : i == 1
                                                        ? 90
                                                        : i == 2
                                                        ? 60
                                                        : 30,
                                                  };

                                            final name =
                                                (c['name'] ??
                                                        c['category'] ??
                                                        'Categoría')
                                                    .toString();
                                            final rawAmount =
                                                c['amount'] ??
                                                c['monto'] ??
                                                c['value'] ??
                                                c['total'] ??
                                                0;
                                            final amt = rawAmount is num
                                                ? rawAmount.toDouble()
                                                : double.tryParse(
                                                        rawAmount.toString(),
                                                      ) ??
                                                      0.0;
                                            final color =
                                                _categoryColors[i %
                                                    _categoryColors.length];

                                            return Padding(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    vertical: 4,
                                                  ),
                                              child: Row(
                                                children: [
                                                  Container(
                                                    width: 12,
                                                    height: 12,
                                                    decoration: BoxDecoration(
                                                      color: color,
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                            3,
                                                          ),
                                                    ),
                                                  ),
                                                  const SizedBox(width: 8),
                                                  Expanded(
                                                    child: Text(
                                                      '$name — ${_formatCurrency(amt)}',
                                                      style: const TextStyle(
                                                        fontSize: 13,
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            );
                                          }(),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  // Tabs simulados (Resumen / Análisis)
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Text(
                            'Resumen General',
                            style: TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),

                  // Card: Resumen por Categorías (progreso)
                  Card(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Resumen por Categorías',
                            style: TextStyle(fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 12),
                          // Generate summary rows from categories fetched from the backend.
                          // If categories is empty, show fallback static rows.
                          if (categories.isNotEmpty) ...[
                            for (var i = 0; i < categories.length; i++)
                              () {
                                final c = categories[i];
                                final name =
                                    (c['name'] ?? c['category'] ?? 'Categoría')
                                        as String;
                                // Try common amount keys, allow string or number
                                dynamic rawAmount =
                                    c['amount'] ??
                                    c['monto'] ??
                                    c['value'] ??
                                    c['total'] ??
                                    0;
                                double amountDouble = 0.0;
                                if (rawAmount is num) {
                                  amountDouble = rawAmount.toDouble();
                                } else if (rawAmount is String) {
                                  amountDouble =
                                      double.tryParse(
                                        rawAmount.replaceAll(
                                          RegExp('[^0-9\.,-]'),
                                          '',
                                        ),
                                      ) ??
                                      0.0;
                                }
                                final percRaw =
                                    c['percentage'] ?? c['percent'] ?? 0;
                                final percentage = (percRaw is num)
                                    ? percRaw.toDouble()
                                    : double.tryParse('$percRaw') ?? 0.0;
                                final progress = (percentage / 100).clamp(
                                  0.0,
                                  1.0,
                                );
                                final color =
                                    _categoryColors[i % _categoryColors.length];

                                return Column(
                                  children: [
                                    _categoryRow(
                                      name,
                                      _formatCurrency(amountDouble),
                                      progress,
                                      color,
                                    ),
                                    const SizedBox(height: 8),
                                  ],
                                );
                              }(),
                          ] else ...[
                            _categoryRow(
                              'Alimentación',
                              'S/ 120',
                              0.4,
                              Colors.red,
                            ),
                            const SizedBox(height: 8),
                            _categoryRow(
                              'Suministros',
                              'S/ 90',
                              0.3,
                              Colors.blue,
                            ),
                            const SizedBox(height: 8),
                            _categoryRow(
                              'Decoración',
                              'S/ 60',
                              0.2,
                              Colors.orange,
                            ),
                            const SizedBox(height: 8),
                            _categoryRow(
                              'Tecnología',
                              'S/ 30',
                              0.1,
                              Colors.green,
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                ], // end inner Column children
              ), // end inner Column
            ], // end outer Column children
          ), // end outer Column
        ), // end Padding
      ),
    ); // end SingleChildScrollView
  }

  // Helper: tarjeta de métrica
  Widget _metricCard(String title, String value, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        margin: const EdgeInsets.symmetric(horizontal: 6),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black12,
              blurRadius: 6,
              offset: Offset(0, 2),
            ),
          ],
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: TextStyle(color: Colors.black54, fontSize: 12)),
            const SizedBox(height: 6),
            Text(
              value,
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Widget: gráfico de barras para el periodo seleccionado
  Widget _periodicBarChart() {
    // Build bars by grouping actual transactions by date (saved date)
    if (_transactions.isEmpty) {
      return Center(
        child: Text(
          'No hay datos para el periodo seleccionado',
          style: TextStyle(color: Colors.black54),
        ),
      );
    }

    // Helper: parse various date formats used in transactions
    DateTime _parseDate(dynamic raw) {
      final now = DateTime.now();
      try {
        if (raw == null) return now;
        if (raw is DateTime) return raw;
        if (raw is int) return DateTime.fromMillisecondsSinceEpoch(raw);
        final s = raw.toString();
        final parsed = DateTime.tryParse(s);
        if (parsed != null) return parsed;
        // try to parse as int string
        final maybeInt = int.tryParse(s);
        if (maybeInt != null)
          return DateTime.fromMillisecondsSinceEpoch(maybeInt);
      } catch (_) {}
      return now;
    }

    // Determine buckets depending on periodo
    final now = DateTime.now();
    List<DateTime> buckets = [];
    List<String> titles = [];

    if (periodo == 0) {
      // Semana: last 7 days (oldest -> newest) - use weekday short names
      final weekdayShort = ['Lun', 'Mar', 'Mié', 'Jue', 'Vie', 'Sáb', 'Dom'];
      for (int i = 6; i >= 0; i--) {
        final d = DateTime(
          now.year,
          now.month,
          now.day,
        ).subtract(Duration(days: i));
        buckets.add(d);
        titles.add(weekdayShort[d.weekday - 1]);
      }
    } else if (periodo == 1) {
      // Mes: show 12 months of the current year
      final months = [
        'Ene',
        'Feb',
        'Mar',
        'Abr',
        'May',
        'Jun',
        'Jul',
        'Ago',
        'Sep',
        'Oct',
        'Nov',
        'Dic',
      ];
      for (int m = 1; m <= 12; m++) {
        final d = DateTime(now.year, m, 1);
        buckets.add(d);
        titles.add(months[m - 1]);
      }
    } else {
      // Año: show a range of years based on transactions or last 5 years
      int startYear = now.year - 4;
      if (_transactions.isNotEmpty) {
        try {
          final years = _transactions.map((t) {
            final raw = t['occurredAt'] ?? t['createdAt'] ?? t['date'];
            if (raw is DateTime) return raw.year;
            if (raw is int)
              return DateTime.fromMillisecondsSinceEpoch(raw).year;
            final parsed = DateTime.tryParse(raw?.toString() ?? '');
            return parsed?.year ?? now.year;
          }).toList();
          final minYear = years.reduce((a, b) => a < b ? a : b);
          if (minYear < startYear) startYear = minYear;
        } catch (_) {}
      }
      for (int y = startYear; y <= now.year; y++) {
        buckets.add(DateTime(y, 1, 1));
        titles.add(y.toString());
      }
    }

    // Initialize sums
    final values = List<double>.filled(buckets.length, 0.0);

    for (final t in _transactions) {
      try {
        final rawDate = t['occurredAt'] ?? t['createdAt'] ?? t['date'];
        final dt = _parseDate(rawDate);

        // Determine if transaction is an expense
        final rawAmount = t['amount'] ?? t['monto'] ?? t['value'] ?? 0;
        final amount = rawAmount is num
            ? rawAmount.toDouble()
            : double.tryParse(rawAmount?.toString() ?? '0') ?? 0.0;
        final typeRaw = t['type'] ?? t['tipo'] ?? '';
        final typeStr = typeRaw?.toString().toLowerCase() ?? '';
        bool isExpense;
        if (typeStr.isNotEmpty) {
          isExpense =
              typeStr.contains('expense') ||
              typeStr.contains('gasto') ||
              typeStr.contains('outflow');
        } else {
          isExpense = amount < 0;
        }
        if (!isExpense) continue;

        // Find matching bucket
        for (int i = 0; i < buckets.length; i++) {
          final b = buckets[i];
          if (periodo == 0) {
            // Week: match by exact day
            if (dt.year == b.year && dt.month == b.month && dt.day == b.day) {
              values[i] += amount.abs();
              break;
            }
          } else if (periodo == 1) {
            // Month view: match by month
            if (dt.year == b.year && dt.month == b.month) {
              values[i] += amount.abs();
              break;
            }
          } else {
            // Year view: match by year
            if (dt.year == b.year) {
              values[i] += amount.abs();
              break;
            }
          }
        }
      } catch (_) {}
    }

    // Prepare values for rendering (custom rendering below, no fl_chart groups)

    // If all zero, show placeholder
    final allZero = values.every((v) => v <= 0);
    if (allZero) {
      return Center(
        child: Text(
          'No hay datos para el periodo seleccionado',
          style: TextStyle(color: Colors.black54),
        ),
      );
    }

    // Custom lightweight bar chart: capsule-style bars and a label over the
    // tallest bar. This is simpler and easier to style to match the mock.
    final maxVal = values.reduce((a, b) => a > b ? a : b);
    final bgGradient = LinearGradient(
      colors: [Colors.red.shade50, Colors.white],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    );

    return SizedBox(
      height: 200,
      child: Container(
        decoration: BoxDecoration(
          gradient: bgGradient,
          borderRadius: BorderRadius.circular(12),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        child: Column(
          children: [
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final chartHeight = constraints.maxHeight;
                  // Use horizontal scrolling to avoid pixel overflow when there are many buckets
                  return SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: List.generate(values.length, (i) {
                        final val = values[i];
                        final heightFactor = (maxVal <= 0)
                            ? 0.0
                            : (val / maxVal);
                        final isMain = val > 0 && val == maxVal;
                        // Slot width controls spacing; barInnerWidth controls actual rectangle width
                        final slotWidth = isMain ? 56.0 : 40.0;
                        final barInnerWidth = isMain ? 18.0 : 8.0;
                        final barHeight =
                            (chartHeight - 28) * (0.10 + 0.90 * heightFactor);

                        return Container(
                          width: slotWidth,
                          padding: const EdgeInsets.symmetric(horizontal: 6.0),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              // Value label for the main (tallest) bar
                              if (isMain)
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 8.0),
                                  child: Text(
                                    _formatCurrency(val),
                                    style: const TextStyle(
                                      color: Colors.redAccent,
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                )
                              else
                                const SizedBox(height: 20),

                              // Bar (rectangular style)
                              Container(
                                width: barInnerWidth,
                                height: barHeight.clamp(4.0, chartHeight - 20),
                                decoration: BoxDecoration(
                                  color: val > 0
                                      ? Colors.redAccent
                                      : Colors.redAccent.withOpacity(0.25),
                                  borderRadius: BorderRadius.circular(6),
                                  boxShadow: [
                                    if (val > 0)
                                      BoxShadow(
                                        color: Colors.redAccent.withOpacity(
                                          0.12,
                                        ),
                                        blurRadius: 4,
                                        offset: const Offset(0, 2),
                                      ),
                                  ],
                                ),
                              ),

                              const SizedBox(height: 8),
                              // X label
                              Padding(
                                padding: const EdgeInsets.only(top: 6.0),
                                child: Text(
                                  (i >= 0 && i < titles.length)
                                      ? titles[i]
                                      : '',
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: Colors.black54,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            ],
                          ),
                        );
                      }),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Widget: pie chart for categories
  Widget _categoriesPieChart() {
    final cats = _categories;
    if (cats.isEmpty) {
      return Center(
        child: Text(
          'No hay categorías',
          style: TextStyle(color: Colors.black54),
        ),
      );
    }

    final colorList = _categoryColors;

    final sections = <PieChartSectionData>[];
    for (var i = 0; i < cats.length; i++) {
      final c = cats[i];
      final rawAmount =
          c['amount'] ?? c['monto'] ?? c['value'] ?? c['total'] ?? 0;
      final val = rawAmount is num
          ? rawAmount.toDouble()
          : double.tryParse(rawAmount?.toString() ?? '0') ?? 0.0;
      if (val <= 0) continue;

      sections.add(
        PieChartSectionData(
          value: val,
          color: colorList[i % colorList.length],
          title: '',
          radius: 40,
        ),
      );
    }

    if (sections.isEmpty) {
      return Center(
        child: Text(
          'No hay montos para mostrar',
          style: TextStyle(color: Colors.black54),
        ),
      );
    }

    return PieChart(
      PieChartData(sections: sections, centerSpaceRadius: 18, sectionsSpace: 4),
    );
  }

  // (Removed unused helper _shortMonth because labels are taken from backend data)

  // Helper: fila de categoría con progreso
  Widget _categoryRow(
    String title,
    String amount,
    double progress,
    Color color,
  ) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w500)),
              const SizedBox(height: 6),
              LinearProgressIndicator(
                value: progress,
                color: color,
                backgroundColor: color.withOpacity(0.2),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Text(amount, style: const TextStyle(fontWeight: FontWeight.w600)),
      ],
    );
  }
}
