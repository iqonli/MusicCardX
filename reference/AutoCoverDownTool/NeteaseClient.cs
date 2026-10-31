using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Net;
using System.Net.Http;
using System.Text;
using System.Threading;
using System.Threading.Tasks;
using AutoCoverDownTool.Models;
using AutoCoverDownTool.Utils;
using Newtonsoft.Json;
using Newtonsoft.Json.Linq;

namespace AutoCoverDownTool.Services
{
    public sealed class NeteaseClient : IDisposable
    {
        private const string PcUserAgent = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/129.0.0.0 Safari/537.36";
        private const string ImageUserAgent = "Mozilla/5.0 (Windows NT 10.0; Win64; x64; Trident/7.0; rv:11.0) like Gecko";
        private const string MobileUserAgent = "Mozilla/5.0 (Linux; Android 9; PCT-AL10) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/70.0.3538.64 Mobile Safari/537.36";
        private static readonly TimeSpan NeteaseReleaseTimeZoneOffset = TimeSpan.FromHours(8);

        private readonly HttpClient _httpClient;
        private readonly HttpClient _imageHttpClient;
        private volatile bool _preferEapiFirst;
        private bool _disposed;

        static NeteaseClient()
        {
            try
            {
                ServicePointManager.SecurityProtocol |= SecurityProtocolType.Tls12;
                ServicePointManager.Expect100Continue = false;
                if (ServicePointManager.DefaultConnectionLimit < 16)
                    ServicePointManager.DefaultConnectionLimit = 16;
            }
            catch
            {
                // 使用系统默认网络设置。
            }
        }

        public NeteaseClient(int timeoutSeconds)
        {
            HttpClientHandler handler = new HttpClientHandler
            {
                AutomaticDecompression = DecompressionMethods.GZip | DecompressionMethods.Deflate,
                UseCookies = true,
                CookieContainer = new CookieContainer()
            };
            _httpClient = new HttpClient(handler);
            _httpClient.Timeout = TimeSpan.FromSeconds(Math.Max(8, timeoutSeconds));

            HttpClientHandler imageHandler = new HttpClientHandler
            {
                // 图片响应不应压缩。显式关闭自动解压可避开部分 CDN 错误标记 gzip 的响应。
                AutomaticDecompression = DecompressionMethods.None,
                UseCookies = false,
                AllowAutoRedirect = true
            };
            _imageHttpClient = new HttpClient(imageHandler);
            _imageHttpClient.Timeout = TimeSpan.FromSeconds(Math.Max(60, Math.Min(300, timeoutSeconds * 2)));
        }

        public async Task<List<CoverCandidate>> SearchAsync(string query, int limit, CancellationToken cancellationToken)
        {
            if (string.IsNullOrWhiteSpace(query)) return new List<CoverCandidate>();
            limit = Math.Max(1, Math.Min(50, limit));

            Exception lastError = null;
            // 与参考播放器一致：旧 Web 与新版 EAPI 会根据上一轮成功/失败动态调整优先级；
            // WEAPI 始终作为第三路兼容回退。
            string[] names;
            Func<Task<List<CoverCandidate>>>[] attempts;
            if (_preferEapiFirst)
            {
                names = new[] { "EAPI", "Legacy", "WEAPI" };
                attempts = new Func<Task<List<CoverCandidate>>>[]
                {
                    () => SearchEapiAsync(query, limit, cancellationToken),
                    () => SearchLegacyAsync(query, limit, cancellationToken),
                    () => SearchWeapiAsync(query, limit, cancellationToken)
                };
            }
            else
            {
                names = new[] { "Legacy", "EAPI", "WEAPI" };
                attempts = new Func<Task<List<CoverCandidate>>>[]
                {
                    () => SearchLegacyAsync(query, limit, cancellationToken),
                    () => SearchEapiAsync(query, limit, cancellationToken),
                    () => SearchWeapiAsync(query, limit, cancellationToken)
                };
            }

            for (int i = 0; i < attempts.Length; i++)
            {
                cancellationToken.ThrowIfCancellationRequested();
                try
                {
                    List<CoverCandidate> result = await attempts[i]().ConfigureAwait(false);
                    if (result.Count > 0)
                    {
                        if (names[i] == "EAPI") _preferEapiFirst = true;
                        else if (names[i] == "Legacy") _preferEapiFirst = false;
                        return result;
                    }
                }
                catch (OperationCanceledException) { throw; }
                catch (Exception ex)
                {
                    lastError = ex;
                    if (names[i] == "Legacy") _preferEapiFirst = true;
                    else if (names[i] == "EAPI") _preferEapiFirst = false;
                }
            }

            if (lastError != null) throw new HttpRequestException("网易云搜索接口均不可用：" + lastError.Message, lastError);
            return new List<CoverCandidate>();
        }

