import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'relays.dart';
import 'sync_cubit.dart';

/// The Nostr relays this device uses to find the group's other devices: the published ones it keeps
/// on, its own, and the ones a link asks for.
class RelaysPage extends StatelessWidget {
  const RelaysPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Relays')),
      body: BlocBuilder<SyncCubit, SyncState>(builder: (context, state) {
        final cubit = context.read<SyncCubit>();
        final relays = state.relays;
        final fromLink = state.linkRelays.isNotEmpty;
        final active = relays.active;
        Future<void> lastOne(Future<bool> change) async {
          if (!await change && context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                content: Text('Keep at least one relay, or devices can\'t find each other')));
          }
        }

        return ListView(
          padding: const EdgeInsets.symmetric(vertical: 8),
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: Text('Devices find each other through these Nostr relays. Devices only meet '
                  'on a relay they both use, so keep at least one in common. The relays only see '
                  'encrypted messages, never your tasks.'),
            ),
            if (fromLink) _LinkCard(relays: state.linkRelays),
            _Section(fromLink ? 'Your relays (not in use while the link\'s are)' : 'Published relays'),
            for (final r in relays.published)
              SwitchListTile(
                title: Text(relayLabel(r)),
                value: relays.isOn(r),
                onChanged: (on) => lastOne(cubit.setRelayOn(r, on: on)),
              ),
            if (relays.custom.isNotEmpty) const _Section('Added on this device'),
            for (final r in relays.custom)
              ListTile(
                title: Text(relayLabel(r)),
                trailing: IconButton(
                  tooltip: 'Remove',
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () => lastOne(cubit.removeRelay(r)),
                ),
              ),
            const _AddRelay(),
            if (!relays.isDefault)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                      onPressed: () => lastOne(cubit.resetRelays()),
                      child: const Text('Restore the published relays')),
                ),
              ),
            if (!fromLink && active.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('To use this list on another device, add this to the end of the app\'s '
                        'address there:',
                        style: Theme.of(context).textTheme.bodySmall),
                    const SizedBox(height: 4),
                    SelectableText('?relays=${active.map(relayLabel).join(',')}',
                        style: const TextStyle(fontFamily: 'monospace', fontSize: 13)),
                  ],
                ),
              ),
          ],
        );
      }),
    );
  }
}

/// The relays the link that opened the app names, with what to do about them.
class _LinkCard extends StatelessWidget {
  final List<String> relays;

  const _LinkCard({required this.relays});

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<SyncCubit>();
    return Card(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Using the relays from the link', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            for (final r in relays) Text(relayLabel(r), style: const TextStyle(fontFamily: 'monospace')),
            const SizedBox(height: 8),
            const Text('The address this app was opened with names these relays, so they are used '
                'instead of your list below for as long as it stays open.'),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 8, children: [
              FilledButton(onPressed: cubit.keepLinkRelays, child: const Text('Save as my relays')),
              OutlinedButton(onPressed: cubit.useSavedRelays, child: const Text('Use my list instead')),
            ]),
          ],
        ),
      ),
    );
  }
}

class _AddRelay extends StatefulWidget {
  const _AddRelay();

  @override
  State<_AddRelay> createState() => _AddRelayState();
}

class _AddRelayState extends State<_AddRelay> {
  final _controller = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _add() async {
    try {
      await context.read<SyncCubit>().addRelay(_controller.text);
      _controller.clear();
      setState(() => _error = null);
    } on FormatException catch (e) {
      setState(() => _error = e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: TextField(
              controller: _controller,
              keyboardType: TextInputType.url,
              autocorrect: false,
              decoration: InputDecoration(
                border: const OutlineInputBorder(),
                labelText: 'Add a relay',
                hintText: 'wss://relay.example.com',
                errorText: _error,
                errorMaxLines: 3,
              ),
              onChanged: (_) {
                if (_error != null) setState(() => _error = null);
              },
              onSubmitted: (_) => _add(),
            ),
          ),
          const SizedBox(width: 8),
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: FilledButton.tonal(onPressed: _add, child: const Text('Add')),
          ),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  final String title;

  const _Section(this.title);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(title, style: theme.textTheme.titleSmall?.copyWith(color: theme.colorScheme.primary)),
    );
  }
}

/// The Devices page's entry to [RelaysPage]: which relays are in use.
class RelaysTile extends StatelessWidget {
  final SyncState state;

  const RelaysTile({super.key, required this.state});

  @override
  Widget build(BuildContext context) {
    final active = state.activeRelays;
    final names = active.map(relayLabel).join(', ');
    return ListTile(
      leading: const Icon(Icons.cell_tower),
      title: Text(state.linkRelays.isNotEmpty
          ? 'Relays from the link (${active.length})'
          : state.relays.isDefault
              ? 'Relays: the published ${active.length}'
              : 'Relays: your own list (${active.length})'),
      subtitle: Text(names, maxLines: 2, overflow: TextOverflow.ellipsis),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
          builder: (_) => BlocProvider.value(
              value: context.read<SyncCubit>(), child: const RelaysPage()))),
    );
  }
}
