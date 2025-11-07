import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:math';
import 'dart:async';
import 'package:cofi/core/services/home_service.dart';
import 'package:cofi/core/services/metas_service.dart';
import 'package:cofi/core/services/transaction_service.dart';
import 'package:cofi/core/services/budget_service.dart';
import 'package:flutter/services.dart';

// Paquete para las acciones de deslizar (swipe)
import 'package:flutter_slidable/flutter_slidable.dart';

// Importar el widget del micrófono
import 'package:cofi/core/widgets/microphone_button.dart';

class InicioView extends StatefulWidget {
  const InicioView({super.key});

  @override
  State<InicioView> createState() => _InicioViewState();
}

class _InicioViewState extends State<InicioView> {
  final user = FirebaseAuth.instance.currentUser;
  // Inicializar listas vacías para evitar errores por acceso antes de cargar
  List<Map<String, dynamic>> goals = <Map<String, dynamic>>[];
  List<Map<String, dynamic>> movements = <Map<String, dynamic>>[];
  double totalBalance = 0.0;
  double monthlyBudget = 0.0; // monto gastado o usado en el mes
  double monthlyBudgetGoal = 0.0; // presupuesto total del mes
  bool isLoading = true;
  String? error;
  List<Map<String, dynamic>> accounts = [];
  List<Map<String, dynamic>> categories = [];
  String? selectedAccountId;

  // Notifiers para actualizaciones puntuales (evita rebuild completo)
  final ValueNotifier<List<Map<String, dynamic>>> _accountsNotifier =
      ValueNotifier<List<Map<String, dynamic>>>([]);
  final ValueNotifier<List<Map<String, dynamic>>> _movementsNotifier =
      ValueNotifier<List<Map<String, dynamic>>>([]);
  final ValueNotifier<List<Map<String, dynamic>>> _goalsNotifier =
      ValueNotifier<List<Map<String, dynamic>>>([]);
  final ValueNotifier<double> _totalBalanceNotifier = ValueNotifier<double>(
    0.0,
  );
  final ValueNotifier<double> _monthlyBudgetNotifier = ValueNotifier<double>(
    0.0,
  );
  final ValueNotifier<double> _monthlyBudgetGoalNotifier =
      ValueNotifier<double>(0.0);

  // Helper para actualizar el estado de forma segura (evita setState cuando
  // el widget ya no está montado).
  void _safeSetState(VoidCallback fn) {
    if (!mounted) return;
    setState(fn);
  }