        public async Task<string> GetAlbumCoverUrlAsync(string albumId, CancellationToken cancellationToken)
        {
            if (string.IsNullOrWhiteSpace(albumId)) return null;
            string escapedAlbumId = Uri.EscapeDataString(albumId);
            List<string> errors = new List<string>();
            string[] publicUrls =
            {
                "https://music.163.com/api/v1/album/" + escapedAlbumId,
                "https://music.163.com/api/album/" + escapedAlbumId + "?ext=true&id=" + escapedAlbumId
            };

            foreach (string publicUrl in publicUrls)
            {
                cancellationToken.ThrowIfCancellationRequested();
                try
                {
                    string json = await GetTextAsync(
                        publicUrl,
                        PcUserAgent,
                        "https://music.163.com/album?id=" + escapedAlbumId,
                        cancellationToken).ConfigureAwait(false);
                    JObject root = ParseJsonObject(json, "网易云公开专辑接口");
                    int code = ValueInt(root, "code") ?? 200;
                    if (code != 200) throw new InvalidOperationException("返回错误代码：" + code);
                    string cover = ExtractCoverUrl(root["album"]);
                    if (!string.IsNullOrWhiteSpace(cover)) return cover;
                    errors.Add("公开专辑接口未返回封面 URL");
                }
                catch (OperationCanceledException) { throw; }
                catch (Exception ex) { errors.Add(ex.Message); }
            }

            try
            {
                string url = "https://music.163.com/weapi/v1/album/" + escapedAlbumId;
                Dictionary<string, string> data = new Dictionary<string, string> { { "csrf_token", string.Empty } };
                Dictionary<string, string> form = NeteaseCrypto.CreateWeapiForm(data);
                string json = await PostFormAsync(url, form, PcUserAgent, null, cancellationToken).ConfigureAwait(false);
                JObject root = ParseJsonObject(json, "网易云 WEAPI 专辑接口");
                int code = ValueInt(root, "code") ?? 200;
                if (code != 200) throw new InvalidOperationException("返回错误代码：" + code);
                string cover = ExtractCoverUrl(root["album"]);
                if (!string.IsNullOrWhiteSpace(cover)) return cover;
                errors.Add("WEAPI 专辑接口未返回封面 URL");
            }
            catch (OperationCanceledException) { throw; }
            catch (Exception ex) { errors.Add(ex.Message); }

            throw new HttpRequestException("网易云专辑封面刷新失败：" + string.Join("；", errors.Where(x => !string.IsNullOrWhiteSpace(x)).Distinct().Take(5)));
        }


        public async Task<AlbumTrackMetadata> GetAlbumMetadataAsync(
            CoverCandidate candidate,
            CancellationToken cancellationToken)
        {
            if (candidate == null) throw new ArgumentNullException("candidate");

            AlbumTrackMetadata merged = CreateCandidateMetadata(candidate, "163 Search");
            List<string> errors = new List<string>();

            // 歌曲详情通常比专辑页更稳定，并且可直接提供当前曲目的 no、真实专辑 ID 和封面。
            try
            {
                AlbumTrackMetadata songDetail = await GetSongDetailMetadataAsync(candidate, cancellationToken).ConfigureAwait(false);
                MergeMetadata(merged, songDetail);
                if (HasCompleteAlbumMetadata(merged)) return merged;
            }
            catch (OperationCanceledException) { throw; }
            catch (Exception ex) { errors.Add("歌曲详情：" + ex.Message); }

            if (!string.IsNullOrWhiteSpace(candidate.AlbumId))
            {
                string escapedAlbumId = Uri.EscapeDataString(candidate.AlbumId);
                string[] publicUrls =
                {
                    "https://music.163.com/api/v1/album/" + escapedAlbumId,
                    "https://music.163.com/api/album/" + escapedAlbumId + "?ext=true&id=" + escapedAlbumId
                };

                foreach (string publicUrl in publicUrls)
                {
                    cancellationToken.ThrowIfCancellationRequested();
                    try
                    {
                        string json = await GetTextAsync(
                            publicUrl,
                            PcUserAgent,
                            "https://music.163.com/album?id=" + escapedAlbumId,
                            cancellationToken).ConfigureAwait(false);
                        AlbumTrackMetadata metadata = ParseAlbumMetadata(json, candidate, "163 Public Album API");
                        MergeMetadata(merged, metadata);
                        if (HasCompleteAlbumMetadata(merged)) return merged;
                    }
                    catch (OperationCanceledException) { throw; }
                    catch (Exception ex) { errors.Add("公开专辑接口：" + ex.Message); }
                }

                try
                {
                    string url = "https://music.163.com/weapi/v1/album/" + escapedAlbumId;
                    Dictionary<string, string> data = new Dictionary<string, string> { { "csrf_token", string.Empty } };
                    Dictionary<string, string> form = NeteaseCrypto.CreateWeapiForm(data);
                    string json = await PostFormAsync(url, form, PcUserAgent, null, cancellationToken).ConfigureAwait(false);
                    AlbumTrackMetadata metadata = ParseAlbumMetadata(json, candidate, "163 WEAPI Album");
                    MergeMetadata(merged, metadata);
                    if (HasCompleteAlbumMetadata(merged)) return merged;
                }
                catch (OperationCanceledException) { throw; }
                catch (Exception ex) { errors.Add("WEAPI 专辑接口：" + ex.Message); }
            }
            else
            {
                errors.Add("候选缺少专辑 ID");
            }

            // 即使只有部分字段，也应返回并交给上层按用户实际勾选项判断，不能丢掉已取得的日期或音轨。
            if (merged.HasAnyValue) return merged;
            throw new HttpRequestException("网易云歌曲详情与专辑接口均失败："
                + string.Join("；", errors.Where(x => !string.IsNullOrWhiteSpace(x)).Distinct().Take(8)));
        }

