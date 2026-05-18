enum ChatProvider {
  ollama('Ollama', 'batiai/gemma4-e4b:q4', 'http://localhost:11434'),
  openai('ChatGPT', 'gpt-4.1-mini', 'https://api.openai.com'),
  anthropic('Claude', 'claude-sonnet-4-5', 'https://api.anthropic.com'),
  gemini(
    'Gemini',
    'gemini-2.0-flash',
    'https://generativelanguage.googleapis.com',
  ),
  xai('Grok', 'grok-4.3', 'https://api.x.ai');

  const ChatProvider(this.label, this.defaultModel, this.defaultBaseUrl);

  final String label;
  final String defaultModel;
  final String defaultBaseUrl;
}

final class ChatConnectionSettings {
  const ChatConnectionSettings({
    required this.provider,
    required this.model,
    required this.baseUrl,
    required this.apiKey,
    this.systemPrompt =
        'You are a helpful assistant. Reply in Markdown when formatting helps.',
  });

  factory ChatConnectionSettings.defaults(ChatProvider provider) {
    return ChatConnectionSettings(
      provider: provider,
      model: provider.defaultModel,
      baseUrl: provider.defaultBaseUrl,
      apiKey: '',
    );
  }

  final ChatProvider provider;
  final String model;
  final String baseUrl;
  final String apiKey;
  final String systemPrompt;

  ChatConnectionSettings copyWith({
    ChatProvider? provider,
    String? model,
    String? baseUrl,
    String? apiKey,
    String? systemPrompt,
  }) {
    return ChatConnectionSettings(
      provider: provider ?? this.provider,
      model: model ?? this.model,
      baseUrl: baseUrl ?? this.baseUrl,
      apiKey: apiKey ?? this.apiKey,
      systemPrompt: systemPrompt ?? this.systemPrompt,
    );
  }
}

final class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.role,
    required this.content,
    this.complete = false,
  });

  final String id;
  final String role;
  final String content;
  final bool complete;

  ChatMessage copyWith({String? content, bool? complete}) {
    return ChatMessage(
      id: id,
      role: role,
      content: content ?? this.content,
      complete: complete ?? this.complete,
    );
  }
}

final class ChatCompletionRequest {
  const ChatCompletionRequest({required this.settings, required this.messages});

  final ChatConnectionSettings settings;
  final List<ChatMessage> messages;
}
