import 'package:flutter/material.dart';

import '../app_state.dart';
import 'package:flutter/services.dart';

import '../models.dart';
import '../scene_canvas.dart';
import 'lesson_player.dart';

/// Plays the lesson on the whole screen, in landscape.
class FullscreenPlayer extends StatefulWidget {
  const FullscreenPlayer({super.key, required this.lesson, required this.player});

  final Lesson lesson;
  final LessonPlayer player;

  @override
  State<FullscreenPlayer> createState() => _FullscreenPlayerState();
}

class _FullscreenPlayerState extends State<FullscreenPlayer> {
  bool _controls = true;

  @override
  void initState() {
    super.initState();
    SystemChrome.setPreferredOrientations(const [
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  @override
  void dispose() {
    AppState.setOrientation(landscape: AppState.editorLandscape);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  String _clock(int ms) {
    final total = ms ~/ 1000;
    return '${(total ~/ 60).toString().padLeft(2, '0')}:${(total % 60).toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final player = widget.player;
    final lesson = widget.lesson;
    return Scaffold(
      backgroundColor: Colors.black,
      body: AnimatedBuilder(
        animation: player,
        builder: (context, _) {
          if (lesson.scenes.isEmpty) return const SizedBox.shrink();
          final spot = sceneAt(lesson, player.positionMs);
          final scene = lesson.scenes[spot.index];
          final total = player.totalMs <= 0 ? 1 : player.totalMs;
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => setState(() => _controls = !_controls),
            child: Center(
              child: AspectRatio(
                aspectRatio: widget.lesson.aspect,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    SceneCanvas(
                      scene: scene,
                      previewMs: player.playing ? spot.localMs : null,
                    ),
                    if (_controls)
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        child: Container(
                          color: const Color(0x99000000),
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          child: Row(
                            children: [
                              IconButton(
                                onPressed: player.toggle,
                                icon: Icon(
                                  player.playing ? Icons.pause : Icons.play_arrow,
                                  color: Colors.white,
                                ),
                              ),
                              Text(_clock(player.positionMs), style: const TextStyle(color: Colors.white)),
                              Expanded(
                                child: Slider(
                                  value: player.positionMs.clamp(0, total).toDouble(),
                                  min: 0,
                                  max: total.toDouble(),
                                  onChanged: (v) => player.seek(v.round()),
                                ),
                              ),
                              Text(_clock(player.totalMs), style: const TextStyle(color: Colors.white)),
                              IconButton(
                                onPressed: () {
                                  player.pause();
                                  Navigator.of(context).pop();
                                },
                                icon: const Icon(Icons.fullscreen_exit, color: Colors.white),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