        private async Task<AlbumTrackMetadata> GetSongDetailMetadataAsync(
            CoverCandidate candidate,
            CancellationToken cancellationToken)
        {
            AlbumTrackMetadata fallback = CreateCandidateMetadata(candidate, "163 Search");
            if (string.IsNullOrWhiteSpace(candidate.SongId)) return fallback;

            string songId = candidate.SongId.Trim();
            string encodedIds = Uri.EscapeDataString("[" + songId + "]");
            string encodedObjects = Uri.EscapeDataString("[{\"id\":" + songId + "}]");
            string[] urls =
            {
                "https://music.163.com/api/song/detail/?id=" + Uri.EscapeDataString(songId) + "&ids=" + encodedIds,
                "https://music.163.com/api/v3/song/detail?c=" + encodedObjects
            };
            List<string> errors = new List<string>();

            foreach (string url in urls)
            {
                cancellationToken.ThrowIfCancellationRequested();
                try
                {
                    string json = await GetTextAsync(
                        url,
                        PcUserAgent,
                        "https://music.163.com/song?id=" + Uri.EscapeDataString(songId),
                        cancellationToken).ConfigureAwait(false);
                    JObject root = ParseJsonObject(json, "网易云歌曲详情接口");
                    int code = ValueInt(root, "code") ?? 200;
                    if (code != 200) throw new InvalidOperationException("返回错误代码：" + code);
                    JToken rootAlbum = root["album"];
                    JArray songs = root["songs"] as JArray
                        ?? (rootAlbum == null ? null : rootAlbum["songs"] as JArray);
                    if (songs == null || songs.Count == 0) throw new InvalidDataException("未返回歌曲数据");

                    JToken song = songs[0];
                    JToken album = song["al"] ?? song["album"] ?? rootAlbum;
                    AlbumTrackMetadata metadata = CreateCandidateMetadata(candidate, "163 Song Detail");
                    int trackNumber = (int)TokenLong(song["no"] ?? song["trackNo"] ?? song["position"]);
                    if (trackNumber > 0) metadata.TrackNumber = trackNumber;

                    if (album != null)
                    {
                        string albumId = TokenString(album["id"]);
                        if (!string.IsNullOrWhiteSpace(albumId)) candidate.AlbumId = albumId;
                        string albumName = ValueString(album, "name");
                        if (!string.IsNullOrWhiteSpace(albumName)) candidate.Album = albumName;
                        string coverUrl = ExtractCoverUrl(album);
                        if (!string.IsNullOrWhiteSpace(coverUrl)) candidate.CoverUrl = coverUrl;
                        string date = FormatUnixMilliseconds(TokenLong(album["publishTime"]));
                        if (!string.IsNullOrWhiteSpace(date)) metadata.ReleaseDate = date;
                        int total = (int)TokenLong(album["size"] ?? album["trackCount"]);
                        if (total > metadata.TrackTotal) metadata.TrackTotal = total;
                    }
                    return metadata;
                }
                catch (OperationCanceledException) { throw; }
                catch (Exception ex) { errors.Add(ex.Message); }
            }

            if (fallback.HasAnyValue) return fallback;
            throw new HttpRequestException("网易云歌曲详情接口均失败：" + string.Join("；", errors.Distinct().Take(4)));
        }

        private async Task<string> GetTextAsync(
            string url,
            string userAgent,
            string referrer,
            CancellationToken cancellationToken)
        {
            using (HttpRequestMessage request = new HttpRequestMessage(HttpMethod.Get, url))
            {
                request.Headers.TryAddWithoutValidation("User-Agent", userAgent);
                request.Headers.TryAddWithoutValidation("Accept", "application/json,text/plain;q=0.9,*/*;q=0.1");
                request.Headers.TryAddWithoutValidation("Accept-Language", "zh-CN,zh;q=0.9,en;q=0.5");
                request.Headers.TryAddWithoutValidation("Cache-Control", "no-cache");
                if (!string.IsNullOrWhiteSpace(referrer)) request.Headers.Referrer = new Uri(referrer);
                using (HttpResponseMessage response = await _httpClient.SendAsync(
                    request,
                    HttpCompletionOption.ResponseContentRead,
                    cancellationToken).ConfigureAwait(false))
                {
                    string body = await response.Content.ReadAsStringAsync().ConfigureAwait(false);
                    if (!response.IsSuccessStatusCode)
                    {
                        throw new HttpRequestException("HTTP " + (int)response.StatusCode + " " + response.ReasonPhrase
                            + "｜响应=" + BuildResponseSnippet(body));
                    }
                    if (string.IsNullOrWhiteSpace(body))
                        throw new HttpRequestException("HTTP " + (int)response.StatusCode + " 但响应为空");
                    return body;
                }
            }
        }

        private static AlbumTrackMetadata CreateCandidateMetadata(CoverCandidate candidate, string source)
        {
            return new AlbumTrackMetadata
            {
                ReleaseDate = AlbumTrackMetadata.NormalizeReleaseDate(candidate == null ? null : candidate.ReleaseDate),
                TrackNumber = candidate == null ? 0 : candidate.TrackNumber,
                TrackTotal = candidate == null ? 0 : candidate.TrackTotal,
                DetailSource = source
            };
        }

