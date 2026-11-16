import 'package:flutter/material.dart';

import '../app_state.dart';
import '../models.dart';
import '../screens/lesson_editor_screen.dart';
import '../theme.dart';
import 'new_project_wizard.dart';
import 'resource_manager.dart';
import 'resources_screen.dart';
import 'templates.dart';

/// The Home tab: new project, quick actions, the latest project, templates.
class HomeDashboard extends StatelessWidget {
  const HomeDashboard({
    super.key,
    required this.onOpenProjects,
    required this.onOpenTemplates,
    required this.onOpenLibrary,
  });

  final VoidCallback onOpenProjects;
  final VoidCallback onOpenTemplates;
  final VoidCallback onOpenLibrary;

  String _date(int ms) {
    final d = DateTime.fromMillisecondsSinceEpoch(ms);
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(d.day)}/${two(d.month)}/${d.year}';
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final videos = state.courses.where((c) => c.isVideo && c.lessons.isNotEmpty).toList();
    final Course? latest = videos.isEmpty ? null : videos.first;

    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Image.asset('assets/icon/app_icon.png', width: 38, height: 38),
              ),
              const SizedBox(width: 10),
              const Text(
                "Qur'an Studio",
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: Colors.white),
              ),
            ],
          ),
          const SizedBox(height: 18),
          _createCard(context),
          const SizedBox(height: 14),
          _resourceBanner(context),
          const SizedBox(height: 6),
          Row(
            children: [
              _action(Icons.folder_outlined, 'Projects', onOpenProjects),
              _action(Icons.dashboard_customize_outlined, 'Templates', onOpenTemplates),
              _action(Icons.menu_book_outlined, "Qur'an", onOpenLibrary),
              _action(Icons.mic_none, 'Reciters', onOpenLibrary),
            ],
          ),
          const SizedBox(height: 18),
          _heading('Continue Editing', onOpenProjects, 'See All'),
          const SizedBox(height: 8),
          if (latest == null)
            _empty('No projects yet. Create your first Qur\'an video.')
          else
            _projectCard(context, latest),
          const SizedBox(height: 18),
          _heading('Popular Templates', onOpenTemplates, 'See All'),
          const SizedBox(height: 8),
          SizedBox(
            height: 130,
            child: FutureBuilder<List<QTemplate>>(
              future: QTemplates.load(),
              builder: (context, snap) {
                final list = snap.data ?? const <QTemplate>[];
                return ListView(
                  scrollDirection: Axis.horizontal,
                  children: [for (final t in list.take(5)) _tile(context, t)],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _createCard(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => const NewProjectWizard()),
      ),
      child: Ink(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          gradient: const LinearGradient(colors: [KColors.purple, Color(0xFF8B5CF6)]),
        ),
        child: Row(
          children: [
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Create New Project',
                    style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800, color: Colors.white),
                  ),
                  SizedBox(height: 4),
                  Text(
                    "Start a Qur'an video in minutes",
                    style: TextStyle(color: Colors.white70),
                  ),
                ],
              ),
            ),
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: KColors.gold,
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Icon(Icons.add, color: KColors.onGold, size: 30),
            ),
          ],
        ),
      ),
    );
  }

  Widget _resourceBanner(BuildContext context) {
    final rm = ResourceManager.instance;
    return ListenableBuilder(
      listenable: rm,
      builder: (context, _) {
        if (rm.allReady) return const SizedBox.shrink();
        return InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => const ResourcesScreen()),
          ),
          child: Ink(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: KColors.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: KColors.gold.withValues(alpha: 0.6)),
            ),
            child: const Row(
              children: [
                Icon(Icons.cloud_download_outlined, color: KColors.gold),
                SizedBox(width: 12),
                Expanded(
                  child: Text("Download the Qur'an data, translations and font to work offline."),
                ),
                Icon(Icons.chevron_right),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _action(IconData icon, String label, VoidCallback onTap) {
    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Column(
            children: [
              Container(
                width: 54,
                height: 54,
                decoration: BoxDecoration(
                  color: KColors.surface,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(icon, color: Colors.white),
              ),
              const SizedBox(height: 6),
              Text(label, style: const TextStyle(fontSize: 12)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _heading(String title, VoidCallback onTap, String action) {
    return Row(
      children: [
        Expanded(
          child: Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
        ),
        TextButton(onPressed: onTap, child: Text(action)),
      ],
    );
  }

  Widget _empty(String text) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: KColors.surface,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Text(text),
    );
  }

  Widget _projectCard(BuildContext context, Course c) {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => LessonEditorScreen(courseId: c.id, lessonId: c.lessons.first.id),
        ),
      ),
      child: Ink(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: KColors.surface,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                gradient: const LinearGradient(colors: [Color(0xFF7C3A12), KColors.deepPurple]),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.play_arrow, color: Colors.white),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    c.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    'Created ${_date(c.createdAt)}',
                    style: const TextStyle(fontSize: 12, color: KColors.accent),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right),
          ],
        ),
      ),
    );
  }

  Widget _tile(BuildContext context, QTemplate t) {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => NewProjectWizard(templateId: t.id)),
      ),
      child: Container(
        width: 100,
        margin: const EdgeInsets.only(right: 10),
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(16)),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image.asset(t.portraitAsset, fit: BoxFit.cover, cacheWidth: 300),
            Positioned(
              left: 10,
              bottom: 8,
              child: Text(t.name,
                  style: const TextStyle(fontWeight: FontWeight.w700, color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }
}
