// Fonts the editor offers besides the phone fonts. Inter is bundled with the app.
// The Qur'an fonts below are downloaded from Library, Resources (they come from the data
// repo, SIL Open Font Licence); until one is installed the text uses the default font.

const List<(String, String, String)> kBundledFonts = [
  ('Inter', 'Inter', 'Basic'),
  ('Amiri Quran', 'Amiri Quran', "Qur'an"),
  ('Noto Naskh Arabic', 'Noto Naskh Arabic', "Qur'an"),
  ('Scheherazade New', 'Scheherazade New', "Qur'an"),
  ('Noto Kufi Arabic', 'Noto Kufi Arabic', "Qur'an"),
  ('Reem Kufi', 'Reem Kufi', "Qur'an"),
  ('Noto Sans', 'Noto Sans', 'Translation'),
  ('Noto Serif', 'Noto Serif', 'Translation'),
];

const List<String> kFontCategories = [
  'Basic',
  "Qur'an",
  'Translation',
  'Other',
];