        private static void MergeMetadata(AlbumTrackMetadata target, AlbumTrackMetadata source)
        {
            if (target == null || source == null) return;
            string date = AlbumTrackMetadata.NormalizeReleaseDate(source.ReleaseDate);
            if (!string.IsNullOrWhiteSpace(date)) target.ReleaseDate = date;
            if (source.TrackNumber > 0) target.TrackNumber = source.TrackNumber;
            if (source.TrackTotal > target.TrackTotal) target.TrackTotal = source.TrackTotal;
            if (!string.IsNullOrWhiteSpace(source.DetailSource)) target.DetailSource = source.DetailSource;
        }

        private static bool HasCompleteAlbumMetadata(AlbumTrackMetadata metadata)
        {
            return metadata != null
                && !string.IsNullOrWhiteSpace(metadata.ReleaseDate)
                && metadata.TrackNumber > 0
                && metadata.TrackTotal > 0;
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
            catch (JsonReaderException ex)
            {
                throw new HttpRequestException(context + " 返回的不是有效 JSON｜响应=" + BuildResponseSnippet(normalized), ex);
            }
        }

        private static string BuildResponseSnippet(string value)
        {
            if (string.IsNullOrWhiteSpace(value)) return "<empty>";
            string normalized = value.Replace("\r", " ").Replace("\n", " ").Replace("\t", " ").Trim();
            return normalized.Length <= 180 ? normalized : normalized.Substring(0, 180) + "…";
        }

        public async Task<byte[]> DownloadImageAsync(string url, int maximumDimension, CancellationToken cancellationToken)
        {
            if (string.IsNullOrWhiteSpace(url)) throw new ArgumentException("封面 URL 为空。", "url");

            List<string> downloadUrls = BuildImageDownloadUrls(url, maximumDimension);
            List<string> errors = new List<string>();
            const long maximumBytes = 64L * 1024L * 1024L;

            for (int urlIndex = 0; urlIndex < downloadUrls.Count; urlIndex++)
            {
                string downloadUrl = downloadUrls[urlIndex];
                int attemptCount = urlIndex == 0 ? 2 : 1;
                for (int attempt = 0; attempt < attemptCount; attempt++)
                {
                    cancellationToken.ThrowIfCancellationRequested();
                    try
                    {
                        using (CancellationTokenSource attemptCancellation = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken))
                        using (HttpRequestMessage request = new HttpRequestMessage(HttpMethod.Get, downloadUrl))
                        {
                            attemptCancellation.CancelAfter(TimeSpan.FromSeconds(18));
                            CancellationToken attemptToken = attemptCancellation.Token;
                            // 不发送 image/*：现代浏览器 UA + image/* 可能使 CDN 返回 WebP，
                            // 而 .NET Framework 4.8 的 System.Drawing 无法直接解码 WebP。
                            request.Headers.TryAddWithoutValidation("User-Agent", ImageUserAgent);
                            request.Headers.TryAddWithoutValidation("Accept", "image/jpeg,image/png,image/gif;q=0.8,application/octet-stream;q=0.5,*/*;q=0.1");
                            request.Headers.TryAddWithoutValidation("Accept-Encoding", "identity");
                            request.Headers.TryAddWithoutValidation("Accept-Language", "zh-CN,zh;q=0.9,en;q=0.5");
                            request.Headers.TryAddWithoutValidation("Referer", "https://music.163.com/");
                            request.Headers.TryAddWithoutValidation("Cache-Control", "no-cache");
                            request.Headers.TryAddWithoutValidation("Pragma", "no-cache");

                            using (HttpResponseMessage response = await _imageHttpClient.SendAsync(
                                request,
                                HttpCompletionOption.ResponseHeadersRead,
                                attemptToken).ConfigureAwait(false))
                            {
                                if (IsTransient(response.StatusCode) && attempt + 1 < attemptCount)
                                {
                                    await DelayForRetry(1, cancellationToken).ConfigureAwait(false);
                                    continue;
                                }

                                response.EnsureSuccessStatusCode();
                                if (response.Content.Headers.ContentLength.HasValue
                                    && response.Content.Headers.ContentLength.Value > maximumBytes)
                                    throw new InvalidOperationException("封面响应超过 64 MB，已拒绝下载。 ");

                                byte[] bytes = await ReadLimitedAsync(response.Content, maximumBytes, attemptToken).ConfigureAwait(false);
                                string mediaType = response.Content.Headers.ContentType == null
                                    ? string.Empty
                                    : response.Content.Headers.ContentType.MediaType;
                                ValidateDownloadedImage(bytes, mediaType);
                                return bytes;
                            }
                        }
                    }
                    catch (OperationCanceledException)
                    {
                        if (cancellationToken.IsCancellationRequested) throw;
                        errors.Add(ShortUrl(downloadUrl) + "｜单次请求超过 18 秒");
                        if (attempt + 1 < attemptCount) await DelayForRetry(attempt, cancellationToken).ConfigureAwait(false);
                    }
                    catch (Exception ex)
                    {
                        errors.Add(ShortUrl(downloadUrl) + "｜" + ex.Message);
                        if (attempt + 1 < attemptCount) await DelayForRetry(attempt, cancellationToken).ConfigureAwait(false);
                    }
                }
            }

