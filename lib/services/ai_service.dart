abstract class AiService {
  /// Ensures the backend process is running (desktop only).
  Future<void> start();

  /// Returns true if the backend is reachable.
  Future<bool> isRunning();

  /// Returns true if the model is already downloaded.
  Future<bool> hasModel();

  /// Downloads the model. Yields progress 0.0–1.0.
  Stream<double> pullModel();

  /// Streams response tokens for the given conversation history.
  Stream<String> chat(List<Map<String, String>> history);

  String get modelName;
}
