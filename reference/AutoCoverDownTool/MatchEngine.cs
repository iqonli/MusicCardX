using System;
using System.Collections.Generic;
using System.Linq;
using AutoCoverDownTool.Models;
using AutoCoverDownTool.Utils;

namespace AutoCoverDownTool.Services
{
    public sealed class MatchEngine
    {
        public List<CoverCandidate> ScoreAndSort(AudioTaskItem item, IEnumerable<CoverCandidate> candidates)
        {
            if (item == null) throw new ArgumentNullException("item");
            List<CoverCandidate> scored = new List<CoverCandidate>();

            foreach (CoverCandidate candidate in candidates ?? Enumerable.Empty<CoverCandidate>())
            {
                if (candidate == null) continue;

                double title = item.UsesFileNameFallback
                    ? CalculateFileNameSimilarity(item.Title, candidate)
                    : CalculateTitleSimilarity(item.Title, candidate);
                double artist = TextNormalizer.ArtistSimilarity(item.Artist, candidate.Artists);
                double album = TextNormalizer.IsUnknownAlbum(item.Album)
                    ? 0d
                    : TextNormalizer.Similarity(item.Album, candidate.Album);
                double duration = DurationSimilarity(item.DurationMs, candidate.DurationMs);

                double titleVsCandidateAlbum = item.UsesFileNameFallback
                    ? 0d
                    : TextNormalizer.Similarity(item.Title, candidate.Album);
                double albumVsCandidateTitle = TextNormalizer.IsUnknownAlbum(item.Album)
                    ? 0d
                    : TextNormalizer.Similarity(item.Album, candidate.Title);

                bool hasArtist = !string.IsNullOrWhiteSpace(item.Artist);
                bool hasAlbum = !TextNormalizer.IsUnknownAlbum(item.Album);
                bool hasDuration = item.DurationMs > 0 && candidate.DurationMs > 0;

                double titleWeight;
                double artistWeight;
                double albumWeight;
                double durationWeight;
                ResolveWeights(hasArtist, hasAlbum, hasDuration, out titleWeight, out artistWeight, out albumWeight, out durationWeight);

                double totalWeight = titleWeight + artistWeight + albumWeight + durationWeight;
                double score = totalWeight <= 0d
                    ? 0d
                    : (title * titleWeight + artist * artistWeight + album * albumWeight + duration * durationWeight) / totalWeight * 100d;

                List<string> reasons = new List<string>();
                if (item.UsesFileNameFallback) reasons.Add("本地标签为空，使用文件名搜索与匹配");

                // 不再排除任何候选。明显的字段错位仅压低分数并保留说明，所有候选仍下载、显示且可人工选择。
                if (title < 0.55d && titleVsCandidateAlbum >= 0.88d && titleVsCandidateAlbum - title >= 0.25d)
                {
                    score = Math.Min(score, 8d);
                    reasons.Add("候选专辑命中原标题，但候选 Title 不匹配");
                }

                if (hasAlbum && album < 0.45d && albumVsCandidateTitle >= 0.90d && title < 0.75d)
                {
                    score = Math.Min(score, 10d);
                    reasons.Add("候选 Title 命中原专辑名，字段疑似错位");
                }

                if (title < 0.35d)
                {
                    score = Math.Min(score, 20d);
                    reasons.Add("Title 严重不匹配");
                }

                if (hasArtist && artist < 0.25d && title < 0.92d)
                {
                    score = Math.Min(score, 25d);
                    reasons.Add("Artist 严重不匹配");
                }

                if (hasAlbum && album < 0.25d)
                {
                    score = Math.Min(score, 30d);
                    reasons.Add("Album 严重不匹配");
                }

                // Title 与 Artist 是同等主条件；Album 权重较低，但本地 Album 有值时仍限制上限。
                if (title < 0.55d) score = Math.Min(score, 49d);
                else if (title < 0.70d) score = Math.Min(score, 69d);

                if (hasArtist && artist < 0.45d) score = Math.Min(score, 54d);
                else if (hasArtist && artist < 0.65d) score = Math.Min(score, 74d);

                if (hasAlbum && album < 0.45d) score = Math.Min(score, 54d);
                else if (hasAlbum && album < 0.65d) score = Math.Min(score, 74d);

                if (title >= 0.995d && (!hasArtist || artist >= 0.95d)) score += 4d;
                else if (title >= 0.93d && (!hasArtist || artist >= 0.90d)) score += 2d;

                if (hasAlbum && album >= 0.995d) score += 1.5d;
                if (TextNormalizer.HasVersionMismatch(item.Title, candidate.Title))
                {
                    score -= 10d;
                    reasons.Add("版本标记不同");
                }

                if (hasAlbum && album < 0.35d) score -= 4d;
                if (hasDuration && duration <= 0.15d) score -= 5d;

                score = Math.Max(0d, Math.Min(100d, score));
                candidate.TitleScore = title * 100d;
                candidate.ArtistScore = artist * 100d;
                candidate.AlbumScore = album * 100d;
                candidate.DurationScore = duration * 100d;
                candidate.Score = score;
                candidate.IsRejected = false;
                candidate.RejectReason = string.Empty;
                candidate.ScoreDetails = string.Format(
                    "Title {0:0.0}%｜Artist {1:0.0}%｜Album {2:0.0}%｜时长 {3:0.0}%{4}",
                    candidate.TitleScore,
                    candidate.ArtistScore,
                    candidate.AlbumScore,
                    candidate.DurationScore,
                    reasons.Count == 0 ? string.Empty : "｜" + string.Join("；", reasons));
                scored.Add(candidate);
            }

            return scored
                .OrderByDescending(x => x.Score)
                .ThenByDescending(x => x.TitleScore)
                .ThenByDescending(x => x.ArtistScore)
                .ThenBy(x => item.DurationMs > 0 && x.DurationMs > 0 ? Math.Abs(x.DurationMs - item.DurationMs) : long.MaxValue)
                .ToList();
        }

