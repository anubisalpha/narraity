import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/project.dart';
import '../models/todo_item.dart';
import '../state/manuscript_provider.dart';

/// Per-project to-do list — sidebar tab in the project shell.
class TodoPanel extends ConsumerWidget {
  const TodoPanel({super.key, required this.project});

  final Project project;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final todosAsync = ref.watch(todoListProvider(project));

    return todosAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (err, stack) => Center(child: Text('Failed to load todos: $err')),
      data: (todos) {
        final open = todos.where((t) => !t.done).toList();
        final done = todos.where((t) => t.done).toList();

        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(8),
              child: _AddTodoField(project: project),
            ),
            Expanded(
              child: ListView(
                children: [
                  for (final todo in [...open, ...done])
                    CheckboxListTile(
                      dense: true,
                      controlAffinity: ListTileControlAffinity.leading,
                      value: todo.done,
                      title: Text(
                        todo.text,
                        style: todo.done
                            ? const TextStyle(decoration: TextDecoration.lineThrough)
                            : null,
                      ),
                      secondary: todo.priority == TodoPriority.high
                          ? const Icon(Icons.priority_high, color: Colors.red, size: 18)
                          : IconButton(
                              icon: const Icon(Icons.close, size: 16),
                              onPressed: () async {
                                final service =
                                    await ref.read(todoServiceProvider(project).future);
                                await service.deleteTodo(todo.id);
                                ref.invalidate(todoListProvider(project));
                              },
                            ),
                      onChanged: (checked) async {
                        final service =
                            await ref.read(todoServiceProvider(project).future);
                        await service.updateTodo(todo.copyWith(done: checked ?? false));
                        ref.invalidate(todoListProvider(project));
                      },
                    ),
                  if (todos.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(16),
                      child: Text('No to-dos yet.'),
                    ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _AddTodoField extends ConsumerStatefulWidget {
  const _AddTodoField({required this.project});

  final Project project;

  @override
  ConsumerState<_AddTodoField> createState() => _AddTodoFieldState();
}

class _AddTodoFieldState extends ConsumerState<_AddTodoField> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    final service = await ref.read(todoServiceProvider(widget.project).future);
    await service.addTodo(text);
    _controller.clear();
    ref.invalidate(todoListProvider(widget.project));
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _controller,
      decoration: InputDecoration(
        hintText: 'Add a to-do…',
        isDense: true,
        border: const OutlineInputBorder(),
        suffixIcon: IconButton(icon: const Icon(Icons.add), onPressed: _submit),
      ),
      onSubmitted: (_) => _submit(),
    );
  }
}
