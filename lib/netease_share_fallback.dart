import 'cover_search.dart';
import 'music_share.dart';
import 'song_search.dart';

const shareTrackFields = {
  'discnumber',
  'totaldiscs',
  'tracknumber',
  'totaltracks',
};

/// Keep source fields and identity intact; annotate only fields filled by search.
class NeteaseShareFallback {
  final SongSearchClient songs;
  final CoverSearchClient covers;
  NeteaseShareFallback({SongSearchClient? songs, CoverSearchClient? covers})
    : songs = songs ?? SongSearchClient(),
      covers = covers ?? CoverSearchClient();
  void close() {
    songs.close();
    covers.close();
  }

  Future<ShareResult> complete(
    ShareResult input,
    String region,
    CoverCancel cancel,
  ) async {
    final original = input.candidate;
    final identity = original.song;
    if (input.platform != 'netease' ||
        identity.source != 'netease' ||
        identity.title.trim().isEmpty) {
      return input;
    }
    final missing = shareTrackFields
        .where((k) => (original.fields[k] ?? '').trim().isEmpty)
        .toSet();
    if (missing.isEmpty && input.cover.trim().isNotEmpty) return input;
    final fields = {...original.fields};
    final scores = {...original.fieldScores};
    final uncertain = {...original.uncertainFields};
    final warnings = [...input.warnings];
    var cover = input.cover;
    if (missing.isNotEmpty) {
      try {
        final rows =
            (await songs.searchSource(
                '163',
                identity.title,
                identity.artist,
                identity.album,
                region,
                cancel,
              )).where((s) => s.source == '163' && s.score >= 80).toList()
              ..sort((a, b) => b.score.compareTo(a.score));
        cancel.check();
        if (rows.isNotEmpty) {
          // Use one matched record for all four values; never combine different albums.
          final best = rows.first;
          final detail = await songs.details(best, region, cancel);
          cancel.check();
          final filled = <String>[];
          for (final key in missing) {
            final value = (detail.fields[key] ?? '').trim();
            if (!RegExp(r'^[1-9]\d*$').hasMatch(value)) continue;
            fields[key] = value;
            scores[key] = best.score;
            if (best.score < 100) uncertain.add(key);
            filled.add(songSearchFields[key]!);
          }
          if (filled.isNotEmpty) {
            warnings.add(
              '网易云搜索补全${filled.join('、')} ${best.score.toString()}分${best.score < 100 ? ' 存疑' : ''}',
            );
          }
          if (detail.detailError.isNotEmpty) warnings.add(detail.detailError);
        }
      } on CoverCancelled {
        rethrow;
      } catch (e) {
        cancel.check();
        warnings.add('网易云音轨／碟片补全失败：${conciseError(e)}');
      }
    }
    if (cover.trim().isEmpty) {
      try {
        final rows = await covers.search(
          title: identity.title,
          artist: identity.artist,
          album: identity.album,
          enabled: {'163'},
          region: region,
          cancel: cancel,
          onUpdate: (_, _) {},
        );
        cancel.check();
        final exact = rows
            .where(
              (s) =>
                  s.source == '163' &&
                  s.score == 100 &&
                  s.artwork.trim().isNotEmpty,
            )
            .firstOrNull;
        if (exact != null) {
          cover = exact.artwork;
          warnings.add('封面由网易云搜索补全 100分');
        }
      } on CoverCancelled {
        rethrow;
      } catch (e) {
        cancel.check();
        warnings.add('网易云封面补全失败：${conciseError(e)}');
      }
    }
    cancel.check();
    final song = CoverCandidate(
      source: identity.source,
      id: identity.id,
      title: identity.title,
      artist: identity.artist,
      album: identity.album,
      artwork: cover,
      albumId: identity.albumId,
      score: identity.score,
      displaySource: identity.displaySource,
      duration: identity.duration,
      metadata: identity.metadata,
      aliases: identity.aliases,
    );
    return ShareResult(
      SongCandidate(
        song,
        fields,
        detailError: original.detailError,
        fieldScores: scores,
        uncertainFields: uncertain,
      ),
      cover,
      input.platform,
      warnings,
    );
  }
}