            string detail = errors.Count == 0
                ? "未知错误"
                : string.Join("；", errors.Distinct().Take(6));
            throw new HttpRequestException("封面下载失败，已尝试原图、CDN 备用节点和高分辨率回退：" + detail);
        }

        private static List<string> BuildImageDownloadUrls(string url, int maximumDimension)
        {
            string raw = NormalizeImageUrl(url);
            string original = GetOriginalCoverUrl(raw);
            string httpsOriginal = ForceHttps(original);
            List<string> result = new List<string>();

            if (maximumDimension > 0)
            {
                // 有最大边长时只请求不超过限制的 CDN 尺寸，避免为了预览下载原始大图。
                int[] limitedSizes =
                {
                    maximumDimension,
                    Math.Min(maximumDimension, 1200),
                    Math.Min(maximumDimension, 600),
                    Math.Min(maximumDimension, 300)
                };
                foreach (int size in limitedSizes.Where(x => x > 0).Distinct())
                {
                    string sized = SetImageParam(httpsOriginal, size);
                    AddUrl(result, sized);
                    foreach (string hostVariant in ExpandCdnHosts(sized)) AddUrl(result, hostVariant);
                }

                string httpOriginal = ForceHttp(original);
                foreach (int size in limitedSizes.Where(x => x > 0).Distinct())
                {
                    string sized = SetImageParam(httpOriginal, size);
                    AddUrl(result, sized);
                    foreach (string hostVariant in ExpandCdnHosts(sized)) AddUrl(result, hostVariant);
                }
                return result;
            }

            // 不限制时首选删除 param 后的原尺寸 HTTPS 地址。
            AddUrl(result, httpsOriginal);
            foreach (string hostVariant in ExpandCdnHosts(httpsOriginal)) AddUrl(result, hostVariant);

            // 搜索接口原本返回的地址可能带有可工作的尺寸参数，作为第二组候选。
            if (!string.Equals(raw, original, StringComparison.OrdinalIgnoreCase))
            {
                string httpsRaw = ForceHttps(raw);
                AddUrl(result, httpsRaw);
                foreach (string hostVariant in ExpandCdnHosts(httpsRaw)) AddUrl(result, hostVariant);
            }

            int[] fallbackSizes = { 3000, 2000, 1200 };
            foreach (int size in fallbackSizes)
            {
                string sized = SetImageParam(httpsOriginal, size);
                AddUrl(result, sized);
                foreach (string hostVariant in ExpandCdnHosts(sized)) AddUrl(result, hostVariant);
            }

            string httpOriginalUnlimited = ForceHttp(original);
            AddUrl(result, httpOriginalUnlimited);
            foreach (string hostVariant in ExpandCdnHosts(httpOriginalUnlimited)) AddUrl(result, hostVariant);
            AddUrl(result, SetImageParam(httpOriginalUnlimited, 2000));

            return result;
        }

        private static IEnumerable<string> ExpandCdnHosts(string url)
        {
            Uri uri;
            if (!Uri.TryCreate(url, UriKind.Absolute, out uri)) yield break;
            string host = uri.Host;
            if (!host.EndsWith(".music.126.net", StringComparison.OrdinalIgnoreCase)) yield break;
            if (host.Length < 2 || char.ToLowerInvariant(host[0]) != 'p' || host[1] < '1' || host[1] > '4') yield break;

            int hostStart = url.IndexOf("://", StringComparison.Ordinal);
            if (hostStart < 0) yield break;
            hostStart += 3;
            int hostEnd = url.IndexOf('/', hostStart);
            if (hostEnd < 0) hostEnd = url.IndexOf('?', hostStart);
            if (hostEnd < 0) hostEnd = url.Length;

            for (int i = 1; i <= 4; i++)
            {
                string newHost = "p" + i.ToString(CultureInfo.InvariantCulture) + host.Substring(2);
                if (string.Equals(newHost, host, StringComparison.OrdinalIgnoreCase)) continue;
                // 直接替换主机名，避免 UriBuilder 重新转义路径中的 == 等签名字符。
                yield return url.Substring(0, hostStart) + newHost + url.Substring(hostEnd);
            }
        }

        private static void AddUrl(ICollection<string> urls, string url)
        {
            if (string.IsNullOrWhiteSpace(url)) return;
            if (!urls.Contains(url, StringComparer.OrdinalIgnoreCase)) urls.Add(url);
        }

        private static string NormalizeImageUrl(string url)
        {
            if (string.IsNullOrWhiteSpace(url)) return url;
            string value = url.Trim().Replace("&amp;", "&");
            if (value.StartsWith("//", StringComparison.Ordinal)) value = "https:" + value;
            return value;
        }

        private static string ForceHttps(string url)
        {
            if (string.IsNullOrWhiteSpace(url)) return url;
            return url.StartsWith("http://", StringComparison.OrdinalIgnoreCase)
                ? "https://" + url.Substring("http://".Length)
                : url;
        }

        private static string ForceHttp(string url)
        {
            if (string.IsNullOrWhiteSpace(url)) return url;
            return url.StartsWith("https://", StringComparison.OrdinalIgnoreCase)
                ? "http://" + url.Substring("https://".Length)
                : url;
        }

