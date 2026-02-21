/// Resource budget limits for a sandboxed plugin.
///
/// Prevents a misbehaving or badly optimized plugin from freezing the
/// main isolate or exhausting memory by enforcing hard limits on its
/// API usage.
class PluginBudget {
  /// Maximum number of microseconds the plugin's synchronous callbacks
  /// are allowed to consume per frame before being terminated.
  final int maxCpuMicrosPerFrame;

  /// Maximum number of event listeners a plugin can have active at once.
  final int maxEventSubscriptions;

  /// Maximum number of times a plugin can request node IDs per frame.
  final int maxNodeLookupsPerFrame;

  const PluginBudget({
    this.maxCpuMicrosPerFrame = 2000, // 2ms budget per frame by default
    this.maxEventSubscriptions = 10,
    this.maxNodeLookupsPerFrame = 1000,
  });
}
