import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
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
import '../utils/error_text.dart';
import '../utils/money_format.dart';
import 'family_invites_screen.dart';
import '../widgets/language_toggle.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => HomeScreenState();
}

class HomeScreenState extends State<HomeScreen> {
  final _backendService = BackendService();
  final _searchController = TextEditingController();

  DateTime _currentDate = DateTime.now();
  bool _isLoading = true;

  /// A request is in flight while figures are already on screen - either the
  /// previous ones or the copy kept on the device. Drawn as a thin bar, so
  /// figures that may be about to change are never presented as settled.
  bool _isRefreshing = false;
  DashboardData? _dashboardData;
  String _errorMessage = '';
  String? _selectedCategory;
  String? _selectedUser;
  String _searchQuery = '';
  int? _closingDay;
  bool _showUserChart = true;
  bool _showCategoryChart = true;
  Map<String, String> _categoryKeyByLabel = {};

  /// Bumped on every load. A response is applied only if it still belongs to
  /// the latest request — otherwise tapping "next month" twice could leave the
  /// slower first answer on screen under the second month's title.
  int _loadSeq = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  String _money(double value) =>
      formatMoney(value, expenseCurrency, context.locale.toString());

  // ── Loading ────────────────────────────────────────────────────────────────

  Future<void> _load({bool force = false}) async {
    final seq = ++_loadSeq;
    final month = _currentDate.month;
    final year = _currentDate.year;

    setState(() {
      _errorMessage = '';
      // Full-screen spinner only when there is nothing to show yet; a refresh
      // keeps the current figures on screen until the new ones arrive.
      _isLoading = _dashboardData == null;
      _isRefreshing = true;
    });

    // Display only: the backend applies the stored override itself, so the
    // dashboard request does not wait for this one.
    _backendService.getClosingDayOverride(month, year).then((value) {
      if (mounted && seq == _loadSeq) setState(() => _closingDay = value);
    }).catchError((_) {});

    // Nothing to show yet (cold start, or a month not opened in this session):
    // draw the month as this device last saw it while the request below runs.
    // Not awaited - the request must not wait for the disk - and it never
    // overwrites an answer that got here first.
    if (_dashboardData == null &&
        !BackendService.hasDashboardCache(month, year)) {
      _backendService
          .getStoredDashboard(month: month, year: year)
          .then((stored) {
        if (stored == null || !mounted || seq != _loadSeq) return;
        if (_dashboardData != null) return;
        _applyData(stored);
        setState(() => _isLoading = false);
      });
    }

    try {
      final data = await _backendService.getDashboard(
        month: month,
        year: year,
        forceRefresh: force,
        onRefresh: (refreshed) {
          if (mounted && seq == _loadSeq) _applyData(refreshed);
        },
      );
      if (!mounted || seq != _loadSeq) return;
      _applyData(data);
    } catch (e) {
      if (!mounted || seq != _loadSeq) return;
      setState(() => _errorMessage = errorText(e));
    } finally {
      if (mounted && seq == _loadSeq) {
        setState(() {
          _isLoading = false;
          _isRefreshing = false;
        });
      }
    }
  }

  void _applyData(DashboardData data) {
    setState(() {
      _dashboardData = data;
      _categoryKeyByLabel = {
        for (final e in data.expenses)
          if (e['category_label'] != null && e['category_key'] != null)
            e['category_label'] as String: e['category_key'] as String
      };
    });
  }

  /// After a write: other months can be affected too (installments, recurring
  /// definitions), so every cached month is dropped, not just this one.
  Future<void> _reloadAfterMutation() {
    BackendService.clearDashboardCache();
    return _load();
  }

  void _changeMonth(int months) {
    setState(() {
      _currentDate =
          DateTime(_currentDate.year, _currentDate.month + months, 1);
      // Filters describe the month they were set in; carrying them over hid
      // most of the next month for no visible reason.
      _clearFilters();
      _dashboardData = null;
      _closingDay = null;
    });
    _load();
  }

  void _clearFilters() {
    _selectedCategory = null;
    _selectedUser = null;
    _searchQuery = '';
    _searchController.clear();
  }

  // ── Filtering ──────────────────────────────────────────────────────────────

  bool get _hasFilters =>
      _selectedCategory != null ||
      _selectedUser != null ||
      _searchQuery.trim().isNotEmpty;

