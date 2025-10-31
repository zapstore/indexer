import 'package:yaml/yaml.dart';

String filenameWithoutYamlExtension(String filename) {
  if (filename.endsWith('.yaml')) {
    return filename.substring(0, filename.length - '.yaml'.length);
  }
  if (filename.endsWith('.yml')) {
    return filename.substring(0, filename.length - '.yml'.length);
  }
  return filename;
}

String? extractRepository(String yamlText) {
  try {
    final YamlMap doc = loadYaml(yamlText) as YamlMap;
    final dynamic direct =
        doc['repository'] ??
        doc['repo'] ??
        doc['git'] ??
        doc['source'] ??
        doc['github'];
    if (direct is String) {
      return direct.trim();
    }
    final dynamic metadata = doc['metadata'];
    if (metadata is YamlMap) {
      final dynamic nested = metadata['repository'] ?? metadata['repo'];
      if (nested is String) {
        return nested.trim();
      }
    }
  } catch (_) {
    // ignore
  }
  return null;
}

String normalizeRepository(String repositoryOrId) {
  // Legacy normalization used for duplicate detection (lowercased). Kept for compatibility.
  String s = repositoryOrId.trim().toLowerCase();
  final RegExp sshScp = RegExp(r'^git@([^:]+):(.+)$');
  final Match? m = sshScp.firstMatch(s);
  if (m != null) {
    final String host = m.group(1)!;
    String path = m.group(2)!;
    if (path.endsWith('.git')) {
      path = path.substring(0, path.length - 4);
    }
    path = path.replaceAll(RegExp(r'^/+'), '').replaceAll(RegExp(r'/+$'), '');
    return '$host/$path';
  }
  try {
    final Uri uri = Uri.parse(s);
    if (uri.host.isNotEmpty) {
      final String host = uri.host;
      String path = uri.path;
      if (path.endsWith('.git')) {
        path = path.substring(0, path.length - 4);
      }
      path = path.replaceAll(RegExp(r'^/+'), '').replaceAll(RegExp(r'/+$'), '');
      return path.isEmpty ? host : '$host/$path';
    }
  } catch (_) {}
  String path = s;
  if (path.endsWith('.git')) {
    path = path.substring(0, path.length - 4);
  }
  path = path.replaceAll(RegExp(r'^/+'), '').replaceAll(RegExp(r'/+$'), '');
  return path;
}

String normalizeRepositoryForId(String repository) {
  // Normalize for ID: remove scheme (http/https/ssh/git), convert SCP to host/path,
  // drop trailing slash and .git suffix, and lowercase domain/path.
  String s = repository.trim();

  // SCP-like SSH URLs: git@host:owner/repo(.git)? -> host/owner/repo
  final RegExp sshScp = RegExp(r'^git@([^:]+):(.+)$');
  final Match? m = sshScp.firstMatch(s);
  if (m != null) {
    final String host = m.group(1)!;
    String path = m.group(2)!;
    if (path.endsWith('.git')) {
      path = path.substring(0, path.length - 4);
    }
    path = path.replaceAll(RegExp(r'^/+'), '').replaceAll(RegExp(r'/+$'), '');
    return ('$host/$path').toLowerCase();
  }

  // Standard URLs
  try {
    final Uri uri = Uri.parse(s);
    if (uri.host.isNotEmpty) {
      final String host = uri.host;
      String path = uri.path;
      if (path.endsWith('.git')) {
        path = path.substring(0, path.length - 4);
      }
      path = path.replaceAll(RegExp(r'^/+'), '').replaceAll(RegExp(r'/+$'), '');
      return (path.isEmpty ? host : '$host/$path').toLowerCase();
    }
  } catch (_) {
    // fall through
  }

  // Fallback: strip .git and slashes, and any leading scheme-like prefix manually
  s = s.replaceFirst(RegExp(r'^[a-zA-Z]+://'), '');
  String path = s;
  if (path.endsWith('.git')) {
    path = path.substring(0, path.length - 4);
  }
  path = path.replaceAll(RegExp(r'^/+'), '').replaceAll(RegExp(r'/+$'), '');
  return path.toLowerCase();
}
