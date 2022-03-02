import 'package:xmpp_stone/xmpp_stone.dart';

String getPreview(Message message) {
  if (message.images?.isNotEmpty ?? false) {
    return '[图片]';
  } else if (message.files?.isNotEmpty ?? false) {
    return '[文件]';
  } else {
    return message.text;
  }
}
