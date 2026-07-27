const fs = require('fs');
const path = require('path');

const providers = [
  { file: 'profile_provider.dart', type: 'UserModel', varName: 'user' },
  { file: 'transactions_provider.dart', type: 'List<TransactionModel>', varName: 'items' },
  { file: 'budgets_provider.dart', type: 'List<BudgetModel>', varName: 'items' },
  { file: 'goals_provider.dart', type: 'List<GoalModel>', varName: 'items' },
  { file: 'categories_provider.dart', type: 'List<CategoryModel>', varName: 'items' },
  { file: 'recurring_provider.dart', type: 'List<RecurringModel>', varName: 'items' },
  { file: 'reminders_provider.dart', type: 'List<ReminderModel>', varName: 'items' },
  { file: 'notifications_provider.dart', type: 'List<NotificationModel>', varName: 'items' },
  { file: 'wallets_provider.dart', type: 'List<WalletModel>', varName: 'items' },
  { file: 'groups_provider.dart', type: 'List<GroupModel>', varName: 'items' },
  { file: 'debts_provider.dart', type: 'List<DebtModel>', varName: 'items' },
];

for (const p of providers) {
  const filePath = path.join(__dirname, 'lib', 'providers', p.file);
  let content = fs.readFileSync(filePath, 'utf8');

  // Skip if already seeded
  if (content.includes('void seed(')) continue;

  const match = content.match(/Future<void> refresh\(\) async \{/);
  if (match) {
    const seedMethod = `\n  void seed(${p.type} data) {\n    state = state.copyWith(${p.varName}: data, isLoading: false, error: null);\n  }\n\n`;
    content = content.slice(0, match.index) + seedMethod + content.slice(match.index);
    fs.writeFileSync(filePath, content);
    console.log(`Patched ${p.file}`);
  } else {
    console.log(`Could not find refresh() in ${p.file}`);
  }
}
