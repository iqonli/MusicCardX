using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Net;
using System.Net.Http;
using System.Text.RegularExpressions;
using System.Threading;
using System.Threading.Tasks;
using AutoCoverDownTool.Models;
using AutoCoverDownTool.Utils;
using Newtonsoft.Json.Linq;

namespace AutoCoverDownTool.Services
{
    /// <summary>
    /// Apple 音乐目录搜索与静态专辑封面下载。
    /// 搜索使用无需开发者令牌的官方 iTunes Search API；只请求 song 实体，默认使用中国区商店。
    /// </summary>
    public sealed class AppleMusicClient : IDisposable
    {
        private const string SearchUserAgent = "AutoCoverDownTool/0.8.12 (Windows NT 10.0; Win64; x64)";
        private const string ImageUserAgent = "Mozilla/5.0 (Windows NT 10.0; Win64; x64; Trident/7.0; rv:11.0) like Gecko";
        private const int MinimumSearchIntervalMilliseconds = 3100;
        private const long MaximumImageBytes = 96L * 1024L * 1024L;

        private static readonly Regex ArtworkSizeSegmentRegex = new Regex(
            @"/(?:\{w\}|\d+)x(?:\{h\}|\d+)(?:bb)?(?:-[^./?]+)?\.(?:webp|jpe?g|png)$",
            RegexOptions.IgnoreCase | RegexOptions.CultureInvariant | RegexOptions.Compiled);

        private static readonly Regex ArtworkFilenameSizeRegex = new Regex(
            @"\.(?:\{w\}|\d+)x(?:\{h\}|\d+)(?:bb)?(?:-\d+)?\.(?:webp|jpe?g|png)$",
            RegexOptions.IgnoreCase | RegexOptions.CultureInvariant | RegexOptions.Compiled);

        private static readonly Regex StaticMusicPathRegex = new Regex(
            @"/Music\d*(?:/|$)",
            RegexOptions.IgnoreCase | RegexOptions.CultureInvariant | RegexOptions.Compiled);

        private static readonly SemaphoreSlim SearchRateGate = new SemaphoreSlim(1, 1);
        private static readonly object SearchTimeSync = new object();
        private static DateTime _lastSearchRequestUtc = DateTime.MinValue;

        private readonly HttpClient _searchHttpClient;
        private readonly HttpClient _imageHttpClient;
        private bool _disposed;

        static AppleMusicClient()
        {
            try
            {
                ServicePointManager.SecurityProtocol |= SecurityProtocolType.Tls12;
                if (ServicePointManager.DefaultConnectionLimit < 16)
                    ServicePointManager.DefaultConnectionLimit = 16;
            }
            catch
            {
                // 使用系统默认网络设置。
            }
        }

        public AppleMusicClient(int timeoutSeconds)
        {
            HttpClientHandler searchHandler = new HttpClientHandler
            {
                AutomaticDecompression = DecompressionMethods.GZip | DecompressionMethods.Deflate,
                AllowAutoRedirect = true,
                UseCookies = false
            };
            _searchHttpClient = new HttpClient(searchHandler);
            _searchHttpClient.Timeout = TimeSpan.FromSeconds(Math.Max(10, timeoutSeconds));

            HttpClientHandler imageHandler = new HttpClientHandler
            {
                AutomaticDecompression = DecompressionMethods.None,
                AllowAutoRedirect = true,
                UseCookies = false
            };
            _imageHttpClient = new HttpClient(imageHandler);
            _imageHttpClient.Timeout = TimeSpan.FromSeconds(Math.Max(60, Math.Min(300, timeoutSeconds * 3)));
        }

