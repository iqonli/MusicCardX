import 'dart:io';
import 'dart:typed_data';

import 'package:audio_metadata_reader/audio_metadata_reader.dart';

import 'song_fields.dart';

const audioExtensions = {
  'mp3',
  'flac',
  'mp4',
  'm4a',
  'ape',
  'ogg',
  'opus',
  'wav',
  'webm',
  'mkv',
  'aif',
  'aiff',
  'aifc',
  'mov',
};

class AudioInformation {
  final Map<String, dynamic> fields;
  final String? lyrics;
  final Uint8List? cover;
  const AudioInformation(this.fields, this.lyrics, this.cover);
}

AudioInformation readAudioInformation(String path) {
  final m = readMetadata(File(path), getImage: true);
  final raw = readAllMetadata(File(path), getImage: false);
  final picture =
      m.pictures
          .where((p) => p.pictureType == PictureType.coverFront)
          .firstOrNull ??
      m.pictures.firstOrNull;
  final lyrics =
      m.lyrics ??
      (raw is Mp3Metadata
          ? raw.customMetadata.entries
                .where(
                  (e) => [
                    'lyrics',
                    'unsyncedlyrics',
                    'uslt',
                  ].contains(e.key.toLowerCase()),
                )
                .firstOrNull
                ?.value
          : null);
  final extras = <String, dynamic>{
    if (raw is Mp3Metadata) ...raw.customMetadata,
    if (raw is VorbisMetadata) ...raw.unknowns,
  };
  final track = audioNumberPair(m.trackNumber, m.trackTotal, extras);
  return AudioInformation(
    normalizeSongFields({
      if (raw is Mp3Metadata) ...raw.customMetadata,
      if (raw is VorbisMetadata) ...raw.unknowns,
      'title': m.title,
      'artist': raw is Mp3Metadata
          ? raw.leadPerformer ?? raw.originalArtist
          : m.artist,
      'album artist': raw is Mp3Metadata ? raw.bandOrOrchestra : m.albumArtist,
      'album': m.album,
      'date': raw is Mp3Metadata
          ? raw.customMetadata['DATE'] ??
                (raw.year == null ? null : '${raw.year}')
          : m.year == null || m.year!.year <= 0
          ? null
          : m.year!.month == 1 && m.year!.day == 1
          ? '${m.year!.year}'
          : m.year!.toIso8601String().substring(0, 10),
      'discnumber': m.discNumber,
      'totaldiscs': m.totalDisc,
      'tracknumber': track.$1,
      'totaltracks': track.$2,
      'genre': m.genres,
      'language': m.language,
    }),
    lyrics?.replaceAll('\x00', '').replaceAll('\uFEFF', ''),
    picture?.bytes,
  );
}

(int?, int?) audioNumberPair(
  int? number,
  int? total,
  Map<String, dynamic> extras,
) {
  final tags = {
    for (final e in extras.entries)
      e.key.toLowerCase().replaceAll(RegExp(r'[ _-]'), ''): '${e.value}',
  };
  final value =
      tags['tracknumber'] ??
      tags['track'] ??
      tags['trackno'] ??
      tags['trck'] ??
      tags['trk'];
  final pair = value?.replaceAll('\x00', '').trim().split('/');
  int? positive(int? n) => n != null && n > 0 ? n : null;
  number =
      positive(number) ??
      (pair == null ? null : positive(int.tryParse(pair.first.trim())));
  total =
      positive(total) ??
      (pair != null && pair.length > 1
          ? positive(int.tryParse(pair[1].trim()))
          : null);
  total ??= positive(
    int.tryParse(
      (tags['totaltracks'] ?? tags['tracktotal'] ?? tags['trackcount'] ?? '')
          .trim(),
    ),
  );
  return (number, total);
}
