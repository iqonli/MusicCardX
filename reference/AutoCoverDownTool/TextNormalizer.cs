using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text;
using System.Text.RegularExpressions;

namespace AutoCoverDownTool.Utils
{
    internal static class TextNormalizer
    {
        private static readonly Regex BracketRegex = new Regex(@"[\[\]【】()（）{}<>《》]", RegexOptions.Compiled);
        private static readonly Regex PunctuationRegex = new Regex(@"[\p{P}\p{S}_]+", RegexOptions.Compiled);
        private static readonly Regex SpaceRegex = new Regex(@"\s+", RegexOptions.Compiled);
        private static readonly Regex FileNameConnectorRegex = new Regex(@"[_\-‐‑‒–—―]+", RegexOptions.Compiled);
        private static readonly Regex ArtistSplitRegex = new Regex(@"\s*(?:/|\\|,|，|、|;|；|&|＆|\+|\bfeat\.?\b|\bft\.?\b|\bfeaturing\b|\bx\b)\s*", RegexOptions.Compiled | RegexOptions.IgnoreCase);

        private static readonly string[] VersionMarkers =
        {
            "live", "现场", "concert", "remix", "acoustic", "不插电", "instrumental",
            "伴奏", "karaoke", "demo", "cover", "翻唱", "radio edit"
        };

        public static string Normalize(string value)
        {
            if (string.IsNullOrWhiteSpace(value)) return string.Empty;

            string normalized = value.Normalize(NormalizationForm.FormKC).ToLowerInvariant();
            normalized = RemoveDiacritics(normalized);
            normalized = BracketRegex.Replace(normalized, " ");
            normalized = PunctuationRegex.Replace(normalized, " ");
            normalized = SpaceRegex.Replace(normalized, " ").Trim();
            return normalized;
        }

        public static string BuildFileNameSearchText(string filePath)
        {
            string fileName = Path.GetFileNameWithoutExtension(filePath ?? string.Empty);
            if (string.IsNullOrWhiteSpace(fileName)) return string.Empty;
            string query = FileNameConnectorRegex.Replace(fileName, " ");
            return SpaceRegex.Replace(query, " ").Trim();
        }

        public static string[] SplitArtists(string value)
        {
            if (string.IsNullOrWhiteSpace(value)) return new string[0];
            return ArtistSplitRegex.Split(value)
                .Select(Normalize)
                .Where(x => !string.IsNullOrWhiteSpace(x))
                .Distinct(StringComparer.OrdinalIgnoreCase)
                .ToArray();
        }

        public static double Similarity(string left, string right)
        {
            string a = Normalize(left);
            string b = Normalize(right);
            if (a.Length == 0 || b.Length == 0) return 0d;
            if (string.Equals(a, b, StringComparison.Ordinal)) return 1d;
            if (a.Contains(b) || b.Contains(a))
            {
                int shorterLength = Math.Min(a.Length, b.Length);
                double lengthRatio = (double)shorterLength / Math.Max(a.Length, b.Length);
                if (shorterLength <= 2) return lengthRatio * 0.70d;
                if (shorterLength == 3) return Math.Max(0.35d, lengthRatio * 0.80d);
                if (lengthRatio >= 0.80d) return 0.94d;
                if (lengthRatio >= 0.65d) return 0.85d;
                if (lengthRatio >= 0.50d) return 0.72d;
                return Math.Max(0.35d, lengthRatio);
            }

            double levenshtein = LevenshteinRatio(a, b);
            double token = TokenDice(a, b);
            return Math.Max(levenshtein, token);
        }

        public static double ArtistSimilarity(string localArtist, IEnumerable<string> candidateArtists)
        {
            string[] local = SplitArtists(localArtist);
            string[] remote = candidateArtists == null
                ? new string[0]
                : candidateArtists.Select(Normalize).Where(x => x.Length > 0).ToArray();

            if (local.Length == 0 || remote.Length == 0)
                return Similarity(localArtist, string.Join(" ", remote));

            double coverageSum = 0d;
            foreach (string localName in local)
            {
                double localBest = 0d;
                foreach (string remoteName in remote)
                    localBest = Math.Max(localBest, ArtistNameSimilarity(localName, remoteName));
                coverageSum += localBest;
            }

            double coverage = coverageSum / local.Length;
            double joined = Similarity(string.Join(" ", local.OrderBy(x => x)), string.Join(" ", remote.OrderBy(x => x)));
            return Math.Max(coverage, joined);
        }