  String _translateCategoryLabel(String label) {
    final key = _categoryKeyByLabel[label];
    if (key == null) return label;
    final translationKey = 'categories.$key';
    final translated = translationKey.tr();
    // If easy_localization returns the key unchanged, the key isn't in the JSON
    return translated == translationKey ? label : translated;
  }

  /// Expenses passing the active filters. Each breakdown card leaves its own
  /// dimension out ([byCategory] / [byUser] false), so picking one category
  /// still shows the other categories to switch to.
  List<dynamic> _expensesWhere({bool byCategory = true, bool byUser = true}) {
    final data = _dashboardData;
    if (data == null) return const [];
    final query = _searchQuery.trim().toLowerCase();
    return data.expenses.where((e) {
      if (byCategory &&
          _selectedCategory != null &&
          e['category_label'] != _selectedCategory) {
        return false;
      }
      if (byUser && _selectedUser != null && e['user_name'] != _selectedUser) {
        return false;
      }
      if (query.isNotEmpty) {
        final label = e['category_label'] as String?;
        final haystack = [
          e['comment'],
          if (label != null) _translateCategoryLabel(label),
          e['user_name'],
          e['payment_method_name'],
        ].whereType<String>().join(' ').toLowerCase();
        if (!haystack.contains(query)) return false;
      }
      return true;
    }).toList();
  }

  double _sum(Iterable<dynamic> expenses) => expenses.fold(
      0.0, (total, e) => total + (e['amount'] as num).toDouble());

  Map<String, double> _breakdown(Iterable<dynamic> expenses, String field) {
    final result = <String, double>{};
    for (final e in expenses) {
      final key = (e[field] as String?) ?? 'common.unknown'.tr();
      result[key] = (result[key] ?? 0) + (e['amount'] as num).toDouble();
    }
    return result;
  }

