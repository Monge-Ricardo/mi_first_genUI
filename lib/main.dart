import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_ai/firebase_ai.dart';
import 'package:genui/genui.dart';

import 'firebase_options.dart';
import 'message_bubble.dart';
import 'custom_catalog.dart';

const taskDisplaySurfaceId = 'task_display';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 1. Cargar las variables del archivo .env
  await dotenv.load(fileName: '.env');
  final appCheckDebugToken = dotenv.env['FIREBASE_APPCHECK_DEBUG_TOKEN'];

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // 2. Activar App Check usando WebDebugProvider con el token leído de .env
  await FirebaseAppCheck.instance.activate(
    providerWeb: WebDebugProvider(debugToken: appCheckDebugToken),
  );

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Just Today',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF6FA8DC),
          primary: const Color(0xFF5B9BD5),
          brightness: Brightness.light,
        ),
        useMaterial3: true,
      ),
      home: const MyHomePage(title: 'Just Today'),
    );
  }
}

sealed class ConversationItem {}

class TextItem extends ConversationItem {
  final String text;
  final bool isUser;
  TextItem({required this.text, required this.isUser});
}

class SurfaceItem extends ConversationItem {
  final String surfaceId;
  SurfaceItem({required this.surfaceId});
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});
  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final List<ConversationItem> _items = [];

  late final SurfaceController _surfaceController;
  late final A2uiTransportAdapter _transportAdapter;
  late final Conversation _conversation;
  late final GenerativeModel _model;
  late final ChatSession _chatSession;

  bool _isLoading = false;
  bool _hasPersistentSurface = false;

  @override
  void initState() {
    super.initState();

    _surfaceController = SurfaceController(catalogs: [customCatalog]);

    _transportAdapter = A2uiTransportAdapter(
      onSend: (message) async {
        final prompt = message.parts
            .whereType<StandardPart>()
            .map((p) => p.toJson()['text'] ?? '')
            .join();

        if (prompt.isNotEmpty) {
          await _sendToAgent(prompt);
        }
      },
    );

    _conversation = Conversation(
      controller: _surfaceController,
      transport: _transportAdapter,
    );

    _conversation.events.listen((event) {
      if (event is ConversationContentReceived) {
        if (event.text.trim().isNotEmpty) {
          setState(() {
            _items.add(TextItem(text: event.text.trim(), isUser: false));
          });
          _scrollToBottom();
        }
      } else if (event is ConversationSurfaceAdded) {
        // En el paso 6 y 7 del codelab:
        // Si la superficie es 'task_display', se fija en el panel superior dedicado
        if (event.surfaceId == taskDisplaySurfaceId) {
          setState(() {
            _hasPersistentSurface = true;
          });
        } else {
          setState(() {
            _items.add(SurfaceItem(surfaceId: event.surfaceId));
          });
          _scrollToBottom();
        }
      }
    });

    final promptBuilder = PromptBuilder.chat(
      catalog: customCatalog,
      systemPromptFragments: [
        'You are Just Today, a personal task management assistant.',
        '## USER INTERFACE',
        '* To display the list of tasks, create one and only one instance of the "TaskDisplay" catalog item.',
        '* Use "$taskDisplaySurfaceId" as its surface ID.',
        '* Update $taskDisplaySurfaceId as necessary when the list changes or items are completed.',
        '* You can also send conversational messages to the user.',
      ],
    );

    _model = FirebaseAI.googleAI().generativeModel(
      model: 'gemini-3.5-flash',
      systemInstruction: Content.system(promptBuilder.systemPromptJoined()),
    );
    _chatSession = _model.startChat();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _sendMessage() async {
    final text = _textController.text.trim();
    if (text.isEmpty || _isLoading) return;

    _textController.clear();
    setState(() {
      _items.add(TextItem(text: text, isUser: true));
      _isLoading = true;
    });
    _scrollToBottom();

    await _sendToAgent(text);
  }

  Future<void> _sendToAgent(String text) async {
    try {
      final responseStream = _chatSession.sendMessageStream(
        Content.text(text),
      );

      await for (final chunk in responseStream) {
        final chunkText = chunk.text;
        if (chunkText != null && chunkText.isNotEmpty) {
          _transportAdapter.addChunk(chunkText);
        }
      }
    } catch (e) {
      setState(() {
        _items.add(
          TextItem(text: 'Error al procesar respuesta: $e', isUser: false),
        );
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
      _scrollToBottom();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF3F3F3),
      appBar: AppBar(
        title: Text(
          widget.title,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w500,
            fontSize: 18,
          ),
        ),
        centerTitle: true,
        backgroundColor: const Color(0xFF7FA8D8),
        elevation: 0,
      ),
      body: Column(
        children: [
          // Paso 6 y 7: Superficie GenUI fija superior (Today's Tasks)
          Container(
            width: double.infinity,
            constraints: const BoxConstraints(
              minHeight: 140,
              maxHeight: 280,
            ),
            decoration: const BoxDecoration(
              color: Colors.white,
              border: Border(
                bottom: BorderSide(color: Color(0xFFDCDCDC), width: 1.0),
              ),
            ),
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(vertical: 8.0),
              child: _hasPersistentSurface
                  ? Surface(
                      surfaceContext: _surfaceController.contextFor(
                        taskDisplaySurfaceId,
                      ),
                    )
                  : Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: const [
                          Text(
                            "Today's Tasks",
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.black87,
                            ),
                          ),
                          SizedBox(height: 8),
                          Text(
                            "Escribe las tareas que necesitas completar hoy en el chat...",
                            style: TextStyle(color: Colors.black54, fontSize: 14),
                          ),
                        ],
                      ),
                    ),
            ),
          ),

          // Barra de progreso de espera (Paso 5)
          if (_isLoading)
            const LinearProgressIndicator(
              minHeight: 3,
              backgroundColor: Color(0xFFE0E0E0),
              valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF7FA8D8)),
            ),

          // Área de Chat inferior
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.all(12.0),
              itemCount: _items.length,
              itemBuilder: (context, index) {
                final item = _items[index];
                switch (item) {
                  case TextItem(:final text, :final isUser):
                    return MessageBubble(text: text, isUser: isUser);
                  case SurfaceItem(:final surfaceId):
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6.0),
                      child: Surface(
                        surfaceContext: _surfaceController.contextFor(surfaceId),
                      ),
                    );
                }
              },
            ),
          ),

          // Campo de entrada de texto inferior
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
            color: Colors.white,
            child: SafeArea(
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _textController,
                      decoration: const InputDecoration(
                        hintText: 'Enter a message',
                        hintStyle: TextStyle(color: Colors.black38),
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 12.0,
                          vertical: 10.0,
                        ),
                      ),
                      onSubmitted: (_) => _sendMessage(),
                    ),
                  ),
                  TextButton(
                    onPressed: _isLoading ? null : _sendMessage,
                    child: const Text(
                      'Send',
                      style: TextStyle(
                        color: Color(0xFF7FA8D8),
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _textController.dispose();
    _scrollController.dispose();
    super.dispose();
  }
}
