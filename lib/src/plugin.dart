/// Plugin system for the Dart Analyzer
///
/// Plugins can analyze Dart source code and display results in the UI.

/// Base class for all plugins
abstract class Plugin {
  /// Unique identifier for this plugin
  String get id;

  /// Display name shown in the UI
  String get name;

  /// Icon (emoji or text) for the plugin tab
  String get icon;

  /// Whether this plugin is enabled by default
  bool get enabledByDefault => true;

  /// Process the source code and return HTML content to display
  Future<PluginResult> process(String sourceCode, PluginContext context);

  /// Called when the plugin tab is activated
  void onActivate() {}

  /// Called when the plugin tab is deactivated
  void onDeactivate() {}
}

/// Context provided to plugins during processing
class PluginContext {
  final void Function(String message) log;

  PluginContext({
    required this.log,
  });
}

/// Result from plugin processing
class PluginResult {
  final bool success;
  final String content;
  final String? error;
  final Duration? processingTime;

  PluginResult.success(this.content, {this.processingTime})
      : success = true,
        error = null;

  PluginResult.error(this.error)
      : success = false,
        content = '',
        processingTime = null;
}

/// Registry for managing plugins
class PluginRegistry {
  final List<Plugin> _plugins = [];

  void register(Plugin plugin) {
    _plugins.add(plugin);
  }

  List<Plugin> get plugins => List.unmodifiable(_plugins);

  Plugin? getPlugin(String id) {
    for (final plugin in _plugins) {
      if (plugin.id == id) return plugin;
    }
    return null;
  }
}
