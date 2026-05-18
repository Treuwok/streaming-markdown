import '../models/chat_connection_settings.dart';

abstract interface class ChatRepository {
  Stream<String> streamAnswer(ChatCompletionRequest request);

  void dispose();
}
