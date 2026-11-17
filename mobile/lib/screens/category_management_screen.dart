import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import '../models/models.dart';
import '../services/backend_service.dart';
import '../utils/error_text.dart';

class CategoryManagementScreen extends StatefulWidget {
  const CategoryManagementScreen({super.key});

  @override
  State<CategoryManagementScreen> createState() =>
      _CategoryManagementScreenState();
}

class _CategoryManagementScreenState extends State<CategoryManagementScreen> {
  final _backendService = BackendService();
  bool _isLoading = false;
  List<Category> _categories = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    try {
      final cats = await _backendService.getCategoriesForManagement();
      if (!mounted) return;
      setState(() => _categories = cats);
      // The expense form reads categories from this cache.
      BackendService.clearFamilyDataCache();
    } catch (e) {
      _showError(e);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showError(Object error) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('common.error_with_message'
            .tr(namedArgs: {'error': errorText(error)}))));
  }

  /// Global categories are translated by key; a family's own keep their name.
  String _label(Category c) {
    if (!c.isGlobal) return c.label;
    final k = 'categories.${c.key}';
    final t = k.tr();
    return t == k ? c.label : t;
  }

  Future<void> _toggleVisibility(Category cat, bool visible) async {
    try {
      await _backendService.setCategoryVisibility(cat.key, hidden: !visible);
      await _load();
    } catch (e) {
      _showError(e);
    }
  }

  Future<void> _deleteCustom(Category cat) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('category_management.delete_title'.tr()),
        content: Text('category_management.delete_body'
            .tr(namedArgs: {'name': cat.label})),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text('common.cancel'.tr())),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text('common.delete'.tr(),
                  style: const TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await _backendService.deleteCustomCategory(cat.key);
      await _load();
    } catch (e) {
      _showError(e);
    }
  }

  Future<void> _addCustom() async {
    final controller = TextEditingController();
    final label = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('category_management.add_title'.tr()),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(
            labelText: 'category_management.name_label'.tr(),
            border: const OutlineInputBorder(),
          ),
          textCapitalization: TextCapitalization.sentences,
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('common.cancel'.tr())),
          TextButton(
              onPressed: () => Navigator.pop(ctx, controller.text.trim()),
              child: Text('common.add'.tr())),
        ],
      ),
    );
    controller.dispose();
    if (label == null || label.isEmpty) return;
    try {
      await _backendService.createCustomCategory(label);
      await _load();
    } catch (e) {
      _showError(e);
    }
  }

  @override
  Widget build(BuildContext context) {
    context.locale; // subscribe to locale changes so .tr() strings re-evaluate
    final globals = _categories.where((c) => c.isGlobal).toList()
      ..sort((a, b) =>
          _label(a).toLowerCase().compareTo(_label(b).toLowerCase()));
    final customs = _categories.where((c) => !c.isGlobal).toList();

    return Scaffold(
      appBar: AppBar(
        title: Text('category_management.title'.tr()),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _addCustom,
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        child: const Icon(Icons.add),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              children: [
                _SectionHeader(
                  title: 'category_management.default_title'.tr(),
                  subtitle: 'category_management.default_subtitle'.tr(),
                ),
                ...globals.map((cat) => SwitchListTile(
                      title: Text(_label(cat)),
                      secondary: Icon(
                        cat.isHidden
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined,
                        color: cat.isHidden ? Colors.grey : Colors.black,
                      ),
                      value: !cat.isHidden,
                      onChanged: (val) => _toggleVisibility(cat, val),
                    )),
                if (customs.isNotEmpty) ...[
                  _SectionHeader(
                    title: 'category_management.custom_title'.tr(),
                    subtitle: 'category_management.custom_subtitle'.tr(),
                  ),
                  ...customs.map((cat) => ListTile(
                        leading: const Icon(Icons.label_outline),
                        title: Text(cat.label),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete_outline,
                              color: Colors.red),
                          onPressed: () => _deleteCustom(cat),
                        ),
                      )),
                ],
                const SizedBox(height: 80),
              ],
            ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final String subtitle;

  const _SectionHeader({required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: const TextStyle(
                  fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 2),
          Text(subtitle,
              style: const TextStyle(fontSize: 12, color: Colors.grey)),
          const Divider(height: 16),
        ],
      ),
    );
  }
}
