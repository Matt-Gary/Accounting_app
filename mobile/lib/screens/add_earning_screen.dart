import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/models.dart';
import '../repositories/accounting_repository.dart';

class AddEarningScreen extends StatefulWidget {
  const AddEarningScreen({Key? key}) : super(key: key);

  @override
  _AddEarningScreenState createState() => _AddEarningScreenState();
}

class _AddEarningScreenState extends State<AddEarningScreen> {
  final _formKey = GlobalKey<FormState>();
  final _repository = AccountingRepository();

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
      final users = await _repository.getProfiles();
      if (mounted) {
        setState(() {
          _users = users;
          if (_users.isNotEmpty) _selectedUser = _users.first;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading users: $e')),
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
          const SnackBar(content: Text('Please select a user')),
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
        await _repository.addEarning(newEarning);
        if (mounted) {
          Navigator.of(context).pop(true);
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to add earning: $e')),
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
    return Scaffold(
      appBar: AppBar(
        title: const Text('Add Income', style: TextStyle(color: Colors.black)),
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.black),
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
                        const Padding(
                          padding: EdgeInsets.all(8.0),
                          child: Text("Loading users..."),
                        )
                      else
                        Padding(
                          padding: const EdgeInsets.only(bottom: 16),
                          child: DropdownButtonFormField<UserProfile>(
                            value: _selectedUser,
                            decoration: InputDecoration(
                              labelText: 'User',
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
                        decoration: const InputDecoration(
                          labelText: 'Amount',
                          prefixText: 'R\$ ',
                          border: OutlineInputBorder(),
                        ),
                        controller: _amountController,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Please enter an amount';
                          }
                          if (double.tryParse(value.replaceAll(',', '.')) ==
                              null) {
                            return 'Please enter a valid number';
                          }
                          if (double.parse(value.replaceAll(',', '.')) <= 0) {
                            return 'Please enter a number greater than zero';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        decoration: const InputDecoration(
                          labelText: 'Description (Optional)',
                          border: OutlineInputBorder(),
                        ),
                        controller: _descriptionController,
                      ),
                      const SizedBox(height: 20),
                      Row(
                        children: <Widget>[
                          Expanded(
                            child: Text(
                              'Date: ${DateFormat.yMd().format(_earnedAt)}',
                              style: const TextStyle(fontSize: 16),
                            ),
                          ),
                          TextButton(
                            onPressed: _presentDatePicker,
                            child: const Text(
                              'Choose Date',
                              style: TextStyle(fontWeight: FontWeight.bold),
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
                        child: const Text('Add Income',
                            style:
                                TextStyle(fontSize: 18, color: Colors.white)),
                      ),
                    ],
                  ),
                ),
              ),
            ),
    );
  }
}