        private static string SetImageParam(string url, int size)
        {
            if (string.IsNullOrWhiteSpace(url)) return url;
            string original = GetOriginalCoverUrl(url);
            string separator = original.IndexOf('?') >= 0 ? "&" : "?";
            return original + separator + "param=" + size.ToString(CultureInfo.InvariantCulture) + "y" + size.ToString(CultureInfo.InvariantCulture);
        }

        private static void ValidateDownloadedImage(byte[] bytes, string mediaType)
        {
            if (bytes == null || bytes.Length < 128)
                throw new InvalidOperationException("响应内容过小，可能不是图片。 ");

            bool jpeg = bytes.Length >= 3 && bytes[0] == 0xFF && bytes[1] == 0xD8 && bytes[2] == 0xFF;
            bool png = bytes.Length >= 8
                && bytes[0] == 0x89 && bytes[1] == 0x50 && bytes[2] == 0x4E && bytes[3] == 0x47
                && bytes[4] == 0x0D && bytes[5] == 0x0A && bytes[6] == 0x1A && bytes[7] == 0x0A;
            bool gif = bytes.Length >= 6
                && bytes[0] == 0x47 && bytes[1] == 0x49 && bytes[2] == 0x46
                && bytes[3] == 0x38 && (bytes[4] == 0x37 || bytes[4] == 0x39) && bytes[5] == 0x61;
            bool bmp = bytes.Length >= 2 && bytes[0] == 0x42 && bytes[1] == 0x4D;
            if (jpeg || png || gif || bmp) return;

            bool webp = bytes.Length >= 12
                && bytes[0] == 0x52 && bytes[1] == 0x49 && bytes[2] == 0x46 && bytes[3] == 0x46
                && bytes[8] == 0x57 && bytes[9] == 0x45 && bytes[10] == 0x42 && bytes[11] == 0x50;
            if (webp)
                throw new InvalidOperationException("CDN 返回 WebP；已切换兼容请求继续重试。 ");

            string typeText = string.IsNullOrWhiteSpace(mediaType) ? "未知 Content-Type" : mediaType;
            throw new InvalidOperationException("响应不是可识别的 JPEG/PNG/GIF/BMP（" + typeText + "）。 ");
        }

        private static string ShortUrl(string url)
        {
            if (string.IsNullOrWhiteSpace(url)) return "空 URL";
            return url.Length <= 90 ? url : url.Substring(0, 87) + "...";
        }

        private async Task<List<CoverCandidate>> SearchEapiAsync(string query, int limit, CancellationToken cancellationToken)
        {
            const string endpoint = "https://interface.music.163.com/eapi/cloudsearch/pc";
            const string apiPath = "/api/cloudsearch/pc";

            Dictionary<string, string> header = NeteaseCrypto.CreateAnonymousEapiHeader();
            Dictionary<string, object> data = new Dictionary<string, object>
            {
                { "s", query },
                { "type", "1" },
                { "limit", limit.ToString(CultureInfo.InvariantCulture) },
                { "offset", "0" },
                { "total", "true" },
                { "csrf_token", string.Empty },
                { "header", JsonConvert.SerializeObject(header) }
            };
            Dictionary<string, string> form = NeteaseCrypto.CreateEapiForm(apiPath, data);
            string cookie = string.Join("; ", header.Select(x => x.Key + "=" + x.Value));
            string json = await PostFormAsync(endpoint, form, MobileUserAgent, cookie, cancellationToken).ConfigureAwait(false);
            return ParseSearchResponse(json, "EAPI");
        }

        private async Task<List<CoverCandidate>> SearchWeapiAsync(string query, int limit, CancellationToken cancellationToken)
        {
            const string endpoint = "https://music.163.com/weapi/search/get";
            Dictionary<string, string> data = new Dictionary<string, string>
            {
                { "s", query },
                { "type", "1" },
                { "limit", limit.ToString(CultureInfo.InvariantCulture) },
                { "offset", "0" },
                { "total", "true" },
                { "csrf_token", string.Empty }
            };
            Dictionary<string, string> form = NeteaseCrypto.CreateWeapiForm(data);
            string json = await PostFormAsync(endpoint, form, PcUserAgent, null, cancellationToken).ConfigureAwait(false);
            return ParseSearchResponse(json, "WEAPI");
        }

        private async Task<List<CoverCandidate>> SearchLegacyAsync(string query, int limit, CancellationToken cancellationToken)
        {
            string url = "https://music.163.com/api/search/get/web?csrf_token=&hlpretag=&hlposttag=&s="
                + Uri.EscapeDataString(query)
                + "&type=1&offset=0&total=true&limit="
                + limit.ToString(CultureInfo.InvariantCulture);

            using (HttpRequestMessage request = new HttpRequestMessage(HttpMethod.Get, url))
            {
                request.Headers.TryAddWithoutValidation("User-Agent", PcUserAgent);
                request.Headers.Referrer = new Uri("https://music.163.com/");
                using (HttpResponseMessage response = await _httpClient.SendAsync(request, cancellationToken).ConfigureAwait(false))
                {
                    response.EnsureSuccessStatusCode();
                    string json = await response.Content.ReadAsStringAsync().ConfigureAwait(false);
                    return ParseSearchResponse(json, "Legacy");
                }
            }
        }

