import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../bloc/tasks_bloc.dart';
import '../version/build_info.dart';
import 'app_links.dart';
import 'pairing.dart';
import 'peer.dart' show syncProtocol;
import 'share_link.dart';
import 'sync_cubit.dart';

/// Pairs this device with others. Every device in a group shares the same group secret.
class SyncPage extends StatelessWidget {
  /// The code from a share link the app was opened with, to join that group.
  final String? joinCode;

  const SyncPage({super.key, this.joinCode});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Devices')),
      body: BlocBuilder<SyncCubit, SyncState>(
        builder: (context, state) => ListView(
          padding: const EdgeInsets.all(16),
          children: !state.supported
              ? const [
                  Text('Sync could not start on this device, '
                      'because its encryption library did not load.')
                ]
              : state.device == null
              ? const [Center(child: CircularProgressIndicator())]
              : state.paired
                  ? _paired(context, state)
                  : _unpaired(context, state),
        ),
      ),
    );
  }

  List<Widget> _unpaired(BuildContext context, SyncState state) => joinCode != null
      ? [
          const Text('You opened a link to join another device\'s group. This device then gets '
              'the group\'s tasks and timers, and its own tasks go to the group too, unless it '
              'starts empty.'),
          const SizedBox(height: 16),
          _JoinForm(code: joinCode),
        ]
      : [
          const Text('Pair your devices to keep the same tasks and timers on all of them. '
              'Start a group here, then open its link or scan its QR code on your other device.'),
          const SizedBox(height: 16),
          ElevatedButton(
              onPressed: () => context.read<SyncCubit>().createGroup(),
              child: const Text('Start a new group')),
          const SizedBox(height: 32),
          const _JoinForm(),
        ];

  /// Shown when a share link opened the app on a device that is already in a group.
  Widget? _linkNotice(BuildContext context, SyncState state) {
    final code = joinCode;
    if (code == null) return null;
    final same = code == state.code;
    return Card(
      child: ListTile(
        leading: Icon(same ? Icons.check_circle_outline : Icons.info_outline),
        title: Text(same
            ? 'This device is in the group from the link'
            : 'The link is for another group'),
        subtitle: same
            ? null
            : const Text('This device is already in a group. To join the one from the link, '
                'leave this group first, then join.'),
      ),
    );
  }

  /// The link to this group, which another device opens to join it.
  static String _link(SyncState state) =>
      ShareLink.build(AppLinks.ownBase ?? Uri.parse(ShareLink.defaultBase), state.code!).toString();

  List<Widget> _paired(BuildContext context, SyncState state) => [
        if (_linkNotice(context, state) case final notice?) ...[notice, const SizedBox(height: 16)],
        const Text('Scan this QR code with your other device\'s camera, or send it the link. '
            'Anyone with the link can join the group, so only share it with your own devices.'),
        const SizedBox(height: 16),
        Center(
          child: QrImageView(
            data: _link(state),
            size: 240,
            backgroundColor: Colors.white,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          alignment: WrapAlignment.center,
          children: [
            if (AppLinks.canShare)
              TextButton.icon(
                  onPressed: () => AppLinks.share(_link(state)),
                  icon: const Icon(Icons.share),
                  label: const Text('Share link')),
            TextButton.icon(
                onPressed: () => _copy(context, _link(state), 'Link copied'),
                icon: const Icon(Icons.link),
                label: const Text('Copy link')),
            TextButton.icon(
                onPressed: () => _copy(context, state.code!, 'Code copied'),
                icon: const Icon(Icons.copy),
                label: const Text('Copy code')),
          ],
        ),
        ExpansionTile(
          title: const Text('Show the code'),
          subtitle: const Text('To type into a device that can\'t open the link'),
          children: [
            SelectableText(state.code!,
                textAlign: TextAlign.center,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 13)),
            const SizedBox(height: 8),
          ],
        ),
        const SizedBox(height: 16),
        ListTile(
          title: const Text('This device'),
          subtitle: Text('Device ${_shortId(state.device!.id)}\n'
              'Version ${BuildInfo.current.label}, sync version $syncProtocol'),
          isThreeLine: true,
        ),
        ListTile(
          title: const Text('Group fingerprint'),
          subtitle: Text('${state.keys!.fingerprint}\nIt should be the same on every device in the group.'),
          isThreeLine: true,
        ),
        SwitchListTile(
          title: const Text('Find my devices online'),
          subtitle: const Text('Uses public Nostr relays to find the group\'s other devices when they '
              'are online. The relays only see encrypted messages, never your tasks. '
              'Your tasks then sync directly between devices on the same network.'),
          isThreeLine: true,
          value: state.live,
          onChanged: (on) => context.read<SyncCubit>().setLive(on),
        ),
        if (state.live) ..._status(context, state),
        if (state.live)
          ListTile(
            title: Text(state.online.isEmpty
                ? 'No other device online'
                : state.online.length == 1
                    ? '1 other device online'
                    : '${state.online.length} other devices online'),
            subtitle: Text(state.online.isEmpty
                ? 'Open bringmeback on another device in this group.'
                : state.connected.length == state.online.length
                    ? 'Syncing directly, end to end encrypted.'
                    : '${state.connected.length} of ${state.online.length} connected directly. '
                        'Devices connect only when they are on the same network.'),
          ),
        const SizedBox(height: 16),
        OutlinedButton(
            onPressed: () => _confirmLeave(context),
            child: const Text('Leave group')),
      ];

  /// What stops sync right now, if anything: the relays, or a device that can't connect.
  List<Widget> _status(BuildContext context, SyncState state) {
    final error = Theme.of(context).colorScheme.error;
    Widget problem(String title, String detail) => ListTile(
          leading: Icon(Icons.error_outline, color: error),
          title: Text(title),
          subtitle: Text(detail),
          isThreeLine: true,
        );
    return [
      if (state.relaysUnreachable)
        problem(
            'Can\'t reach the relays',
            'None of the ${state.relayCount} relays answered, so this device can\'t find the '
                'others. Check the internet connection, or whether a blocker stops connections '
                'to the relays.')
      else if (state.relayCount > 0)
        ListTile(
          dense: true,
          title: Text('Connected to ${state.relaysUp} of ${state.relayCount} relays'),
        ),
      for (final MapEntry(key: id, value: p) in state.problems.entries)
        problem('Device ${_shortId(id)} isn\'t syncing', p.message),
      for (final id in state.online)
        if (state.builds[id] case final build?)
          ListTile(
            dense: true,
            leading: Icon(
                state.connected.contains(id) ? Icons.sync : Icons.sync_disabled),
            title: Text('Device ${_shortId(id)}: version ${build.label}'),
            subtitle: _compare(build) == null ? null : Text(_compare(build)!),
          ),
    ];
  }

  /// How another device's build compares with this one, when it differs.
  static String? _compare(BuildInfo other) {
    final mine = BuildInfo.current;
    if (!other.isKnown || !mine.isKnown || other.sameAs(mine)) return null;
    if (mine.isOlderThan(other)) return 'Newer than this device. Reload or update this one.';
    if (other.isOlderThan(mine)) return 'Older than this device. Reload or update it.';
    return 'A different build from this device.';
  }

  static void _copy(BuildContext context, String text, String done) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(done)));
  }

  static String _shortId(String id) => id.length > 6 ? id.substring(0, 6) : id;

  Future<void> _confirmLeave(BuildContext context) async {
    final cubit = context.read<SyncCubit>();
    final leave = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Leave this group?'),
        content: const Text('Your tasks stay on this device. To pair again you need the link or code from another device in the group.'),
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
  /// A code to join with, from a share link.
  final String? code;

  const _JoinForm({this.code});

  @override
  State<_JoinForm> createState() => _JoinFormState();
}