        public async Task<List<CoverCandidate>> SearchAsync(
            string query,
            int limit,
            string storefront,
            CancellationToken cancellationToken)
        {
            if (string.IsNullOrWhiteSpace(query)) return new List<CoverCandidate>();
            limit = Math.Max(1, Math.Min(200, limit));
            storefront = NormalizeStorefront(storefront);

            string url = "https://itunes.apple.com/search?term=" + Uri.EscapeDataString(query.Trim())
                + "&country=" + Uri.EscapeDataString(storefront)
                + "&media=music&entity=song&limit=" + limit.ToString(CultureInfo.InvariantCulture)
                + "&explicit=Yes";

            cancellationToken.ThrowIfCancellationRequested();
            await WaitForSearchSlotAsync(cancellationToken).ConfigureAwait(false);
            try
            {
                using (HttpRequestMessage request = new HttpRequestMessage(HttpMethod.Get, url))
                {
                    request.Headers.TryAddWithoutValidation("User-Agent", SearchUserAgent);
                    request.Headers.TryAddWithoutValidation("Accept", "application/json,text/javascript;q=0.9,*/*;q=0.1");
                    request.Headers.TryAddWithoutValidation("Accept-Language", "zh-CN,zh;q=0.9,en;q=0.5");
                    request.Headers.TryAddWithoutValidation("Cache-Control", "no-cache");

                    using (HttpResponseMessage response = await _searchHttpClient.SendAsync(
                        request,
                        HttpCompletionOption.ResponseContentRead,
                        cancellationToken).ConfigureAwait(false))
                    {
                        response.EnsureSuccessStatusCode();
                        string json = await response.Content.ReadAsStringAsync().ConfigureAwait(false);
                        return ParseSearchResponse(json, storefront);
                    }
                }
            }
            catch (OperationCanceledException) { throw; }
            catch (Exception ex)
            {
                throw new HttpRequestException("Apple Music 搜索失败：" + ex.Message, ex);
            }
        }


        public async Task<AlbumTrackMetadata> GetAlbumMetadataAsync(
            CoverCandidate candidate,
            CancellationToken cancellationToken)
        {
            if (candidate == null) throw new ArgumentNullException("candidate");
            string albumId = StripPrefix(candidate.AlbumId, "apple:");
            if (string.IsNullOrWhiteSpace(albumId))
            {
                return new AlbumTrackMetadata
                {
                    ReleaseDate = AlbumTrackMetadata.NormalizeReleaseDate(candidate.ReleaseDate),
                    TrackNumber = candidate.TrackNumber,
                    TrackTotal = candidate.TrackTotal,
                    DetailSource = "Apple Search"
                };
            }

            string storefront = NormalizeStorefront(candidate.Storefront);
            string url = "https://itunes.apple.com/lookup?id=" + Uri.EscapeDataString(albumId)
                + "&country=" + Uri.EscapeDataString(storefront)
                + "&entity=song&explicit=Yes";

            await WaitForSearchSlotAsync(cancellationToken).ConfigureAwait(false);
            using (HttpRequestMessage request = new HttpRequestMessage(HttpMethod.Get, url))
            {
                request.Headers.TryAddWithoutValidation("User-Agent", SearchUserAgent);
                request.Headers.TryAddWithoutValidation("Accept", "application/json,*/*;q=0.1");
                request.Headers.TryAddWithoutValidation("Accept-Language", "zh-CN,zh;q=0.9,en;q=0.5");
                using (HttpResponseMessage response = await _searchHttpClient.SendAsync(
                    request,
                    HttpCompletionOption.ResponseContentRead,
                    cancellationToken).ConfigureAwait(false))
                {
                    response.EnsureSuccessStatusCode();
                    string json = await response.Content.ReadAsStringAsync().ConfigureAwait(false);
                    return ParseAlbumLookup(json, candidate);
                }
            }
        }

