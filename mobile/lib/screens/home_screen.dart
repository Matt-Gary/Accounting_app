import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:open_file/open_file.dart';
import '../services/backend_service.dart';
import 'add_expense_screen.dart';
import 'add_earning_screen.dart';
import 'expense_details_screen.dart';
import 'recurring_expenses_screen.dart';
import 'category_management_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _backendService = BackendService();

  DateTime _currentDate = DateTime.now();
  bool _isLoading = false;
  DashboardData? _dashboardData;
  String _errorMessage = '';
  String? _selectedCategory;
  int? _closingDay;
  bool _showUserChart = true;
  bool _showCategoryChart = true;

  @override
  void initState() {
    super.initState();
    _loadClosingDay();
  }

  Future<void> _loadClosingDay() async {
    try {
      final override = await _backendService.getClosingDayOverride(
        _currentDate.month,
        _currentDate.year,
      );
      setState(() {
        _closingDay = override;
      });
    } catch (e) {
      // No override found or error, use default
      setState(() {
        _closingDay = null;
      });
    }
    _loadDashboard();
  }

  Future<void> _checkForUpdate() async {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Checking for updates...')),
    );
    try {
      final versionData = await _backendService.checkForUpdate();
      if (versionData == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not reach update server.')),
          );
        }
        return;
      }
      final packageInfo = await PackageInfo.fromPlatform();
      final currentCode = int.tryParse(packageInfo.buildNumber) ?? 1;
      final remoteCode = versionData['version_code'] as int? ?? 1;
      if (remoteCode <= currentCode) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('You are on the latest version (${packageInfo.version}).')),
          );
        }
        return;
      }
      final remoteName = versionData['version_name'] ?? 'unknown';
      final releaseNotes = versionData['release_notes'] ?? '';
      final downloadUrl = versionData['apk_url'] as String?;
      if (downloadUrl == null || !mounted) return;

      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Update Available'),
          content: Text('Version $remoteName is available.\n\n$releaseNotes\n\nDownload and install now?'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Later')),
            ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Update')),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;

      final progressNotifier = ValueNotifier<double>(0.0);
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => ValueListenableBuilder<double>(
          valueListenable: progressNotifier,
          builder: (_, progress, __) => AlertDialog(
            title: const Text('Downloading Update'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                LinearProgressIndicator(value: progress == 0 ? null : progress),
                const SizedBox(height: 12),
                Text(progress == 0 ? 'Starting...' : '${(progress * 100).toStringAsFixed(0)}%'),
              ],
            ),
          ),
        ),
      );

      final apkPath = await _backendService.downloadApk(
        downloadUrl: downloadUrl,
        onProgress: (p) => progressNotifier.value = p,
      );
      progressNotifier.dispose();
      if (mounted) Navigator.of(context).pop();

      final result = await OpenFile.open(apkPath, type: 'application/vnd.android.package-archive');
      if (result.type != ResultType.done && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not open installer: ${result.message}')),
        );
      }
    } catch (e) {
      if (mounted) {
        Navigator.of(context).popUntil((r) => r.isFirst);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Update failed: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _loadDashboard() async {
    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });

    try {
      final data = await _backendService.getDashboard(
        month: _currentDate.month,
        year: _currentDate.year,
        closingDay: _closingDay,
      );
      setState(() => _dashboardData = data);
    } catch (e) {
      setState(() => _errorMessage = e.toString());
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _changeMonth(int months) {
    setState(() {
      _currentDate =
          DateTime(_currentDate.year, _currentDate.month + months, 1);
      _selectedCategory = null; // Reset filter when changing month
    });
    _loadClosingDay(); // Reload closing day for the new month
  }

  List<String> _getUniqueCategories() {
    if (_dashboardData == null) return [];
    final categories = _dashboardData!.expenses
        .map((e) => e['category_label'] as String)
        .toSet()
        .toList();
    categories.sort();
    return categories;
  }

  List<dynamic> _getFilteredExpenses() {
    if (_dashboardData == null) return [];
    final filtered = _selectedCategory == null
        ? List.from(_dashboardData!.expenses)
        : _dashboardData!.expenses
            .where((e) => e['category_label'] == _selectedCategory)
            .toList();

    // Sort by date descending
    filtered.sort((a, b) {
      final dateA = DateTime.parse(a['spent_at']);
      final dateB = DateTime.parse(b['spent_at']);
      return dateB.compareTo(dateA);
    });

    return filtered;
  }

  void _showClosingDayPicker() {
    final daysInMonth =
        DateUtils.getDaysInMonth(_currentDate.year, _currentDate.month);
    showModalBottomSheet(
      context: context,
      builder: (ctx) {
        return Container(
          height: 300,
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              const Text(
                'Select Closing Day',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 10),
              Expanded(
                child: ListView.builder(
                  itemCount: daysInMonth,
                  itemBuilder: (context, index) {
                    final day = index + 1;
                    return ListTile(
                      title: Text('Day $day'),
                      selected: _closingDay == day,
                      trailing: _closingDay == day
                          ? const Icon(Icons.check, color: Colors.blue)
                          : null,
                      onTap: () async {
                        try {
                          await _backendService.setClosingDayOverride(
                            _currentDate.month,
                            _currentDate.year,
                            day,
                          );
                          setState(() {
                            _closingDay = day;
                          });
                          if (ctx.mounted) Navigator.pop(ctx);
                          _loadDashboard();
                        } catch (e) {
                          if (ctx.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Error: $e')),
                            );
                          }
                        }
                      },
                    );
                  },
                ),
              ),
              TextButton(
                onPressed: () async {
                  try {
                    await _backendService.deleteClosingDayOverride(
                      _currentDate.month,
                      _currentDate.year,
                    );
                    setState(() {
                      _closingDay = null; // Reset to default
                    });
                    if (ctx.mounted) Navigator.pop(ctx);
                    _loadDashboard();
                  } catch (e) {
                    if (ctx.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Error: $e')),
                      );
                    }
                  }
                },
                child: const Text('Reset to Default (23)'),
              ),
            ],
          ),
        );
      },
    );
  }

  double _getFilteredTotalSpent() {
    final filtered = _getFilteredExpenses();
    return filtered.fold(
        0.0, (sum, e) => sum + (e['amount'] as num).toDouble());
  }

  Map<String, double> _getFilteredUserBreakdown() {
    final filtered = _getFilteredExpenses();
    final breakdown = <String, double>{};
    for (var exp in filtered) {
      final user = exp['user_name'] as String;
      final amount = (exp['amount'] as num).toDouble();
      breakdown[user] = (breakdown[user] ?? 0) + amount;
    }
    return breakdown;
  }

  Future<void> _deleteExpense(Map<String, dynamic> expense) async {
    // Block deletion of recurring-linked expenses
    if (expense['recurring_id'] != null) {
      await showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text("Cannot Delete"),
          content: const Text(
              "This expense is auto-generated from a recurring definition. "
              "It will reappear next time the dashboard loads. "
              "To stop it permanently, deactivate the recurring expense in Recurring Expenses settings."),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text("OK"),
            ),
          ],
        ),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Delete Expense"),
        content: const Text("Are you sure you want to delete this expense?"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text("Cancel"),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text("Delete", style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await _backendService.deleteExpense(expense['id']);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Expense deleted successfully')),
          );
          _loadDashboard();
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error: $e')),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: const Text('Accounting App',
            style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.system_update_alt, color: Colors.black),
            tooltip: 'Check for Updates',
            onPressed: _checkForUpdate,
          ),
          IconButton(
            icon: const Icon(Icons.category_outlined, color: Colors.black),
            tooltip: 'Manage Categories',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => const CategoryManagementScreen()),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.logout, color: Colors.black),
            tooltip: 'Sign out',
            onPressed: () => Supabase.instance.client.auth.signOut(),
          ),
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.black),
            onPressed: _loadDashboard,
          ),
          IconButton(
            icon: const Icon(Icons.download, color: Colors.black),
            onPressed: () async {
              try {
                await _backendService.downloadReport(
                    _currentDate.month, _currentDate.year);
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Opening report download...')),
                  );
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                        content: Text('Failed to download report: $e'),
                        backgroundColor: Colors.red),
                  );
                }
              }
            },
          ),
          IconButton(
            icon: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.calendar_today, color: Colors.black, size: 20),
                Text(
                  '${_closingDay ?? 23}',
                  style: const TextStyle(
                    fontSize: 10,
                    color: Colors.black,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            onPressed: _showClosingDayPicker,
            tooltip: 'Set Closing Day',
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            // Month Selector
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                IconButton(
                    icon: const Icon(Icons.arrow_back_ios),
                    onPressed: () => _changeMonth(-1)),
                Text(
                  DateFormat('MMMM yyyy').format(_currentDate),
                  style: const TextStyle(
                      fontSize: 20, fontWeight: FontWeight.bold),
                ),
                IconButton(
                    icon: const Icon(Icons.arrow_forward_ios),
                    onPressed: () => _changeMonth(1)),
              ],
            ),
            const SizedBox(height: 20),

            if (_isLoading)
              const SizedBox(
                  height: 200,
                  child: Center(child: CircularProgressIndicator()))
            else if (_errorMessage.isNotEmpty)
              Center(
                  child: Text('Error: $_errorMessage',
                      style: const TextStyle(color: Colors.red)))
            else if (_dashboardData != null) ...[
              // Category Filter
              if (_dashboardData!.categoryBreakdown.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 20),
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        FilterChip(
                          label: const Text('All'),
                          selected: _selectedCategory == null,
                          onSelected: (selected) {
                            setState(() => _selectedCategory = null);
                          },
                          selectedColor: Colors.black,
                          labelStyle: TextStyle(
                            color: _selectedCategory == null
                                ? Colors.white
                                : Colors.black,
                          ),
                        ),
                        const SizedBox(width: 8),
                        ..._getUniqueCategories().map((cat) {
                          final isSelected = _selectedCategory == cat;
                          return Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: FilterChip(
                              label: Text(cat),
                              selected: isSelected,
                              onSelected: (selected) {
                                setState(() =>
                                    _selectedCategory = selected ? cat : null);
                              },
                              selectedColor: Colors.black,
                              labelStyle: TextStyle(
                                color: isSelected ? Colors.white : Colors.black,
                              ),
                            ),
                          );
                        }),
                      ],
                    ),
                  ),
                ),

              // Total Spent Card
              _buildTotalCard(),

              const SizedBox(height: 20),

              // User Breakdown
              if (_dashboardData!.userSpendBreakdown.isNotEmpty)
                _buildUserSpendChart(),

              if (_dashboardData!.userEarnedBreakdown.isNotEmpty) ...[
                const SizedBox(height: 20),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12)),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Income by User',
                          style: TextStyle(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 10),
                      ..._dashboardData!.userEarnedBreakdown.entries.map((e) {
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(e.key),
                              Text('R\$ ${e.value.toStringAsFixed(2)}',
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: Colors.green)),
                            ],
                          ),
                        );
                      }),
                    ],
                  ),
                ),
              ],

              const SizedBox(height: 20),

              // Category Chart
              if (_dashboardData!.categoryBreakdown.isNotEmpty)
                _buildCategoryChart()
              else
                const SizedBox(
                    height: 100,
                    child: Center(child: Text('No expenses this month'))),

              const SizedBox(height: 20),

              // Recent Expenses List (from raw expenses)
              const Text('Recent Expenses',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 10),

              ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _getFilteredExpenses().length,
                itemBuilder: (context, index) {
                  final exp = _getFilteredExpenses()[index];
                  return Card(
                    elevation: 0,
                    margin: const EdgeInsets.only(bottom: 8),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                    child: ListTile(
                      onTap: () async {
                        final result = await Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) =>
                                  ExpenseDetailsScreen(expense: exp)),
                        );
                        if (result == true) {
                          _loadDashboard(); // Reload if expense was deleted
                        }
                      },
                      onLongPress: () => _deleteExpense(exp),
                      leading: CircleAvatar(
                        backgroundColor: Colors.blue[50],
                        child: Text(exp['category_label'][0]),
                      ),
                      title: Text(exp['category_label']),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                              '${exp['user_name']} • ${exp['payment_method_name']}'),
                          if (exp['comment'] != null &&
                              exp['comment'].isNotEmpty)
                            Text('"${exp['comment']}"',
                                style: const TextStyle(
                                    fontStyle: FontStyle.italic, fontSize: 12)),
                        ],
                      ),
                      trailing: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            DateFormat('dd/MM')
                                .format(DateTime.parse(exp['spent_at'])),
                            style: const TextStyle(
                                fontSize: 12, color: Colors.grey),
                          ),
                          Text(
                            'R\$ ${(exp['amount'] as num).toDouble().toStringAsFixed(2)}',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ],
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showAddOptions(context),
        child: const Icon(Icons.add, color: Colors.white),
        backgroundColor: Colors.black,
      ),
    );
  }

  void _showAddOptions(BuildContext context) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.money_off, color: Colors.red),
                title: const Text('Add Expense'),
                onTap: () async {
                  Navigator.pop(ctx);
                  await Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const AddExpenseScreen()),
                  );
                  _loadDashboard();
                },
              ),
              ListTile(
                leading: const Icon(Icons.attach_money, color: Colors.green),
                title: const Text('Add Income'),
                onTap: () async {
                  Navigator.pop(ctx);
                  await Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const AddEarningScreen()),
                  );
                  _loadDashboard();
                },
              ),
              ListTile(
                leading: const Icon(Icons.repeat, color: Colors.blue),
                title: const Text('Recurring Expenses'),
                onTap: () async {
                  Navigator.pop(ctx);
                  await Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const RecurringExpensesScreen()),
                  );
                  _loadDashboard();
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildTotalCard() {
    final balance = _dashboardData!.totalEarned - _dashboardData!.totalSpent;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 10,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        children: [
          const Text('Balance', style: TextStyle(color: Colors.white70)),
          const SizedBox(height: 5),
          Text(
            'R\$ ${balance.toStringAsFixed(2)}',
            style: TextStyle(
                color: balance >= 0 ? Colors.greenAccent : Colors.redAccent,
                fontSize: 36,
                fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              Column(
                children: [
                  const Text('Income', style: TextStyle(color: Colors.white54)),
                  const SizedBox(height: 4),
                  Text(
                    'R\$ ${_dashboardData!.totalEarned.toStringAsFixed(2)}',
                    style: const TextStyle(
                        color: Colors.green,
                        fontSize: 18,
                        fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              Container(height: 30, width: 1, color: Colors.white24),
              Column(
                children: [
                  const Text('Expense',
                      style: TextStyle(color: Colors.white54)),
                  const SizedBox(height: 4),
                  Text(
                    'R\$ ${_getFilteredTotalSpent().toStringAsFixed(2)}',
                    style: const TextStyle(
                        color: Colors.red,
                        fontSize: 18,
                        fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Map<String, double> _getFilteredCategoryBreakdown() {
    if (_selectedCategory == null) {
      return _dashboardData!.categoryBreakdown;
    }
    final filtered = _getFilteredExpenses();
    final Map<String, double> breakdown = {};
    for (final e in filtered) {
      final label = e['category_label'] as String? ?? 'Unknown';
      final amount = (e['amount'] as num).toDouble();
      breakdown[label] = (breakdown[label] ?? 0.0) + amount;
    }
    return breakdown;
  }

  static const List<Color> _personColors = [
    Color(0xFF1565C0), // blue
    Color(0xFFC62828), // red
    Color(0xFF2E7D32), // green
    Color(0xFF6A1B9A), // purple
    Color(0xFFE65100), // orange
    Color(0xFF00695C), // teal
    Color(0xFFAD1457), // pink
    Color(0xFF4527A0), // deep purple
  ];

  Widget _buildUserSpendChart() {
    final breakdown = _getFilteredUserBreakdown();
    if (breakdown.isEmpty) return const SizedBox.shrink();

    final total = breakdown.values.fold(0.0, (a, b) => a + b);
    final entries = breakdown.entries
        .where((e) => e.value > 0)
        .toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    final sections = entries.asMap().entries.map((e) {
      final color = _personColors[e.key % _personColors.length];
      return PieChartSectionData(
        color: color,
        value: e.value.value,
        title: '',
        radius: 60,
      );
    }).toList();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onTap: () => setState(() => _showUserChart = !_showUserChart),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Spending by Person',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                Icon(_showUserChart
                    ? Icons.keyboard_arrow_up
                    : Icons.keyboard_arrow_down),
              ],
            ),
          ),
          if (_showUserChart) ...[
            const SizedBox(height: 16),
            SizedBox(
              height: 200,
              child: PieChart(
                PieChartData(
                  sections: sections,
                  centerSpaceRadius: 40,
                  sectionsSpace: 2,
                ),
              ),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              children: entries.asMap().entries.map((e) {
                final color = _personColors[e.key % _personColors.length];
                final pct = total > 0 ? (e.value.value / total * 100) : 0.0;
                return Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        color: color,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '${e.value.key}: ${pct.toStringAsFixed(1)}%',
                      style: const TextStyle(fontSize: 11),
                    ),
                  ],
                );
              }).toList(),
            ),
          ],
        ],
      ),
    );
  }

  static const List<Color> _chartColors = [
    Color(0xFF1565C0), // blue 800
    Color(0xFFC62828), // red 800
    Color(0xFF2E7D32), // green 800
    Color(0xFFE65100), // orange 800
    Color(0xFF6A1B9A), // purple 800
    Color(0xFF00695C), // teal 800
    Color(0xFF0277BD), // light blue 800
    Color(0xFFAD1457), // pink 800
    Color(0xFF558B2F), // light green 800
    Color(0xFF4527A0), // deep purple 800
    Color(0xFF00838F), // cyan 800
    Color(0xFFF9A825), // amber 800
    Color(0xFF4E342E), // brown 800
    Color(0xFF37474F), // blue grey 800
  ];

  Widget _buildCategoryChart() {
    final breakdown = _getFilteredCategoryBreakdown();
    if (breakdown.isEmpty) return const SizedBox.shrink();

    final total = breakdown.values.fold(0.0, (a, b) => a + b);
    // Sort descending by value and remove zero entries
    final entries = breakdown.entries
        .where((e) => e.value > 0)
        .toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    final sections = entries.asMap().entries.map((e) {
      final color = _chartColors[e.key % _chartColors.length];
      return PieChartSectionData(
        color: color,
        value: e.value.value,
        title: '',
        radius: 60,
      );
    }).toList();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onTap: () =>
                setState(() => _showCategoryChart = !_showCategoryChart),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Expenses by Category',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                Icon(_showCategoryChart
                    ? Icons.keyboard_arrow_up
                    : Icons.keyboard_arrow_down),
              ],
            ),
          ),
          if (_showCategoryChart) ...[
            const SizedBox(height: 16),
            SizedBox(
              height: 200,
              child: PieChart(
                PieChartData(
                  sections: sections,
                  centerSpaceRadius: 40,
                  sectionsSpace: 2,
                ),
              ),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              children: entries.asMap().entries.map((e) {
                final color = _chartColors[e.key % _chartColors.length];
                final pct = total > 0 ? (e.value.value / total * 100) : 0.0;
                return Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        color: color,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '${e.value.key}: ${pct.toStringAsFixed(1)}%',
                      style: const TextStyle(fontSize: 11),
                    ),
                  ],
                );
              }).toList(),
            ),
          ],
        ],
      ),
    );
  }
}
