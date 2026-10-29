import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'sync_cubit.dart';

/// Pairs this device with others. Every device in a group shares the same group secret.
class SyncPage extends StatelessWidget {
  const SyncPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Devices')),
      body: BlocBuilder<SyncCubit, SyncState>(
        builder: (context, state) => ListView(
          padding: const EdgeInsets.all(16),
          children: state.device == null
              ? const [Center(child: CircularProgressIndicator())]
              : state.paired
                  ? _paired(context, state)
                  : _unpaired(context),
        ),
      ),
    );
  }

  List<Widget> _unpaired(BuildContext context) => [
        const Text('Pair your devices to keep the same tasks and timers on all of them. '
            'Start a group here, then enter its code on your other device.'),
        const SizedBox(height: 16),
        ElevatedButton(
            onPressed: () => context.read<SyncCubit>().createGroup(),
            child: const Text('Start a new group')),
        const SizedBox(height: 32),
        const _JoinForm(),
      ];

  List<Widget> _paired(BuildContext context, SyncState state) => [
        const Text('Show this code to your other device, or copy it there. '
            'Anyone with the code can join the group, so only share it with your own devices.'),
        const SizedBox(height: 16),
        Center(
          child: QrImageView(
            data: state.code!,
            size: 240,
            backgroundColor: Colors.white,
          ),
        ),
        const SizedBox(height: 8),
        SelectableText(state.code!,
            textAlign: TextAlign.center,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 13)),
        TextButton.icon(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: state.code!));
              ScaffoldMessenger.of(context)
                  .showSnackBar(const SnackBar(content: Text('Code copied')));
            },
            icon: const Icon(Icons.copy),
            label: const Text('Copy code')),
        const SizedBox(height: 16),
        ListTile(
          title: const Text('Group fingerprint'),
          subtitle: Text('${state.keys!.fingerprint}\nIt should be the same on every device in the group.'),
          isThreeLine: true,
        ),
        const ListTile(
          title: Text('Sync'),
          subtitle: Text('Devices are paired. Live sync between them is coming in the next version.'),
        ),
        const SizedBox(height: 16),
        OutlinedButton(
            onPressed: () => _confirmLeave(context),
            child: const Text('Leave group')),
      ];

  Future<void> _confirmLeave(BuildContext context) async {
    final cubit = context.read<SyncCubit>();
    final leave = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Leave this group?'),
        content: const Text('Your tasks stay on this device. To pair again you need the code from another device in the group.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Leave')),
        ],
      ),
    );
    if (leave == true) await cubit.leaveGroup();
  }
}

class _JoinForm extends StatefulWidget {
  const _JoinForm();

  @override
  State<_JoinForm> createState() => _JoinFormState();
}

class _JoinFormState extends State<_JoinForm> {
  final _controller = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _join() async {
    try {
      await context.read<SyncCubit>().joinGroup(_controller.text);
    } on FormatException catch (e) {
      setState(() => _error = e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('Or join the group of another device:'),
        const SizedBox(height: 8),
        TextField(
          controller: _controller,
          decoration: InputDecoration(
            border: const OutlineInputBorder(),
            hintText: 'bmb1-…',
            errorText: _error,
          ),
          onChanged: (_) {
            if (_error != null) setState(() => _error = null);
          },
          onSubmitted: (_) => _join(),
        ),
        const SizedBox(height: 8),
        ElevatedButton(onPressed: _join, child: const Text('Join group')),
      ],
    );
  }
}