        public async Task<byte[]> DownloadArtworkAsync(
            string artworkUrl,
            int maximumDimension,
            CancellationToken cancellationToken)
        {
            if (!IsStaticMusicArtworkUrl(artworkUrl))
                throw new InvalidOperationException("Apple 候选不是静态 Music 封面，已拒绝下载。 ");

            List<string> urls = BuildArtworkDownloadUrls(artworkUrl, maximumDimension);
            List<string> errors = new List<string>();

            for (int urlIndex = 0; urlIndex < urls.Count; urlIndex++)
            {
                string url = urls[urlIndex];
                int attempts = urlIndex == 0 ? 2 : 1;
                for (int attempt = 0; attempt < attempts; attempt++)
                {
                    cancellationToken.ThrowIfCancellationRequested();
                    try
                    {
                        using (CancellationTokenSource timeout = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken))
                        using (HttpRequestMessage request = new HttpRequestMessage(HttpMethod.Get, url))
                        {
                            timeout.CancelAfter(TimeSpan.FromSeconds(28));
                            request.Headers.TryAddWithoutValidation("User-Agent", ImageUserAgent);
                            request.Headers.TryAddWithoutValidation("Accept", "image/png,image/jpeg;q=0.9,application/octet-stream;q=0.3,*/*;q=0.1");
                            request.Headers.TryAddWithoutValidation("Accept-Encoding", "identity");
                            request.Headers.TryAddWithoutValidation("Accept-Language", "zh-CN,zh;q=0.9,en;q=0.5");
                            request.Headers.TryAddWithoutValidation("Referer", "https://music.apple.com/");

                            using (HttpResponseMessage response = await _imageHttpClient.SendAsync(
                                request,
                                HttpCompletionOption.ResponseHeadersRead,
                                timeout.Token).ConfigureAwait(false))
                            {
                                if (IsTransient(response.StatusCode) && attempt + 1 < attempts)
                                {
                                    await DelayForRetry(attempt, cancellationToken).ConfigureAwait(false);
                                    continue;
                                }

                                response.EnsureSuccessStatusCode();
                                if (response.Content.Headers.ContentLength.HasValue
                                    && response.Content.Headers.ContentLength.Value > MaximumImageBytes)
                                    throw new InvalidOperationException("Apple 封面超过 96 MB，已停止下载。 ");

                                byte[] bytes = await ReadLimitedAsync(response.Content, MaximumImageBytes, timeout.Token).ConfigureAwait(false);
                                if (bytes == null || bytes.Length < 64)
                                    throw new InvalidDataException("Apple 封面响应为空或过短。 ");
                                if (!LooksLikeSupportedImage(bytes))
                                    throw new InvalidDataException("Apple CDN 未返回 JPEG 或 PNG 图片。 ");
                                return bytes;
                            }
                        }
                    }
                    catch (OperationCanceledException)
                    {
                        cancellationToken.ThrowIfCancellationRequested();
                        errors.Add("超时：" + url);
                    }
                    catch (Exception ex)
                    {
                        errors.Add(ex.Message + "｜" + url);
                    }
                }
            }

            throw new HttpRequestException("Apple 静态封面所有尺寸均下载失败：" + string.Join("；", errors.Take(5)));
        }

        public static bool IsStaticMusicArtworkUrl(string url)
        {
            if (string.IsNullOrWhiteSpace(url)) return false;
            Uri uri;
            if (!Uri.TryCreate(url.Trim(), UriKind.Absolute, out uri)) return false;
            if (uri.Scheme != Uri.UriSchemeHttp && uri.Scheme != Uri.UriSchemeHttps) return false;

            string path = Uri.UnescapeDataString(uri.AbsolutePath ?? string.Empty);
            if (path.IndexOf("/Video", StringComparison.OrdinalIgnoreCase) >= 0) return false;
            if (path.IndexOf("Preview_Image", StringComparison.OrdinalIgnoreCase) >= 0) return false;
            if (path.IndexOf("Intermediate_nonvideo", StringComparison.OrdinalIgnoreCase) >= 0) return false;
            if (path.IndexOf("nonvideo", StringComparison.OrdinalIgnoreCase) >= 0) return false;
            return StaticMusicPathRegex.IsMatch(path);
        }

