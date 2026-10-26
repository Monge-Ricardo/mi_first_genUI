import 'package:flutter/material.dart';
import 'package:genui/genui.dart';
import 'package:json_schema_builder/json_schema_builder.dart';

final taskDisplaySchema = S.object(
  description: 'Displays a list of tasks with interactive checkboxes.',
  properties: {
    'title': S.string(description: 'Title of the task list (e.g. "Today\'s Tasks")'),
    'tasks': S.list(
      description: 'List of task items to complete',
      items: S.object(
        properties: {
          'title': S.string(description: 'Description/name of the task'),
          'isCompleted': S.boolean(description: 'Whether the task is checked/completed'),
        },
        required: ['title', 'isCompleted'],
      ),
    ),
  },
  required: ['tasks'],
);

class TaskItemData {
  final String title;
  final bool isCompleted;

  TaskItemData({required this.title, required this.isCompleted});

  factory TaskItemData.fromMap(Map<String, dynamic> map) {
    return TaskItemData(
      title: (map['title'] as String?) ?? '',
      isCompleted: (map['isCompleted'] as bool?) ?? false,
    );
  }
}

class TaskDisplayData {
  final String title;
  final List<TaskItemData> tasks;

  TaskDisplayData({required this.title, required this.tasks});

  factory TaskDisplayData.fromMap(Map<String, dynamic> map) {
    final rawTasks = map['tasks'] as List<dynamic>? ?? [];
    return TaskDisplayData(
      title: (map['title'] as String?) ?? "Today's Tasks",
      tasks: rawTasks
          .map((e) => TaskItemData.fromMap(Map<String, dynamic>.from(e as Map)))
          .toList(),
    );
  }
}

class TaskDisplayWidget extends StatefulWidget {
  final CatalogItemContext itemContext;
  final TaskDisplayData data;

  const TaskDisplayWidget({
    super.key,
    required this.itemContext,
    required this.data,
  });

  @override
  State<TaskDisplayWidget> createState() => _TaskDisplayWidgetState();
}

class _TaskDisplayWidgetState extends State<TaskDisplayWidget> {
  late List<TaskItemData> _tasks;

  @override
  void initState() {
    super.initState();
    _tasks = List.from(widget.data.tasks);
  }

  @override
  void didUpdateWidget(covariant TaskDisplayWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    _tasks = List.from(widget.data.tasks);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.data.title.isEmpty ? "Today's Tasks" : widget.data.title,
            style: const TextStyle(
              fontSize: 20.0,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 12.0),
          ..._tasks.asMap().entries.map((entry) {
            final index = entry.key;
            final task = entry.value;

            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 4.0),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      task.title,
                      style: TextStyle(
                        fontSize: 16.0,
                        color: task.isCompleted ? Colors.grey : Colors.black87,
                        decoration: task.isCompleted
                            ? TextDecoration.lineThrough
                            : null,
                      ),
                    ),
                  ),
                  Checkbox(
                    value: task.isCompleted,
                    onChanged: (val) {
                      setState(() {
                        _tasks[index] = TaskItemData(
                          title: task.title,
                          isCompleted: val ?? false,
                        );
                      });

                      // Enviar evento de usuario al agente
                      widget.itemContext.dispatchEvent(
                        UserActionEvent(
                          name: 'onCompleteTask',
                          sourceComponentId: widget.itemContext.id,
                          context: {
                            'task': task.title,
                            'isCompleted': val ?? false,
                          },
                        ),
                      );
                    },
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}

final taskDisplay = CatalogItem(
  name: 'TaskDisplay',
  dataSchema: taskDisplaySchema,
  widgetBuilder: (itemContext) {
    final taskData = TaskDisplayData.fromMap(
      Map<String, dynamic>.from(itemContext.data as Map),
    );
    return TaskDisplayWidget(itemContext: itemContext, data: taskData);
  },
);

final customCatalog = Catalog(
  [
    ...BasicCatalogItems.asCatalog().items,
    taskDisplay,
  ],
  catalogId: 'https://a2ui.org/specification/v0_9/catalogs/basic/catalog.json',
  catalogIdAliases: const [
    'task_catalog',
    'https://a2ui.org/specification/v0_9/basic_catalog.json',
  ],
);
