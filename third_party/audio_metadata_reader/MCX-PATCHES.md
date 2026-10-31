# MusicCardX本地兼容补丁

基于audio_metadata_reader1.8.1（MIT）。保留原版权与许可证。

- Vorbis的TRACKNUMBER/DISCNUMBER兼容n/total并保留总数。
- WAV LIST/INFO文本先严格UTF-8解码，失败后使用Latin-1。
- MP3分别映射TPE1艺术家和TPE2专辑艺术家，保留完整日期文本。
- 修正标准USLT歌词的描述字段与文本边界，UTF-8及UTF-16不会丢失首字。
- MP4识别aART并保留专辑艺术家，与©ART分开。
- MusicCardX的导入适配层补充TXXX歌词和额外Tag。

自造音频样本回归见test/fixtures/audio及test/v131_test.dart。

1.3.3：补齐ID3v1.1尾部track字节及v2缺失时的尾部回填；TRCK去空字符、容忍n/total间空格；增加ID3v2.2帧头及常见字段映射。Vorbis扩展TRACK/编号与总数字段别名，非数值安全忽略。导入适配层可从额外TXXX Tag回填编号。回归见test/v133_test.dart，协议依据https://id3.org/ID3v1和https://id3.org/id3v2-00。
