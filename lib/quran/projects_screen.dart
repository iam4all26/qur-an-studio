import 'package:flutter/material.dart';

import '../app_state.dart';
import '../models.dart';
import '../screens/lesson_editor_screen.dart';
import '../theme.dart';
import 'new_project_wizard.dart';

class ProjectsScreen extends StatelessWidget {
  const ProjectsScreen({super.key});

  String _date(int ms) {
    final d = DateTime.fromMillisecondsSinceEpoch(ms);
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(d.day)}/${two(d.month)}/${d.year}';
  }

  String _len(int ms) {
    final s = (ms / 1000).round();
    return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
  }

  Future<void> _rename(BuildContext context, AppState state, Course c) async {
    final ctrl = TextEditingController(text: c.title);
    final name = await showDialog<String>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('Rename project'),
        content: TextField(controller: ctrl, autofocus: true),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(d, ctrl.text.trim()), child: const Text('Save')),
        ],
      ),
    );
    if (name != null && name.isNotEmpty) await state.renameCourse(c.id, name);
  }

  Future<void> _delete(BuildContext context, AppState state, Course c) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('Delete project'),
        content: Text('Delete "${c.title}"? This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(d, true), child: const Text('Delete')),
        ],
      ),
    );
    if (ok == true) await state.deleteCourse(c.id);
  }

  Widget _thumb(Course c) {
    Widget fill = Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(colors: [Color(0xFF7C3A12), KColors.deepPurple]),
      ),
    );
    final scenes = c.lessons.isEmpty ? <Scene>[] : c.lessons.first.scenes;
    if (scenes.isNotEmpty) {
      final s = scenes.first;
      if (s.bgType == 'asset') {
        fill = Image.asset(s.bgValue, fit: BoxFit.cover, cacheWidth: 200);
      } else if (s.bgType != 'file') {
        final v = int.tryParse(s.bgValue);
        if (v != null) fill = ColoredBox(color: Color(v));
      }
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        width: 64,
        height: 64,
        child: Stack(
          fit: StackFit.expand,
          children: [fill, const Icon(Icons.play_arrow, color: Colors.white)],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final videos = state.courses.where((c) => c.isVideo && c.lessons.isNotEmpty).toList();
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          const Text('Projects', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const NewProjectWizard()),
            ),
            icon: const Icon(Icons.add),
            label: const Text('Create New Project'),
          ),
          const SizedBox(height: 12),
          if (videos.isEmpty)
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(color: KColors.surface, borderRadius: BorderRadius.circular(16)),
              child: const Text('No projects yet. Create your first Qur\'an video.'),
            ),
          for (final c in videos)
            Card(
              child: ListTile(
                contentPadding: const EdgeInsets.all(10),
                leading: _thumb(c),
                title: Text(c.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text(
                  '${c.lessons.first.scenes.length} scenes  -  ${_len(c.totalMs)}  -  ${_date(c.createdAt)}',
                  style: const TextStyle(fontSize: 12),
                ),
                trailing: PopupMenuButton<String>(
                  onSelected: (v) {
                    if (v == 'rename') _rename(context, state, c);
                    if (v == 'copy') state.duplicateCourse(c.id);
                    if (v == 'delete') _delete(context, state, c);
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'rename', child: Text('Rename')),
                    PopupMenuItem(value: 'copy', child: Text('Duplicate')),
                    PopupMenuItem(value: 'delete', child: Text('Delete')),
                  ],
                ),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => LessonEditorScreen(courseId: c.id, lessonId: c.lessons.first.id),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