  @override
  void initState() {
    super.initState();
    // Cargar datos al montar el widget. Usamos addPostFrameCallback para
    // asegurar que el contexto esté listo y evitar llamados prematuros.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadHomeData();
    });
  }

  // Robust number parser used across the view (acepta String, num o null)
  double _toDouble(dynamic v) {
    if (v == null) return 0.0;
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v.replaceAll(',', '.')) ?? 0.0;
    return 0.0;
  }

  // Helper para formatear fechas usadas en la UI (admits DateTime, String or null)
  String _formatDisplayDate(dynamic raw) {
    if (raw == null) return _formatDate();

    DateTime dt;
    if (raw is DateTime) {
      dt = raw;
    } else if (raw is String) {
      dt = DateTime.tryParse(raw) ?? DateTime.now();
    } else if (raw is int) {
      dt = DateTime.fromMillisecondsSinceEpoch(raw);
    } else {
      // Fallback
      dt = DateTime.now();
    }

    final day = dt.day;
    const months = [
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
    final monthName = months[(dt.month - 1).clamp(0, 11)];
    final hour = dt.hour;
    final minute = dt.minute.toString().padLeft(2, '0');
    return '$day $monthName, $hour:$minute';
  }

  Future<void> _loadHomeData({bool showLoading = true}) async {
    if (showLoading) {
      _safeSetState(() {
        isLoading = true;
        error = null;
      });
    } else {
      // keep previous isLoading value; clear error silently
      error = null;
    }

    try {
      final data = await HomeService.getHomeData();

      // Mapear accounts. Solo reemplazar si el backend devolvió datos.
      final accountsData = data['accounts'] as List<dynamic>? ?? [];
      if (accountsData.isNotEmpty) {
        final newAccounts = accountsData
            .map((a) {
              return {
                'id': (a['id'] ?? '').toString(),
                'name': (a['name'] ?? 'Cuenta').toString(),
                'balance': _toDouble(a['balance']),
                'currency': (a['currency'] ?? 'PEN').toString(),
              };
            })
            .cast<Map<String, dynamic>>()
            .where((a) => (a['id'] as String).isNotEmpty)
            .toList();

        accounts = newAccounts;
        _accountsNotifier.value = List<Map<String, dynamic>>.from(newAccounts);
        // Mantener la cuenta seleccionada si ya existe, sino seleccionar la primera
        selectedAccountId =
            selectedAccountId ??
            (accounts.isNotEmpty ? accounts.first['id'] as String? : null);
      }

      // Mapear budgets -> obtener presupuesto mensual si existe
      final budgetsData = data['budgets'] as List<dynamic>? ?? [];
      if (budgetsData.isNotEmpty) {
        try {
          // Intentar encontrar presupuesto mensual entre los budgets devueltos
          final monthlyObj = budgetsData.firstWhere((b) {
            if (b is Map) {
              final p = (b['period'] ?? b['type'] ?? b['frequency'])
                  ?.toString()
                  .toLowerCase();
              return p == 'monthly' || p == 'mensual';
            }
            return false;
          }, orElse: () => budgetsData.first);

          if (monthlyObj is Map) {
            final budgetAmount = _toDouble(
              monthlyObj['budget'] ??
                  monthlyObj['amount'] ??
                  monthlyObj['value'] ??
                  0,
            );
            if (budgetAmount > 0) {
              monthlyBudgetGoal = budgetAmount;
              _monthlyBudgetGoalNotifier.value = monthlyBudgetGoal;
            }
          }
        } catch (_) {
          // ignore parsing errors, no budgets available
        }
      }

      // Mapear categories (solo si el backend devolvió categorías)
      final categoriesData = data['categories'] as List<dynamic>? ?? [];
      if (categoriesData.isNotEmpty) {
        categories = categoriesData
            .map((c) {
              return {
                'id': c['id'] ?? c['_id'],
                'name': c['name'] ?? c['title'] ?? 'Otros',
                'type': c['type'] ?? 'expense',
              };
            })
            .cast<Map<String, dynamic>>()
            .toList();
      }

      // Mapear transactions (solo si el backend devolvió datos). Evitar sobrescribir
      // movimientos existentes con una lista vacía por errores transitorios.
      final transactionsData = data['transactions'] as List<dynamic>? ?? [];
      if (transactionsData.isNotEmpty) {
        final newMovements = transactionsData
            .map((t) {
              final type = (t['type'] ?? 'expense').toString().toLowerCase();
              final rawAmount = t['amount'];
              final parsedAmount = _toDouble(rawAmount);
              // Ensure amount sign reflects the type
              final amount = type == 'income'
                  ? parsedAmount.abs()
                  : -parsedAmount.abs();
              final rawDate = t['occurredAt'] ?? t['createdAt'] ?? t['date'];
              final displayDate = _formatDisplayDate(rawDate);

              return {
                'id': t['id'] ?? t['_id'] ?? t['transactionId'],
                // backend uses 'note' for extra text
                'amount': amount,
                'title': t['note'] ?? t['description'] ?? t['title'] ?? '',
                'type': type,
                'date': displayDate,
                // si la transacción incluye un objeto category, preferir su nombre
                'category': (t['category'] is Map)
                    ? (t['category']['name'] ?? 'Otros')
                    : (t['category'] ?? t['categoryId'] ?? 'Otros'),
                'categoryId': (t['category'] is Map)
                    ? (t['category']['id'] ?? t['category']['_id'])
                    : (t['categoryId'] ?? t['category'] ?? null),
              };
            })
            .cast<Map<String, dynamic>>()
            .toList();

        movements = newMovements;
        _movementsNotifier.value = newMovements;

        // Initialize monthlyBudget as the sum of expenses (absolute value)
        monthlyBudget = movements.fold(0.0, (sum, m) {
          final amt = _toDouble(m['amount']);
          return sum + (amt < 0 ? amt.abs() : 0.0);
        });
        _monthlyBudgetNotifier.value = monthlyBudget;

        // totalBalance: if a monthly budget is set, treat the budget as the
        // starting balance and subtract expenses; otherwise, sum all amounts.
        if (monthlyBudgetGoal > 0) {
          totalBalance = (monthlyBudgetGoal - monthlyBudget);
        } else {
          totalBalance = movements.fold(
            0.0,
            (sum, m) => sum + _toDouble(m['amount']),
          );
        }
        _totalBalanceNotifier.value = totalBalance;
      }

      // Si no vinieron transacciones desde el backend, aún recalcular
      // montos a partir del estado local (puede venir de cache o estado previo)
      if (transactionsData.isEmpty) {
        // Recalcular monthlyBudget como suma de gastos actuales
        monthlyBudget = movements.fold(0.0, (sum, m) {
          final amt = _toDouble(m['amount']);
          return sum + (amt < 0 ? amt.abs() : 0.0);
        });
        _monthlyBudgetNotifier.value = monthlyBudget;

        if (monthlyBudgetGoal > 0) {
          totalBalance = (monthlyBudgetGoal - monthlyBudget);
        } else {
          totalBalance = movements.fold(
            0.0,
            (sum, m) => sum + _toDouble(m['amount']),
          );
        }
        _totalBalanceNotifier.value = totalBalance;
      }

      // Mapear metas (goals)
      // Obtener metas directamente desde el servicio de metas (/savings)
      try {
        final goalService = GoalService();
        final fetchedGoals = await goalService.getGoals();
        if (fetchedGoals.isNotEmpty) {
          final mapped = fetchedGoals
              .map((g) {
                return {
                  'title': g['title'] ?? g['name'] ?? 'Meta',
                  'current': _toDouble(
                    g['currentAmount'] ??
                        g['saved'] ??
                        g['amountSaved'] ??
                        g['current'] ??
                        0,
                  ),
                  'total': _toDouble(
                    g['targetAmount'] ??
                        g['target'] ??
                        g['goalAmount'] ??
                        g['amount'] ??
                        0,
                  ),
                };
              })
              .cast<Map<String, dynamic>>()
              .toList();

          goals = mapped;
          _goalsNotifier.value = mapped;
        } else {
          // No reemplazar metas existentes si la respuesta está vacía
        }
      } catch (_) {
        // Si falla la petición de metas, conservar las metas cargadas previamente
      }

      // Si no tiene metas, dejamos una lista vacía (la UI mostrará mensaje)

      if (showLoading) {
        _safeSetState(() {
          isLoading = false;
        });
      }
    } catch (e) {
      if (showLoading) {
        _safeSetState(() {
          isLoading = false;
          error = e.toString();
        });
      } else {
        // For background refreshes, record error silently
        error = e.toString();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final nombre = user?.displayName ?? 'Usuario';
    // totalBalance y otros valores se actualizan mediante ValueNotifiers para
    // evitar reconstruir todo el árbol; no calcular aquí.

    return Scaffold(
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 40),
            Text(
              '¡Hola, $nombre!',
              style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(
              'Resumen de tus finanzas',
              style: TextStyle(fontSize: 16, color: Colors.grey[600]),
            ),
            // account selector + total card
            if (isLoading)
              const Center(child: CircularProgressIndicator())
            else if (error != null)
              Column(
                children: [
                  Text(
                    'Error: $error',
                    style: const TextStyle(color: Colors.red),
                  ),
                  const SizedBox(height: 8),
                  ElevatedButton(
                    onPressed: _loadHomeData,
                    child: const Text('Reintentar'),
                  ),
                ],
              )
            else ...[
              // Account selector: built from notifier so changing accounts does
              // not rebuild the whole screen.
              ValueListenableBuilder<List<Map<String, dynamic>>>(
                valueListenable: _accountsNotifier,
                builder: (context, accs, _) {
                  if (accs.isEmpty) return const SizedBox.shrink();
                  return DropdownButtonFormField<String>(
                    value: selectedAccountId,
                    decoration: const InputDecoration(labelText: 'Cuenta'),
                    items: accs
                        .map(
                          (a) => DropdownMenuItem<String>(
                            value: (a['id'] ?? '').toString(),
                            child: Text((a['name'] ?? 'Cuenta').toString()),
                          ),
                        )
                        .toList(),
                    onChanged: (v) {
                      // small local state change only
                      _safeSetState(() {
                        selectedAccountId = v;
                      });
                    },
                  );
                },
              ),
              const SizedBox(height: 8),
              _buildTotalBalanceCard(context),
            ],
            const SizedBox(height: 16),
            _buildMonthlyBudgetCard(context),
            const SizedBox(height: 24),
            _buildRecentMovements(),
            const SizedBox(height: 20),
            _buildSavingsGoals(context),
            const SizedBox(height: 20),
            _buildReports(),
            const SizedBox(height: 80),
          ],
        ),
      ),
      floatingActionButton: const MicrophoneButton(),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
    );
  }

  /// --- TARJETA DE SALDO TOTAL (DISEÑO MEJORADO) ---
  Widget _buildTotalBalanceCard(BuildContext context) {
    // Calcular porcentaje de cambio (simulado)
    return ValueListenableBuilder<double>(
      valueListenable: _totalBalanceNotifier,
      builder: (context, total, _) {
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Saldo Total',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey[600],
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Text(
                    'S/ ${total.toStringAsFixed(2)}',
                    style: const TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: CustomActionButton(
                      onPressed: () =>
                          _showAddTransactionModal(context, isIncome: true),
                      backgroundColor: Colors.green.shade500,
                      icon: Icons.arrow_upward,
                      label: 'Ingreso',
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: CustomActionButton(
                      onPressed: () =>
                          _showAddTransactionModal(context, isIncome: false),
                      backgroundColor: Colors.red.shade500,
                      icon: Icons.arrow_downward,
                      label: 'Gasto',
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  /// --- TARJETA DE PRESUPUESTO (DISEÑO MEJORADO) ---
  Widget _buildMonthlyBudgetCard(BuildContext context) {
    return GestureDetector(
      onTap: () => _showBudgetModal(context),
      child: ValueListenableBuilder<double>(
        valueListenable: _monthlyBudgetNotifier,
        builder: (context, monthly, _) {
          return ValueListenableBuilder<double>(
            valueListenable: _monthlyBudgetGoalNotifier,
            builder: (context, goal, __) {
              final progress = (goal > 0)
                  ? (monthly / goal).clamp(0.0, 1.0)
                  : 0.0;
              final remaining = goal - monthly;
              final percentUsed = (progress * 100).toInt();

              return Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.05),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Presupuesto Mensual',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.black87,
                          ),
                        ),
                        Text(
                          'S/ ${monthly.toStringAsFixed(2)} / S/ ${goal.toStringAsFixed(2)}',
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.grey[600],
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: SizedBox(
                        height: 12,
                        child: LinearProgressIndicator(
                          value: progress,
                          backgroundColor: Colors.blue.shade100,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            progress > 0.8
                                ? Colors.orange
                                : Colors.green.shade500,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Queda S/ ${remaining.toStringAsFixed(2)}',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey[700],
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        Text(
                          '$percentUsed% usado',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey[700],
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }

  void _showBudgetModal(BuildContext context) {
    // Si ya existe un presupuesto mensual, no permitir modificarlo desde UI
    if (monthlyBudgetGoal > 0) {
      showDialog(
        context: context,
        builder: (dctx) => AlertDialog(
          title: const Text('Presupuesto fijo'),
          content: const Text(
            'El presupuesto mensual ya fue establecido y no se puede modificar desde aquí.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dctx),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      return;
    }
    final controller = TextEditingController(
      text: monthlyBudgetGoal > 0 ? monthlyBudgetGoal.toStringAsFixed(2) : '',
    );

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        String? selectedCategoryId = categories.isNotEmpty
            ? categories.first['id']?.toString()
            : null;

        return StatefulBuilder(
          builder: (ctx2, setModalState) {
            return Padding(
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
                top: 20,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Establecer Presupuesto Mensual',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),

                  if (categories.isNotEmpty) ...[
                    DropdownButtonFormField<String>(
                      value: selectedCategoryId,
                      decoration: InputDecoration(
                        labelText: 'Categoría',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        filled: true,
                        fillColor: Colors.grey.shade50,
                      ),
                      items: categories
                          .map(
                            (c) => DropdownMenuItem<String>(
                              value: (c['id'] ?? c['_id'] ?? '').toString(),
                              child: Text(
                                (c['name'] ?? c['title'] ?? 'Categoría')
                                    .toString(),
                              ),
                            ),
                          )
                          .toList(),
                      onChanged: (v) {
                        setModalState(() {
                          selectedCategoryId = v;
                        });
                      },
                    ),
                    const SizedBox(height: 12),
                  ] else ...[
                    const Text(
                      'No hay categorías disponibles. Crea una categoría antes.',
                    ),
                    const SizedBox(height: 12),
                  ],

                  TextField(
                    controller: controller,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    inputFormatters: [
                      // Permitir solo números y un punto decimal (máx 2 decimales)
                      FilteringTextInputFormatter.allow(
                        RegExp(r'^\d*\.?\d{0,2}$'),
                      ),
                    ],
                    decoration: InputDecoration(
                      labelText: 'Presupuesto mensual (S/)',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      filled: true,
                      fillColor: Colors.grey.shade50,
                    ),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: CustomActionButton(
                      onPressed: () async {
                        final value = double.tryParse(controller.text) ?? 0.0;
                        if (value <= 0) {
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Ingresa un monto válido mayor a 0',
                                ),
                                backgroundColor: Colors.red,
                              ),
                            );
                          }
                          return;
                        }

                        if (selectedCategoryId == null ||
                            selectedCategoryId!.isEmpty) {
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Selecciona una categoría antes de guardar.',
                                ),
                                backgroundColor: Colors.red,
                              ),
                            );
                          }
                          return;
                        }

                        final bs = BudgetService();
                        final success = await bs.saveMonthlyBudget(
                          value,
                          categoryId: selectedCategoryId,
                        );
                        if (success) {
                          monthlyBudgetGoal = value;
                          _monthlyBudgetGoalNotifier.value = value;

                          totalBalance = (monthlyBudgetGoal - monthlyBudget);
                          _totalBalanceNotifier.value = totalBalance;

                          try {
                            await _loadHomeData(showLoading: false);
                          } catch (_) {}

                          Navigator.pop(context);
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  'Presupuesto mensual guardado: S/ ${value.toStringAsFixed(2)}',
                                ),
                                backgroundColor: Colors.blue,
                              ),
                            );
                          }
                        } else {
                          if (mounted) {
                            final msg =
                                bs.lastErrorMessage ??
                                'Error guardando presupuesto. Intenta de nuevo.';
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(msg),
                                backgroundColor: Colors.red,
                              ),
                            );
                          }
                        }
                      },
                      backgroundColor: Colors.blue.shade500,
                      icon: Icons.save,
                      label: 'Guardar Presupuesto',
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            );
          },
        );
      },
    );
  }

  /// --- MOVIMIENTOS RECIENTES (CON SWIPE ACTIONS) ---
  Widget _buildRecentMovements() {
    return ValueListenableBuilder<List<Map<String, dynamic>>>(
      valueListenable: _movementsNotifier,
      builder: (context, movementsList, _) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Movimientos Recientes',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: movementsList.length,
              itemBuilder: (context, index) {
                final movement = movementsList[index];
                return Slidable(
                  key: Key(
                    (movement['title'] ?? '') + (movement['date'] ?? ''),
                  ),

                  startActionPane: ActionPane(
                    motion: const DrawerMotion(),
                    children: [
                      SlidableAction(
                        onPressed: (context) {
                          _showEditTransactionModal(context, index);
                        },
                        backgroundColor: Colors.blue,
                        foregroundColor: Colors.white,
                        icon: Icons.edit,
                        label: 'Editar',
                      ),
                    ],
                  ),

                  endActionPane: ActionPane(
                    motion: const DrawerMotion(),
                    children: [
                      SlidableAction(
                        onPressed: (context) {
                          _deleteMovement(context, index);
                        },
                        backgroundColor: const Color(0xFFFE4A49),
                        foregroundColor: Colors.white,
                        icon: Icons.delete,
                        label: 'Eliminar',
                      ),
                    ],
                  ),

                  child: _MovementItem(
                    title: movement['title'],
                    amount: movement['amount'],
                    date: movement['date'],
                    category: movement['category'],
                  ),
                );
              },
            ),
          ],
        );
      },
    );
  }

  /// --- METAS DE AHORRO ---
  Widget _buildSavingsGoals(BuildContext context) {
    const double cardHeight = 130.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Metas de Ahorro',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        ValueListenableBuilder<List<Map<String, dynamic>>>(
          valueListenable: _goalsNotifier,
          builder: (context, goalsList, _) {
            if (goalsList.isEmpty) {
              return Container(
                height: cardHeight,
                alignment: Alignment.center,
                child: Text(
                  'No tienes metas',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey[600], fontSize: 14),
                ),
              );
            }

            return SizedBox(
              height: cardHeight,
              child: PageView.builder(
                controller: PageController(viewportFraction: 1.0),
                itemCount: goalsList.length,
                itemBuilder: (context, index) {
                  final g = goalsList[index];
                  final double current = _toDouble(g['current']);
                  final double total = _toDouble(g['total']);
                  final double progress = (total > 0)
                      ? (current / total).clamp(0.0, 1.0)
                      : 0.0;
                  final title = (g['title'] ?? 'Meta').toString();

                  return Padding(
                    padding: const EdgeInsets.only(right: 8.0),
                    child: _buildGoalCard(
                      title,
                      current,
                      total,
                      progress,
                      index,
                      context,
                      cardHeight,
                    ),
                  );
                },
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _buildGoalCard(
    String title,
    double current,
    double total,
    double progress,
    int index,
    BuildContext context, [
    double cardHeight = 130,
  ]) {
    final cardWidth = MediaQuery.of(context).size.width - 48;
    final percent = (progress * 100).clamp(0, 100).round();

    return GestureDetector(
      onTap: () => _showGoalFormModal(context, index),
      child: Container(
        width: cardWidth,
        height: cardHeight,
        decoration: BoxDecoration(
          color: Colors.purple.shade50,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.03),
              blurRadius: 8,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Colors.black87,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.6),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '$percent%',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: Colors.black87,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'S/ ${current.toStringAsFixed(0)} / S/ ${total.toStringAsFixed(0)}',
              style: TextStyle(color: Colors.grey[700], fontSize: 12.5),
            ),
            const SizedBox(height: 12),
            // Custom rounded progress bar
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Stack(
                children: [
                  Container(
                    height: 12,
                    color: Colors.blue.shade100.withOpacity(0.6),
                  ),
                  FractionallySizedBox(
                    widthFactor: progress,
                    child: Container(
                      height: 12,
                      decoration: BoxDecoration(
                        color: progress > 0.8
                            ? Colors.orange
                            : Colors.green.shade500,
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Meta ${index + 1}',
                  style: TextStyle(color: Colors.grey[600], fontSize: 12),
                ),
                Text(
                  'Queda S/ ${(total - current).clamp(0.0, double.infinity).toStringAsFixed(2)}',
                  style: TextStyle(
                    color: Colors.grey[700],
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// --- FUNCIÓN PARA ELIMINAR UN MOVIMIENTO ---
  void _deleteMovement(BuildContext parentContext, int index) {
    final deletedMovement = movements[index];
    final id = deletedMovement['id'] as String?;

    showDialog(
      context: parentContext,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Eliminar movimiento'),
        content: const Text(
          '¿Estás seguro de que deseas eliminar este movimiento?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(dialogContext);
              try {
                if (id != null) {
                  await TransactionService.deleteTransaction(id);
                }

                if (!mounted) return;

                // Update local lists and notifiers without triggering a full rebuild
                final double amount = _toDouble(deletedMovement['amount']);
                totalBalance -= amount;
                if (amount < 0) {
                  monthlyBudget -= amount.abs();
                }
                movements.removeAt(index);
                _movementsNotifier.value = List<Map<String, dynamic>>.from(
                  movements,
                );
                _totalBalanceNotifier.value = totalBalance;
                _monthlyBudgetNotifier.value = monthlyBudget;
                if (mounted)
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Movimiento eliminado correctamente'),
                      backgroundColor: Colors.red,
                    ),
                  );
                // refresh to reflect backend state (silent refresh, no spinner)
                if (mounted) await _loadHomeData(showLoading: false);
              } catch (e) {
                if (mounted)
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Error eliminando: $e'),
                      backgroundColor: Colors.orange,
                    ),
                  );
              }
            },
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
  }

  /// --- MODAL PARA EDITAR UN MOVIMIENTO ---
  void _showEditTransactionModal(BuildContext context, int index) {
    final originalMovement = movements[index];
    final double originalAmount = originalMovement['amount'];

    final montoController = TextEditingController(
      text: originalAmount.abs().toStringAsFixed(2),
    );
    final descripcionController = TextEditingController(
      text: originalMovement['title'],
    );

    // categorias vienen del backend; se usa id como valor y name para mostrar
    final categorias = categories;
    String categoriaSeleccionada = '';
    // intentar mapear category existente a id
    final origCat = originalMovement['category'];
    if (origCat is String) {
      // buscar por name
      final found = categories.firstWhere(
        (c) =>
            (c['name'] ?? '').toString().toLowerCase() == origCat.toLowerCase(),
        orElse: () => {},
      );
      if (found.isNotEmpty)
        categoriaSeleccionada = (found['id'] ?? '').toString();
    } else if (origCat is Map && origCat['id'] != null) {
      categoriaSeleccionada = origCat['id'].toString();
    } else if (origCat != null) {
      categoriaSeleccionada = origCat.toString();
    }
    final bool isIncome = originalAmount >= 0;

    showModalBottomSheet(
      isScrollControlled: true,
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setModalState) {
            return Padding(
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                bottom: MediaQuery.of(context).viewInsets.bottom + 20,
                top: 20,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Editar Movimiento',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 20),
                  TextField(
                    controller: montoController,
                    decoration: InputDecoration(
                      labelText: 'Monto',
                      prefixText: 'S/ ',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      filled: true,
                      fillColor: Colors.grey.shade50,
                    ),
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    autofocus: true,
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: descripcionController,
                    decoration: InputDecoration(
                      labelText: 'Descripción',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      filled: true,
                      fillColor: Colors.grey.shade50,
                    ),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: categoriaSeleccionada.isEmpty
                        ? null
                        : categoriaSeleccionada,
                    decoration: InputDecoration(
                      labelText: 'Categoría',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      filled: true,
                      fillColor: Colors.grey.shade50,
                    ),
                    items: categorias
                        .map(
                          (c) => DropdownMenuItem<String>(
                            value: (c['id'] ?? '').toString(),
                            child: Text((c['name'] ?? 'Otros').toString()),
                          ),
                        )
                        .toList(),
                    onChanged: (v) {
                      setModalState(() {
                        categoriaSeleccionada = v ?? '';
                      });
                    },
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: CustomActionButton(
                      onPressed: () async {
                        final newMonto =
                            double.tryParse(montoController.text) ?? 0.0;
                        if (newMonto <= 0 ||
                            descripcionController.text.trim().isEmpty) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'Por favor, completa todos los campos',
                              ),
                              backgroundColor: Colors.orange,
                            ),
                          );
                          return;
                        }

                        final id = originalMovement['id'] as String?;
                        final newAmount = isIncome ? newMonto : -newMonto;

                        try {
                          if (id != null) {
                            final updated =
                                await TransactionService.updateTransaction(
                                  id: id,
                                  amount: newAmount,
                                  type: isIncome ? 'income' : 'expense',
                                  note: descripcionController.text.trim(),
                                  categoryId: categoriaSeleccionada,
                                );

                            // Update local model and notifiers without a full rebuild
                            final amountDifference = newAmount - originalAmount;
                            totalBalance += amountDifference;

                            if (originalAmount < 0)
                              monthlyBudget -= originalAmount.abs();
                            if (!isIncome) monthlyBudget += newMonto;

                            final rawDate =
                                updated['occurredAt'] ?? updated['createdAt'];

                            movements[index] = {
                              'id': updated['id'] ?? updated['_id'] ?? id,
                              'title': descripcionController.text.trim(),
                              'amount': newAmount,
                              'date': _formatDisplayDate(
                                rawDate ?? _formatDate(),
                              ),
                              'category':
                                  (categories.firstWhere(
                                    (c) =>
                                        (c['id'] ?? '').toString() ==
                                        categoriaSeleccionada,
                                    orElse: () => {},
                                  )['name']) ??
                                  categoriaSeleccionada,
                              'categoryId': categoriaSeleccionada,
                            };
                            _movementsNotifier.value =
                                List<Map<String, dynamic>>.from(movements);
                            _totalBalanceNotifier.value = totalBalance;
                            _monthlyBudgetNotifier.value = monthlyBudget;
                          } else {
                            // If no id, just update locally
                            final amountDifference = newAmount - originalAmount;
                            totalBalance += amountDifference;
                            movements[index] = {
                              'title': descripcionController.text.trim(),
                              'amount': newAmount,
                              'date': _formatDate(),
                              'category':
                                  (categories.firstWhere(
                                    (c) =>
                                        (c['id'] ?? '').toString() ==
                                        categoriaSeleccionada,
                                    orElse: () => {},
                                  )['name']) ??
                                  categoriaSeleccionada,
                              'categoryId': categoriaSeleccionada,
                            };
                            _movementsNotifier.value =
                                List<Map<String, dynamic>>.from(movements);
                            _totalBalanceNotifier.value = totalBalance;
                          }

                          Navigator.pop(context);
                          if (mounted)
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  '✓ Movimiento actualizado correctamente',
                                ),
                                backgroundColor: Colors.blue,
                                duration: Duration(seconds: 2),
                              ),
                            );
                          // refresh data from backend after update (silent)
                          if (mounted) await _loadHomeData(showLoading: false);
                        } catch (e) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Error actualizando: $e'),
                              backgroundColor: Colors.orange,
                            ),
                          );
                        }
                      },
                      backgroundColor: Colors.blue.shade500,
                      icon: Icons.check,
                      label: 'Guardar Cambios',
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  /// --- MODAL PARA AGREGAR O RETIRAR EN METAS ---
  void _showGoalFormModal(BuildContext context, int index) {
    final goal = goals[index];
    final montoController = TextEditingController();
    final descripcionController = TextEditingController();

    final categorias = categories;
    String categoriaSeleccionada = categorias.isNotEmpty
        ? (categorias.first['id'] ?? '').toString()
        : '';

    showModalBottomSheet(
      isScrollControlled: true,
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setModalState) {
            return Padding(
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                bottom: MediaQuery.of(context).viewInsets.bottom + 20,
                top: 20,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    goal['title'],
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: montoController,
                    decoration: InputDecoration(
                      labelText: 'Monto',
                      prefixText: 'S/ ',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      filled: true,
                      fillColor: Colors.grey.shade50,
                    ),
                    keyboardType: TextInputType.number,
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: descripcionController,
                    decoration: InputDecoration(
                      labelText: 'Descripción',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      filled: true,
                      fillColor: Colors.grey.shade50,
                    ),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: categoriaSeleccionada.isEmpty
                        ? null
                        : categoriaSeleccionada,
                    decoration: InputDecoration(
                      labelText: 'Categoría',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      filled: true,
                      fillColor: Colors.grey.shade50,
                    ),
                    items: categorias
                        .map(
                          (c) => DropdownMenuItem<String>(
                            value: (c['id'] ?? '').toString(),
                            child: Text((c['name'] ?? 'Otros').toString()),
                          ),
                        )
                        .toList(),
                    onChanged: (v) {
                      setModalState(() {
                        categoriaSeleccionada = v ?? '';
                      });
                    },
                  ),
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      Expanded(
                        child: CustomActionButton(
                          onPressed: () {
                            final monto =
                                double.tryParse(montoController.text) ?? 0.0;
                            // Update local state and notifiers without full rebuild
                            goal['current'] = (goal['current'] + monto).clamp(
                              0,
                              goal['total'],
                            );
                            totalBalance += monto;
                            movements.insert(0, {
                              'title': descripcionController.text.isEmpty
                                  ? goal['title']
                                  : descripcionController.text,
                              'amount': monto,
                              'date': _formatDate(),
                              'category':
                                  (categories.firstWhere(
                                    (c) =>
                                        (c['id'] ?? '').toString() ==
                                        categoriaSeleccionada,
                                    orElse: () => {},
                                  )['name']) ??
                                  categoriaSeleccionada,
                              'categoryId': categoriaSeleccionada,
                            });
                            _movementsNotifier.value =
                                List<Map<String, dynamic>>.from(movements);
                            _totalBalanceNotifier.value = totalBalance;
                            _goalsNotifier.value =
                                List<Map<String, dynamic>>.from(goals);
                            Navigator.pop(context);
                          },
                          backgroundColor: Colors.green.shade500,
                          icon: Icons.add,
                          label: 'Agregar Ahorro',
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: CustomActionButton(
                          onPressed: () {
                            final monto =
                                double.tryParse(montoController.text) ?? 0.0;
                            goal['current'] = max(0, goal['current'] - monto);
                            totalBalance -= monto;
                            monthlyBudget += monto;
                            movements.insert(0, {
                              'title': descripcionController.text.isEmpty
                                  ? goal['title']
                                  : descripcionController.text,
                              'amount': -monto,
                              'date': _formatDate(),
                              'category':
                                  (categories.firstWhere(
                                    (c) =>
                                        (c['id'] ?? '').toString() ==
                                        categoriaSeleccionada,
                                    orElse: () => {},
                                  )['name']) ??
                                  categoriaSeleccionada,
                              'categoryId': categoriaSeleccionada,
                            });
                            _movementsNotifier.value =
                                List<Map<String, dynamic>>.from(movements);
                            _totalBalanceNotifier.value = totalBalance;
                            _monthlyBudgetNotifier.value = monthlyBudget;
                            _goalsNotifier.value =
                                List<Map<String, dynamic>>.from(goals);
                            Navigator.pop(context);
                          },
                          backgroundColor: Colors.red.shade500,
                          icon: Icons.remove,
                          label: 'Retirar Monto',
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  /// --- MODAL PARA AGREGAR INGRESO O GASTO ---
  void _showAddTransactionModal(
    BuildContext context, {
    required bool isIncome,
  }) {
    final montoController = TextEditingController();
    final descripcionController = TextEditingController();

    final categorias = categories;
    String categoriaSeleccionada = isIncome
        ? (categorias.firstWhere(
                    (c) => (c['type'] ?? 'income') == 'income',
                    orElse: () =>
                        (categorias.isNotEmpty ? categorias.first : {}),
                  )['id'] ??
                  '')
              .toString()
        : (categorias.isNotEmpty
              ? (categorias.first['id'] ?? '').toString()
              : '');

    showModalBottomSheet(
      isScrollControlled: true,
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setModalState) {
            return Padding(
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                bottom: MediaQuery.of(context).viewInsets.bottom + 20,
                top: 20,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        isIncome ? Icons.arrow_upward : Icons.arrow_downward,
                        color: isIncome ? Colors.green : Colors.red,
                        size: 24,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        isIncome ? 'Agregar Ingreso' : 'Agregar Gasto',
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  TextField(
                    controller: montoController,
                    decoration: InputDecoration(
                      labelText: 'Monto',
                      prefixText: 'S/ ',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      filled: true,
                      fillColor: Colors.grey.shade50,
                    ),
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    autofocus: true,
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: descripcionController,
                    decoration: InputDecoration(
                      labelText: 'Descripción',
                      hintText: 'Ej: Compra en supermercado',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      filled: true,
                      fillColor: Colors.grey.shade50,
                    ),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: categoriaSeleccionada.isEmpty
                        ? null
                        : categoriaSeleccionada,
                    decoration: InputDecoration(
                      labelText: 'Categoría',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      filled: true,
                      fillColor: Colors.grey.shade50,
                    ),
                    items: categorias
                        .map(
                          (c) => DropdownMenuItem<String>(
                            value: (c['id'] ?? '').toString(),
                            child: Text((c['name'] ?? 'Otros').toString()),
                          ),
                        )
                        .toList(),
                    onChanged: (v) {
                      setModalState(() {
                        categoriaSeleccionada = v ?? '';
                      });
                    },
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: CustomActionButton(
                      onPressed: () async {
                        final monto =
                            double.tryParse(montoController.text) ?? 0.0;

                        if (monto <= 0) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'Por favor ingresa un monto válido',
                              ),
                              backgroundColor: Colors.orange,
                            ),
                          );
                          return;
                        }

                        if (descripcionController.text.trim().isEmpty) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'Por favor ingresa una descripción',
                              ),
                              backgroundColor: Colors.orange,
                            ),
                          );
                          return;
                        }

                        // llamar al backend para crear transacción (backend crea/encuentra cuenta principal)
                        try {
                          final amount = isIncome ? monto : -monto;
                          final createdResp =
                              await TransactionService.createTransaction(
                                amount: monto,
                                type: isIncome ? 'income' : 'expense',
                                note: descripcionController.text.trim(),
                                categoryId: categoriaSeleccionada,
                              );

                          // backend devuelve { message, transaction, newBalance }
                          final created =
                              createdResp['transaction'] ?? createdResp;
                          final newBalanceRaw = createdResp['newBalance'];
                          final newBalance = newBalanceRaw != null
                              ? _toDouble(newBalanceRaw)
                              : null;

                          // Update local state and notifiers without full rebuild
                          if (newBalance != null)
                            totalBalance = newBalance;
                          else
                            totalBalance += amount;

                          if (!isIncome) monthlyBudget += monto;

                          final rawDate = created != null
                              ? (created['occurredAt'] ?? created['createdAt'])
                              : null;

                          movements.insert(0, {
                            'id': created != null
                                ? (created['id'] ??
                                      created['_id'] ??
                                      created['transactionId'])
                                : null,
                            'title': descripcionController.text.trim(),
                            'amount': amount,
                            'date': _formatDisplayDate(
                              rawDate ?? _formatDate(),
                            ),
                            'category':
                                (categories.firstWhere(
                                  (c) =>
                                      (c['id'] ?? '').toString() ==
                                      categoriaSeleccionada,
                                  orElse: () => {},
                                )['name']) ??
                                categoriaSeleccionada,
                            'categoryId': categoriaSeleccionada,
                          });
                          _movementsNotifier.value =
                              List<Map<String, dynamic>>.from(movements);
                          _totalBalanceNotifier.value = totalBalance;
                          _monthlyBudgetNotifier.value = monthlyBudget;

                          Navigator.pop(context);

                          if (mounted)
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  isIncome
                                      ? '✓ Ingreso agregado correctamente'
                                      : '✓ Gasto registrado correctamente',
                                ),
                                backgroundColor: isIncome
                                    ? Colors.green
                                    : Colors.red,
                                duration: const Duration(seconds: 2),
                              ),
                            );
                          // refresh data from backend after creation (silent)
                          if (mounted) await _loadHomeData(showLoading: false);
                        } catch (e) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Error creando transacción: $e'),
                              backgroundColor: Colors.orange,
                            ),
                          );
                        }
                      },
                      backgroundColor: isIncome
                          ? Colors.green.shade500
                          : Colors.red.shade500,
                      icon: Icons.check,
                      label: isIncome ? 'Confirmar Ingreso' : 'Confirmar Gasto',
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  String _formatDate() {
    final now = DateTime.now();
    return '${now.day}/${now.month}, ${now.hour}:${now.minute.toString().padLeft(2, '0')}';
  }

  Widget _buildReports() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Reportes - Personal',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: InkWell(
                onTap: () async {
                  // Navegar a la pantalla del gráfico
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) =>
                          const _ChartPage(title: 'Gastos de la semana'),
                    ),
                  );
                },
                borderRadius: BorderRadius.circular(4),
                child: Card(
                  child: Container(
                    height: 150,
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Gastos de la semana',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 12),
                        // Small preview chart (simple custom painter)
                        SizedBox(
                          height: 80,
                          child: CustomPaint(
                            painter: _SmallSparklinePainter(),
                            child: Container(),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: InkWell(
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const _ChartPage(title: 'Por categorías'),
                    ),
                  );
                },
                borderRadius: BorderRadius.circular(4),
                child: Card(
                  child: Container(
                    height: 150,
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Por categorías',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 12),
                        SizedBox(
                          height: 80,
                          child: CustomPaint(
                            painter: _SmallBarPainter(),
                            child: Container(),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  // Small preview painters
}

class _SmallSparklinePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.purple.shade300
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final points = [
      Offset(0, size.height * 0.7),
      Offset(size.width * 0.2, size.height * 0.5),
      Offset(size.width * 0.4, size.height * 0.6),
      Offset(size.width * 0.6, size.height * 0.35),
      Offset(size.width * 0.8, size.height * 0.45),
      Offset(size.width, size.height * 0.3),
    ];

    final path = Path();
    for (var i = 0; i < points.length; i++) {
      if (i == 0)
        path.moveTo(points[i].dx, points[i].dy);
      else
        path.lineTo(points[i].dx, points[i].dy);
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _SmallBarPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.teal.shade200;
    final barWidth = size.width / 9;
    final heights = [0.6, 0.4, 0.8, 0.3, 0.7];
    for (var i = 0; i < heights.length; i++) {
      final left = i * (barWidth * 1.6);
      final top = size.height * (1 - heights[i]);
      final rect = Rect.fromLTWH(left, top, barWidth, size.height - top);
      final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(6));
      canvas.drawRRect(rrect, paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _ChartPage extends StatelessWidget {
  final String title;
  const _ChartPage({Key? key, required this.title}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title), backgroundColor: Colors.deepPurple),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: Center(
                child: SizedBox(
                  width: double.infinity,
                  child: CustomPaint(
                    size: const Size(double.infinity, 300),
                    painter: _LargeSparklinePainter(),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Este es un gráfico de ejemplo. Aquí podrías mostrar tus datos reales por semana o por categorías.',
              style: TextStyle(color: Colors.grey[700]),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}

class _LargeSparklinePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.deepPurple.shade400
      ..strokeWidth = 4
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final points = [
      Offset(0, size.height * 0.7),
      Offset(size.width * 0.15, size.height * 0.55),
      Offset(size.width * 0.3, size.height * 0.6),
      Offset(size.width * 0.45, size.height * 0.35),
      Offset(size.width * 0.6, size.height * 0.5),
      Offset(size.width * 0.75, size.height * 0.4),
      Offset(size.width, size.height * 0.3),
    ];

    final path = Path();
    for (var i = 0; i < points.length; i++) {
      if (i == 0)
        path.moveTo(points[i].dx, points[i].dy);
      else
        path.lineTo(points[i].dx, points[i].dy);
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ============================================
// WIDGET REUTILIZABLE: CustomActionButton
// ============================================
class CustomActionButton extends StatelessWidget {
  final VoidCallback onPressed;
  final Color backgroundColor;
  final IconData icon;
  final String label;

  const CustomActionButton({
    super.key,
    required this.onPressed,
    required this.backgroundColor,
    required this.icon,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return ElevatedButton.icon(
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: backgroundColor,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        elevation: 0,
      ),
      icon: Icon(icon, size: 18),
      label: Text(
        label,
        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
      ),
    );
  }
}

// ============================================
// WIDGET PARA ITEM DE MOVIMIENTO
// ============================================
class _MovementItem extends StatelessWidget {
  final String title;
  final double amount;
  final String date;
  final String category;

  const _MovementItem({
    Key? key,
    required this.title,
    required this.amount,
    required this.date,
    required this.category,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final isNegative = amount < 0;
    return ListTile(
      title: Text(title.isEmpty ? category : title),
      subtitle: Text('$date | $category'),
      trailing: Text(
        'S/ ${amount.toStringAsFixed(2)}',
        style: TextStyle(
          color: isNegative ? Colors.red : Colors.green,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}