        public static string RemoveFeaturingSuffix(string title)
        {
            if (string.IsNullOrWhiteSpace(title)) return string.Empty;
            string result = title.Trim();
            string lower = result.ToLowerInvariant();
            string[] markers = { "(feat.", "(feat ", "[feat.", "[feat ", " - feat.", " - feat ", " feat.", " ft.", " featuring " };
            int bestIndex = -1;
            foreach (string marker in markers)
            {
                int index = lower.IndexOf(marker, StringComparison.Ordinal);
                if (index >= 0 && (bestIndex < 0 || index < bestIndex)) bestIndex = index;
            }
            return bestIndex > 0 ? result.Substring(0, bestIndex).Trim() : result;
        }

        private static double ArtistNameSimilarity(string left, string right)
        {
            string a = Normalize(left);
            string b = Normalize(right);
            if (a.Length == 0 || b.Length == 0) return 0d;
            if (string.Equals(a, b, StringComparison.Ordinal)) return 1d;
            string shorter = a.Length <= b.Length ? a : b;
            string longer = a.Length <= b.Length ? b : a;
            if (shorter.Length >= 4 && longer.StartsWith(shorter, StringComparison.Ordinal)) return 0.94d;
            if (shorter.Length >= 4 && longer.Contains(shorter)) return 0.88d;
            return Similarity(a, b);
        }

        public static bool HasVersionMismatch(string left, string right)
        {
            string a = Normalize(left);
            string b = Normalize(right);
            foreach (string marker in VersionMarkers)
            {
                bool inA = ContainsMarker(a, marker);
                bool inB = ContainsMarker(b, marker);
                if (inA != inB) return true;
            }
            return false;
        }

        public static bool IsUnknownAlbum(string album)
        {
            string value = Normalize(album);
            return value.Length == 0 || value == "unknown album" || value == "未知专辑" || value == "未分类";
        }

        public static string BuildCacheKey(string artist, string album, string title)
        {
            string normalizedArtist = Normalize(artist);
            string normalizedAlbum = Normalize(album);
            if (!IsUnknownAlbum(album) && normalizedArtist.Length > 0)
                return normalizedArtist + "|album|" + normalizedAlbum;
            return normalizedArtist + "|song|" + Normalize(title) + "|" + normalizedAlbum;
        }

        private static bool ContainsMarker(string normalizedText, string marker)
        {
            if (marker.Any(ch => ch > 127) || marker.Contains(" "))
                return normalizedText.Contains(marker);
            return normalizedText.Split(new[] { ' ' }, StringSplitOptions.RemoveEmptyEntries)
                .Any(token => string.Equals(token, marker, StringComparison.Ordinal));
        }

        private static string RemoveDiacritics(string value)
        {
            string formD = value.Normalize(NormalizationForm.FormD);
            StringBuilder builder = new StringBuilder(formD.Length);
            foreach (char ch in formD)
            {
                UnicodeCategory category = CharUnicodeInfo.GetUnicodeCategory(ch);
                if (category != UnicodeCategory.NonSpacingMark)
                    builder.Append(ch);
            }
            return builder.ToString().Normalize(NormalizationForm.FormC);
        }

        private static double LevenshteinRatio(string a, string b)
        {
            if (a.Length == 0 || b.Length == 0) return 0d;
            int[] previous = new int[b.Length + 1];
            int[] current = new int[b.Length + 1];
            for (int j = 0; j <= b.Length; j++) previous[j] = j;

            for (int i = 1; i <= a.Length; i++)
            {
                current[0] = i;
                for (int j = 1; j <= b.Length; j++)
                {
                    int cost = a[i - 1] == b[j - 1] ? 0 : 1;
                    current[j] = Math.Min(
                        Math.Min(current[j - 1] + 1, previous[j] + 1),
                        previous[j - 1] + cost);
                }
                int[] swap = previous;
                previous = current;
                current = swap;
            }

            int distance = previous[b.Length];
            return 1d - (double)distance / Math.Max(a.Length, b.Length);
        }

        private static double TokenDice(string a, string b)
        {
            HashSet<string> left = new HashSet<string>(a.Split(new[] { ' ' }, StringSplitOptions.RemoveEmptyEntries));
            HashSet<string> right = new HashSet<string>(b.Split(new[] { ' ' }, StringSplitOptions.RemoveEmptyEntries));
            if (left.Count == 0 || right.Count == 0) return 0d;
            int common = left.Count(right.Contains);
            return (2d * common) / (left.Count + right.Count);
        }
    }
}
