import 'package:flutter/material.dart';

import '../app_state.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets.dart';
import 'lesson_editor_screen.dart';

class LessonsScreen extends StatelessWidget {
  const LessonsScreen({super.key, required this.courseId});

  final String courseId;

  Future<void> _addLesson(BuildContext context) async {
    final state = AppScope.read(context);
    final title = await promptText(
      context,
      title: 'New lesson',
      label: 'Lesson title',
      confirm: 'Add',
    );
    if (title != null) {
      await state.addLesson(courseId, title);
    }
  }

  Future<void> _renameCourse(BuildContext context, Course course) async {
    final state = AppScope.read(context);
    final title = await promptText(
      context,
      title: 'Rename course',
      label: 'Course title',
      initial: course.title,
    );
    if (title != null) {
      await state.renameCourse(course.id, title);
    }
  }

  Future<void> _renameLesson(BuildContext context, Lesson lesson) async {
    final state = AppScope.read(context);
    final title = await promptText(
      context,
      title: 'Rename lesson',
      label: 'Lesson title',
      initial: lesson.title,
    );
    if (title != null) {
      await state.renameLesson(courseId, lesson.id, title);
    }
  }

  Future<void> _deleteLesson(BuildContext context, Lesson lesson) async {
    final state = AppScope.read(context);
    final ok = await confirmDialog(
      context,
      title: 'Delete lesson',
      message: 'Delete "${lesson.title}"?',
    );
    if (ok) {
      await state.deleteLesson(courseId, lesson.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final course = state.courseById(courseId);

    if (course == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: Text('This course no longer exists.')),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(course.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Row(
              children: [
                const CourseCover(size: 64),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        course.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${lessonCountText(course.lessons.length)} - ${minutesText(course.totalMs)}',
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () => _addLesson(context),
                    icon: const Icon(Icons.add),
                    label: const Text('Add Lesson'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _renameCourse(context, course),
                    icon: const Icon(Icons.edit_outlined),
                    label: const Text('Rename'),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 8, 4),
            child: Row(
              children: [
                Text(
                  'Lessons (${course.lessons.length})',
                  style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
                ),
                const SizedBox(width: 2),
                const HelpIcon('Drag the handle on a lesson to change the order.', title: 'Lessons'),
              ],
            ),
          ),
          Expanded(
            child: course.lessons.isEmpty
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.all(32),
                      child: Text(
                        'No lessons yet.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Color(0xFFB5ABD6)),
                      ),
                    ),
                  )
                : ReorderableListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                    buildDefaultDragHandles: false,
                    itemCount: course.lessons.length,
                    onReorder: (oldIndex, newIndex) =>
                        state.reorderLessons(course.id, oldIndex, newIndex),
                    itemBuilder: (context, index) {
                      final lesson = course.lessons[index];
                      return Card(
                        key: ValueKey(lesson.id),
                        margin: const EdgeInsets.only(bottom: 8),
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: KColors.lavender,
                            foregroundColor: KColors.accent,
                            child: Text('${index + 1}'),
                          ),
                          title: Text(
                            lesson.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          subtitle: Text(
                            '${sceneCountText(lesson.scenes.length)} - ${formatClock(lesson.durationMs)}',
                          ),
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => LessonEditorScreen(
                                courseId: course.id,
                                lessonId: lesson.id,
                              ),
                            ),
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              PopupMenuButton<String>(
                                onSelected: (value) {
                                  if (value == 'rename') _renameLesson(context, lesson);
                                  if (value == 'delete') _deleteLesson(context, lesson);
                                },
                                itemBuilder: (_) => const [
                                  PopupMenuItem(value: 'rename', child: Text('Rename')),
                                  PopupMenuItem(value: 'delete', child: Text('Delete')),
                                ],
                              ),
                              ReorderableDragStartListener(
                                index: index,
                                child: const Padding(
                                  padding: EdgeInsets.all(8),
                                  child: Icon(Icons.drag_handle),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
