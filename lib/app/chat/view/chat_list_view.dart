import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:child_track/app/chat/view_model/bloc/chat_bloc.dart';
import 'package:child_track/app/chat/view_model/bloc/chat_event.dart';
import 'package:child_track/app/chat/view_model/bloc/chat_state.dart';
import 'package:child_track/core/constants/app_colors.dart';
import 'package:child_track/core/constants/app_sizes.dart';
import 'package:child_track/core/constants/app_text_styles.dart';
import 'package:child_track/core/utils/responsive_font.dart';
import 'package:child_track/core/models/chat_models.dart';
import 'package:child_track/app/chat/view/chat_screen.dart';
import 'package:intl/intl.dart';
import 'package:child_track/core/di/injector.dart';
import 'package:child_track/core/services/shared_prefs_service.dart';

class ChatListView extends StatefulWidget {
  const ChatListView({super.key});

  @override
  State<ChatListView> createState() => _ChatListViewState();
}

class _ChatListViewState extends State<ChatListView> {
  @override
  void initState() {
    super.initState();
    context.read<ChatBloc>().add(LoadChatList());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundColor,
      appBar: AppBar(
        title: const Text(
          'Messages',
          style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.white,
        elevation: 1,
        iconTheme: const IconThemeData(color: AppColors.textPrimary),
      ),
      body: BlocBuilder<ChatBloc, ChatState>(
        builder: (context, state) {
          if (state is ChatLoading) {
            return const Center(child: CircularProgressIndicator());
          }

          if (state is ChatError) {
            return Center(child: Text(state.message));
          }

          if (state is ChatListLoaded) {
            final conversations = state.conversations;
            if (conversations.isEmpty) {
              return const Center(child: Text('No conversations yet'));
            }

            return ListView.separated(
              padding: const EdgeInsets.all(AppSizes.paddingM),
              itemCount: conversations.length,
              separatorBuilder: (context, index) => const Divider(),
              itemBuilder: (context, index) {
                final conversation = conversations[index];
                return _buildConversationTile(conversation);
              },
            );
          }

          return const Center(child: Text('Start a conversation'));
        },
      ),
    );
  }

  Widget _buildConversationTile(ChatConversation conversation) {
    // Determine the other participant (not me)
    final currentUserId = injector<SharedPrefsService>().getString('parent_id') ??
        injector<SharedPrefsService>().getString('child_id') ??
        '';

    final otherParticipant = conversation.participants.firstWhere(
      (p) => p.id != currentUserId,
      orElse: () => conversation.participants.firstWhere(
        (p) => p.role == 'admin' || p.role == 'support' || p.role == '2',
        orElse: () => conversation.participants.isNotEmpty
            ? conversation.participants.first
            : ChatParticipant(id: '', name: 'Support', role: ''),
      ),
    );

    return ListTile(
      leading: CircleAvatar(
        backgroundColor: AppColors.primaryColor.withValues(alpha: 0.1),
        child: Text(
          otherParticipant.name.substring(0, 1).toUpperCase(),
          style: const TextStyle(color: AppColors.primaryColor, fontWeight: FontWeight.bold),
        ),
      ),
      title: Text(
        otherParticipant.name,
        style: AppTextStyles.subtitle1.copyWith(fontWeight: FontWeight.w600),
      ),
      subtitle: Text(
        conversation.lastMessage == null
            ? 'No messages yet'
            : (conversation.lastMessage!.text.isEmpty
                ? 'Tap to view conversation'
                : conversation.lastMessage!.text),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: AppTextStyles.caption.copyWith(color: AppColors.textSecondary),
      ),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            DateFormat('HH:mm').format(conversation.updatedAt),
            style: AppTextStyles.caption.copyWith(fontSize: 10.0.sp),
          ),
          if (conversation.unreadCount > 0)
            Container(
              margin: const EdgeInsets.only(top: 4),
              padding: const EdgeInsets.all(6),
              decoration: const BoxDecoration(
                color: AppColors.primaryColor,
                shape: BoxShape.circle,
              ),
              child: Text(
                '${conversation.unreadCount}',
                style: TextStyle(color: Colors.white, fontSize: 10.0.sp),
              ),
            ),
        ],
      ),
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => BlocProvider.value(
              value: context.read<ChatBloc>(),
              child: ChatScreen(
                chatId: conversation.id,
                recipientId: otherParticipant.id,
                recipientName: otherParticipant.name,
              ),
            ),
          ),
        );
      },
    );
  }
}
