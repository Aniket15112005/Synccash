// lib/features/chatbot/presentation/providers/chat_provider.dart

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:synccash/features/auth/presentation/providers/auth_provider.dart'
    show currentCashbookIdProvider;

import '../../data/chat_query_engine.dart';
import '../../domain/chat_models.dart';

final chatEngineProvider = Provider<ChatQueryEngine?>((ref) {
  final apiKey = dotenv.env['GROQ_API_KEY'];
  if (apiKey == null || apiKey.isEmpty) return null;
  return ChatQueryEngine(groqApiKey: apiKey);
});

/// Whether a question is currently being answered. Kept as its own provider
/// so the chat screen can watch it independently of the message list.
class ChatBusyNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  void setBusy(bool value) => state = value;
}

final chatBusyProvider =
    NotifierProvider<ChatBusyNotifier, bool>(ChatBusyNotifier.new);

class ChatController extends Notifier<List<ChatMessage>> {
  @override
  List<ChatMessage> build() {
    return [
      ChatMessage(
        role: ChatRole.bot,
        text: "Hi! Ask me things like \"when did I pay Ramesh 5000\", "
            "\"list pending bills\", or \"whom did I pay 1000 to\".",
      ),
    ];
  }

  Future<void> send(String question) async {
    final q = question.trim();
    if (q.isEmpty || ref.read(chatBusyProvider)) return;

    final cashbookId = ref.read(currentCashbookIdProvider);
    if (cashbookId == null || cashbookId.isEmpty) {
      state = [
        ...state,
        ChatMessage(role: ChatRole.user, text: q),
        ChatMessage(role: ChatRole.bot, text: "No cashbook is set up yet."),
      ];
      return;
    }

    ref.read(chatBusyProvider.notifier).setBusy(true);
    state = [...state, ChatMessage(role: ChatRole.user, text: q)];

    try {
      final engine = ref.read(chatEngineProvider);
      if (engine == null) {
        state = [
          ...state,
          ChatMessage(
            role: ChatRole.bot,
            text: "The AI assistant isn't configured yet. "
                "Please add GROQ_API_KEY to the .env file and rebuild the app.",
          ),
        ];
        return;
      }
      final answer = await engine.answer(q, cashbookId: cashbookId);
      state = [...state, ChatMessage(role: ChatRole.bot, text: answer)];
    } catch (e) {
      state = [
        ...state,
        ChatMessage(role: ChatRole.bot, text: "Something went wrong: $e"),
      ];
    } finally {
      ref.read(chatBusyProvider.notifier).setBusy(false);
    }
  }
}

final chatControllerProvider =
    NotifierProvider<ChatController, List<ChatMessage>>(ChatController.new);