        public static string BuildArtworkUrl(string sourceUrl, int size, string format)
        {
            if (string.IsNullOrWhiteSpace(sourceUrl)) return sourceUrl;
            if (size <= 0) size = 4000;
            format = string.Equals(format, "jpg", StringComparison.OrdinalIgnoreCase) ? "jpg" : "png";

            Uri source;
            if (!Uri.TryCreate(sourceUrl.Trim(), UriKind.Absolute, out source)) return sourceUrl;
            string scheme = source.Scheme == Uri.UriSchemeHttp ? Uri.UriSchemeHttps : source.Scheme;
            string baseUrl = scheme + "://" + source.Authority + Uri.UnescapeDataString(source.AbsolutePath);
            string replacement = "/" + size.ToString(CultureInfo.InvariantCulture)
                + "x" + size.ToString(CultureInfo.InvariantCulture) + "." + format;

            string transformed = ArtworkSizeSegmentRegex.Replace(baseUrl, replacement);
            if (string.Equals(transformed, baseUrl, StringComparison.Ordinal))
            {
                string filenameReplacement = "." + size.ToString(CultureInfo.InvariantCulture)
                    + "x" + size.ToString(CultureInfo.InvariantCulture) + "." + format;
                transformed = ArtworkFilenameSizeRegex.Replace(baseUrl, filenameReplacement);
            }
            if (string.Equals(transformed, baseUrl, StringComparison.Ordinal))
            {
                if (!transformed.EndsWith("/", StringComparison.Ordinal)) transformed += "/";
                transformed += size.ToString(CultureInfo.InvariantCulture)
                    + "x" + size.ToString(CultureInfo.InvariantCulture) + "." + format;
            }
            return transformed;
        }

        private static List<string> BuildArtworkDownloadUrls(string sourceUrl, int maximumDimension)
        {
            List<int> sizes = new List<int>();
            if (maximumDimension > 0)
            {
                sizes.Add(Math.Max(1, maximumDimension));
            }
            else
            {
                sizes.AddRange(new[] { 4000, 3000, 2000, 1200 });
            }

            List<string> urls = new List<string>();
            foreach (int size in sizes.Distinct())
            {
                urls.Add(BuildArtworkUrl(sourceUrl, size, "png"));
                urls.Add(BuildArtworkUrlWithBbSuffix(sourceUrl, size, "jpg"));
                urls.Add(BuildArtworkUrl(sourceUrl, size, "jpg"));
            }

            string lower = sourceUrl.ToLowerInvariant();
            if (lower.EndsWith(".jpg", StringComparison.Ordinal)
                || lower.EndsWith(".jpeg", StringComparison.Ordinal)
                || lower.EndsWith(".png", StringComparison.Ordinal))
                urls.Add(sourceUrl.Replace("http://", "https://"));

            return urls
                .Where(x => !string.IsNullOrWhiteSpace(x) && IsStaticMusicArtworkUrl(x))
                .Distinct(StringComparer.OrdinalIgnoreCase)
                .ToList();
        }

        private static string BuildArtworkUrlWithBbSuffix(string sourceUrl, int size, string format)
        {
            Uri source;
            if (!Uri.TryCreate(sourceUrl.Trim(), UriKind.Absolute, out source)) return sourceUrl;
            string scheme = source.Scheme == Uri.UriSchemeHttp ? Uri.UriSchemeHttps : source.Scheme;
            string baseUrl = scheme + "://" + source.Authority + Uri.UnescapeDataString(source.AbsolutePath);
            string replacement = "/" + size.ToString(CultureInfo.InvariantCulture)
                + "x" + size.ToString(CultureInfo.InvariantCulture) + "bb." + format;
            string transformed = ArtworkSizeSegmentRegex.Replace(baseUrl, replacement);
            if (string.Equals(transformed, baseUrl, StringComparison.Ordinal))
            {
                string filenameReplacement = "." + size.ToString(CultureInfo.InvariantCulture)
                    + "x" + size.ToString(CultureInfo.InvariantCulture) + "bb." + format;
                transformed = ArtworkFilenameSizeRegex.Replace(baseUrl, filenameReplacement);
            }
            if (string.Equals(transformed, baseUrl, StringComparison.Ordinal))
            {
                if (!transformed.EndsWith("/", StringComparison.Ordinal)) transformed += "/";
                transformed += size.ToString(CultureInfo.InvariantCulture)
                    + "x" + size.ToString(CultureInfo.InvariantCulture) + "bb." + format;
            }
            return transformed;
        }

