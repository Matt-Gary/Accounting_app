import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/backend_service.dart';

class SuperAdminScreen extends StatefulWidget {
  const SuperAdminScreen({super.key});

  @override
  State<SuperAdminScreen> createState() => _SuperAdminScreenState();
}

class _SuperAdminScreenState extends State<SuperAdminScreen> {
  final _backendService = BackendService();
  bool _loading = true;
  String? _errorMessage;
  List<Map<String, dynamic>> _families = [];
  String? _myFamilyId;
  String? _myProfileId;

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
      final me = await _backendService.getMe();
      final families = await _backendService.adminListFamilies();
      if (!mounted) return;
      setState(() {
        _myFamilyId = me['family_id'] as String?;
        _myProfileId = me['profile_id'] as String?;
        _families = families;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _confirmDeleteFamily(Map<String, dynamic> fam) async {
    final name = fam['name'] as String? ?? 'this family';
    final memberCount = (fam['members'] as List?)?.length ?? 0;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete "$name"?'),
        content: Text(
          'This permanently removes $memberCount user(s) and ALL their '
          'expenses, earnings, investments, recurring expenses, '
          'categories, and payment methods. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await _backendService.adminDeleteFamily(fam['id'] as String);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Deleted "$name"')),
      );
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString()), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _confirmDeleteUser(Map<String, dynamic> member) async {
    final name =
        (member['name'] ?? member['display_name'] ?? member['email']) as String? ??
            'this user';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete "$name"?'),
        content: const Text(
          'This permanently removes the user and all their expenses, '
          'earnings, and investments. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await _backendService.adminDeleteUser(member['profile_id'] as String);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Deleted "$name"')),
      );
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString()), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _editUser(Map<String, dynamic> member) async {
    final nameCtrl =
        TextEditingController(text: (member['name'] ?? '') as String? ?? '');
    final emailCtrl =
        TextEditingController(text: (member['email'] ?? '') as String? ?? '');

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Edit user'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl,
              decoration: const InputDecoration(labelText: 'Display name'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: emailCtrl,
              decoration: const InputDecoration(labelText: 'Email'),
              keyboardType: TextInputType.emailAddress,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (saved != true) return;

    final newName = nameCtrl.text.trim();
    final newEmail = emailCtrl.text.trim();
    final originalName = (member['name'] ?? '') as String? ?? '';
    final originalEmail = (member['email'] ?? '') as String? ?? '';
    final nameChanged = newName.isNotEmpty && newName != originalName;
    final emailChanged = newEmail.isNotEmpty && newEmail != originalEmail;
    if (!nameChanged && !emailChanged) return;

    try {
      await _backendService.adminUpdateUser(
        member['profile_id'] as String,
        name: nameChanged ? newName : null,
        email: emailChanged ? newEmail : null,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('User updated')),
      );
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString()), backgroundColor: Colors.red),
      );
    }
  }

  Widget _buildFamilyCard(Map<String, dynamic> fam) {
    final members = (fam['members'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final isMyFamily = fam['id'] == _myFamilyId;

    return Card(
      elevation: 0,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: Colors.grey[300]!),
      ),
      child: ExpansionTile(
        title: Row(
          children: [
            Expanded(
              child: Text(
                fam['name'] as String? ?? '(unnamed)',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
            if (isMyFamily)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.blue[50],
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Text('You',
                    style: TextStyle(fontSize: 11, color: Colors.blue)),
              ),
          ],
        ),
        subtitle: Text('${members.length} member(s)'),
        trailing: isMyFamily
            ? const SizedBox(width: 48)
            : IconButton(
                icon: const Icon(Icons.delete, color: Colors.red),
                tooltip: 'Delete family',
                onPressed: () => _confirmDeleteFamily(fam),
              ),
        children: members.map((m) => _buildMemberTile(m)).toList(),
      ),
    );
  }

  Widget _buildMemberTile(Map<String, dynamic> member) {
    final isSelf = member['profile_id'] == _myProfileId;
    final isAdmin = member['is_super_admin'] == true;
    final role = member['role'] as String?;

    return Container(
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: Colors.grey[200]!)),
      ),
      child: ListTile(
        title: Row(
          children: [
            Expanded(
                child: Text(member['name'] as String? ??
                    member['display_name'] as String? ??
                    '(no name)')),
            if (role != null)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: role == 'owner' ? Colors.amber[50] : Colors.grey[100],
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(role,
                    style: TextStyle(
                        fontSize: 11,
                        color: role == 'owner'
                            ? Colors.amber[900]
                            : Colors.grey[700])),
              ),
          ],
        ),
        subtitle: Text(member['email'] as String? ?? ''),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.edit, size: 20),
              tooltip: 'Edit',
              onPressed: () => _editUser(member),
            ),
            if (!isSelf && !isAdmin)
              IconButton(
                icon: const Icon(Icons.delete_outline,
                    size: 20, color: Colors.red),
                tooltip: 'Delete user',
                onPressed: () => _confirmDeleteUser(member),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _signOut() async {
    await Supabase.instance.client.auth.signOut();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: const Text('Super Admin'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: _load,
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Sign out',
            onPressed: _signOut,
          ),
        ],
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
                            onPressed: _load, child: const Text('Retry')),
                      ],
                    ),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: _families.isEmpty
                      ? ListView(
                          padding: const EdgeInsets.all(24),
                          children: const [
                            SizedBox(height: 80),
                            Icon(Icons.group_off,
                                size: 64, color: Colors.grey),
                            SizedBox(height: 16),
                            Text(
                              'No families found.',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: Colors.grey),
                            ),
                          ],
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          itemCount: _families.length,
                          itemBuilder: (ctx, i) =>
                              _buildFamilyCard(_families[i]),
                        ),
                ),
    );
  }
}
