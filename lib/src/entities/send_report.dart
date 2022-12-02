import 'message.dart';

class SendReport {
  final Message mail;
  final DateTime connectionOpened;
  final DateTime messageSendingStart;
  final DateTime messageSendingEnd;
  final List<int>? sentData;

  SendReport(this.mail, this.connectionOpened, this.messageSendingStart,
      this.messageSendingEnd, [this.sentData]);

  @override
  String toString() {
    return 'Message successfully sent.\n'
        'Connection was opened at: $connectionOpened.\n'
        'Sending the message started at: $messageSendingStart and finished at: $messageSendingEnd.';
  }
}