        private async Task WaitForSearchSlotAsync(CancellationToken cancellationToken)
        {
            await SearchRateGate.WaitAsync(cancellationToken).ConfigureAwait(false);
            try
            {
                TimeSpan delay;
                lock (SearchTimeSync)
                {
                    delay = TimeSpan.FromMilliseconds(MinimumSearchIntervalMilliseconds)
                        - (DateTime.UtcNow - _lastSearchRequestUtc);
                }
                if (delay > TimeSpan.Zero)
                    await Task.Delay(delay, cancellationToken).ConfigureAwait(false);
                lock (SearchTimeSync)
                {
                    _lastSearchRequestUtc = DateTime.UtcNow;
                }
            }
            finally
            {
                SearchRateGate.Release();
            }
        }

        private static List<CoverCandidate> ParseSearchResponse(string json, string storefront)
        {
            JObject root = ParseJsonObject(json, "Apple JSON 接口");
            JArray results = root["results"] as JArray;
            if (results == null) return new List<CoverCandidate>();

            List<CoverCandidate> candidates = new List<CoverCandidate>();
            foreach (JToken result in results)
            {
                string wrapperType = TokenString(result["wrapperType"]);
                string kind = TokenString(result["kind"]);
                if (!string.Equals(wrapperType, "track", StringComparison.OrdinalIgnoreCase)) continue;
                if (!string.Equals(kind, "song", StringComparison.OrdinalIgnoreCase)) continue;

                string artworkUrl = TokenString(result["artworkUrl100"])
                    ?? TokenString(result["artworkUrl60"]);
                if (!IsStaticMusicArtworkUrl(artworkUrl)) continue;

                string title = TokenString(result["trackName"]);
                if (string.IsNullOrWhiteSpace(title)) continue;
                string artistName = TokenString(result["artistName"]);
                string album = TokenString(result["collectionName"]);
                string trackId = TokenString(result["trackId"]);
                string collectionId = TokenString(result["collectionId"]);

                List<string> aliases = new List<string>();
                string censored = TokenString(result["trackCensoredName"]);
                if (!string.IsNullOrWhiteSpace(censored)
                    && !string.Equals(censored, title, StringComparison.OrdinalIgnoreCase))
                    aliases.Add(censored);

                candidates.Add(new CoverCandidate
                {
                    Provider = "Apple",
                    Storefront = storefront,
                    SongId = "apple:" + (trackId ?? title + "|" + artistName),
                    Title = title,
                    Aliases = aliases,
                    Artists = SplitArtists(artistName),
                    AlbumId = string.IsNullOrWhiteSpace(collectionId) ? null : "apple:" + collectionId,
                    Album = album ?? string.Empty,
                    CoverUrl = artworkUrl.Replace("http://", "https://"),
                    DurationMs = TokenLong(result["trackTimeMillis"]),
                    ReleaseDate = AlbumTrackMetadata.NormalizeReleaseDate(TokenString(result["releaseDate"])),
                    TrackNumber = (int)TokenLong(result["trackNumber"]),
                    TrackTotal = (int)TokenLong(result["trackCount"]),
                    Source = "Apple·" + storefront.ToUpperInvariant()
                });
            }

            return candidates
                .GroupBy(x => x.SongId, StringComparer.OrdinalIgnoreCase)
                .Select(x => x.First())
                .ToList();
        }


