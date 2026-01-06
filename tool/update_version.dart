import 'dart:io';

/// Extracts the analyzer version from pubspec.lock and generates a version file.
void main() {
  final lockFile = File('pubspec.lock');
  if (!lockFile.existsSync()) {
    stderr.writeln('pubspec.lock not found. Run "dart pub get" first.');
    exit(1);
  }

  final content = lockFile.readAsStringSync();
  final analyzerVersion = _extractAnalyzerVersion(content);

  if (analyzerVersion == null) {
    stderr.writeln('Could not find analyzer version in pubspec.lock');
    exit(1);
  }

  final versionFile = File('lib/src/analyzer_version.dart');
  versionFile.writeAsStringSync('''// Generated file - do not edit manually.
// Run: dart run tool/update_version.dart

/// The version of the analyzer package being used.
const analyzerVersion = '$analyzerVersion';
''');

  print('Updated analyzer version to $analyzerVersion');
}

String? _extractAnalyzerVersion(String lockContent) {
  final lines = lockContent.split('\n');
  var inAnalyzer = false;

  for (final line in lines) {
    if (line.trim() == 'analyzer:') {
      inAnalyzer = true;
      continue;
    }
    if (inAnalyzer && line.trim().startsWith('version:')) {
      final match = RegExp(r'version:\s*"?([^"]+)"?').firstMatch(line.trim());
      return match?.group(1);
    }
    if (inAnalyzer && !line.startsWith(' ') && line.trim().isNotEmpty) {
      break;
    }
  }
  return null;
}
