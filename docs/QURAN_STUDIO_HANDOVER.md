# Qur'an Studio - Handover (16 Nov 2026, updated after batch 6)

Owner: Usama (Elguduwis), founder of KAIDA. GitHub: Iam4all26. Read with QURAN_STUDIO_MASTER_DOC.md, KAINUWA_STUDIO_HANDOVER.md and FAST_DELIVERY_GUIDE.md. Rules unchanged: English only, no emojis, complete files with exact paths, small zip batches (zip first, short note after), never claim code was tested, never ask for secrets, build is on his phone (K-Git Studio + GitHub Actions), free plan with a tiny usage window.

## 1. Decisions made (answers to master doc section 13)
1. Business model: free for now, no ads (keeps Tanzil and QuranEnc terms clean).
2. Package name: com.kainuwa.quranstudio (from app_package.txt). App name: Qur'an Studio.
3. First reciters: Alafasy, Husary, Abdul Basit, Muaiqly, Sudais, Ghamdi.
4. First translations: English Sahih International, Hausa Abu Bakr Gumi (QuranEnc key hausa_gummi).
5. Basmala: its own unnumbered scene at the start of every surah video, except At-Tawbah (surah 9). Surah 1 counts it as verse 1.
6. Separate repository from Kainuwa Studio (code copied, no shared build).
7. New data repo: Iam4all26/qurans-data.

## 2. Status (after batch 6)
Verified by Usama on his phone: Phase 0 (one verse built into a video; Arabic and Hausa render), data repo report.json ok (114 surahs, 6,236 verses, 6 of 6 reciters, Amiri Quran), batch 2 (Resources screen downloads and verifies all 5 files; Verify data passes).
Batch 3 (home, splash, navigation) confirmed building on his phone. Batches 4, 5 and 6 delivered, UNCOMPILED and UNTESTED until he builds. He builds later and reports errors with the build log.
Shell repo files never to edit: kgit_build.yml (K-Git overwrites it). Batches are not cumulative: unzip each over the previous ones in order.

## 3. Batch log
- Batch 1 (phase0): full app tree from Kainuwa Studio batch 59, Phase 0 screen, data repo (tools/build_data.py, workflow, README).
- Batch 2 (resources): lib/quran/resource_manager.dart (downloads catalog.json and files from raw.githubusercontent.com/Iam4all26/qurans-data/main/data/, SHA-256 check, installed.json record, font loading via FontLoader), quran_db.dart (read-only sqflite access, BOM stripped, selfCheck), resources_screen.dart, quran_hub_screen.dart; pubspec adds sqflite and crypto. Files live in filesDir/quran/data.
- Batch 3 (home): new splash, lib/quran/home_dashboard.dart (create card, quick actions, continue editing, popular templates tiles, data banner), home_screen.dart with tabs Home, Projects (old CoursesTab), Templates (old TemplatesTab), Library (hub), More (old SettingsTab). Assets and Store tabs are out of the navigation (files remain).
- Batch 4 (library): quran_library_screen.dart (search, All/Makki/Madani), verse_select_screen.dart (Select Verses and By Range, shared selection, VerseSelection class).
- Batch 5 (wizard): lib/quran/new_project_wizard.dart (5 steps: Details, Verses, Translation, Reciter, Template; creates one scene per verse and opens the editor), library pick mode (QuranLibraryScreen(pick: true) returns a VerseSelection), QuranDb.offsetOf, home Create New Project now opens the wizard, this document.

- Batch 6 (reciters, about, data fix): reciters_screen.dart (All, Favorites, Downloaded, delete downloads, Import My Audio list), about_screen.dart (credits; linked from Library and Settings), "Kainuwa Studio" text replaced in five screens, QuranDb reopens when a newer quran.db is installed and selfCheck now fails if the Basmala is attached to verse 1. data-repo/tools/build_data.py replaces tools/build_data.py in the qurans-data repo.

## 3b. Data bug found in batch 6 (important)
The quran.db built in Phase 0 stores the Basmala glued to the start of verse 1 of every surah except 1 and 9 (checked on 2, 3, 18, 67, 114). Cause: the source text starts with an invisible BOM (U+FEFF), so the exact prefix match in strip_basmala_prefix never matched and the report said "removed from 0". The fixed script removes the BOM first, then strips the Basmala, and fails the build unless it was removed from 112 surahs or 0, and fails if any first verse still starts with it. After replacing tools/build_data.py and running the workflow, open Resources, Check for updates, update Qur'an text, then Verify data. Until then wizard videos would show the Basmala twice on verse 1 (once in the extra Basmala scene, once inside verse 1).

## 4. How the wizard builds a video
- Verses and Basmala: text comes from quran.db. If the selection includes verse 1 and the surah is not 1 or 9, a Basmala scene is added first (text from meta.basmala, audio 001001, translation from the first entry of the translation file).
- Translation files are one flat list of 6,236 strings in Qur'an order; index = QuranDb.offsetOf(surah) + ayah - 1. Only en_sahih and ha_gumi exist.
- Audio: per-ayah mp3 from the URL template in reciters.json, cached as filesDir/quran/audio/<folder>_<SSSAAA>.mp3. Scene length = audio length + 800 ms.
- Text: Arabic layer (font Amiri Quran when downloaded) and optional translation layer. Words are wrapped by adding line breaks only (Arabic 4 per line tall or 8 wide; translation 5 or 11). Font size shrinks when a verse has many lines (Arabic over 7 tall or 5 wide lines, translation over 8 or 4). These limits are guesses; adjust after seeing long verses on the phone.
- Colours: four simple looks (Emerald, Midnight, Royal purple, Sand) stored as scene colour backgrounds. Real templates are Phase 3.

## 5. Unverified (check on the phone)
- Everything in batches 3 to 5 compiles and behaves as intended (no compiler on the server; only bracket balance was checked).
- Long verses (Al-Baqarah 2:282) fit the frame in 9:16 and 16:9; many-scene projects export without running out of memory.
- Audio plays in sync per scene; the Basmala scene sounds right.
- Tanzil terms (non-commercial) still apply to the Arabic text; credit Tanzil in About. QuranEnc conditions (credit, version number, no modification) are shown on the Resources screen and in the wizard; also add them to an About screen.
- The invisible BOM (U+FEFF) at the start of verse 1 and meta.basmala in quran.db: stripped on read; better fixed in tools/build_data.py.

## 6. Next steps
1. Build batches 3 to 5, fix errors (grep the log for error lines; Gradle 403 or "Repository not found" is transient: re-run failed jobs).
2. Remaining Phase 1/2 items: reciters library screen (Downloaded, Favorites, Import My Audio), project storage with schemaVersion and Qur'an layer references by (surah, verse, translation id), prune Kainuwa assets and "Kainuwa Studio" strings (project_package.dart, media_library.dart, courses_tab.dart, settings_tab.dart, export_screen.dart, plugin comment), rename plugin kainuwa_encoder, About screen with credits.
3. Phase 3: templates as JSON (replace the four colour looks). Phase 4: editor styling, sync studio with waveform and Set Start/Set End/Auto Sync. Phase 5: export settings and success screens per mockup. Phase 6: timing import (QUL, quran-align), word highlighting.
4. Rules in code: Qur'an text is read-only, never normalised or trimmed (only U+FEFF is removed); re-read text from the database at render time.

## 7. Merge notes
Batch 1 is a full tree; later batches contain only changed files with repo paths. Order matters: 1 to 6. Lineage: every Kainuwa file is at its latest Kainuwa state (batch 59) except those listed above.