        private static AlbumTrackMetadata ParseAlbumLookup(string json, CoverCandidate candidate)
        {
            JObject root = ParseJsonObject(json, "Apple JSON 接口");
            JArray results = root["results"] as JArray;
            AlbumTrackMetadata metadata = new AlbumTrackMetadata
            {
                ReleaseDate = AlbumTrackMetadata.NormalizeReleaseDate(candidate.ReleaseDate),
                TrackNumber = candidate.TrackNumber,
                TrackTotal = candidate.TrackTotal,
                DetailSource = "Apple Lookup"
            };
            if (results == null) return metadata;

            string expectedTrackId = StripPrefix(candidate.SongId, "apple:");
            int maximumTrack = 0;
            int songCount = 0;
            JToken bestTrack = null;
            double bestScore = -1d;

            foreach (JToken result in results)
            {
                string wrapperType = TokenString(result["wrapperType"]);
                if (string.Equals(wrapperType, "collection", StringComparison.OrdinalIgnoreCase))
                {
                    string date = AlbumTrackMetadata.NormalizeReleaseDate(TokenString(result["releaseDate"]));
                    if (!string.IsNullOrWhiteSpace(date)) metadata.ReleaseDate = date;
                    int collectionTrackCount = (int)TokenLong(result["trackCount"]);
                    if (collectionTrackCount > metadata.TrackTotal) metadata.TrackTotal = collectionTrackCount;
                    continue;
                }

                if (!string.Equals(wrapperType, "track", StringComparison.OrdinalIgnoreCase)) continue;
                if (!string.Equals(TokenString(result["kind"]), "song", StringComparison.OrdinalIgnoreCase)) continue;
                songCount++;
                int trackNumber = (int)TokenLong(result["trackNumber"]);
                if (trackNumber > maximumTrack) maximumTrack = trackNumber;

                string resultId = TokenString(result["trackId"]);
                if (!string.IsNullOrWhiteSpace(expectedTrackId)
                    && string.Equals(resultId, expectedTrackId, StringComparison.OrdinalIgnoreCase))
                {
                    bestTrack = result;
                    bestScore = 10d;
                    continue;
                }

                double score = TextNormalizer.Similarity(candidate.Title, TokenString(result["trackName"])) * 0.65d
                    + TextNormalizer.ArtistSimilarity(candidate.ArtistText, SplitArtists(TokenString(result["artistName"]))) * 0.35d;
                if (score > bestScore)
                {
                    bestScore = score;
                    bestTrack = result;
                }
            }

            metadata.TrackTotal = Math.Max(metadata.TrackTotal, Math.Max(songCount, maximumTrack));
            if (bestTrack != null && bestScore >= 0.55d)
            {
                int track = (int)TokenLong(bestTrack["trackNumber"]);
                if (track > 0) metadata.TrackNumber = track;
                int total = (int)TokenLong(bestTrack["trackCount"]);
                if (total > metadata.TrackTotal) metadata.TrackTotal = total;
                string date = AlbumTrackMetadata.NormalizeReleaseDate(TokenString(bestTrack["releaseDate"]));
                if (string.IsNullOrWhiteSpace(metadata.ReleaseDate) && !string.IsNullOrWhiteSpace(date)) metadata.ReleaseDate = date;
            }
            return metadata;
        }

        private static string StripPrefix(string value, string prefix)
        {
            if (string.IsNullOrWhiteSpace(value)) return null;
            return value.StartsWith(prefix, StringComparison.OrdinalIgnoreCase)
                ? value.Substring(prefix.Length)
                : value;
        }

