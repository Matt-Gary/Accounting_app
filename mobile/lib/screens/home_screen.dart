import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import '../services/backend_service.dart';
import 'add_expense_screen.dart';
import 'add_earning_screen.dart';
import 'expense_details_screen.dart';

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

  @override
  void initState() {
    super.initState();
    _loadDashboard();
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
    });
    _loadDashboard();
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
            icon: const Icon(Icons.refresh, color: Colors.black),
            onPressed: _loadDashboard,
          ),
          IconButton(
            icon: const Icon(Icons.download, color: Colors.black),
            onPressed: () {
              // Trigger download
              _backendService.downloadReport(
                  _currentDate.month, _currentDate.year);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Report download started...')),
              );
            },
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
              // Total Spent Card
              _buildTotalCard(),

              const SizedBox(height: 20),

              // User Breakdown
              if (_dashboardData!.userSpendBreakdown.isNotEmpty)
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12)),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Spending by User',
                          style: TextStyle(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 10),
                      ..._dashboardData!.userSpendBreakdown.entries.map((e) {
                        // Simple progress bar-like visualization or just text
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(e.key),
                              Text('R\$ ${e.value.toStringAsFixed(2)}',
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold)),
                            ],
                          ),
                        );
                      }),
                    ],
                  ),
                ),

              const SizedBox(height: 20),

              // Category Chart
              if (_dashboardData!.categoryBreakdown.isNotEmpty)
                SizedBox(
                  height: 250,
                  child: PieChart(
                    PieChartData(
                      sections: _getChartSections(),
                      centerSpaceRadius: 40,
                      sectionsSpace: 2,
                    ),
                  ),
                )
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
                itemCount: _dashboardData!.expenses.length,
                itemBuilder: (context, index) {
                  final exp = _dashboardData!.expenses[index];
                  return Card(
                    elevation: 0,
                    margin: const EdgeInsets.only(bottom: 8),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                    child: ListTile(
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) =>
                                  ExpenseDetailsScreen(expense: exp)),
                        );
                      },
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
                      trailing: Text(
                        'R\$ ${(exp['amount'] as num).toDouble().toStringAsFixed(2)}',
                        style: const TextStyle(fontWeight: FontWeight.bold),
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
                    'R\$ ${_dashboardData!.totalSpent.toStringAsFixed(2)}',
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

  List<PieChartSectionData> _getChartSections() {
    final List<Color> colors = [
      Colors.blue,
      Colors.red,
      Colors.green,
      Colors.orange,
      Colors.purple,
      Colors.teal
    ];
    int i = 0;

    return _dashboardData!.categoryBreakdown.entries.map((entry) {
      final color = colors[i % colors.length];
      i++;
      return PieChartSectionData(
        color: color,
        value: entry.value,
        title: '',
        radius: 50,
        badgeWidget: Text(entry.key, style: const TextStyle(fontSize: 10)),
        badgePositionPercentageOffset: 1.3,
      );
    }).toList();
  }
}
