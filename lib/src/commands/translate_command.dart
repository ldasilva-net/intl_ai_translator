import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:mason_logger/mason_logger.dart';

class TranslateCommand extends Command<int> {
  TranslateCommand({
    required Logger logger,
  }) : _logger = logger {
    argParser.addOption(
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
    final apiKey = argResults?['api-key'] as String?;

    if (apiKey == null) {
      _logger.err('Option api-key is mandatory');
      return ExitCode.software.code;
    }

    model = GenerativeModel(
      model: 'gemini-1.5-flash',
      apiKey: apiKey,
    );

    _logger.progress('Starting translation...');

    try {
      await _replaceTranslations(
        '/Users/ldasilva/workspace/ai_squiz/lib/l10n/intl_en.arb',
        '/Users/ldasilva/workspace/ai_squiz/lib/l10n/intl_es_AR.arb',
      );
    } catch (error) {
      _logger.err('$error');

      return ExitCode.software.code;
    }

    _logger.success('Done!');

    return ExitCode.success.code;
  }

  Future<void> _replaceTranslations(
    String refFilePath,
    String targetFilePath,
  ) async {
    final referenceContent = jsonDecode(File(refFilePath).readAsStringSync())
        as Map<String, dynamic>;

    final targetContent = jsonDecode(File(targetFilePath).readAsStringSync())
        as Map<String, dynamic>;

    final languageCode = _extractLocale(targetFilePath);

    final entriesToTranslate = targetContent.entries
        .where(
          (copy) => copy.value == referenceContent[copy.key],
        )
        .toList();

    if (entriesToTranslate.isEmpty) {
      _logger.success('Nothing to translate');
      return;
    }

    final copiesToTranslate =
        entriesToTranslate.map((entry) => entry.value).join('||');
    final translations =
        await _getTranslations(copiesToTranslate, languageCode);
    final translationsList = translations.split('||');

    for (var i = 0; i < entriesToTranslate.length; i++) {
      targetContent[entriesToTranslate[i].key] = translationsList[i].trim();
    }

    const encoder = JsonEncoder.withIndent('  ');
    final jsonString = encoder.convert(targetContent);

    File(targetFilePath).writeAsStringSync(
      jsonString,
      flush: true,
    );

    _logger.success('Translations replaced successfully in "$targetFilePath" '
        'for language "$languageCode"');
  }

  Future<String> _getTranslations(
    String copies,
    String targetLanguage,
  ) async {
    final prompt = 'Translate the following text to '
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

    if (match != null) {
      final languageCode = match.group(1);
      final countryCode = match.group(2);

      if (countryCode != null) {
        return '${languageCode}_$countryCode';
      } else {
        return languageCode.toString();
      }
    }

    return '';
  }
}