        private async Task<string> PostFormAsync(
            string url,
            IDictionary<string, string> form,
            string userAgent,
            string cookie,
            CancellationToken cancellationToken)
        {
            cancellationToken.ThrowIfCancellationRequested();
            try
            {
                using (HttpRequestMessage request = new HttpRequestMessage(HttpMethod.Post, url))
                {
                    request.Headers.TryAddWithoutValidation("User-Agent", userAgent);
                    request.Headers.Referrer = new Uri("https://music.163.com/");
                    if (!string.IsNullOrWhiteSpace(cookie)) request.Headers.TryAddWithoutValidation("Cookie", cookie);
                    request.Content = new FormUrlEncodedContent(form);

                    using (HttpResponseMessage response = await _httpClient.SendAsync(request, cancellationToken).ConfigureAwait(false))
                    {
                        response.EnsureSuccessStatusCode();
                        return await response.Content.ReadAsStringAsync().ConfigureAwait(false);
                    }
                }
            }
            catch (OperationCanceledException) { throw; }
            catch (Exception ex)
            {
                throw new HttpRequestException("请求失败：" + ex.Message, ex);
            }
        }

        private static bool IsTransient(HttpStatusCode statusCode)
        {
            int code = (int)statusCode;
            return code == 408 || code == 429 || code >= 500;
        }

        private static Task DelayForRetry(int attempt, CancellationToken cancellationToken)
        {
            return Task.Delay(450 * (attempt + 1), cancellationToken);
        }

        private static async Task<byte[]> ReadLimitedAsync(HttpContent content, long maximumBytes, CancellationToken cancellationToken)
        {
            using (System.IO.Stream input = await content.ReadAsStreamAsync().ConfigureAwait(false))
            using (System.IO.MemoryStream output = new System.IO.MemoryStream())
            {
                byte[] buffer = new byte[81920];
                while (true)
                {
                    cancellationToken.ThrowIfCancellationRequested();
                    int read = await input.ReadAsync(buffer, 0, buffer.Length, cancellationToken).ConfigureAwait(false);
                    if (read <= 0) break;
                    if (output.Length + read > maximumBytes) throw new InvalidOperationException("下载内容超过允许大小。 ");
                    output.Write(buffer, 0, read);
                }
                return output.ToArray();
            }
        }

        private static List<CoverCandidate> ParseSearchResponse(string json, string source)
        {
            JObject root = ParseJsonObject(json, "网易云 " + source + " 搜索接口");
            int code = ValueInt(root, "code") ?? 200;
            if (code != 200) throw new InvalidOperationException(source + " 返回错误代码：" + code);

            JToken result = root["result"];
            JArray songs = result == null ? null : result["songs"] as JArray;
            if (songs == null) return new List<CoverCandidate>();

            List<CoverCandidate> candidates = new List<CoverCandidate>();
            foreach (JToken song in songs)
            {
                JToken album = song["album"] ?? song["al"];
                JToken artists = song["artists"] ?? song["ar"];
                List<string> artistNames = new List<string>();
                JArray artistArray = artists as JArray;
                if (artistArray != null)
                {
                    foreach (JToken artist in artistArray)
                    {
                        string name = ValueString(artist, "name");
                        if (!string.IsNullOrWhiteSpace(name)) artistNames.Add(name);
                    }
                }

                List<string> aliases = new List<string>();
                JArray aliasArray = (song["alias"] ?? song["alia"]) as JArray;
                if (aliasArray != null)
                {
                    foreach (JToken alias in aliasArray)
                    {
                        string aliasText = TokenString(alias);
                        if (!string.IsNullOrWhiteSpace(aliasText)) aliases.Add(aliasText);
                    }
                }

                CoverCandidate candidate = new CoverCandidate
                {
                    Provider = "163",
                    Storefront = "cn",
                    SongId = TokenString(song["id"]),
                    Title = ValueString(song, "name") ?? string.Empty,
                    Aliases = aliases,
                    Artists = artistNames,
                    AlbumId = album == null ? null : TokenString(album["id"]),
                    Album = album == null ? string.Empty : (ValueString(album, "name") ?? string.Empty),
                    CoverUrl = ExtractCoverUrl(album),
                    DurationMs = TokenLong(song["duration"] ?? song["dt"]),
                    ReleaseDate = FormatUnixMilliseconds(album == null ? 0L : TokenLong(album["publishTime"])),
                    TrackNumber = (int)TokenLong(song["no"] ?? song["trackNo"] ?? song["position"]),
                    TrackTotal = album == null ? 0 : (int)TokenLong(album["size"] ?? album["trackCount"]),
                    Source = "163·" + source
                };
                if (!string.IsNullOrWhiteSpace(candidate.Title)) candidates.Add(candidate);
            }

            return candidates
                .GroupBy(x => string.IsNullOrWhiteSpace(x.SongId) ? x.Title + "|" + x.Album + "|" + x.ArtistText : x.SongId)
                .Select(x => x.First())
                .ToList();
        }