        private static double CalculateFileNameSimilarity(string fileNameQuery, CoverCandidate candidate)
        {
            double best = CalculateTitleSimilarity(fileNameQuery, candidate);
            string titleAndArtist = string.Join(" ", new[]
            {
                candidate.Title,
                candidate.ArtistText
            }.Where(x => !string.IsNullOrWhiteSpace(x)));
            string completeMetadata = string.Join(" ", new[]
            {
                candidate.Title,
                candidate.ArtistText,
                candidate.Album
            }.Where(x => !string.IsNullOrWhiteSpace(x)));
            best = Math.Max(best, TextNormalizer.Similarity(fileNameQuery, titleAndArtist));
            best = Math.Max(best, TextNormalizer.Similarity(fileNameQuery, completeMetadata));
            return best;
        }

        private static double CalculateTitleSimilarity(string localTitle, CoverCandidate candidate)
        {
            string localWithoutFeaturing = TextNormalizer.RemoveFeaturingSuffix(localTitle);
            string remoteWithoutFeaturing = TextNormalizer.RemoveFeaturingSuffix(candidate.Title);
            double best = Math.Max(
                TextNormalizer.Similarity(localTitle, candidate.Title),
                TextNormalizer.Similarity(localWithoutFeaturing, remoteWithoutFeaturing));
            foreach (string alias in candidate.Aliases ?? new List<string>())
            {
                best = Math.Max(best, TextNormalizer.Similarity(localTitle, alias));
                best = Math.Max(best, TextNormalizer.Similarity(localWithoutFeaturing, TextNormalizer.RemoveFeaturingSuffix(alias)));
            }
            return best;
        }

        private static void ResolveWeights(
            bool hasArtist,
            bool hasAlbum,
            bool hasDuration,
            out double titleWeight,
            out double artistWeight,
            out double albumWeight,
            out double durationWeight)
        {
            titleWeight = 40d;
            artistWeight = hasArtist ? 40d : 0d;
            albumWeight = hasAlbum ? 15d : 0d;
            durationWeight = hasDuration ? 5d : 0d;

            if (!hasArtist && hasAlbum)
            {
                titleWeight = 65d;
                albumWeight = 25d;
                durationWeight = hasDuration ? 10d : 0d;
            }
            else if (hasArtist && !hasAlbum)
            {
                titleWeight = 45d;
                artistWeight = 45d;
                durationWeight = hasDuration ? 10d : 0d;
            }
            else if (!hasArtist && !hasAlbum)
            {
                titleWeight = 90d;
                durationWeight = hasDuration ? 10d : 0d;
            }
        }

        private static double DurationSimilarity(long localMs, long remoteMs)
        {
            if (localMs <= 0 || remoteMs <= 0) return 0d;
            double difference = Math.Abs(localMs - remoteMs) / 1000d;
            if (difference <= 2d) return 1d;
            if (difference <= 5d) return 0.92d;
            if (difference <= 10d) return 0.75d;
            if (difference <= 20d) return 0.45d;
            if (difference <= 40d) return 0.15d;
            return 0d;
        }
    }
}