  // ── Actions ────────────────────────────────────────────────────────────────

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
                  'update.failed'.tr(namedArgs: {'error': errorText(e)})),
              backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _downloadReport() async {
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
              content: Text(
                  'home.report_failed'.tr(namedArgs: {'error': errorText(e)})),
              backgroundColor: Colors.red),
        );
      }
    }
  }

  /// Sign-out sits in a menu next to everyday actions, so it asks first.
  Future<void> _signOut() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('home.sign_out_confirm_title'.tr()),
        content: Text('home.sign_out_confirm_body'.tr()),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('common.cancel'.tr()),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('home.sign_out_tooltip'.tr(),
                style: const TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('remember_me');
    await Supabase.instance.client.auth.signOut();
  }

  Future<void> _openScreen(Widget screen, {bool reload = false}) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => screen));
    if (reload && mounted) _reloadAfterMutation();
  }

  void _onMenuSelected(String action) {
    switch (action) {
      case 'report':
        _downloadReport();
      case 'closing':
        _showClosingDayPicker();
      case 'recurring':
        _openScreen(const RecurringExpensesScreen(), reload: true);
      case 'categories':
        _openScreen(const CategoryManagementScreen(), reload: true);
      case 'invites':
        _openScreen(const FamilyInvitesScreen());
      case 'update':
        _checkForUpdate();
      case 'signout':
        _signOut();
    }
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
                style:
                    const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 10),
              Expanded(
                child: ListView.builder(
                  itemCount: daysInMonth,
                  itemBuilder: (context, index) {
                    final day = index + 1;
                    return ListTile(
                      title: Text('closing_day.day'
                          .tr(namedArgs: {'day': day.toString()})),
                      selected: _closingDay == day,
                      trailing: _closingDay == day
                          ? const Icon(Icons.check, color: Colors.blue)
                          : null,
                      onTap: () => _saveClosingDay(ctx, day),
                    );
                  },
                ),
              ),
              TextButton(
                onPressed: () => _saveClosingDay(ctx, null),
                child: Text('closing_day.reset'.tr()),
              ),
            ],
          ),
        );
      },
    );
  }

  /// Stores [day] as this month's override; null removes the override.
  Future<void> _saveClosingDay(BuildContext sheetContext, int? day) async {
    try {
      if (day == null) {
        await _backendService.deleteClosingDayOverride(
            _currentDate.month, _currentDate.year);
      } else {
        await _backendService.setClosingDayOverride(
            _currentDate.month, _currentDate.year, day);
      }
      if (!mounted) return;
      setState(() => _closingDay = day);
      if (sheetContext.mounted) Navigator.pop(sheetContext);
      _reloadAfterMutation();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('common.error_with_message'
                .tr(namedArgs: {'error': errorText(e)}))),
      );
    }
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
            SnackBar(
                content: Text('common.error_with_message'
                    .tr(namedArgs: {'error': errorText(e)}))),
          );
        }
      }
    }
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
                onTap: () {
                  Navigator.pop(ctx);
                  _openScreen(const AddExpenseScreen(), reload: true);
                },
              ),
              ListTile(
                leading: const Icon(Icons.attach_money, color: Colors.green),
                title: Text('add_options.income'.tr()),
                onTap: () {
                  Navigator.pop(ctx);
                  _openScreen(const AddEarningScreen(), reload: true);
                },
              ),
              ListTile(
                leading: const Icon(Icons.repeat, color: Colors.blue),
                title: Text('add_options.recurring'.tr()),
                onTap: () {
                  Navigator.pop(ctx);
                  _openScreen(const RecurringExpensesScreen(), reload: true);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  PopupMenuItem<String> _menuItem(String value, IconData icon, String label) {
    return PopupMenuItem<String>(
      value: value,
      child: Row(
        children: [
          Icon(icon, size: 20, color: Colors.black87),
          const SizedBox(width: 12),
          Flexible(child: Text(label)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    context.locale; // subscribe to locale changes so .tr() strings re-evaluate
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: Text('home.app_title'.tr(),
            style: const TextStyle(
                color: Colors.black, fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white,
        elevation: 0,
        actions: [
          const LanguageToggle(),
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.black),
            tooltip: 'home.refresh_tooltip'.tr(),
            onPressed: () => _load(force: true),
          ),
          // Everything that is not a several-times-a-day action lives here;
          // eight icons in a row left no room for the title on a phone.
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, color: Colors.black),
            onSelected: _onMenuSelected,
            itemBuilder: (_) => <PopupMenuEntry<String>>[
              _menuItem('report', Icons.download, 'home.menu_report'.tr()),
              _menuItem(
                'closing',
                Icons.calendar_today,
                _closingDay == null
                    ? 'home.menu_closing_day_default'.tr()
                    : 'home.menu_closing_day'
                        .tr(namedArgs: {'day': '$_closingDay'}),
              ),
              _menuItem('recurring', Icons.repeat, 'home.menu_recurring'.tr()),
              _menuItem('categories', Icons.category_outlined,
                  'home.manage_categories_tooltip'.tr()),
              _menuItem('invites', Icons.group_add_outlined,
                  'home.family_invites_tooltip'.tr()),
              _menuItem('update', Icons.system_update_alt,
                  'home.check_updates_tooltip'.tr()),
              const PopupMenuDivider(),
              _menuItem('signout', Icons.logout, 'home.sign_out_tooltip'.tr()),
            ],
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        // Distinct tag: the Investments tab has its own FAB in the same route.
        heroTag: 'home_fab',
        onPressed: showAddOptions,
        tooltip: 'home.add_tooltip'.tr(),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        child: const Icon(Icons.add),
      ),
      body: RefreshIndicator(
        onRefresh: () => _load(force: true),
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          // Bottom room so the FAB never covers the last expense.
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
          child: Column(
            children: [
              _buildMonthSelector(),
              // Fixed-height slot: the figures below must not jump when the
              // bar appears or goes away.
              SizedBox(
                height: 20,
                child: _isRefreshing && _dashboardData != null
                    ? const Center(
                        child: LinearProgressIndicator(minHeight: 2))
                    : null,
              ),
              if (_isLoading)
                const SizedBox(
                    height: 200,
                    child: Center(child: CircularProgressIndicator()))
              else if (_dashboardData == null)
                _buildError()
              else
                ..._buildDashboard(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMonthSelector() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        IconButton(
            icon: const Icon(Icons.arrow_back_ios),
            onPressed: () => _changeMonth(-1)),
        Text(
          DateFormat('MMMM yyyy').format(_currentDate),
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        IconButton(
            icon: const Icon(Icons.arrow_forward_ios),
            onPressed: () => _changeMonth(1)),
      ],
    );
  }

  Widget _buildError() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 32),
      child: Column(
        children: [
          const Icon(Icons.cloud_off, size: 40, color: Colors.grey),
          const SizedBox(height: 12),
          Text('home.load_failed'.tr(),
              style:
                  const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          if (_errorMessage.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(_errorMessage,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.grey)),
          ],
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: () => _load(force: true),
            child: Text('common.retry'.tr()),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildDashboard() {
    final data = _dashboardData!;
    final filtered = _expensesWhere()
      ..sort((a, b) => DateTime.parse(b['spent_at'])
          .compareTo(DateTime.parse(a['spent_at'])));
    final userBreakdown = _breakdown(_expensesWhere(byUser: false), 'user_name');
    final categoryBreakdown =
        _breakdown(_expensesWhere(byCategory: false), 'category_label');

    return [
      // A refresh that failed while older figures are still on screen.
      if (_errorMessage.isNotEmpty) ...[
        Text(_errorMessage,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.red, fontSize: 12)),
        const SizedBox(height: 12),
      ],
      _buildTotalCard(data, _sum(filtered)),
      if (_hasFilters) ...[
        const SizedBox(height: 12),
        _buildActiveFilters(),
      ],
      const SizedBox(height: 20),
      if (userBreakdown.isNotEmpty) ...[
        _buildBreakdownCard(
          title: 'home.spending_by_person'.tr(),
          breakdown: userBreakdown,
          selected: _selectedUser,
          expanded: _showUserChart,
          onToggle: () => setState(() => _showUserChart = !_showUserChart),
          onSelect: (name) => setState(() => _selectedUser = name),
          labelOf: (name) => name,
          leadingOf: (name, color) => Text(
            name.isEmpty ? '?' : name[0].toUpperCase(),
            style: TextStyle(
                color: color, fontWeight: FontWeight.bold, fontSize: 14),
          ),
        ),
        const SizedBox(height: 20),
      ],
      if (data.userEarnedBreakdown.isNotEmpty) ...[
        _buildIncomeCard(data),
        const SizedBox(height: 20),
      ],
      if (categoryBreakdown.isNotEmpty)
        _buildBreakdownCard(
          title: 'home.expenses_by_category'.tr(),
          breakdown: categoryBreakdown,
          selected: _selectedCategory,
          expanded: _showCategoryChart,
          onToggle: () =>
              setState(() => _showCategoryChart = !_showCategoryChart),
          onSelect: (label) => setState(() => _selectedCategory = label),
          labelOf: _translateCategoryLabel,
          leadingOf: (label, color) => Icon(
              categoryIcon(_categoryKeyByLabel[label]),
              color: color,
              size: 18),
        )
      else
        SizedBox(
            height: 100,
            child: Center(child: Text('home.no_expenses_this_month'.tr()))),
      const SizedBox(height: 20),
      if (data.earnings.isNotEmpty) ...[
        _buildEarningsTile(data),
        const SizedBox(height: 20),
      ],
      if (data.expenses.isNotEmpty) ..._buildExpenseList(filtered),
    ];
  }

  /// Balance, income and expense always describe the whole month, so the card
  /// adds up. With a filter on, its total is an extra line — it used to
  /// replace "Expense" while the balance stayed unfiltered.
  Widget _buildTotalCard(DashboardData data, double filteredTotal) {
    final balance = data.totalEarned - data.totalSpent;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
            blurRadius: 10,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        children: [
          Text('home.balance'.tr(),
              style: const TextStyle(color: Colors.white70)),
          const SizedBox(height: 5),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              _money(balance),
              style: TextStyle(
                  color: balance >= 0 ? Colors.greenAccent : Colors.redAccent,
                  fontSize: 36,
                  fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildTotalColumn(
                  'home.income'.tr(), data.totalEarned, Colors.green),
              Container(height: 30, width: 1, color: Colors.white24),
              _buildTotalColumn(
                  'home.expense'.tr(), data.totalSpent, Colors.red),
            ],
          ),
          if (_hasFilters) ...[
            const SizedBox(height: 16),
            Text(
              'home.filtered_total'
                  .tr(namedArgs: {'amount': _money(filteredTotal)}),
              style: const TextStyle(
                  color: Colors.white, fontWeight: FontWeight.w600),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildTotalColumn(String label, double value, Color color) {
    return Column(
      children: [
        Text(label, style: const TextStyle(color: Colors.white54)),
        const SizedBox(height: 4),
        Text(
          _money(value),
          style: TextStyle(
              color: color, fontSize: 18, fontWeight: FontWeight.bold),
        ),
      ],
    );
  }

  /// Every active filter in one place, each removable on its own.
  Widget _buildActiveFilters() {
    return Align(
      alignment: Alignment.centerLeft,
      child: Wrap(
        spacing: 8,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          if (_selectedCategory != null)
            InputChip(
              avatar: const Icon(Icons.category_outlined, size: 16),
              label: Text('home.category_filter'.tr(namedArgs: {
                'name': _translateCategoryLabel(_selectedCategory!)
              })),
              onDeleted: () => setState(() => _selectedCategory = null),
            ),
          if (_selectedUser != null)
            InputChip(
              avatar: const Icon(Icons.person, size: 16),
              label: Text(
                  'home.filtered_by'.tr(namedArgs: {'name': _selectedUser!})),
              onDeleted: () => setState(() => _selectedUser = null),
            ),
          TextButton(
            onPressed: () => setState(_clearFilters),
            child: Text('home.clear_filters'.tr()),
          ),
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

  /// A ranked list of bars with the amount and share on every row. Replaces
  /// the pie charts: fourteen slices with a percent-only legend made it
  /// impossible to read off what a category actually cost. Tapping a row
  /// filters the dashboard by it; tapping it again clears the filter.
  Widget _buildBreakdownCard({
    required String title,
    required Map<String, double> breakdown,
    required String? selected,
    required bool expanded,
    required VoidCallback onToggle,
    required ValueChanged<String?> onSelect,
    required String Function(String) labelOf,
    required Widget Function(String, Color) leadingOf,
  }) {
    final total = breakdown.values.fold(0.0, (a, b) => a + b);
    final entries = breakdown.entries.where((e) => e.value > 0).toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: onToggle,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(title,
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                Icon(expanded
                    ? Icons.keyboard_arrow_up
                    : Icons.keyboard_arrow_down),
              ],
            ),
          ),
          if (expanded) ...[
            const SizedBox(height: 12),
            for (var i = 0; i < entries.length; i++)
              _buildBreakdownRow(
                name: entries[i].key,
                label: labelOf(entries[i].key),
                value: entries[i].value,
                share: total > 0 ? entries[i].value / total : 0,
                color: _chartColors[i % _chartColors.length],
                isSelected: selected == entries[i].key,
                onSelect: onSelect,
                leadingOf: leadingOf,
              ),
          ],
        ],
      ),
    );
  }

  Widget _buildBreakdownRow({
    required String name,
    required String label,
    required double value,
    required double share,
    required Color color,
    required bool isSelected,
    required ValueChanged<String?> onSelect,
    required Widget Function(String, Color) leadingOf,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () => onSelect(isSelected ? null : name),
      child: Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
        decoration: isSelected
            ? BoxDecoration(
                color: color.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: color.withValues(alpha: 0.5)),
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
              child: Center(child: leadingOf(name, color)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  LinearProgressIndicator(
                    value: share,
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
                Text(_money(value),
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                Text('${(share * 100).toStringAsFixed(1)}%',
                    style: const TextStyle(fontSize: 12, color: Colors.grey)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildIncomeCard(DashboardData data) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
          color: Colors.white, borderRadius: BorderRadius.circular(12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('home.income_by_user'.tr(),
              style: const TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 10),
          ...data.userEarnedBreakdown.entries.map((e) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(e.key),
                  Text(_money(e.value),
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, color: Colors.green)),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildEarningsTile(DashboardData data) {
    return ExpansionTile(
      title: Text('home.recent_earnings'.tr(),
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
      children: data.earnings.map((earning) {
        return ListTile(
          leading: const CircleAvatar(
            backgroundColor: Colors.green,
            child: Icon(Icons.attach_money, color: Colors.white),
          ),
          title: Text(earning.userName ?? 'common.unknown'.tr()),
          subtitle:
              earning.description != null && earning.description!.isNotEmpty
                  ? Text(earning.description!)
                  : null,
          trailing: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                DateFormat('dd/MM').format(earning.earnedAt),
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
              Text(
                _money(earning.amount),
                style: const TextStyle(
                    fontWeight: FontWeight.bold, color: Colors.green),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  /// The month's expenses, newest first, grouped by day with a daily total.
  /// [filtered] is computed once per build by the caller — the list used to
  /// re-filter and re-sort the whole month for every single row.
  List<Widget> _buildExpenseList(List<dynamic> filtered) {
    final byDay = <String, List<dynamic>>{};
    for (final e in filtered) {
      final day = (e['spent_at'] as String).substring(0, 10);
      (byDay[day] ??= []).add(e);
    }

    return [
      Align(
        alignment: Alignment.centerLeft,
        child: Text(
            'home.expenses_title'
                .tr(namedArgs: {'count': filtered.length.toString()}),
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
      ),
      const SizedBox(height: 10),
      TextField(
        controller: _searchController,
        onChanged: (value) => setState(() => _searchQuery = value),
        decoration: InputDecoration(
          hintText: 'home.search_hint'.tr(),
          prefixIcon: const Icon(Icons.search),
          suffixIcon: _searchQuery.isEmpty
              ? null
              : IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => setState(() {
                    _searchQuery = '';
                    _searchController.clear();
                  }),
                ),
          isDense: true,
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
        ),
      ),
      const SizedBox(height: 8),
      if (filtered.isEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 32),
          child: Text('home.no_results'.tr(),
              style: const TextStyle(color: Colors.grey)),
        ),
      for (final entry in byDay.entries) ...[
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 12, 4, 6),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                DateFormat('EEE, d MMM').format(DateTime.parse(entry.key)),
                style: TextStyle(
                    fontWeight: FontWeight.w600, color: Colors.grey[700]),
              ),
              Text(_money(_sum(entry.value)),
                  style: TextStyle(
                      fontWeight: FontWeight.w600, color: Colors.grey[700])),
            ],
          ),
        ),
        for (final exp in entry.value) _buildExpenseTile(exp),
      ],
    ];
  }

  Widget _buildExpenseTile(dynamic exp) {
    final isRecurring = exp['recurring_id'] != null;
    const recurringColor = Color(0xFFE65100);
    final comment = exp['comment'] as String?;

    return Dismissible(
      key: ValueKey(exp['id']),
      direction: DismissDirection.endToStart,
      // Never dismissed by the gesture itself: the row leaves when the reload
      // after a confirmed delete no longer contains it.
      confirmDismiss: (_) async {
        await _deleteExpense(exp);
        return false;
      },
      background: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.only(right: 20),
        alignment: Alignment.centerRight,
        decoration: BoxDecoration(
          color: Colors.red,
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      child: Card(
        elevation: 0,
        margin: const EdgeInsets.only(bottom: 8),
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Container(
          decoration: isRecurring
              ? const BoxDecoration(
                  border: Border(
                    left: BorderSide(color: recurringColor, width: 4),
                  ),
                )
              : null,
          child: ListTile(
            onTap: () async {
              final result = await Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => ExpenseDetailsScreen(expense: exp)),
              );
              // The details screen can also edit in place, so any return may
              // carry a change — not only a delete.
              if (result == true && mounted) _reloadAfterMutation();
            },
            onLongPress: () => _deleteExpense(exp),
            leading: CircleAvatar(
              backgroundColor: Colors.blue[50],
              child: Icon(categoryIcon(exp['category_key'] as String?),
                  color: Colors.blue, size: 20),
            ),
            title: Row(
              children: [
                Flexible(
                    child: Text(_translateCategoryLabel(
                        (exp['category_label'] as String?) ??
                            'common.unknown'.tr()))),
                if (isRecurring) ...[
                  const SizedBox(width: 6),
                  const Icon(Icons.repeat, size: 14, color: recurringColor),
                ],
              ],
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${exp['user_name']} • ${exp['payment_method_name']}'),
                if (comment != null && comment.isNotEmpty)
                  Text('"$comment"',
                      style: const TextStyle(
                          fontStyle: FontStyle.italic, fontSize: 12)),
              ],
            ),
            trailing: Text(
              _money((exp['amount'] as num).toDouble()),
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
            ),
          ),
        ),
      ),
    );
  }
}