        private static List<string> SplitArtists(string artistName)
        {
            if (string.IsNullOrWhiteSpace(artistName)) return new List<string>();
            string normalized = artistName
                .Replace(" feat. ", " / ")
                .Replace(" featuring ", " / ")
                .Replace(" & ", " / ")
                .Replace("、", " / ")
                .Replace("，", " / ")
                .Replace(", ", " / ");
            return normalized
                .Split(new[] { " / " }, StringSplitOptions.RemoveEmptyEntries)
                .Select(x => x.Trim())
                .Where(x => x.Length > 0)
                .Distinct(StringComparer.OrdinalIgnoreCase)
                .ToList();
        }

        private static string NormalizeStorefront(string storefront)
        {
            string value = string.IsNullOrWhiteSpace(storefront) ? "cn" : storefront.Trim().ToLowerInvariant();
            return Regex.IsMatch(value, "^[a-z]{2}$", RegexOptions.CultureInvariant) ? value : "cn";
        }

        private static bool IsTransient(HttpStatusCode statusCode)
        {
            int code = (int)statusCode;
            return code == 408 || code == 429 || code >= 500;
        }

        private static Task DelayForRetry(int attempt, CancellationToken cancellationToken)
        {
            return Task.Delay(800 * (attempt + 1), cancellationToken);
        }

        private static async Task<byte[]> ReadLimitedAsync(
            HttpContent content,
            long maximumBytes,
            CancellationToken cancellationToken)
        {
            using (Stream input = await content.ReadAsStreamAsync().ConfigureAwait(false))
            using (MemoryStream output = new MemoryStream())
            {
                byte[] buffer = new byte[81920];
                while (true)
                {
                    cancellationToken.ThrowIfCancellationRequested();
                    int read = await input.ReadAsync(buffer, 0, buffer.Length, cancellationToken).ConfigureAwait(false);
                    if (read <= 0) break;
                    if (output.Length + read > maximumBytes)
                        throw new InvalidOperationException("下载内容超过允许大小。 ");
                    output.Write(buffer, 0, read);
                }
                return output.ToArray();
            }
        }

        private static bool LooksLikeSupportedImage(byte[] bytes)
        {
            if (bytes == null) return false;
            if (bytes.Length >= 3 && bytes[0] == 0xFF && bytes[1] == 0xD8 && bytes[2] == 0xFF)
                return true;
            return bytes.Length >= 8
                && bytes[0] == 0x89 && bytes[1] == 0x50 && bytes[2] == 0x4E && bytes[3] == 0x47
                && bytes[4] == 0x0D && bytes[5] == 0x0A && bytes[6] == 0x1A && bytes[7] == 0x0A;
        }

        private static string TokenString(JToken token)
        {
            if (token == null || token.Type == JTokenType.Null) return null;
            return token.ToString();
        }

        private static long TokenLong(JToken token)
        {
            if (token == null || token.Type == JTokenType.Null) return 0L;
            long value;
            return long.TryParse(token.ToString(), NumberStyles.Integer, CultureInfo.InvariantCulture, out value)
                ? value
                : 0L;
        }

        private static JObject ParseJsonObject(string json, string context)
        {
            if (string.IsNullOrWhiteSpace(json))
                throw new HttpRequestException(context + " 返回空响应");
            string normalized = json.TrimStart('\uFEFF', ' ', '\t', '\r', '\n');
            try
            {
                return JObject.Parse(normalized);
            }
            catch (Exception ex)
            {
                string snippet = normalized.Replace("\r", " ").Replace("\n", " ").Replace("\t", " ").Trim();
                if (snippet.Length > 180) snippet = snippet.Substring(0, 180) + "…";
                throw new HttpRequestException(context + " 返回的不是有效 JSON｜响应=" + snippet, ex);
            }
        }

        public void Dispose()
        {
            if (_disposed) return;
            _imageHttpClient.Dispose();
            _searchHttpClient.Dispose();
            _disposed = true;
        }
    }
}
