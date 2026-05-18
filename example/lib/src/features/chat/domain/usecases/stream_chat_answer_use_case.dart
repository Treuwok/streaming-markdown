import '../models/chat_connection_settings.dart';
import '../repositories/chat_repository.dart';

final class StreamChatAnswerUseCase {
  StreamChatAnswerUseCase(this._repository);

  final ChatRepository _repository;

  Stream<String> call(ChatCompletionRequest request) {
    return _repository.streamAnswer(request);
  }

  void dispose() {
    _repository.dispose();
  }
}
