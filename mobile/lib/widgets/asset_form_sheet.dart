import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import '../models/models.dart';

/// Create or edit an asset.
///
/// Pops an [InvestmentAsset] carrying the form's values — the caller decides
/// whether that becomes a create or an update, so this widget stays free of
/// network concerns.
class AssetFormSheet extends StatefulWidget {
  /// When set, the sheet edits this asset instead of creating one.
  final InvestmentAsset? existing;

  /// How many transactions the asset already has. Editing the currency or the
  /// category of a live position changes how its history is valued, so the
  /// sheet warns when this is non-zero.
  final int transactionCount;

  const AssetFormSheet({
    super.key,
    this.existing,
    this.transactionCount = 0,
  });

  @override
  State<AssetFormSheet> createState() => _AssetFormSheetState();
}

class _AssetFormSheetState extends State<AssetFormSheet> {
  final _formKey = GlobalKey<FormState>();

  late String _category;
  late String _currency;
  late final TextEditingController _nameCtrl;
  late final TextEditingController _symbolCtrl;
  late final TextEditingController _accountCtrl;
  late final TextEditingController _sectorCtrl;
  late final TextEditingController _countryCtrl;
  late final TextEditingController _notesCtrl;

  // Mirrors CATEGORY_ORDER in service/portfolio/categories.py.
  static const _categoryKeys = [
    'stock', 'etf', 'crypto', 'bond',
    'cash_equivalent', 'cash_broker', 'cash_home', 'cash_bank',
  ];
  static const _currencies = ['BRL', 'USD', 'EUR', 'PLN'];

  bool get _isEditing => widget.existing != null;
  bool get _showSymbol =>
      InvestmentAsset.pricedCategories.contains(_category);

  /// Sector and country only mean something for a traded instrument.
  bool get _showClassification =>
      _category == 'stock' || _category == 'etf';

  /// True when a change would reinterpret existing history.
  bool get _riskyEdit =>
      _isEditing &&
      widget.transactionCount > 0 &&
      (_category != widget.existing!.category ||
          _currency != widget.existing!.currency);

  @override
  void initState() {
    super.initState();
    final a = widget.existing;
    _category = a?.category ?? 'stock';
    _currency = a?.currency ?? 'BRL';
    _nameCtrl = TextEditingController(text: a?.name ?? '');
    _symbolCtrl = TextEditingController(text: a?.symbol ?? '');
    _accountCtrl = TextEditingController(text: a?.account ?? '');
    _sectorCtrl = TextEditingController(text: a?.sector ?? '');
    _countryCtrl = TextEditingController(text: a?.country ?? '');
    _notesCtrl = TextEditingController(text: a?.notes ?? '');
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _symbolCtrl.dispose();
    _accountCtrl.dispose();
    _sectorCtrl.dispose();
    _countryCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  String? _trimmedOrNull(TextEditingController c) =>
      c.text.trim().isEmpty ? null : c.text.trim();

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    final result = InvestmentAsset(
      id: widget.existing?.id,
      familyId: widget.existing?.familyId ?? '',
      category: _category,
      name: _nameCtrl.text.trim(),
      symbol: _showSymbol ? _trimmedOrNull(_symbolCtrl)?.toUpperCase() : null,
      currency: _currency,
      account: _trimmedOrNull(_accountCtrl),
      sector: _showClassification ? _trimmedOrNull(_sectorCtrl) : null,
      country: _showClassification ? _trimmedOrNull(_countryCtrl) : null,
      notes: _trimmedOrNull(_notesCtrl),
    );
    Navigator.pop(context, result);
  }

  @override
  Widget build(BuildContext context) {
    context.locale; // subscribe to locale changes so .tr() strings re-evaluate
    final scheme = Theme.of(context).colorScheme;

    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                (_isEditing
                        ? 'investments.asset_form.title_edit'
                        : 'investments.asset_form.title')
                    .tr(),
                style: const TextStyle(
                    fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),

              DropdownButtonFormField<String>(
                value: _category,
                decoration: InputDecoration(
                  labelText: 'investments.asset_form.category'.tr(),
                  border: const OutlineInputBorder(),
                  helperText: _category == 'cash_equivalent'
                      ? 'investments.category_hints.cash_equivalent'.tr()
                      : null,
                  helperMaxLines: 3,
                ),
                items: _categoryKeys
                    .map((k) => DropdownMenuItem(
                        value: k,
                        child: Text('investments.categories.$k'.tr())))
                    .toList(),
                onChanged: (v) => setState(() => _category = v!),
              ),
              const SizedBox(height: 12),

              TextFormField(
                controller: _nameCtrl,
                decoration: InputDecoration(
                    labelText: 'investments.asset_form.name'.tr(),
                    border: const OutlineInputBorder()),
                validator: (v) => v == null || v.trim().isEmpty
                    ? 'investments.asset_form.name_required'.tr()
                    : null,
              ),

              if (_showSymbol) ...[
                const SizedBox(height: 12),
                TextFormField(
                  controller: _symbolCtrl,
                  decoration: InputDecoration(
                    labelText: 'investments.asset_form.ticker'.tr(),
                    border: const OutlineInputBorder(),
                    helperText:
                        'investments.asset_form.ticker_helper'.tr(),
                    helperMaxLines: 2,
                  ),
                  textCapitalization: TextCapitalization.characters,
                ),
              ],

              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: _currency,
                decoration: InputDecoration(
                    labelText: 'investments.asset_form.currency'.tr(),
                    border: const OutlineInputBorder()),
                items: _currencies
                    .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                    .toList(),
                onChanged: (v) => setState(() => _currency = v!),
              ),

              const SizedBox(height: 12),
              TextFormField(
                controller: _accountCtrl,
                decoration: InputDecoration(
                    labelText: 'investments.asset_form.account'.tr(),
                    border: const OutlineInputBorder()),
              ),

              if (_showClassification) ...[
                const SizedBox(height: 12),
                TextFormField(
                  controller: _sectorCtrl,
                  decoration: InputDecoration(
                      labelText: 'investments.asset_form.sector'.tr(),
                      border: const OutlineInputBorder()),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _countryCtrl,
                  decoration: InputDecoration(
                      labelText: 'investments.asset_form.country'.tr(),
                      border: const OutlineInputBorder()),
                ),
              ],

              const SizedBox(height: 12),
              TextFormField(
                controller: _notesCtrl,
                decoration: InputDecoration(
                    labelText: 'investments.asset_form.notes'.tr(),
                    border: const OutlineInputBorder()),
                maxLines: 2,
              ),

              // Changing the currency or category of an asset that already has
              // history changes how that history is valued. Legitimate when
              // fixing a mistake, so it is allowed — but never silently.
              if (_riskyEdit) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: scheme.errorContainer.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.warning_amber_rounded,
                          size: 18, color: scheme.error),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'investments.asset_form.risky_edit'.tr(namedArgs: {
                            'count': '${widget.transactionCount}'
                          }),
                          style:
                              TextStyle(fontSize: 12, color: scheme.error),
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _submit,
                  child: Text((_isEditing
                          ? 'investments.asset_form.save'
                          : 'investments.asset_form.submit')
                      .tr()),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
