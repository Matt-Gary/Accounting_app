import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import '../models/models.dart';
import '../services/backend_service.dart';
import '../widgets/language_toggle.dart';

class AddEarningScreen extends StatefulWidget {
  const AddEarningScreen({super.key});

  @override
  _AddEarningScreenState createState() => _AddEarningScreenState();
}

class _AddEarningScreenState extends State<AddEarningScreen> {
  final _formKey = GlobalKey<FormState>();
  final _backendService = BackendService();

  final TextEditingController _amountController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();
  DateTime _earnedAt = DateTime.now();
  bool _isLoading = false;

  List<UserProfile> _users = [];
  UserProfile? _selectedUser;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      final familyData =
          await _backendService.getFamilyData(forceRefresh: true);
      if (mounted) {
        setState(() {
          _users = familyData.profiles.where((u) => !u.isVirtual).toList();
          if (_users.isNotEmpty) _selectedUser = _users.first;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('add_earning.load_users_failed'
                  .tr(namedArgs: {'error': e.toString()}))),
        );
      }
    }
  }

  @override
  void dispose() {
    _amountController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _submitData() async {
    if (_formKey.currentState!.validate()) {
      if (_selectedUser == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('add_earning.select_user'.tr())),
        );
        return;
      }

      setState(() {
        _isLoading = true;
      });

      final enteredAmount =
          double.parse(_amountController.text.replaceAll(',', '.'));
      final enteredDescription = _descriptionController.text;

      final newEarning = Earning(
        userId: _selectedUser!.id,
        amount: enteredAmount,
        description: enteredDescription,
        earnedAt: _earnedAt,
      );

      try {
        await _backendService.addEarning(newEarning);
        if (mounted) {
          Navigator.of(context).pop(true);
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content: Text('add_earning.add_failed'
                    .tr(namedArgs: {'error': e.toString()}))),
          );
        }
      } finally {
        if (mounted) {
          setState(() {
            _isLoading = false;
          });
        }
      }
    }
  }

  void _presentDatePicker() {
    showDatePicker(
      context: context,
      initialDate: _earnedAt,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    ).then((pickedDate) {
      if (pickedDate == null) {
        return;
      }
      setState(() {
        _earnedAt = pickedDate;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    context.locale; // subscribe to locale changes so .tr() strings re-evaluate
    return Scaffold(
      appBar: AppBar(
        title: Text('add_earning.title'.tr(),
            style: const TextStyle(color: Colors.black)),
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.black),
        actions: const [LanguageToggle()],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      if (_users.isEmpty)
                        Padding(
                          padding: const EdgeInsets.all(8.0),
                          child: Text('add_earning.loading_users'.tr()),
                        )
                      else
                        Padding(
                          padding: const EdgeInsets.only(bottom: 16),
                          child: DropdownButtonFormField<UserProfile>(
                            initialValue: _selectedUser,
                            decoration: InputDecoration(
                              labelText: 'add_earning.user'.tr(),
                              border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8)),
                            ),
                            items: _users.map((u) {
                              return DropdownMenuItem(
                                value: u,
                                child: Text(u.name),
                              );
                            }).toList(),
                            onChanged: (val) =>
                                setState(() => _selectedUser = val),
                          ),
                        ),
                      TextFormField(
                        decoration: InputDecoration(
                          labelText: 'add_earning.amount'.tr(),
                          prefixText: 'R\$ ',
                          border: const OutlineInputBorder(),
                        ),
                        controller: _amountController,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'add_earning.amount_required'.tr();
                          }
                          if (double.tryParse(value.replaceAll(',', '.')) ==
                              null) {
                            return 'add_earning.amount_invalid'.tr();
                          }
                          if (double.parse(value.replaceAll(',', '.')) <= 0) {
                            return 'add_earning.amount_positive'.tr();
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        decoration: InputDecoration(
                          labelText: 'add_earning.description_optional'.tr(),
                          border: const OutlineInputBorder(),
                        ),
                        controller: _descriptionController,
                      ),
                      const SizedBox(height: 20),
                      Row(
                        children: <Widget>[
                          Expanded(
                            child: Text(
                              'add_earning.date_label'.tr(namedArgs: {
                                'date': DateFormat.yMd().format(_earnedAt)
                              }),
                              style: const TextStyle(fontSize: 16),
                            ),
                          ),
                          TextButton(
                            onPressed: _presentDatePicker,
                            child: Text(
                              'add_earning.choose_date'.tr(),
                              style: const TextStyle(fontWeight: FontWeight.bold),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 30),
                      ElevatedButton(
                        onPressed: _submitData,
                        style: ElevatedButton.styleFrom(
                          backgroundColor:
                              Colors.green, // Differentiate from Expense
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                        child: Text('add_options.income'.tr(),
                            style: const TextStyle(
                                fontSize: 18, color: Colors.white)),
                      ),
                    ],
                  ),
                ),
              ),
            ),
    );
  }
}
