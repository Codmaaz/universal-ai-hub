import 'provider.dart';

/// Per-conversation generation parameters (user adjustable).
class GenerationSettings {
  const GenerationSettings({
    this.temperature,
    this.maxTokens,
    this.topP,
    this.frequencyPenalty,
    this.presencePenalty,
    this.stopSequences = const [],
    this.seed,
  });

  final double? temperature;
  final int? maxTokens;
  final double? topP;
  final double? frequencyPenalty;
  final double? presencePenalty;
  final List<String> stopSequences;
  final int? seed;

  /// Strips parameters the selected [provider] does not support so invalid
  /// requests are never emitted.
  GenerationSettings filteredBy(AIProvider provider) {
    final caps = provider.capabilities;
    return GenerationSettings(
      temperature: caps.supportsTemperature ? temperature : null,
      maxTokens: caps.supportsMaxTokens ? maxTokens : null,
      topP: caps.supportsTopP ? topP : null,
      frequencyPenalty: caps.supportsFrequencyPenalty ? frequencyPenalty : null,
      presencePenalty: caps.supportsPresencePenalty ? presencePenalty : null,
      stopSequences:
          caps.supportsStopSequences ? List<String>.from(stopSequences) : const [],
      seed: caps.supportsSeed ? seed : null,
    );
  }

  GenerationSettings copyWith({
    double? temperature,
    int? maxTokens,
    double? topP,
    double? frequencyPenalty,
    double? presencePenalty,
    List<String>? stopSequences,
    int? seed,
    bool clearTemperature = false,
    bool clearMaxTokens = false,
    bool clearTopP = false,
    bool clearStopSequences = false,
  }) {
    return GenerationSettings(
      temperature: clearTemperature ? null : (temperature ?? this.temperature),
      maxTokens: clearMaxTokens ? null : (maxTokens ?? this.maxTokens),
      topP: clearTopP ? null : (topP ?? this.topP),
      frequencyPenalty: frequencyPenalty ?? this.frequencyPenalty,
      presencePenalty: presencePenalty ?? this.presencePenalty,
      stopSequences: clearStopSequences ? const [] : (stopSequences ?? this.stopSequences),
      seed: seed ?? this.seed,
    );
  }

  Map<String, dynamic> toJson() => {
        if (temperature != null) 'temperature': temperature,
        if (maxTokens != null) 'maxTokens': maxTokens,
        if (topP != null) 'topP': topP,
        if (frequencyPenalty != null) 'frequencyPenalty': frequencyPenalty,
        if (presencePenalty != null) 'presencePenalty': presencePenalty,
        if (stopSequences.isNotEmpty) 'stopSequences': stopSequences,
        if (seed != null) 'seed': seed,
      };

  static GenerationSettings fromJson(Map<String, dynamic> json) {
    return GenerationSettings(
      temperature: (json['temperature'] as num?)?.toDouble(),
      maxTokens: (json['maxTokens'] as num?)?.toInt(),
      topP: (json['topP'] as num?)?.toDouble(),
      frequencyPenalty: (json['frequencyPenalty'] as num?)?.toDouble(),
      presencePenalty: (json['presencePenalty'] as num?)?.toDouble(),
      stopSequences:
          ((json['stopSequences'] as List?) ?? const []).cast<String>(),
      seed: (json['seed'] as num?)?.toInt(),
    );
  }
}

/// Shared set of well-known generation presets shown to the user.
abstract final class GenerationPresets {
  static const List<({String name, GenerationSettings settings})> presets = [
    (
      name: 'Balanced',
      settings: GenerationSettings(temperature: 0.7, maxTokens: null),
    ),
    (
      name: 'Creative',
      settings: GenerationSettings(
        temperature: 1.2,
        topP: 0.95,
      ),
    ),
    (
      name: 'Precise',
      settings: GenerationSettings(
        temperature: 0.2,
        topP: 0.1,
      ),
    ),
    (
      name: 'Code',
      settings: GenerationSettings(temperature: 0.1),
    ),
  ];
}
