import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:open_file/open_file.dart';
import 'package:permission_handler/permission_handler.dart';
import '../services/backend_service.dart';
import 'add_expense_screen.dart';
import 'add_earning_screen.dart';
import 'expense_details_screen.dart';
import 'recurring_expenses_screen.dart';
import 'category_management_screen.dart';
import '../utils/category_icons.dart';
import 'family_invites_screen.dart';
import '../widgets/language_toggle.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => HomeScreenState();
}

class HomeScreenState extends State<HomeScreen> {
  final _backendService = BackendService();

  DateTime _currentDate = DateTime.now();
  bool _isLoading = false;
  DashboardData? _dashboardData;
  String _errorMessage = '';
  String? _selectedCategory;
  String? _selectedUser;
  int? _closingDay;
  bool _showUserChart = true;
  bool _showCategoryChart = true;
  Map<String, String> _categoryKeyByLabel = {};

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
      SnackBar(content: Text('update.checking'.tr())),
    );
    try {
      final versionData = await _backendService.checkForUpdate();
      final packageInfo = await PackageInfo.fromPlatform();
      final currentCode = int.tryParse(packageInfo.buildNumber) ?? 1;
      final remoteCode = versionData['version_code'] as int? ?? 1;
      if (remoteCode <= currentCode) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content: Text('update.latest'
                    .tr(namedArgs: {'version': packageInfo.version}))),
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
          title: Text('update.title'.tr()),
          content: Text('update.body'.tr(namedArgs: {
            'name': remoteName.toString(),
            'notes': releaseNotes.toString(),
          })),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text('update.later'.tr())),
            ElevatedButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: Text('update.update_button'.tr())),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;

      // Check install-unknown-apps permission (Android 8+) before downloading.
      // .request() opens the Settings screen and returns immediately — it does NOT
      // wait for the user to grant. So if not granted, open settings and bail out;
      // the user taps the button again after enabling the toggle.
      final installPermission = await Permission.requestInstallPackages.status;
      if (!installPermission.isGranted) {
        await openAppSettings(); // opens Install Unknown Apps settings page
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('update.enable_unknown_apps'.tr()),
              duration: const Duration(seconds: 6),
            ),
          );
        }
        return;
      }

      if (!mounted) return;
      final progressNotifier = ValueNotifier<double>(0.0);
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => ValueListenableBuilder<double>(
          valueListenable: progressNotifier,
          builder: (_, progress, __) => AlertDialog(
            title: Text('update.downloading'.tr()),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                LinearProgressIndicator(value: progress == 0 ? null : progress),
                const SizedBox(height: 12),
                Text(progress == 0
                    ? 'update.starting'.tr()
                    : '${(progress * 100).toStringAsFixed(0)}%'),
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

      final result = await OpenFile.open(apkPath,
          type: 'application/vnd.android.package-archive');
      if (result.type != ResultType.done && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('update.cannot_open'
                  .tr(namedArgs: {'message': result.message}))),
        );
      }
    } catch (e) {
      if (mounted) {
        Navigator.of(context).popUntil((r) => r.isFirst);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(
                  'update.failed'.tr(namedArgs: {'error': e.toString()})),
              backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _loadDashboard() async {
    final hasCached =
        BackendService.hasDashboardCache(_currentDate.month, _currentDate.year);

    if (!hasCached) {
      setState(() {
        _isLoading = true;
        _errorMessage = '';
      });
    }

    try {
      final data = await _backendService.getDashboard(
        month: _currentDate.month,
        year: _currentDate.year,
        closingDay: _closingDay,
        onRefresh: (refreshed) {
          if (mounted) {
            setState(() {
            _dashboardData = refreshed;
            _buildCategoryMap();
          });
          }
        },
      );
      if (mounted) {
        setState(() {
        _dashboardData = data;
        _buildCategoryMap();
      });
      }
    } catch (e) {
      if (mounted) setState(() => _errorMessage = e.toString());
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _reloadAfterMutation() {
    BackendService.clearDashboardCache();
    return _loadDashboard();
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

  void _buildCategoryMap() {
    if (_dashboardData == null) {
      _categoryKeyByLabel = {};
      return;
    }
    _categoryKeyByLabel = {
      for (final e in _dashboardData!.expenses)
        if (e['category_label'] != null && e['category_key'] != null)
          e['category_label'] as String: e['category_key'] as String
    };
  }

  String _translateCategoryLabel(String label) {
    final key = _categoryKeyByLabel[label];
    if (key == null) return label;
    final translationKey = 'categories.$key';
    final translated = translationKey.tr();
    // If easy_localization returns the key unchanged, the key isn't in the JSON
    return translated == translationKey ? label : translated;
  }

  List<dynamic> _getFilteredExpenses() {
    if (_dashboardData == null) return [];
    Iterable<dynamic> filtered = _dashboardData!.expenses;
    if (_selectedCategory != null) {
      filtered =
          filtered.where((e) => e['category_label'] == _selectedCategory);
    }
    if (_selectedUser != null) {
      filtered = filtered.where((e) => e['user_name'] == _selectedUser);
    }
    final list = filtered.toList()
      ..sort((a, b) {
        final dateA = DateTime.parse(a['spent_at']);
        final dateB = DateTime.parse(b['spent_at']);
        return dateB.compareTo(dateA);
      });
    return list;
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
              Text(
                'closing_day.title'.tr(),
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 10),
              Expanded(
                child: ListView.builder(
                  itemCount: daysInMonth,
                  itemBuilder: (context, index) {
                    final day = index + 1;
                    return ListTile(
                      title: Text(
                          'closing_day.day'.tr(namedArgs: {'day': day.toString()})),
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
                          _reloadAfterMutation();
                        } catch (e) {
                          if (ctx.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('common.error_with_message'
                                  .tr(namedArgs: {'error': e.toString()}))),
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
                    _reloadAfterMutation();
                  } catch (e) {
                    if (ctx.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Error: $e')),
                      );
                    }
                  }
                },
                child: Text('closing_day.reset'.tr()),
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
          title: Text('delete_expense.cannot_delete_title'.tr()),
          content: Text('delete_expense.recurring_warning'.tr()),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('common.ok'.tr()),
            ),
          ],
        ),
      );
      return;
    }

    final bool isInstallment = expense['installment_group_id'] != null;
    final String? scope = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('delete_expense.title'.tr()),
        content: Text(isInstallment
            ? 'delete_expense.installment_body'.tr()
            : 'delete_expense.confirm_body'.tr()),
        actions: isInstallment
            ? [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, null),
                  child: Text('common.cancel'.tr()),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(ctx, 'this'),
                  child: Text('delete_expense.only_this'.tr()),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(ctx, 'future'),
                  child: Text('delete_expense.this_and_future'.tr(),
                      style: const TextStyle(color: Colors.red)),
                ),
              ]
            : [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, null),
                  child: Text('common.cancel'.tr()),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(ctx, 'this'),
                  child: Text('common.delete'.tr(),
                      style: const TextStyle(color: Colors.red)),
                ),
              ],
      ),
    );

    if (scope != null) {
      try {
        await _backendService.deleteExpense(expense['id'], scope: scope);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('delete_expense.success'.tr())),
          );
          _reloadAfterMutation();
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('common.error_with_message'
                .tr(namedArgs: {'error': e.toString()}))),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    context.locale; // subscribe to locale changes so .tr() strings re-evaluate
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: Text('home.app_title'.tr(),
            style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white,
        elevation: 0,
        actions: [
          const LanguageToggle(),
          IconButton(
            icon: const Icon(Icons.system_update_alt, color: Colors.black),
            tooltip: 'home.check_updates_tooltip'.tr(),
            onPressed: _checkForUpdate,
          ),
          IconButton(
            icon: const Icon(Icons.category_outlined, color: Colors.black),
            tooltip: 'home.manage_categories_tooltip'.tr(),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => const CategoryManagementScreen()),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.group_add_outlined, color: Colors.black),
            tooltip: 'home.family_invites_tooltip'.tr(),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const FamilyInvitesScreen()),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.logout, color: Colors.black),
            tooltip: 'home.sign_out_tooltip'.tr(),
            onPressed: () async {
              final prefs = await SharedPreferences.getInstance();
              await prefs.remove('remember_me');
              await Supabase.instance.client.auth.signOut();
            },
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
                    SnackBar(content: Text('home.opening_report'.tr())),
                  );
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                        content: Text('home.report_failed'
                            .tr(namedArgs: {'error': e.toString()})),
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
            tooltip: 'home.set_closing_day_tooltip'.tr(),
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
                          label: Text('common.all'.tr()),
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
                              label: Text(_translateCategoryLabel(cat)),
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
                      Text('home.income_by_user'.tr(),
                          style: const TextStyle(fontWeight: FontWeight.bold)),
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
                SizedBox(
                    height: 100,
                    child: Center(child: Text('home.no_expenses_this_month'.tr()))),

              const SizedBox(height: 20),

              if (_dashboardData!.earnings.isNotEmpty) ...[
                ExpansionTile(
                  title: Text('home.recent_earnings'.tr(),
                      style:
                          const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  children: _dashboardData!.earnings.map((earning) {
                    return ListTile(
                      leading: const CircleAvatar(
                        backgroundColor: Colors.green,
                        child: Icon(Icons.attach_money, color: Colors.white),
                      ),
                      title: Text(earning.userName ?? 'common.unknown'.tr()),
                      subtitle: earning.description != null &&
                              earning.description!.isNotEmpty
                          ? Text(earning.description!)
                          : null,
                      trailing: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            DateFormat('dd/MM').format(earning.earnedAt),
                            style: const TextStyle(
                                fontSize: 12, color: Colors.grey),
                          ),
                          Text(
                            'R\$ ${earning.amount.toStringAsFixed(2)}',
                            style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Colors.green),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 20),
              ],

              // Recent Expenses List (from raw expenses)
              Text('home.recent_expenses'.tr(),
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 10),

              if (_selectedUser != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: InputChip(
                      avatar: const Icon(Icons.person, size: 16),
                      label: Text('home.filtered_by'
                          .tr(namedArgs: {'name': _selectedUser ?? ''})),
                      onDeleted: () => setState(() => _selectedUser = null),
                      deleteIcon: const Icon(Icons.close, size: 16),
                    ),
                  ),
                ),

              ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _getFilteredExpenses().length,
                itemBuilder: (context, index) {
                  final exp = _getFilteredExpenses()[index];
                  final isRecurring = exp['recurring_id'] != null;
                  const recurringColor = Color(0xFFE65100);
                  return Card(
                    elevation: 0,
                    margin: const EdgeInsets.only(bottom: 8),
                    clipBehavior: Clip.antiAlias,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                    child: Container(
                      decoration: isRecurring
                          ? const BoxDecoration(
                              border: Border(
                                left:
                                    BorderSide(color: recurringColor, width: 4),
                              ),
                            )
                          : null,
                      child: ListTile(
                        onTap: () async {
                          final result = await Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (_) =>
                                    ExpenseDetailsScreen(expense: exp)),
                          );
                          if (result == true) {
                            _reloadAfterMutation(); // Reload if expense was deleted
                          }
                        },
                        onLongPress: () => _deleteExpense(exp),
                        leading: CircleAvatar(
                          backgroundColor: Colors.blue[50],
                          child: Icon(
                              categoryIcon(exp['category_key'] as String?),
                              color: Colors.blue,
                              size: 20),
                        ),
                        title: Row(
                          children: [
                            Flexible(child: Text(_translateCategoryLabel(exp['category_label'] as String))),
                            if (isRecurring) ...[
                              const SizedBox(width: 6),
                              const Icon(Icons.repeat,
                                  size: 14, color: recurringColor),
                            ],
                          ],
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                                '${exp['user_name']} • ${exp['payment_method_name']}'),
                            if (exp['comment'] != null &&
                                exp['comment'].isNotEmpty)
                              Text('"${exp['comment']}"',
                                  style: const TextStyle(
                                      fontStyle: FontStyle.italic,
                                      fontSize: 12)),
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
                              style:
                                  const TextStyle(fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ],
          ],
        ),
      ),
    );
  }

  void showAddOptions() {
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
                title: Text('add_options.expense'.tr()),
                onTap: () async {
                  Navigator.pop(ctx);
                  await Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const AddExpenseScreen()),
                  );
                  _reloadAfterMutation();
                },
              ),
              ListTile(
                leading: const Icon(Icons.attach_money, color: Colors.green),
                title: Text('add_options.income'.tr()),
                onTap: () async {
                  Navigator.pop(ctx);
                  await Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const AddEarningScreen()),
                  );
                  _reloadAfterMutation();
                },
              ),
              ListTile(
                leading: const Icon(Icons.repeat, color: Colors.blue),
                title: Text('add_options.recurring'.tr()),
                onTap: () async {
                  Navigator.pop(ctx);
                  await Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const RecurringExpensesScreen()),
                  );
                  _reloadAfterMutation();
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
          Text('home.balance'.tr(), style: const TextStyle(color: Colors.white70)),
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
                  Text('home.income'.tr(), style: const TextStyle(color: Colors.white54)),
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
                  Text('home.expense'.tr(),
                      style: const TextStyle(color: Colors.white54)),
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
    final entries = breakdown.entries.where((e) => e.value > 0).toList()
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
                Text('home.spending_by_person'.tr(),
                    style: const TextStyle(fontWeight: FontWeight.bold)),
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
            const SizedBox(height: 16),
            const Divider(height: 1),
            const SizedBox(height: 12),
            ...entries.asMap().entries.map((e) {
              final color = _personColors[e.key % _personColors.length];
              final pct = total > 0 ? (e.value.value / total * 100) : 0.0;
              final userName = e.value.key;
              final isSelected = _selectedUser == userName;
              return InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: () => setState(() {
                  _selectedUser = isSelected ? null : userName;
                }),
                child: Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                  decoration: isSelected
                      ? BoxDecoration(
                          color: color.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(8),
                        )
                      : null,
                  child: Row(
                    children: [
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: color.withValues(alpha: 0.12),
                          shape: BoxShape.circle,
                        ),
                        child: Center(
                          child: Text(
                            userName[0].toUpperCase(),
                            style: TextStyle(
                              color: color,
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              userName,
                              style:
                                  const TextStyle(fontWeight: FontWeight.w600),
                            ),
                            const SizedBox(height: 2),
                            LinearProgressIndicator(
                              value: total > 0 ? e.value.value / total : 0,
                              backgroundColor: Colors.grey[200],
                              color: color,
                              minHeight: 4,
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            'R\$ ${e.value.value.toStringAsFixed(2)}',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          Text(
                            '${pct.toStringAsFixed(1)}%',
                            style: const TextStyle(
                                fontSize: 11, color: Colors.grey),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            }),
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
    final entries = breakdown.entries.where((e) => e.value > 0).toList()
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
                Text('home.expenses_by_category'.tr(),
                    style: const TextStyle(fontWeight: FontWeight.bold)),
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
