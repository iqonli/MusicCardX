using System;
using System.Collections.Generic;
using System.Globalization;
using System.Linq;
using System.Numerics;
using System.Security.Cryptography;
using System.Text;
using Newtonsoft.Json;

namespace AutoCoverDownTool.Utils
{
    internal static class NeteaseCrypto
    {
        private const string PresetKey = "0CoJUm6Qyw8W8jud";
        private const string Iv = "0102030405060708";
        private const string PublicExponent = "010001";
        private const string Modulus = "00e0b509f6259df8642dbc35662901477df22677ec152b5ff68ace615bb7b725152b3ab17a876aea8a5aa76d2e417629ec4ee341f56135fccf695280104e0312ecbda92557c93870114af6c9d05c4f7f0c3685b7a46bee255932575cce10b424d813cfe4875d3e82047b97ddef52741d546b8e289dc6935b3ece0462db0a22b8e7";
        private const string EapiKey = "e82ckenh8dichen8";
        private const string Base62 = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789";

        public static Dictionary<string, string> CreateWeapiForm(IDictionary<string, string> data)
        {
            string json = JsonConvert.SerializeObject(data);
            string secretKey = CreateSecretKey(16);
            string first = AesCbcBase64(Encoding.UTF8.GetBytes(json), Encoding.ASCII.GetBytes(PresetKey));
            string second = AesCbcBase64(Encoding.UTF8.GetBytes(first), Encoding.ASCII.GetBytes(secretKey));
            string encryptedKey = RsaEncrypt(secretKey);

            return new Dictionary<string, string>
            {
                { "params", second },
                { "encSecKey", encryptedKey }
            };
        }

        public static Dictionary<string, string> CreateEapiForm(string apiPath, IDictionary<string, object> data)
        {
            string json = JsonConvert.SerializeObject(data);
            string message = "nobody" + apiPath + "use" + json + "md5forencrypt";
            string digest = HashHelper.Md5Lower(message);
            string plain = apiPath + "-36cd479b6b5-" + json + "-36cd479b6b5-" + digest;
            byte[] encrypted = AesEcb(Encoding.UTF8.GetBytes(plain), Encoding.ASCII.GetBytes(EapiKey));

            return new Dictionary<string, string>
            {
                { "params", BitConverter.ToString(encrypted).Replace("-", string.Empty) }
            };
        }

        public static Dictionary<string, string> CreateAnonymousEapiHeader()
        {
            long seconds = DateTimeOffset.UtcNow.ToUnixTimeSeconds();
            long milliseconds = DateTimeOffset.UtcNow.ToUnixTimeMilliseconds();
            int requestSuffix;
            using (RandomNumberGenerator rng = RandomNumberGenerator.Create())
            {
                byte[] random = new byte[2];
                rng.GetBytes(random);
                requestSuffix = BitConverter.ToUInt16(random, 0) % 10000;
            }

            return new Dictionary<string, string>
            {
                { "__csrf", string.Empty },
                { "appver", "8.0.0" },
                { "buildver", seconds.ToString(CultureInfo.InvariantCulture) },
                { "channel", string.Empty },
                { "deviceId", string.Empty },
                { "mobilename", string.Empty },
                { "resolution", "1920x1080" },
                { "os", "android" },
                { "osver", string.Empty },
                { "requestId", milliseconds.ToString(CultureInfo.InvariantCulture) + "_" + requestSuffix.ToString("0000") },
                { "versioncode", "140" },
                { "MUSIC_U", string.Empty }
            };
        }

        private static string CreateSecretKey(int length)
        {
            byte[] random = new byte[length];
            using (RandomNumberGenerator rng = RandomNumberGenerator.Create()) rng.GetBytes(random);
            char[] chars = new char[length];
            for (int i = 0; i < length; i++) chars[i] = Base62[random[i] % Base62.Length];
            return new string(chars);
        }

        private static string AesCbcBase64(byte[] plain, byte[] key)
        {
            using (Aes aes = Aes.Create())
            {
                aes.BlockSize = 128;
                aes.KeySize = 128;
                aes.Mode = CipherMode.CBC;
                aes.Padding = PaddingMode.PKCS7;
                aes.Key = key;
                aes.IV = Encoding.ASCII.GetBytes(Iv);
                using (ICryptoTransform encryptor = aes.CreateEncryptor())
                {
                    byte[] result = encryptor.TransformFinalBlock(plain, 0, plain.Length);
                    return Convert.ToBase64String(result);
                }
            }
        }

        private static byte[] AesEcb(byte[] plain, byte[] key)
        {
            using (Aes aes = Aes.Create())
            {
                aes.BlockSize = 128;
                aes.KeySize = 128;
                aes.Mode = CipherMode.ECB;
                aes.Padding = PaddingMode.PKCS7;
                aes.Key = key;
                using (ICryptoTransform encryptor = aes.CreateEncryptor())
                {
                    return encryptor.TransformFinalBlock(plain, 0, plain.Length);
                }
            }
        }

        private static string RsaEncrypt(string secretKey)
        {
            string reversed = new string(secretKey.Reverse().ToArray());
            string textHex = BitConverter.ToString(Encoding.UTF8.GetBytes(reversed)).Replace("-", string.Empty);

            BigInteger text = ParsePositiveHex(textHex);
            BigInteger exponent = ParsePositiveHex(PublicExponent);
            BigInteger modulus = ParsePositiveHex(Modulus);
            string encrypted = BigInteger.ModPow(text, exponent, modulus).ToString("x");
            return encrypted.PadLeft(256, '0');
        }

        private static BigInteger ParsePositiveHex(string value)
        {
            return BigInteger.Parse("0" + value, NumberStyles.AllowHexSpecifier, CultureInfo.InvariantCulture);
        }
    }
}