        private static AlbumTrackMetadata ParseAlbumMetadata(string json, CoverCandidate candidate, string detailSource)
        {
            JObject root = ParseJsonObject(json, detailSource);
            int code = ValueInt(root, "code") ?? 200;
            if (code != 200) throw new InvalidOperationException("网易云专辑接口返回错误代码：" + code);

            JToken album = root["album"];
            JArray songs = root["songs"] as JArray ?? (album == null ? null : album["songs"] as JArray);
            AlbumTrackMetadata metadata = new AlbumTrackMetadata
            {
                ReleaseDate = AlbumTrackMetadata.NormalizeReleaseDate(candidate.ReleaseDate),
                TrackNumber = candidate.TrackNumber,
                TrackTotal = candidate.TrackTotal,
                DetailSource = detailSource
            };

            if (album != null)
            {
                string releaseDate = FormatUnixMilliseconds(TokenLong(album["publishTime"]));
                if (!string.IsNullOrWhiteSpace(releaseDate))
                    metadata.ReleaseDate = releaseDate;
                int explicitTotal = (int)TokenLong(album["size"] ?? album["trackCount"]);
                if (explicitTotal > metadata.TrackTotal) metadata.TrackTotal = explicitTotal;
            }

            if (songs == null) return metadata;
            string expectedId = candidate.SongId;
            int maximumTrack = 0;
            int songCount = 0;
            JToken bestSong = null;
            double bestScore = -1d;
            foreach (JToken song in songs)
            {
                songCount++;
                int number = (int)TokenLong(song["no"] ?? song["trackNo"] ?? song["position"]);
                if (number > maximumTrack) maximumTrack = number;
                string id = TokenString(song["id"]);
                if (!string.IsNullOrWhiteSpace(expectedId)
                    && string.Equals(id, expectedId, StringComparison.OrdinalIgnoreCase))
                {
                    bestSong = song;
                    bestScore = 10d;
                    continue;
                }

                JToken artists = song["artists"] ?? song["ar"];
                List<string> artistNames = new List<string>();
                JArray array = artists as JArray;
                if (array != null)
                {
                    foreach (JToken artist in array)
                    {
                        string name = ValueString(artist, "name");
                        if (!string.IsNullOrWhiteSpace(name)) artistNames.Add(name);
                    }
                }
                double score = TextNormalizer.Similarity(candidate.Title, ValueString(song, "name")) * 0.65d
                    + TextNormalizer.ArtistSimilarity(candidate.ArtistText, artistNames) * 0.35d;
                if (score > bestScore)
                {
                    bestScore = score;
                    bestSong = song;
                }
            }

            metadata.TrackTotal = Math.Max(metadata.TrackTotal, Math.Max(songCount, maximumTrack));
            if (bestSong != null && bestScore >= 0.55d)
            {
                int number = (int)TokenLong(bestSong["no"] ?? bestSong["trackNo"] ?? bestSong["position"]);
                if (number > 0) metadata.TrackNumber = number;
            }
            return metadata;
        }

        public static string GetOriginalCoverUrl(string url)
        {
            if (string.IsNullOrWhiteSpace(url)) return url;
            string value = url.Trim();
            int question = value.IndexOf('?');
            if (question < 0) return value;

            string baseUrl = value.Substring(0, question);
            string query = value.Substring(question + 1);
            string[] parts = query.Split(new[] { '&' }, StringSplitOptions.RemoveEmptyEntries);
            List<string> kept = new List<string>();
            foreach (string part in parts)
            {
                string key = part;
                int equals = part.IndexOf('=');
                if (equals >= 0) key = part.Substring(0, equals);
                if (string.Equals(key, "param", StringComparison.OrdinalIgnoreCase)) continue;
                kept.Add(part);
            }
            return kept.Count == 0 ? baseUrl : baseUrl + "?" + string.Join("&", kept);
        }

        private static string ExtractCoverUrl(JToken album)
        {
            if (album == null) return null;
            string[] fields = { "picUrl", "coverImgUrl" };
            foreach (string field in fields)
            {
                string value = ValueString(album, field);
                if (string.IsNullOrWhiteSpace(value)) continue;
                if (value.StartsWith("http://", StringComparison.OrdinalIgnoreCase)
                    || value.StartsWith("https://", StringComparison.OrdinalIgnoreCase))
                    return NormalizeImageUrl(value);
            }
            return null;
        }


        private static string FormatUnixMilliseconds(long value)
        {
            if (value <= 0) return string.Empty;
            try
            {
                // 网易云的 publishTime 表示中国区页面上的发布日期。
                // 常见值是北京时间当天 00:00；直接取 UTC 日历日会稳定早一天。
                return DateTimeOffset.FromUnixTimeMilliseconds(value)
                    .ToOffset(NeteaseReleaseTimeZoneOffset)
                    .ToString("yyyy-MM-dd", CultureInfo.InvariantCulture);
            }
            catch { return string.Empty; }
        }

        private static string ValueString(JToken parent, string name)
        {
            if (parent == null) return null;
            return TokenString(parent[name]);
        }

        private static int? ValueInt(JToken parent, string name)
        {
            if (parent == null || parent[name] == null) return null;
            int value;
            return int.TryParse(parent[name].ToString(), NumberStyles.Integer, CultureInfo.InvariantCulture, out value) ? value : (int?)null;
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
            return long.TryParse(token.ToString(), NumberStyles.Integer, CultureInfo.InvariantCulture, out value) ? value : 0L;
        }

        public void Dispose()
        {
            if (_disposed) return;
            _imageHttpClient.Dispose();
            _httpClient.Dispose();
            _disposed = true;
        }
    }
}
