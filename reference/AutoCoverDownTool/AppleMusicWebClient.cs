using System;
using System.Collections.Generic;
using System.Globalization;
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
    /// Apple Music 网页端 Catalog 搜索。
    /// 该接口与 music.apple.com 使用同一类目录搜索服务；不添加 iTunes Search API 的固定 3.1 秒等待。
    /// 服务端仍可能返回 429，因此保留自动退避和令牌刷新。
    /// </summary>
    public sealed class AppleMusicWebClient : IDisposable
    {
        private const string UserAgent = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36";
        private static readonly Regex ScriptSourceRegex = new Regex(
            "<script[^>]+src\\s*=\\s*[\\\"'](?<src>[^\\\"']+\\.js(?:\\?[^\\\"']*)?)[\\\"']",
            RegexOptions.IgnoreCase | RegexOptions.CultureInvariant | RegexOptions.Compiled);
        private static readonly Regex JwtRegex = new Regex(
            @"eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}",
            RegexOptions.CultureInvariant | RegexOptions.Compiled);
        private static readonly SemaphoreSlim TokenGate = new SemaphoreSlim(1, 1);
        private static readonly object TokenSync = new object();
        private static string _accessToken;
        private static DateTime _accessTokenValidUntilUtc = DateTime.MinValue;

        private readonly HttpClient _httpClient;
        private bool _disposed;

        public AppleMusicWebClient(int timeoutSeconds)
        {
            HttpClientHandler handler = new HttpClientHandler
            {
                AutomaticDecompression = DecompressionMethods.GZip | DecompressionMethods.Deflate,
                AllowAutoRedirect = true,
                UseCookies = false
            };
            _httpClient = new HttpClient(handler);
            _httpClient.Timeout = TimeSpan.FromSeconds(Math.Max(15, Math.Min(90, timeoutSeconds * 2)));
        }

        public async Task<List<CoverCandidate>> SearchAsync(
            string query,
            int limit,
            string storefront,
            CancellationToken cancellationToken)
        {
            if (string.IsNullOrWhiteSpace(query)) return new List<CoverCandidate>();
            storefront = NormalizeStorefront(storefront);
            limit = Math.Max(1, Math.Min(25, limit));

            cancellationToken.ThrowIfCancellationRequested();
            try
            {
                string token = await EnsureAccessTokenAsync(storefront, false, cancellationToken).ConfigureAwait(false);
                string language = string.Equals(storefront, "cn", StringComparison.OrdinalIgnoreCase)
                    ? "zh-Hans-CN"
                    : "en-US";
                string url = "https://amp-api.music.apple.com/v1/catalog/" + storefront
                    + "/search?term=" + Uri.EscapeDataString(query.Trim())
                    + "&types=songs&include%5Bsongs%5D=albums&limit=" + limit.ToString(CultureInfo.InvariantCulture)
                    + "&l=" + Uri.EscapeDataString(language);

                using (HttpRequestMessage request = new HttpRequestMessage(HttpMethod.Get, url))
                {
                    AddCatalogHeaders(request, token, language);
                    using (HttpResponseMessage response = await _httpClient.SendAsync(
                        request,
                        HttpCompletionOption.ResponseContentRead,
                        cancellationToken).ConfigureAwait(false))
                    {
                        if (response.StatusCode == HttpStatusCode.Unauthorized
                            || response.StatusCode == HttpStatusCode.Forbidden)
                        {
                            InvalidateAccessToken();
                            throw new HttpRequestException("Apple 网页访问令牌已失效。 ");
                        }

                        response.EnsureSuccessStatusCode();
                        string json = await response.Content.ReadAsStringAsync().ConfigureAwait(false);
                        return ParseSearchResponse(json, storefront);
                    }
                }
            }
            catch (OperationCanceledException) { throw; }
            catch (Exception ex)
            {
                throw new HttpRequestException("Apple不限速源搜索失败：" + ex.Message, ex);
            }
        }


        public async Task<AlbumTrackMetadata> GetAlbumMetadataAsync(
            CoverCandidate candidate,
            CancellationToken cancellationToken)
        {
            if (candidate == null) throw new ArgumentNullException("candidate");
            string albumId = StripPrefix(candidate.AlbumId, "appleweb:");
            AlbumTrackMetadata fallback = new AlbumTrackMetadata
            {
                ReleaseDate = AlbumTrackMetadata.NormalizeReleaseDate(candidate.ReleaseDate),
                TrackNumber = candidate.TrackNumber,
                TrackTotal = candidate.TrackTotal,
                DetailSource = "Apple Catalog Search"
            };
            if (string.IsNullOrWhiteSpace(albumId)) return fallback;

            string storefront = NormalizeStorefront(candidate.Storefront);
            string language = string.Equals(storefront, "cn", StringComparison.OrdinalIgnoreCase)
                ? "zh-Hans-CN"
                : "en-US";
            string url = "https://amp-api.music.apple.com/v1/catalog/" + storefront
                + "/albums/" + Uri.EscapeDataString(albumId)
                + "?include=tracks&l=" + Uri.EscapeDataString(language);
            string json = await GetCatalogJsonAsync(url, storefront, language, cancellationToken).ConfigureAwait(false);
            return ParseAlbumResponse(json, candidate, fallback);
        }

        private async Task<string> GetCatalogJsonAsync(
            string url,
            string storefront,
            string language,
            CancellationToken cancellationToken)
        {
            for (int tokenAttempt = 0; tokenAttempt < 2; tokenAttempt++)
            {
                string token = await EnsureAccessTokenAsync(storefront, tokenAttempt > 0, cancellationToken).ConfigureAwait(false);
                using (HttpRequestMessage request = new HttpRequestMessage(HttpMethod.Get, url))
                {
                    AddCatalogHeaders(request, token, language);
                    using (HttpResponseMessage response = await _httpClient.SendAsync(
                        request,
                        HttpCompletionOption.ResponseContentRead,
                        cancellationToken).ConfigureAwait(false))
                    {
                        if ((response.StatusCode == HttpStatusCode.Unauthorized
                            || response.StatusCode == HttpStatusCode.Forbidden)
                            && tokenAttempt == 0)
                        {
                            InvalidateAccessToken();
                            continue;
                        }
                        response.EnsureSuccessStatusCode();
                        return await response.Content.ReadAsStringAsync().ConfigureAwait(false);
                    }
                }
            }
            throw new HttpRequestException("Apple 网页访问令牌刷新后仍不可用。 ");
        }

        private async Task<string> EnsureAccessTokenAsync(
            string storefront,
            bool forceRefresh,
            CancellationToken cancellationToken)
        {
            string cached = GetCachedToken(forceRefresh);
            if (!string.IsNullOrWhiteSpace(cached)) return cached;

            await TokenGate.WaitAsync(cancellationToken).ConfigureAwait(false);
            try
            {
                cached = GetCachedToken(forceRefresh);
                if (!string.IsNullOrWhiteSpace(cached)) return cached;

                string token = await FetchAccessTokenAsync(storefront, cancellationToken).ConfigureAwait(false);
                lock (TokenSync)
                {
                    _accessToken = token;
                    _accessTokenValidUntilUtc = DateTime.UtcNow.AddMinutes(20);
                }
                return token;
            }
            finally
            {
                TokenGate.Release();
            }
        }

        private string GetCachedToken(bool forceRefresh)
        {
            if (forceRefresh) return null;
            lock (TokenSync)
            {
                return !string.IsNullOrWhiteSpace(_accessToken)
                    && _accessTokenValidUntilUtc > DateTime.UtcNow.AddMinutes(1)
                    ? _accessToken
                    : null;
            }
        }

        private async Task<string> FetchAccessTokenAsync(string storefront, CancellationToken cancellationToken)
        {
            Uri pageUri = new Uri("https://music.apple.com/" + storefront + "/new");
            string html = await GetStringAsync(pageUri, cancellationToken).ConfigureAwait(false);
            string token = FindToken(html);
            if (!string.IsNullOrWhiteSpace(token)) return token;

            List<Uri> scripts = ScriptSourceRegex.Matches(html)
                .Cast<Match>()
                .Select(match => match.Groups["src"].Value)
                .Where(value => !string.IsNullOrWhiteSpace(value))
                .Select(value => new Uri(pageUri, WebUtility.HtmlDecode(value)))
                .Distinct(new UriAbsoluteComparer())
                .OrderByDescending(uri => uri.AbsoluteUri.IndexOf("index", StringComparison.OrdinalIgnoreCase) >= 0)
                .ThenByDescending(uri => uri.AbsoluteUri.IndexOf("main", StringComparison.OrdinalIgnoreCase) >= 0)
                .Take(14)
                .ToList();

            if (scripts.Count == 0)
            {
                Match fallback = Regex.Match(
                    html,
                    @"(?<src>(?:https://music\.apple\.com)?/assets/index[^""']+\.js)",
                    RegexOptions.IgnoreCase | RegexOptions.CultureInvariant);
                if (fallback.Success) scripts.Add(new Uri(pageUri, fallback.Groups["src"].Value));
            }

            List<string> errors = new List<string>();
            foreach (Uri script in scripts)
            {
                cancellationToken.ThrowIfCancellationRequested();
                try
                {
                    string javascript = await GetStringAsync(script, cancellationToken).ConfigureAwait(false);
                    token = FindToken(javascript);
                    if (!string.IsNullOrWhiteSpace(token)) return token;
                }
                catch (OperationCanceledException) { throw; }
                catch (Exception ex)
                {
                    errors.Add(ex.Message);
                }
            }

            throw new InvalidOperationException(
                "无法从 music.apple.com 获取网页访问令牌。"
                + (errors.Count == 0 ? string.Empty : " " + string.Join("；", errors.Take(3))));
        }

        private async Task<string> GetStringAsync(Uri url, CancellationToken cancellationToken)
        {
            using (HttpRequestMessage request = new HttpRequestMessage(HttpMethod.Get, url))
            {
                request.Headers.TryAddWithoutValidation("User-Agent", UserAgent);
                request.Headers.TryAddWithoutValidation("Accept", "text/html,application/javascript,application/json;q=0.9,*/*;q=0.5");
                request.Headers.TryAddWithoutValidation("Accept-Language", "zh-CN,zh;q=0.9,en;q=0.6");
                request.Headers.TryAddWithoutValidation("Referer", "https://music.apple.com/");
                using (HttpResponseMessage response = await _httpClient.SendAsync(
                    request,
                    HttpCompletionOption.ResponseContentRead,
                    cancellationToken).ConfigureAwait(false))
                {
                    response.EnsureSuccessStatusCode();
                    return await response.Content.ReadAsStringAsync().ConfigureAwait(false);
                }
            }
        }

        private static string FindToken(string content)
        {
            if (string.IsNullOrWhiteSpace(content)) return null;
            Match match = JwtRegex.Match(content);
            return match.Success ? match.Value : null;
        }

        private static void AddCatalogHeaders(HttpRequestMessage request, string token, string language)
        {
            request.Headers.TryAddWithoutValidation("User-Agent", UserAgent);
            request.Headers.TryAddWithoutValidation("Authorization", "Bearer " + token);
            request.Headers.TryAddWithoutValidation("Origin", "https://music.apple.com");
            request.Headers.TryAddWithoutValidation("Referer", "https://music.apple.com/");
            request.Headers.TryAddWithoutValidation("Accept", "application/json");
            request.Headers.TryAddWithoutValidation("Accept-Language", language + ",zh-CN;q=0.9,en;q=0.6");
        }

        private static List<CoverCandidate> ParseSearchResponse(string json, string storefront)
        {
            JObject root = ParseJsonObject(json, "Apple JSON 接口");
            JArray songs = root["results"] == null
                || root["results"]["songs"] == null
                ? null
                : root["results"]["songs"]["data"] as JArray;
            if (songs == null) return new List<CoverCandidate>();

            List<CoverCandidate> candidates = new List<CoverCandidate>();
            foreach (JToken song in songs)
            {
                JToken attributes = song["attributes"];
                if (attributes == null) continue;
                string title = TokenString(attributes["name"]);
                string artist = TokenString(attributes["artistName"]);
                string album = TokenString(attributes["albumName"]);
                string artworkUrl = attributes["artwork"] == null
                    ? null
                    : TokenString(attributes["artwork"]["url"]);
                if (string.IsNullOrWhiteSpace(title)) continue;
                if (!AppleMusicClient.IsStaticMusicArtworkUrl(artworkUrl)) continue;

                string id = TokenString(song["id"]);
                string albumId = null;
                JArray albumData = song["relationships"] == null
                    || song["relationships"]["albums"] == null
                    ? null
                    : song["relationships"]["albums"]["data"] as JArray;
                if (albumData != null && albumData.Count > 0) albumId = TokenString(albumData[0]["id"]);

                candidates.Add(new CoverCandidate
                {
                    Provider = "AppleWeb",
                    Storefront = storefront,
                    SongId = "appleweb:" + (string.IsNullOrWhiteSpace(id) ? title + "|" + artist : id),
                    Title = title,
                    Artists = SplitArtists(artist),
                    AlbumId = string.IsNullOrWhiteSpace(albumId) ? null : "appleweb:" + albumId,
                    Album = album ?? string.Empty,
                    CoverUrl = artworkUrl.Replace("http://", "https://"),
                    DurationMs = TokenLong(attributes["durationInMillis"]),
                    ReleaseDate = AlbumTrackMetadata.NormalizeReleaseDate(TokenString(attributes["releaseDate"])),
                    TrackNumber = (int)TokenLong(attributes["trackNumber"]),
                    TrackTotal = (int)TokenLong(attributes["trackCount"]),
                    Source = "Apple不限速·" + storefront.ToUpperInvariant()
                });
            }

            return candidates
                .GroupBy(candidate => candidate.SongId, StringComparer.OrdinalIgnoreCase)
                .Select(group => group.First())
                .ToList();
        }


        private static AlbumTrackMetadata ParseAlbumResponse(
            string json,
            CoverCandidate candidate,
            AlbumTrackMetadata fallback)
        {
            JObject root = ParseJsonObject(json, "Apple JSON 接口");
            JArray albums = root["data"] as JArray;
            if (albums == null || albums.Count == 0) return fallback;

            JToken album = albums[0];
            JToken albumAttributes = album["attributes"];
            AlbumTrackMetadata metadata = new AlbumTrackMetadata
            {
                ReleaseDate = fallback.ReleaseDate,
                TrackNumber = fallback.TrackNumber,
                TrackTotal = fallback.TrackTotal,
                DetailSource = "Apple Catalog Album"
            };
            if (albumAttributes != null)
            {
                string date = AlbumTrackMetadata.NormalizeReleaseDate(TokenString(albumAttributes["releaseDate"]));
                if (!string.IsNullOrWhiteSpace(date)) metadata.ReleaseDate = date;
                int explicitTotal = (int)TokenLong(albumAttributes["trackCount"]);
                if (explicitTotal > metadata.TrackTotal) metadata.TrackTotal = explicitTotal;
            }

            JArray tracks = album["relationships"] == null
                || album["relationships"]["tracks"] == null
                ? null
                : album["relationships"]["tracks"]["data"] as JArray;
            if (tracks == null) return metadata;

            string expectedId = StripPrefix(candidate.SongId, "appleweb:");
            int maximumTrack = 0;
            int trackCount = 0;
            JToken bestTrack = null;
            double bestScore = -1d;
            foreach (JToken track in tracks)
            {
                JToken attributes = track["attributes"];
                if (attributes == null) continue;
                trackCount++;
                int number = (int)TokenLong(attributes["trackNumber"]);
                if (number > maximumTrack) maximumTrack = number;
                string id = TokenString(track["id"]);
                if (!string.IsNullOrWhiteSpace(expectedId)
                    && string.Equals(id, expectedId, StringComparison.OrdinalIgnoreCase))
                {
                    bestTrack = track;
                    bestScore = 10d;
                    continue;
                }

                double score = TextNormalizer.Similarity(candidate.Title, TokenString(attributes["name"])) * 0.65d
                    + TextNormalizer.ArtistSimilarity(candidate.ArtistText, SplitArtists(TokenString(attributes["artistName"]))) * 0.35d;
                if (score > bestScore)
                {
                    bestScore = score;
                    bestTrack = track;
                }
            }

            metadata.TrackTotal = Math.Max(metadata.TrackTotal, Math.Max(trackCount, maximumTrack));
            if (bestTrack != null && bestScore >= 0.55d)
            {
                JToken attributes = bestTrack["attributes"];
                int number = (int)TokenLong(attributes["trackNumber"]);
                if (number > 0) metadata.TrackNumber = number;
                int total = (int)TokenLong(attributes["trackCount"]);
                if (total > metadata.TrackTotal) metadata.TrackTotal = total;
                string date = AlbumTrackMetadata.NormalizeReleaseDate(TokenString(attributes["releaseDate"]));
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
                .Select(value => value.Trim())
                .Where(value => value.Length > 0)
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

        private static async Task DelayForRetry(
            int attempt,
            HttpResponseMessage response,
            CancellationToken cancellationToken)
        {
            TimeSpan delay = TimeSpan.FromMilliseconds(1200 * (attempt + 1));
            if (response != null && response.Headers.RetryAfter != null)
            {
                if (response.Headers.RetryAfter.Delta.HasValue)
                    delay = response.Headers.RetryAfter.Delta.Value;
                else if (response.Headers.RetryAfter.Date.HasValue)
                    delay = response.Headers.RetryAfter.Date.Value.UtcDateTime - DateTime.UtcNow;
            }
            if (delay < TimeSpan.FromMilliseconds(300)) delay = TimeSpan.FromMilliseconds(300);
            if (delay > TimeSpan.FromSeconds(30)) delay = TimeSpan.FromSeconds(30);
            await Task.Delay(delay, cancellationToken).ConfigureAwait(false);
        }

        private static string TokenString(JToken token)
        {
            return token == null || token.Type == JTokenType.Null ? null : token.ToString();
        }

        private static long TokenLong(JToken token)
        {
            if (token == null || token.Type == JTokenType.Null) return 0L;
            long value;
            return long.TryParse(token.ToString(), NumberStyles.Integer, CultureInfo.InvariantCulture, out value)
                ? value
                : 0L;
        }

        private static void InvalidateAccessToken()
        {
            lock (TokenSync)
            {
                _accessToken = null;
                _accessTokenValidUntilUtc = DateTime.MinValue;
            }
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
            _httpClient.Dispose();
            _disposed = true;
        }

        private sealed class UriAbsoluteComparer : IEqualityComparer<Uri>
        {
            public bool Equals(Uri x, Uri y)
            {
                if (ReferenceEquals(x, y)) return true;
                if (x == null || y == null) return false;
                return string.Equals(x.AbsoluteUri, y.AbsoluteUri, StringComparison.OrdinalIgnoreCase);
            }

            public int GetHashCode(Uri obj)
            {
                return obj == null ? 0 : StringComparer.OrdinalIgnoreCase.GetHashCode(obj.AbsoluteUri);
            }
        }
    }
}