class _JoinFormState extends State<_JoinForm> {
  late final _controller = TextEditingController(text: widget.code);
  String? _error;
  bool _clearFirst = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _join() async {
    final sync = context.read<SyncCubit>();
    final tasks = context.read<TasksBloc>();
    if (_clearFirst) {
      // A bad code shows its error before anything is asked or deleted.
      try {
        await PairingCode.parse(_controller.text);
      } on FormatException catch (e) {
        setState(() => _error = e.message);
        return;
      }
      if (!mounted || !await _confirmClear()) return;
    }
    if (!mounted) return;
    try {
      await sync.joinGroup(_controller.text, clearFirst: _clearFirst ? tasks.clearAll : null);
    } on FormatException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  Future<bool> _confirmClear() async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Delete this device\'s tasks?'),
          content: const Text('Every task, note and logged time on this device is deleted before it '
              'joins, and it then gets the group\'s tasks. This can\'t be undone.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
            TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Delete and join')),
          ],
        ),
      ) ==
      true;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.code == null) ...[
          const Text('Or join the group of another device, with its link or code:'),
          const SizedBox(height: 8),
        ],
        TextField(
          controller: _controller,
          decoration: InputDecoration(
            border: const OutlineInputBorder(),
            hintText: 'https://… or bmb1-…',
            errorText: _error,
          ),
          onChanged: (_) {
            if (_error != null) setState(() => _error = null);
          },
          onSubmitted: (_) => _join(),
        ),
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          title: const Text('Start empty'),
          subtitle: const Text('Delete the tasks and history on this device first, so only the '
              'group\'s tasks are here and none of this device\'s go to the others.'),
          value: _clearFirst,
          onChanged: (on) => setState(() => _clearFirst = on ?? false),
        ),
        ElevatedButton(onPressed: _join, child: const Text('Join group')),
      ],
    );
  }
}
