import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/backend_service.dart';
import '../utils/error_text.dart';

class FamilyInvitesScreen extends StatefulWidget {
  const FamilyInvitesScreen({super.key});

  @override
  State<FamilyInvitesScreen> createState() => _FamilyInvitesScreenState();
}

class _FamilyInvitesScreenState extends State<FamilyInvitesScreen> {
  final _backendService = BackendService();
  bool _loading = true;
  bool _creating = false;
  List<Map<String, dynamic>> _invites = [];
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _errorMessage = null;
    });
    try {
      final invites = await _backendService.listInvites();
      if (!mounted) return;
      setState(() {
        _invites = invites;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = errorText(e);
        _loading = false;
      });
    }
  }

  Future<void> _generate() async {
    setState(() => _creating = true);
    try {
      final invite = await _backendService.createInvite();
      if (!mounted) return;
      await _showCodeDialog(invite['code'] as String);
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(errorText(e)), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  Future<void> _showCodeDialog(String code) async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('family_invites.generated_title'.tr()),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('family_invites.generated_body'.tr()),
            const SizedBox(height: 16),
            SelectableText(
              code,
              style: const TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                letterSpacing: 4,
                fontFamily: 'monospace',
              ),
            ),
          ],
        ),
        actions: [
          TextButton.icon(
            icon: const Icon(Icons.copy),
            label: Text('family_invites.copy'.tr()),
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: code));
              if (ctx.mounted) {
                ScaffoldMessenger.of(ctx).showSnackBar(
                  SnackBar(content: Text('family_invites.copied'.tr())),
                );
              }
            },
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text('family_invites.done'.tr()),
          ),
        ],
      ),
    );
  }

  Future<void> _revoke(String code) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('family_invites.revoke_title'.tr()),
        content:
            Text('family_invites.revoke_body'.tr(namedArgs: {'code': code})),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text('common.cancel'.tr()),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: Text('family_invites.revoke'.tr()),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await _backendService.revokeInvite(code);
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(errorText(e)), backgroundColor: Colors.red),
      );
    }
  }

  String _formatExpiry(String iso) {
    final dt = DateTime.tryParse(iso)?.toLocal();
    if (dt == null) return iso;
    return DateFormat('MMM d, y · HH:mm').format(dt);
  }

  @override
  Widget build(BuildContext context) {
    context.locale; // subscribe to locale changes so .tr() strings re-evaluate
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: Text('family_invites.title'.tr()),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _creating ? null : _generate,
        icon: _creating
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: Colors.white))
            : const Icon(Icons.add),
        label: Text('family_invites.generate'.tr()),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_errorMessage!,
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: Colors.red)),
                        const SizedBox(height: 16),
                        ElevatedButton(
                            onPressed: _load,
                            child: Text('common.retry'.tr())),
                      ],
                    ),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: _invites.isEmpty
                      ? ListView(
                          padding: const EdgeInsets.all(24),
                          children: [
                            const SizedBox(height: 80),
                            const Icon(Icons.mail_outline,
                                size: 64, color: Colors.grey),
                            const SizedBox(height: 16),
                            Text(
                              'family_invites.empty'.tr(),
                              textAlign: TextAlign.center,
                              style: const TextStyle(color: Colors.grey),
                            ),
                          ],
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
                          itemCount: _invites.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 8),
                          itemBuilder: (ctx, i) {
                            final inv = _invites[i];
                            final code = inv['code'] as String;
                            return Card(
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                                side: BorderSide(color: Colors.grey[300]!),
                              ),
                              child: ListTile(
                                title: Text(
                                  code,
                                  style: const TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 3,
                                    fontFamily: 'monospace',
                                  ),
                                ),
                                subtitle: Text('family_invites.expires'.tr(
                                    namedArgs: {
                                      'date': _formatExpiry(
                                          inv['expires_at'] as String)
                                    })),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      icon: const Icon(Icons.copy),
                                      tooltip: 'family_invites.copy'.tr(),
                                      onPressed: () async {
                                        final messenger =
                                            ScaffoldMessenger.of(context);
                                        await Clipboard.setData(
                                            ClipboardData(text: code));
                                        messenger.showSnackBar(SnackBar(
                                            content: Text(
                                                'family_invites.copied'
                                                    .tr())));
                                      },
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.delete_outline,
                                          color: Colors.red),
                                      tooltip: 'family_invites.revoke'.tr(),
                                      onPressed: () => _revoke(code),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                ),
    );
  }
}
