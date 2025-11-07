import 'package:flutter/material.dart';
import 'dart:math';
import '../../../core/services/report_service.dart';
import '../../../core/services/home_service.dart';

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

    return SingleChildScrollView(
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
                // Botón Categorías
                OutlinedButton.icon(
                  onPressed: () {},
                  icon: Icon(Icons.category, color: Colors.green[700]),
                  label: const Text(
                    'Categorías',
                    style: TextStyle(
                      color: Colors.green,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: Colors.green.shade300),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(24),
                    ),
                  ),
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
                ToggleButtons(
                  isSelected: [isPersonal, !isPersonal],
                  borderRadius: BorderRadius.circular(22),
                  selectedColor: Colors.white,
                  color: Colors.black87,
                  fillColor: Colors.green,
                  borderColor: Colors.green,
                  selectedBorderColor: Colors.green,
                  constraints: const BoxConstraints(
                    minHeight: 38,
                    minWidth: 100,
                  ),
                  onPressed: (index) {
                    setState(() {
                      isPersonal = index == 0;
                    });
                  },
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: const [
                        Icon(Icons.person, size: 20),
                        SizedBox(width: 6),
                        Text(
                          'Personal',
                          style: TextStyle(fontWeight: FontWeight.w500),
                        ),
                      ],
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: const [
                        Icon(Icons.groups, size: 20),
                        SizedBox(width: 6),
                        Text(
                          'Grupos',
                          style: TextStyle(fontWeight: FontWeight.w500),
                        ),
                      ],
                    ),
                  ],
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
                    Text('Mes', style: TextStyle(fontWeight: FontWeight.w500)),
                    Text('Año', style: TextStyle(fontWeight: FontWeight.w500)),
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
                      const SizedBox(width: 8),
                      const Opacity(
                        opacity: 0.8,
                        child: Text('Análisis Detallado'),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),

                // Card: Evolución (dinámico según datos del backend)
                Card(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          periodo == 0
                              ? 'Evolución Semanal - Personal'
                              : periodo == 1
                              ? 'Evolución Mensual - Personal'
                              : 'Evolución Anual - Personal',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Gastos del periodo seleccionado',
                          style: TextStyle(color: Colors.black54),
                        ),
                        const SizedBox(height: 12),
                        SizedBox(
                          height: 140,
                          child: Builder(
                            builder: (context) {
                              // seleccionar data según periodo
                              final List<Map<String, dynamic>> data =
                                  periodo == 0
                                  ? _weeklyReport
                                  : periodo == 1
                                  ? _monthlyReport
                                  : _yearlyReport;

                              if (data.isEmpty) {
                                // mostrar gráfico vacío con borde y leyenda simple
                                return Center(
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: const [
                                      SizedBox(
                                        width: 200,
                                        height: 70,
                                        child: DecoratedBox(
                                          decoration: BoxDecoration(
                                            border: Border(
                                              top: BorderSide(
                                                color: Colors.black12,
                                              ),
                                              left: BorderSide(
                                                color: Colors.black12,
                                              ),
                                              right: BorderSide(
                                                color: Colors.black12,
                                              ),
                                              bottom: BorderSide(
                                                color: Colors.black12,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                      SizedBox(height: 8),
                                      Text(
                                        'No hay gastos en este periodo',
                                        style: TextStyle(color: Colors.black54),
                                      ),
                                    ],
                                  ),
                                );
                              }

                              // extraer valores de gastos y etiquetas de forma defensiva
                              final values = data.map<double>((item) {
                                final val =
                                    (item['expenses'] ??
                                    item['egresos'] ??
                                    item['amount'] ??
                                    0);
                                if (val is num) return val.toDouble();
                                if (val is String)
                                  return double.tryParse(val) ?? 0.0;
                                return 0.0;
                              }).toList();

                              final labels = data.map<String>((item) {
                                return (item['label'] ??
                                            item['month'] ??
                                            item['week'] ??
                                            item['year'] ??
                                            item['name'])
                                        ?.toString() ??
                                    '';
                              }).toList();

                              final maxVal = (values.isNotEmpty)
                                  ? values.reduce((a, b) => a > b ? a : b)
                                  : 0.0;
                              final usableMax = maxVal > 0
                                  ? maxVal
                                  : 1.0; // evitar división por cero

                              return Row(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: List.generate(values.length, (i) {
                                  final height =
                                      (values[i] / usableMax) * 96; // map to px
                                  return Expanded(
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 6,
                                      ),
                                      child: Column(
                                        mainAxisAlignment:
                                            MainAxisAlignment.end,
                                        children: [
                                          AnimatedContainer(
                                            duration: const Duration(
                                              milliseconds: 500,
                                            ),
                                            curve: Curves.easeOutCubic,
                                            height: height.clamp(4.0, 120.0),
                                            decoration: BoxDecoration(
                                              color: Colors.redAccent,
                                              borderRadius:
                                                  BorderRadius.circular(6),
                                            ),
                                          ),
                                          const SizedBox(height: 8),
                                          Text(
                                            labels[i].length > 6
                                                ? labels[i].substring(0, 6)
                                                : labels[i],
                                            style: const TextStyle(
                                              fontSize: 10,
                                              color: Colors.black54,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  );
                                }),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 14),

                // Card: Pie chart mock + distribución
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
                        const SizedBox(height: 8),
                        const Text(
                          'Tus gastos organizados por categoría',
                          style: TextStyle(color: Colors.black54),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            // Pie chart segmentado (estático)
                            SizedBox(
                              width: 90,
                              height: 90,
                              child: Builder(
                                builder: (ctx) {
                                  // Build pie values defensively: backend may return
                                  // either `percentage` or absolute `amount` for each
                                  // category. If `amount` is provided we compute the
                                  // percentages here.
                                  if (categories.isEmpty) {
                                    return _StaticPieChart(
                                      values: const [30, 20, 23, 14, 13],
                                      colors: const [
                                        Colors.red,
                                        Colors.blue,
                                        Colors.green,
                                        Colors.orange,
                                        Colors.purple,
                                      ],
                                    );
                                  }

                                  // detect if categories contain absolute amounts
                                  final hasAmount = categories.any(
                                    (c) =>
                                        c.containsKey('amount') ||
                                        c.containsKey('monto'),
                                  );
                                  if (hasAmount) {
                                    final amounts = categories.map<double>((c) {
                                      final raw =
                                          c['amount'] ?? c['monto'] ?? 0;
                                      if (raw is num) return raw.toDouble();
                                      return double.tryParse(
                                            raw?.toString() ?? '0',
                                          ) ??
                                          0.0;
                                    }).toList();
                                    final total = amounts.fold(
                                      0.0,
                                      (a, b) => a + b,
                                    );
                                    final values = total > 0
                                        ? amounts
                                              .map((a) => (a / total) * 100)
                                              .toList()
                                        : amounts.map((_) => 0.0).toList();
                                    return _StaticPieChart(
                                      values: values,
                                      colors: const [
                                        Colors.red,
                                        Colors.blue,
                                        Colors.green,
                                        Colors.orange,
                                        Colors.purple,
                                      ],
                                    );
                                  }

                                  // default: use provided percentage field (or 0)
                                  final values = categories.map<double>((c) {
                                    final raw =
                                        c['percentage'] ?? c['porcentaje'] ?? 0;
                                    if (raw is num) return raw.toDouble();
                                    return double.tryParse(
                                          raw?.toString() ?? '0',
                                        ) ??
                                        0.0;
                                  }).toList();
                                  return _StaticPieChart(
                                    values: values,
                                    colors: const [
                                      Colors.red,
                                      Colors.blue,
                                      Colors.green,
                                      Colors.orange,
                                      Colors.purple,
                                    ],
                                  );
                                },
                              ),
                            ),
                            const SizedBox(width: 16),
                            // Legend
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // Build legend entries defensively similar to pie
                                  for (
                                    var i = 0;
                                    i <
                                        (categories.isNotEmpty
                                            ? categories.length
                                            : 5);
                                    i++
                                  )
                                    _LegendItem(
                                      color: [
                                        Colors.red,
                                        Colors.blue,
                                        Colors.green,
                                        Colors.orange,
                                        Colors.purple,
                                      ][i % 5],
                                      text: categories.isNotEmpty
                                          ? () {
                                              final c = categories[i];
                                              final name =
                                                  (c['name'] ??
                                                          c['title'] ??
                                                          'Sin nombre')
                                                      ?.toString();
                                              // Prefer to show both amount and percentage when available
                                              double? pct;
                                              double? amt;
                                              if (c.containsKey('percentage') ||
                                                  c.containsKey('porcentaje')) {
                                                final rawP =
                                                    c['percentage'] ??
                                                    c['porcentaje'];
                                                if (rawP is num)
                                                  pct = rawP.toDouble();
                                                else
                                                  pct = double.tryParse(
                                                    rawP?.toString() ?? '0',
                                                  );
                                              }
                                              if (c.containsKey('amount') ||
                                                  c.containsKey('monto')) {
                                                final raw =
                                                    c['amount'] ?? c['monto'];
                                                if (raw is num)
                                                  amt = raw.toDouble();
                                                else
                                                  amt = double.tryParse(
                                                    raw?.toString() ?? '0',
                                                  );
                                              }

                                              if (amt != null && pct != null) {
                                                return '$name — S/ ${amt.toStringAsFixed(0)} (${pct.toStringAsFixed(1)}%)';
                                              }
                                              if (amt != null)
                                                return '$name — S/ ${amt.toStringAsFixed(0)}';
                                              if (pct != null)
                                                return '$name — ${pct.toStringAsFixed(1)}%';
                                              return '$name: 0%';
                                            }()
                                          : [
                                              'Comida: 30%',
                                              'Transporte: 20%',
                                              'Servicios: 23%',
                                              'Compras: 14%',
                                              'Entretenimiento: 13%',
                                            ][i],
                                    ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 14),

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
                              final colorList = [
                                Colors.red,
                                Colors.blue,
                                Colors.orange,
                                Colors.purple,
                                Colors.green,
                              ];
                              final color = colorList[i % colorList.length];

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

// Legend item widget (const constructor so it can be used in const lists)
class _LegendItem extends StatelessWidget {
  final Color color;
  final String text;
  const _LegendItem({Key? key, required this.color, required this.text})
    : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(3),
            ),
          ),
          const SizedBox(width: 8),
          Text(text, style: const TextStyle(fontSize: 13)),
        ],
      ),
    );
  }
}

// Static pie chart widget
class _StaticPieChart extends StatelessWidget {
  final List<double> values;
  final List<Color> colors;
  const _StaticPieChart({Key? key, required this.values, required this.colors})
    : super(key: key);

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _PiePainter(values: values, colors: colors),
      size: Size.infinite,
    );
  }
}

class _PiePainter extends CustomPainter {
  final List<double> values;
  final List<Color> colors;
  _PiePainter({required this.values, required this.colors});

  @override
  void paint(Canvas canvas, Size size) {
    final total = values.fold(0.0, (a, b) => a + b);
    final rect = Offset.zero & size;
    final center = rect.center;
    final radius = (size.shortestSide) / 2;

    var startRadian = -pi / 2; // start at top
    final paint = Paint()..style = PaintingStyle.fill;

    if (total <= 0) {
      // Draw an empty subtle circle to indicate no data
      final emptyPaint = Paint()..color = Colors.grey.withOpacity(0.12);
      canvas.drawCircle(center, radius, emptyPaint);
    } else {
      for (var i = 0; i < values.length; i++) {
        final sweepRadian = (values[i] / total) * 2 * pi;
        paint.color = colors[i % colors.length];
        canvas.drawArc(
          Rect.fromCircle(center: center, radius: radius),
          startRadian,
          sweepRadian,
          true,
          paint,
        );

        // draw separator line
        final separatorPaint = Paint()
          ..color = Colors.white.withOpacity(0.9)
          ..strokeWidth = 1.5
          ..style = PaintingStyle.stroke;
        final p1 = center;
        final p2 = Offset(
          center.dx + radius * cos(startRadian),
          center.dy + radius * sin(startRadian),
        );
        canvas.drawLine(p1, p2, separatorPaint);

        startRadian += sweepRadian;
      }
    }

    // draw inner subtle border
    final borderPaint = Paint()
      ..color = Colors.black.withOpacity(0.04)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    canvas.drawCircle(center, radius, borderPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
