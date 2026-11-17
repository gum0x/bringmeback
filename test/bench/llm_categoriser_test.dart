import 'package:bringmeback/bloc/task_document.dart';
import 'package:flutter_test/flutter_test.dart';

import 'llm_categoriser.dart';

void main() {
  test('the chat lists each category, then sorted tasks as turns, then the task', () {
    final chat = LlmCategoriser.chat('Ship BMB', const [
      TaskCategory(id: 'work-planning', name: 'Work planning', keywords: 'email plan'),
      TaskCategory(id: 'p', name: 'Personal projects', rules: 'bringmeback, BMB'),
    ], examples: [
      (text: 'backlog grooming', category: 'work-planning'),
      (text: 'gone', category: 'deleted'),
    ]);
    final text = [for (final m in chat) '${m.role.name}: ${m.content}'];
    expect(text.first, contains('- Work planning (email, plan)'));
    expect(text.first, contains('- Personal projects. Always for tasks that mention: bringmeback, bmb'));
    expect(text.sublist(1), [
      'user: Answer work emails',
      'assistant: Work planning',
      'user: backlog grooming',
      'assistant: Work planning',
      'user: Ship BMB',
    ]);
  });

  test('softmax turns log-probabilities into probabilities', () {
    final p = LlmCategoriser.softmax([-1, -1, -3]);
    expect(p.reduce((a, b) => a + b), closeTo(1, 1e-9));
    expect(p[0], closeTo(p[1], 1e-9));
    expect(p[2], lessThan(p[0]));
  });

}
