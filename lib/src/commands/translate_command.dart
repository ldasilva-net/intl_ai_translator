import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:mason_logger/mason_logger.dart';

class TranslateCommand extends Command<int> {
  TranslateCommand({
    required Logger logger,
  }) : _logger = logger {
    argParser
      ..addOption(
        'l10n-path',
        abbr: 'p',
        help: 'Path to .arb files.',
        mandatory: true,
      )
      ..addOption(
        'main-lang',
        abbr: 'l',
        help: 'Main language code.',
        mandatory: true,
      )
      ..addOption(
        'api-key',
        abbr: 'k',
        help: 'Gemini API Key.',
        mandatory: true,
      );
  }

  @override
  String get description => 'Translate .arb files';

  @override
  String get name => 'translate';

  final Logger _logger;

  late GenerativeModel model;

  @override
  Future<int> run() async {
    final l10nPath = argResults?['l10n-path'] as String?;
    final mainLanguageCode = argResults?['main-lang'] as String?;
    final apiKey = argResults?['api-key'] as String?;

    if (l10nPath == null || mainLanguageCode == null || apiKey == null) {
      _logger.err('You need to set the mandatory options');
      return ExitCode.software.code;
    }

    model = GenerativeModel(
      model: 'gemini-1.5-flash',
      apiKey: apiKey,
    );

    _logger.info(
      'Starting translation with config\n'
      '- Path: $l10nPath\n'
      '- Main lang: $mainLanguageCode\n',
    );

    try {
      await _translateFiles(
        l10nPath,
        mainLanguageCode,
      );
    } catch (error) {
      _logger.err('$error');

      return ExitCode.software.code;
    }

    _logger.info('\nDone!');

    return ExitCode.success.code;
  }

  Future<void> _translateFiles(
    String l10nPath,
    String mainLanguageCode,
  ) async {
    final l10nFiles = Directory(l10nPath).listSync().whereType<File>().toList();

    final mainFile = l10nFiles
        .firstWhere((file) => file.path.endsWith('_$mainLanguageCode.arb'));

    final mainContent =
        jsonDecode(mainFile.readAsStringSync()) as Map<String, dynamic>;

    for (final l10nFile in l10nFiles) {
      if (l10nFile == mainFile) continue;

      final l10nFilePath = l10nFile.path;
      final l10nFileContent =
          jsonDecode(l10nFile.readAsStringSync()) as Map<String, dynamic>;
      final languageCode = _extractLocale(l10nFilePath);

      final entriesToTranslate = l10nFileContent.entries
          .where(
            (copy) => copy.value == mainContent[copy.key],
          )
          .toList();

      if (entriesToTranslate.isEmpty) {
        _logger.alert('Nothing to translate on $l10nFilePath');
        continue;
      }

      const separator = '||';
      final copiesToTranslate =
          entriesToTranslate.map((entry) => entry.value).join(separator);

      final translations = await _getTranslations(
        copiesToTranslate,
        mainLanguageCode,
        languageCode,
      );
      final translationsList = translations.split(separator);

      for (var i = 0; i < entriesToTranslate.length; i++) {
        l10nFileContent[entriesToTranslate[i].key] = translationsList[i].trim();
      }

      const encoder = JsonEncoder.withIndent('  ');
      final jsonString = encoder.convert(l10nFileContent);

      File(l10nFilePath).writeAsStringSync(
        jsonString,
        flush: true,
      );

      _logger.success('Translations replaced successfully in "$l10nFilePath" '
          'for language "$languageCode"');
    }
  }

  Future<String> _getTranslations(
    String copies,
    String mainLanguage,
    String targetLanguage,
  ) async {
    final prompt = 'Translate the following text from "$mainLanguage" to '
        '"$targetLanguage" and return only the translated text, '
        'maintaining the same order and separating each translation '
        'with "||":\n\n$copies';

    final content = [Content.text(prompt)];
    final response = await model.generateContent(content);

    return response.text.toString();
  }

  String _extractLocale(String filePath) {
    final regex = RegExp(r'_(\w{2})(?:_(\w{2}))?\.arb$');
    final match = regex.firstMatch(filePath);

    if (match == null) {
      return '';
    }

    final languageCode = match.group(1);
    final countryCode = match.group(2);

    if (countryCode == null) {
      return languageCode.toString();
    }

    return '${languageCode}_$countryCode';
  }
}
