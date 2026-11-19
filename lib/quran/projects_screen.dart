import 'package:flutter/material.dart';

import '../app_state.dart';
import '../models.dart';
import '../screens/lesson_editor_screen.dart';
import '../theme.dart';
import 'new_project_wizard.dart';

class ProjectsScreen extends StatefulWidget {
  const ProjectsScreen({super.key});

  @override
  State<ProjectsScreen> createState() => _ProjectsScreenState();
}

class _ProjectsScreenState extends State<ProjectsScreen> {
  /// Ids of the projects ticked for deletion. Empty and [_selecting] false = normal mode.
  final Set<String> _picked = {};
  bool _selecting = false;

  void _exitSelect() => setState(() {
        _selecting = false;
        _picked.clear();
      });

  void _toggle(String id) {
    setState(() {
      if (!_picked.add(id)) _picked.remove(id);
    });
  }

  Future<void> _deletePicked(AppState state) async {
    final n = _picked.length;
    if (n == 0) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text(n == 1 ? 'Delete 1 project' : 'Delete $n projects'),
        content: const Text('The selected projects will be deleted. This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(d, true), child: const Text('Delete')),
        ],
      ),
    );
    if (ok != true) return;
    await state.deleteCourses({..._picked});
    if (mounted) _exitSelect();
  }

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
    // Forget ticked projects that no longer exist.
    _picked.removeWhere((id) => !videos.any((c) => c.id == id));
    return PopScope(
      canPop: !_selecting,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _selecting) _exitSelect();
      },
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          children: [
            if (_selecting)
              Row(
                children: [
                  IconButton(onPressed: _exitSelect, icon: const Icon(Icons.close), tooltip: 'Cancel'),
                  Expanded(
                    child: Text('${_picked.length} selected',
                        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                  ),
                  IconButton(
                    tooltip: _picked.length == videos.length ? 'Select none' : 'Select all',
                    onPressed: () => setState(() {
                      if (_picked.length == videos.length) {
                        _picked.clear();
                      } else {
                        _picked.addAll(videos.map((c) => c.id));
                      }
                    }),
                    icon: Icon(_picked.length == videos.length ? Icons.deselect : Icons.select_all),
                  ),
                  IconButton(
                    tooltip: 'Delete',
                    onPressed: _picked.isEmpty ? null : () => _deletePicked(state),
                    icon: Icon(Icons.delete_outline, color: _picked.isEmpty ? null : Colors.redAccent),
                  ),
                ],
              )
            else
              Row(
                children: [
                  const Expanded(child: Text('Projects', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800))),
                  if (videos.isNotEmpty)
                    TextButton.icon(
                      onPressed: () => setState(() => _selecting = true),
                      icon: const Icon(Icons.checklist),
                      label: const Text('Select'),
                    ),
                ],
              ),
            const SizedBox(height: 12),
            if (!_selecting)
              FilledButton.icon(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: (_) => const NewProjectWizard()),
                ),
                icon: const Icon(Icons.add),
                label: const Text('Create New Project'),
              ),
            if (!_selecting) const SizedBox(height: 12),
            if (videos.isEmpty)
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(color: KColors.surface, borderRadius: BorderRadius.circular(16)),
                child: const Text('No projects yet. Create your first Qur\'an video.'),
              ),
            for (final c in videos)
              Card(
                shape: _selecting && _picked.contains(c.id)
                    ? RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                        side: const BorderSide(color: KColors.selected, width: 2),
                      )
                    : null,
                child: ListTile(
                  contentPadding: const EdgeInsets.all(10),
                  leading: _selecting
                      ? Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Checkbox(value: _picked.contains(c.id), onChanged: (_) => _toggle(c.id)),
                            _thumb(c),
                          ],
                        )
                      : _thumb(c),
                  title: Text(c.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text(
                    '${c.lessons.first.scenes.length} scenes  -  ${_len(c.totalMs)}  -  ${_date(c.createdAt)}',
                    style: const TextStyle(fontSize: 12),
                  ),
                  trailing: _selecting
                      ? null
                      : PopupMenuButton<String>(
                          onSelected: (v) {
                            if (v == 'rename') _rename(context, state, c);
                            if (v == 'copy') state.duplicateCourse(c.id);
                            if (v == 'delete') _delete(context, state, c);
                            if (v == 'select') {
                              setState(() {
                                _selecting = true;
                                _picked.add(c.id);
                              });
                            }
                          },
                          itemBuilder: (_) => const [
                            PopupMenuItem(value: 'rename', child: Text('Rename')),
                            PopupMenuItem(value: 'copy', child: Text('Duplicate')),
                            PopupMenuItem(value: 'select', child: Text('Select several')),
                            PopupMenuItem(value: 'delete', child: Text('Delete')),
                          ],
                        ),
                  onLongPress: _selecting
                      ? null
                      : () => setState(() {
                            _selecting = true;
                            _picked.add(c.id);
                          }),
                  onTap: () {
                    if (_selecting) {
                      _toggle(c.id);
                      return;
                    }
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => LessonEditorScreen(courseId: c.id, lessonId: c.lessons.first.id),
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}
