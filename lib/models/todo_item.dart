/// One entry in a project's to-do list (`todos/todos.json`).
enum TodoPriority { low, normal, high }

class TodoItem {
  final String id;
  final String text;
  final bool done;
  final TodoPriority priority;
  final String? linkedSceneId;

  const TodoItem({
    required this.id,
    required this.text,
    this.done = false,
    this.priority = TodoPriority.normal,
    this.linkedSceneId,
  });

  TodoItem copyWith({String? text, bool? done, TodoPriority? priority}) => TodoItem(
        id: id,
        text: text ?? this.text,
        done: done ?? this.done,
        priority: priority ?? this.priority,
        linkedSceneId: linkedSceneId,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'text': text,
        'done': done,
        'priority': priority.name,
        if (linkedSceneId != null) 'linkedSceneId': linkedSceneId,
      };

  factory TodoItem.fromJson(Map<String, dynamic> json) => TodoItem(
        id: json['id'] as String,
        text: json['text'] as String,
        done: json['done'] as bool? ?? false,
        priority: TodoPriority.values.firstWhere(
          (v) => v.name == json['priority'],
          orElse: () => TodoPriority.normal,
        ),
        linkedSceneId: json['linkedSceneId'] as String?,
      );
}
