import 'package:flutter/material.dart';

import '../theme.dart';

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  Widget _h(String t) => Padding(
        padding: const EdgeInsets.only(top: 18, bottom: 6),
        child: Text(t, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: KColors.gold)),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('About')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text("Qur'an Studio", style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          const Text('Version 1.0.0. Works offline. Projects stay on this phone. Free, with no ads.'),
          _h("Qur'an text"),
          const SelectableText(
            "The Arabic text is the Uthmani text of the Tanzil Project (tanzil.net), used "
            'unmodified. Tanzil makes its text available under its own terms; see '
            'tanzil.net/docs/faq. Tanzil does not guarantee its translations.',
          ),
          _h('Translations'),
          const SelectableText(
            'English: Sahih International, via Tanzil.\n'
            'Hausa: Abu Bakr Mahmoud Gumi, from QuranEnc.com (key hausa_gummi), version 1.2.2. '
            'The translation is shown unmodified and QuranEnc.com is the source.',
          ),
          _h('Recitations'),
          const SelectableText(
            'Verse recordings are fetched from EveryAyah.com when you make a video and are kept on '
            'your phone. The recordings belong to their reciters: Mishary Rashid Alafasy, '
            'Mahmoud Khalil Al-Husary, Abdul Basit Abdus Samad, Maher Al Muaiqly, '
            'Abdurrahman As-Sudais and Saad Al-Ghamdi.',
          ),
          _h('Font'),
          const SelectableText(
            'Amiri Quran, Noto Naskh Arabic, Scheherazade New, Noto Kufi Arabic, Reem Kufi, Noto Sans '
            'and Noto Serif, all under the SIL Open Font Licence 1.1.',
          ),
          _h('Your videos'),
          const SelectableText(
            'Check the text and the recitation before you publish a video. If you share a video, '
            'keep the credits above with it.',
          ),
        ],
      ),
    );
  }
}
