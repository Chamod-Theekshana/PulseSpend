import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:pulsespend/models/group_model.dart';
import 'package:pulsespend/providers/groups_provider.dart';
import 'package:pulsespend/providers/auth_provider.dart';
import 'package:pulsespend/providers/currency_provider.dart';
import 'package:pulsespend/providers/repository_providers.dart';
import 'package:pulsespend/repositories/group_repository.dart';
import 'package:pulsespend/features/groups/screens/group_detail_screen.dart';
import 'package:pulsespend/features/groups/screens/groups_screen.dart';

const testGroup = GroupModel(
  id: 1,
  name: 'Home',
  ownerId: '1',
  inviteCode: 'ABC123XY',
  memberCount: 2,
  role: 'owner',
);

final testFeed = GroupFeed(
  summary: const GroupSummary(income: 1000, expense: 400, balance: 600, currency: 'USD', transactionCount: 3),
  transactions: [
    GroupTransaction(id: 1, memberName: 'Alice', title: 'Lunch', amount: -20, currency: 'USD', category: 'Food', createdAt: DateTime(2026, 7, 10)),
  ],
);

/// A feed with a shared INCOME row (positive amount) — the receiver owes the
/// others, so the row should read "received by / you're owed".
final incomeFeed = GroupFeed(
  summary: const GroupSummary(income: 900, expense: 0, balance: 900, currency: 'USD', transactionCount: 1),
  transactions: [
    GroupTransaction(id: 2, memberName: 'Alice', title: 'Refund', amount: 900, currency: 'USD', category: 'Income', createdAt: DateTime(2026, 7, 11), viewerOwed: 300),
  ],
);

final testMembers = [
  const GroupMember(userId: '1', name: 'Alice', email: 'a@b.com', role: 'owner'),
  const GroupMember(userId: '2', name: null, email: 'bob@b.com', role: 'member'),
];

/// In-memory stand-in so the real GroupsController runs without a network.
class _FakeGroupRepo extends GroupRepository {
  @override
  Future<List<GroupModel>> list() async => [testGroup];
  @override
  Future<GroupModel> create(String name) async => testGroup;
  @override
  Future<GroupModel> join(String inviteCode) async => testGroup;
  @override
  Future<List<GroupMember>> members(int groupId) async => testMembers;
  @override
  Future<GroupFeed> feed(int groupId) async => testFeed;
  @override
  Future<void> leave(int groupId) async {}
}

void main() {
  testWidgets('GroupDetailScreen — data state builds without error', (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        moneyFormatterProvider.overrideWithValue(const MoneyFormatter('USD', {'USD': 1.0})),
        currentUserIdProvider.overrideWithValue('1'),
        groupFeedProvider(1).overrideWith((ref) async => testFeed),
        groupMembersProvider(1).overrideWith((ref) async => testMembers),
        groupBalancesProvider(1).overrideWith((ref) async =>
            const GroupBalances(members: [], suggestions: [], total: 0, currency: 'USD')),
        groupSettlementsProvider(1).overrideWith((ref) async => const []),
        groupGoalsProvider(1).overrideWith((ref) async => const []),
      ],
      child: const MaterialApp(home: GroupDetailScreen(group: testGroup)),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(tester.takeException(), isNull);
  });

  testWidgets('GroupDetailScreen — shared income row reads "received by / you\'re owed"', (tester) async {
    // Tall surface so the lazy ListView lays out the feed row (it sits below the
    // summary/balances/settlements sections, past the default viewport).
    await tester.binding.setSurfaceSize(const Size(1200, 3000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(ProviderScope(
      overrides: [
        moneyFormatterProvider.overrideWithValue(const MoneyFormatter('USD', {'USD': 1.0})),
        currentUserIdProvider.overrideWithValue('1'),
        groupFeedProvider(1).overrideWith((ref) async => incomeFeed),
        groupMembersProvider(1).overrideWith((ref) async => testMembers),
        groupBalancesProvider(1).overrideWith((ref) async =>
            const GroupBalances(members: [], suggestions: [], total: 0, currency: 'USD')),
        groupSettlementsProvider(1).overrideWith((ref) async => const []),
        groupGoalsProvider(1).overrideWith((ref) async => const []),
      ],
      child: const MaterialApp(home: GroupDetailScreen(group: testGroup)),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(tester.takeException(), isNull);
    // Income wording (not "paid by / you owe").
    expect(find.textContaining('received by'), findsOneWidget);
    expect(find.textContaining("you're owed"), findsOneWidget);
  });

  testWidgets('GroupDetailScreen — settle-up history offers Undo to a party', (tester) async {
    final settlement = GroupSettlement(
      id: 9,
      fromName: 'You',
      toName: 'Bob',
      fromUserId: '1', // I'm the payer → I can undo
      toUserId: '2',
      amount: 500,
      currency: 'USD',
      status: 'confirmed',
      createdAt: DateTime(2026, 7, 12),
    );
    await tester.pumpWidget(ProviderScope(
      overrides: [
        moneyFormatterProvider.overrideWithValue(const MoneyFormatter('USD', {'USD': 1.0})),
        currentUserIdProvider.overrideWithValue('1'),
        groupFeedProvider(1).overrideWith((ref) async => testFeed),
        groupMembersProvider(1).overrideWith((ref) async => testMembers),
        groupBalancesProvider(1).overrideWith((ref) async =>
            const GroupBalances(members: [], suggestions: [], total: 0, currency: 'USD')),
        groupSettlementsProvider(1).overrideWith((ref) async => [settlement]),
        groupGoalsProvider(1).overrideWith((ref) async => const []),
      ],
      child: const MaterialApp(home: GroupDetailScreen(group: testGroup)),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(tester.takeException(), isNull);
    expect(find.text('Settle-up history'), findsOneWidget);
    expect(find.text('Undo'), findsOneWidget);
  });

  testWidgets('GroupsScreen — populated list builds without error', (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        moneyFormatterProvider.overrideWithValue(const MoneyFormatter('USD', {'USD': 1.0})),
        groupRepositoryProvider.overrideWithValue(_FakeGroupRepo()),
      ],
      child: const MaterialApp(home: GroupsScreen()),
    ));
    // Let GroupsController.refresh() resolve and the list rebuild.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(tester.takeException(), isNull);
    expect(find.text('Home'), findsOneWidget);
  });

  testWidgets('create group flow → navigates to detail without error', (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        moneyFormatterProvider.overrideWithValue(const MoneyFormatter('USD', {'USD': 1.0})),
        groupRepositoryProvider.overrideWithValue(_FakeGroupRepo()),
      ],
      child: const MaterialApp(home: GroupsScreen()),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    // Open the "New group" dialog.
    await tester.tap(find.text('New group'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    // Enter a name and create → should navigate to GroupDetailScreen.
    await tester.enterText(find.byType(TextField), 'Trip');
    await tester.tap(find.text('Create'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
