import 'package:flutter/material.dart';

class TemplatesTab extends StatelessWidget {
  const TemplatesTab({super.key});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Templates', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
            Expanded(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.dashboard_customize_outlined, size: 56, color: Colors.white.withValues(alpha: 0.3)),
                    const SizedBox(height: 12),
                    const Text('Coming soon', style: TextStyle(color: Color(0xFFB5ABD6))),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
