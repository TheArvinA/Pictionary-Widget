import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../models/app_user.dart';
import '../../widgets/error_state.dart';

final _meProvider = StreamProvider.autoDispose<AppUser?>((ref) {
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null) return Stream.value(null);
  return ref.watch(firestoreServiceProvider).watchUser(uid);
});

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = ref.watch(_meProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: me.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => ErrorState(
          message: 'Something went wrong',
          onRetry: () => ref.invalidate(_meProvider),
        ),
        data: (user) {
          if (user == null) return const Center(child: Text('No profile yet.'));
          return Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(user.displayName,
                    style: Theme.of(context).textTheme.headlineSmall),
                const SizedBox(height: 8),
                Text('Invite code: ${user.inviteCode}'),
                const SizedBox(height: 8),
                Text('Streak: ${user.streakCount} days'),
                const Spacer(),
                FilledButton.tonal(
                  onPressed: () =>
                      ref.read(authServiceProvider).signOut(),
                  child: const Text('Sign out'),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
