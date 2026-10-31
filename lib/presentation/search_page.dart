import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../application/music_controller.dart';
import 'widgets/provider_status_banner.dart';
import 'widgets/track_result_tile.dart';

class SearchPage extends StatefulWidget {
  const SearchPage({super.key});

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final TextEditingController _queryController = TextEditingController();

  @override
  void dispose() {
    _queryController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final query = _queryController.text;
    await context.read<MusicController>().searchFor(query);
  }

  @override
  Widget build(BuildContext context) {
    final music = context.watch<MusicController>();
    final search = music.search;
    final theme = Theme.of(context);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('搜索', style: theme.textTheme.headlineSmall),
                const SizedBox(width: 12),
                if (music.usedOfficialSearch)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: theme.colorScheme.primary),
                    ),
                    child: Text(
                      '官方页面实时结果',
                      style: theme.textTheme.labelSmall,
                    ),
                  )
                else if (music.isDemo)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: theme.dividerColor),
                    ),
                    child: Text('演示数据', style: theme.textTheme.labelSmall),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    key: const Key('search-field'),
                    controller: _queryController,
                    textInputAction: TextInputAction.search,
                    onSubmitted: (_) => _submit(),
                    decoration: const InputDecoration(
                      hintText: '搜索歌曲、艺人或专辑',
                      prefixIcon: Icon(Icons.search),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                FilledButton(
                  key: const Key('search-submit'),
                  onPressed: search.loading ? null : _submit,
                  child: const Text('搜索'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final snapshot in music.providerStates.values)
                  ProviderStatusBanner(
                    snapshot: snapshot,
                    errorMessage: search.errors[snapshot.service]?.message,
                    onRetry: search.query.isEmpty ? null : _submit,
                  ),
              ],
            ),
            const SizedBox(height: 8),
            if (search.loading) const LinearProgressIndicator(minHeight: 2),
            const SizedBox(height: 8),
            Expanded(
              child: search.loading && search.results.isEmpty
                  ? const Center(child: CircularProgressIndicator())
                  : search.results.isEmpty
                      ? _EmptyResults(hasQuery: search.query.isNotEmpty)
                      : ListView.separated(
                          itemCount: search.results.length,
                          separatorBuilder: (_, _) =>
                              const SizedBox(height: 8),
                          itemBuilder: (context, index) {
                            final track = search.results[index];
                            return TrackResultTile(
                              track: track,
                              imageBytes: music.coverBytesFor(track),
                              onTap: () =>
                                  music.selectTrack(track),
                              onSelectSource: (service) =>
                                  music.selectTrack(track, service: service),
                              onAddToQueue: () => music.enqueue(track),
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyResults extends StatelessWidget {
  const _EmptyResults({required this.hasQuery});

  final bool hasQuery;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.music_note_outlined,
            size: 40,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(height: 10),
          Text(
            hasQuery ? '没有找到结果，试试别的关键词' : '输入关键词，同时搜索 Spotify 与网易云音乐',
            style: theme.textTheme.bodyMedium,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
