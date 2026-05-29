import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../models/app_user.dart';

final _meProvider = StreamProvider.autoDispose<AppUser?>((ref) {
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null) return Stream.value(null);
  return ref.watch(firestoreServiceProvider).watchUser(uid);
});

final _friendProvider =
    StreamProvider.autoDispose.family<AppUser?, String>((ref, friendId) {
  return ref.watch(firestoreServiceProvider).watchUser(friendId);
});

class FriendsScreen extends ConsumerStatefulWidget {
  const FriendsScreen({super.key});

  @override
  ConsumerState<FriendsScreen> createState() => _FriendsScreenState();
}

class _FriendsScreenState extends ConsumerState<FriendsScreen> {
  final _codeController = TextEditingController();
  bool _submitting = false;

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _addFriend() async {
    final code = _codeController.text.trim();
    if (code.isEmpty || _submitting) return;

    setState(() => _submitting = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final result =
          await ref.read(functionsServiceProvider).addFriendByCode(code);
      _codeController.clear();
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            result.alreadyFriends
                ? 'Already friends with ${result.displayName}'
                : 'Added ${result.displayName}!',
          ),
        ),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final me = ref.watch(_meProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Friends')),
      body: me.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (user) {
          if (user == null) return const Center(child: Text('No profile yet.'));
          return ListView(
            padding: const EdgeInsets.all(24),
            children: [
              _InviteCodeCard(code: user.inviteCode),
              const SizedBox(height: 24),
              Text('Add a friend',
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: TextField(
                      controller: _codeController,
                      enabled: !_submitting,
                      textCapitalization: TextCapitalization.characters,
                      decoration: const InputDecoration(
                        labelText: 'Friend code',
                        border: OutlineInputBorder(),
                      ),
                      onSubmitted: (_) => _addFriend(),
                    ),
                  ),
                  const SizedBox(width: 12),
                  FilledButton(
                    onPressed: _submitting ? null : _addFriend,
                    child: _submitting
                        ? const SizedBox(
                            height: 18,
                            width: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Add friend'),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              Text('Your friends',
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              if (user.friendIds.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Center(
                    child: Text('No friends yet — share your code above!'),
                  ),
                )
              else
                for (final friendId in user.friendIds)
                  _FriendTile(friendId: friendId),
            ],
          );
        },
      ),
    );
  }
}

class _InviteCodeCard extends StatelessWidget {
  const _InviteCodeCard({required this.code});
  final String code;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      color: scheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Your code',
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                          color: scheme.onPrimaryContainer,
                        ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    code.isEmpty ? '—' : code,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          color: scheme.onPrimaryContainer,
                          letterSpacing: 2,
                        ),
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: 'Copy code',
              icon: Icon(Icons.copy, color: scheme.onPrimaryContainer),
              onPressed: code.isEmpty
                  ? null
                  : () {
                      Clipboard.setData(ClipboardData(text: code));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Code copied')),
                      );
                    },
            ),
          ],
        ),
      ),
    );
  }
}

class _FriendTile extends ConsumerWidget {
  const _FriendTile({required this.friendId});
  final String friendId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final friend = ref.watch(_friendProvider(friendId));
    return friend.when(
      loading: () => ListTile(
        leading: const CircleAvatar(child: Icon(Icons.person)),
        title: Text(friendId),
      ),
      error: (_, __) => ListTile(
        leading: const CircleAvatar(child: Icon(Icons.person)),
        title: Text(friendId),
      ),
      data: (user) => ListTile(
        leading: const CircleAvatar(child: Icon(Icons.person)),
        title: Text(user?.displayName ?? friendId),
        subtitle:
            user != null ? Text('${user.streakCount} day streak') : null,
      ),
    );
  }
}
