'use strict';

/*
 * MusicCard v4.16.7
 * Copyright (C) 2026 PerryDing/IQ Online Studio
 *
 * MusicCard是自由软件：你可以依据自由软件基金会发布的
 * GNU Lesser General Public License条款重新发布和/或修改本程序；
 * 你可以选择许可证第3版，或（由你选择）任何后续版本。
 *
 * MusicCard按“现状”发布，不提供任何担保；甚至不包括适销性或
 * 特定用途适用性的默示担保。详情请参阅GNU Lesser General Public License。
 *
 * 你应当已随MusicCard收到GNU Lesser General Public License和
 * GNU General Public License的副本；若没有，请见https://www.gnu.org/licenses/。
 * SPDX-License-Identifier: LGPL-3.0-or-later
 * 项目地址：https://github.com/iqonli/MusicCard
 *
 * 本版本随附第三方组件opencc-js v1.4.1。
 * Copyright (c) 2020-2021 The nk2028 Project
 * opencc-js代码许可证：MIT；内置opencc-data词典数据许可证：Apache-2.0。
 * opencc-js项目地址：https://github.com/nk2028/opencc-js
 * opencc-data项目地址：https://github.com/nk2028/opencc-data
 */

// Spider Monkey Panel主脚本；按顺序从主脚本同目录、foobar2000安装根目录和profile目录加载opencc-js-1.4.1.js
// Main UI: preview + copy image + style configuration

const MUSICCARD_VERSION = '4.16.7';
const MUSICCARD_TITLE = 'MusicCard v' + MUSICCARD_VERSION;
const MUSICCARD_PROJECT_URL = 'https://github.com/iqonli/MusicCard';
const MUSICCARD_OPENCC_JS_FILENAME = 'opencc-js-1.4.1.js';
const MUSICCARD_OPENCC_JS_VERSION = '1.4.1';
const MUSICCARD_OPENCC_PROJECT_URL = 'https://github.com/nk2028/opencc-js';
const MUSICCARD_OPENCC_DATA_PROJECT_URL = 'https://github.com/nk2028/opencc-data';
const MUSICCARD_OPENCC_DOWNLOAD_URL = 'https://registry.npmjs.org/opencc-js/-/opencc-js-1.4.1.tgz';
const MUSICCARD_OPENCC_SCRIPT_RELATIVE_PATH = '.\\' + MUSICCARD_OPENCC_JS_FILENAME;
const MUSICCARD_OPENCC_DEFAULT_FOOBAR_ROOT_DIR = 'D:\\Program Files\\foobar2000\\foobar2000-with_foobox8';
const MUSICCARD_OPENCC_DEFAULT_PROFILE_DIR = MUSICCARD_OPENCC_DEFAULT_FOOBAR_ROOT_DIR + '\\profile';
let MUSICCARD_OPENCC = null;
let MUSICCARD_OPENCC_LOAD_ERROR = '';
let MUSICCARD_OPENCC_LOAD_MS = null;
let MUSICCARD_OPENCC_LOAD_PATH = '';
let MUSICCARD_OPENCC_FOOBAR_ROOT_PATH = '';
let MUSICCARD_OPENCC_PROFILE_PATH = '';
const MUSICCARD_OPENCC_LOAD_ATTEMPTS = [];

function musicCardJoinPath(basePath, fileName) {
    const base = String(basePath || '');
    if (!base) return '';
    return /[\\\/]$/.test(base) ? base + fileName : base + '\\' + fileName;
}
function musicCardOpenCCFileExists(path) {
    if (!path) return false;
    try {
        if (typeof utils !== 'undefined' && typeof utils.IsFile === 'function') return !!utils.IsFile(path);
    } catch (e) {}
    try {
        if (typeof utils !== 'undefined' && typeof utils.FileExists === 'function') return !!utils.FileExists(path);
    } catch (e2) {}
    try {
        const fso = new ActiveXObject('Scripting.FileSystemObject');
        return !!fso.FileExists(path);
    } catch (e3) {}
    return false;
}
function musicCardResolveOpenCCGlobal() {
    if (typeof OpenCC !== 'undefined') return OpenCC;
    if (typeof globalThis !== 'undefined' && globalThis.OpenCC) return globalThis.OpenCC;
    return null;
}
function musicCardRecordOpenCCAttempt(label, path, result, reason) {
    MUSICCARD_OPENCC_LOAD_ATTEMPTS.push({
        label: String(label || ''),
        path: String(path || ''),
        result: String(result || ''),
        reason: String(reason || '')
    });
}
function musicCardFormatOpenCCAttempts() {
    const lines = [];
    for (let i = 0; i < MUSICCARD_OPENCC_LOAD_ATTEMPTS.length; i++) {
        const item = MUSICCARD_OPENCC_LOAD_ATTEMPTS[i];
        lines.push((i + 1) + '.' + item.label);
        lines.push('路径：' + (item.path || '未知'));
        lines.push('结果：' + (item.result || '失败'));
        if (item.reason) lines.push('原因：' + item.reason);
        if (i + 1 < MUSICCARD_OPENCC_LOAD_ATTEMPTS.length) lines.push('');
    }
    return lines.join('\n');
}
function musicCardTryIncludeOpenCC(includePath, displayPath, label, checkAbsolutePath) {
    const attemptStarted = Date.now();
    if (checkAbsolutePath && !musicCardOpenCCFileExists(includePath)) {
        const reason = '指定路径中不存在' + MUSICCARD_OPENCC_JS_FILENAME + '。';
        musicCardRecordOpenCCAttempt(label, displayPath, '失败', reason);
        try { console.log('[MusicCard][OpenCC]' + label + '未找到文件；路径=' + displayPath); } catch (e) {}
        return false;
    }
    try { console.log('[MusicCard][OpenCC]尝试加载：' + label + '；路径=' + displayPath); } catch (e2) {}
    try {
        include(includePath);
        const api = musicCardResolveOpenCCGlobal();
        if (!api || typeof api.Converter !== 'function') {
            throw new Error('文件已执行，但未导出OpenCC.Converter；文件可能损坏、版本不匹配或不是UMD完整构建。');
        }
        MUSICCARD_OPENCC = api;
        MUSICCARD_OPENCC_LOAD_PATH = displayPath;
        const elapsed = Date.now() - attemptStarted;
        musicCardRecordOpenCCAttempt(label, displayPath, '成功', '加载并识别OpenCC.Converter，用时' + elapsed + 'ms。');
        try { console.log('[MusicCard][OpenCC]' + label + '加载成功，耗时' + elapsed + 'ms；路径=' + displayPath); } catch (e3) {}
        return true;
    } catch (e4) {
        const message = String(e4 && e4.message ? e4.message : e4);
        musicCardRecordOpenCCAttempt(label, displayPath, '失败', message);
        try { console.log('[MusicCard][OpenCC]' + label + '加载失败：' + message + '；路径=' + displayPath); } catch (e5) {}
        return false;
    }
}
(function loadMusicCardOpenCC() {
    const started = Date.now();
    let profileDir = '';
    try {
        profileDir = typeof fb !== 'undefined' && fb.ProfilePath ? String(fb.ProfilePath) : '';
    } catch (e) {}
    if (!profileDir) profileDir = MUSICCARD_OPENCC_DEFAULT_PROFILE_DIR;

    const normalizedProfileDir = profileDir.replace(/[\\\/]+$/, '');
    let foobarRootDir = MUSICCARD_OPENCC_DEFAULT_FOOBAR_ROOT_DIR;
    if (/[\\\/]profile$/i.test(normalizedProfileDir)) {
        foobarRootDir = normalizedProfileDir.replace(/[\\\/]profile$/i, '');
    }

    MUSICCARD_OPENCC_FOOBAR_ROOT_PATH = musicCardJoinPath(foobarRootDir, MUSICCARD_OPENCC_JS_FILENAME);
    MUSICCARD_OPENCC_PROFILE_PATH = musicCardJoinPath(normalizedProfileDir || MUSICCARD_OPENCC_DEFAULT_PROFILE_DIR, MUSICCARD_OPENCC_JS_FILENAME);

    //相对include由SMP按当前MusicCard脚本目录解析；内存脚本则按SMP自身规则解析。
    let loaded = musicCardTryIncludeOpenCC(
        MUSICCARD_OPENCC_JS_FILENAME,
        MUSICCARD_OPENCC_SCRIPT_RELATIVE_PATH + '（由SMP按MusicCard主脚本同目录解析）',
        'MusicCard主脚本同目录',
        false
    );
    if (!loaded && MUSICCARD_OPENCC_FOOBAR_ROOT_PATH) {
        loaded = musicCardTryIncludeOpenCC(
            MUSICCARD_OPENCC_FOOBAR_ROOT_PATH,
            MUSICCARD_OPENCC_FOOBAR_ROOT_PATH,
            'foobar2000安装根目录',
            true
        );
    }
    if (!loaded && MUSICCARD_OPENCC_PROFILE_PATH) {
        loaded = musicCardTryIncludeOpenCC(
            MUSICCARD_OPENCC_PROFILE_PATH,
            MUSICCARD_OPENCC_PROFILE_PATH,
            'foobar2000 profile目录',
            true
        );
    }

    MUSICCARD_OPENCC_LOAD_MS = Date.now() - started;
    if (loaded) {
        MUSICCARD_OPENCC_LOAD_ERROR = '';
        try {
            console.log('[MusicCard][OpenCC]最终加载路径：' + MUSICCARD_OPENCC_LOAD_PATH);
            console.log('[MusicCard][OpenCC]总加载耗时' + MUSICCARD_OPENCC_LOAD_MS + 'ms。');
        } catch (e) {}
        return;
    }

    MUSICCARD_OPENCC = null;
    MUSICCARD_OPENCC_LOAD_ERROR = musicCardFormatOpenCCAttempts() || '没有可用的opencc-js加载记录。';
    try {
        console.log('[MusicCard][OpenCC]全部加载路径均失败。\n' + MUSICCARD_OPENCC_LOAD_ERROR);
        console.log('[MusicCard][OpenCC]下载地址：' + MUSICCARD_OPENCC_DOWNLOAD_URL);
    } catch (e2) {}
})();

const PROP_OUTPUT_DIR = 'MusicCard.v4.13.1.OutputDir';
const PROP_CUSTOM_COVER = 'MusicCard.v4.13.1.CustomCoverPath';
const PROP_SCALE = 'MusicCard.v4.13.1.ExportScale';
const PROP_CUSTOM_SCALE = 'MusicCard.v4.15.4.CustomExportScale';
const PROP_STYLE_JSON = 'MusicCard.v4.13.1.StyleJson';
const PROP_BG_STYLE = 'MusicCard.v4.13.1.BackgroundStyle';
const PROP_BLUR_STRENGTH = 'MusicCard.v4.13.1.BlurStrength';
const PROP_SOLID_HEX = 'MusicCard.v4.13.1.SolidHex';
const PROP_SHADOW_OPACITY = 'MusicCard.v4.13.1.CoverShadowOpacity';
const PROP_SHADOW_DEPTH = 'MusicCard.v4.13.1.CoverShadowDepth';
const PROP_TEXT_RENDERING_HINT = 'MusicCard.v4.13.1.TextRenderingHint';
const PROP_COVER_CORNER_RADIUS = 'MusicCard.v4.13.1.CoverCornerRadius';
const PROP_IRREGULAR_COVER_MODE = 'MusicCard.v4.13.1.IrregularCoverMode';
const PROP_BLUR_BG_CROP_POSITION = 'MusicCard.v4.15.8.BlurBackgroundCropPosition';
const PROP_BLUR_BG_CROP_POSITION_LEGACY = 'MusicCard.v4.15.7.BlurBackgroundCropPosition';
const PROP_RAINBOW_SAMPLE_MAX_SIDE = 'MusicCard.v4.15.8.RainbowSampleMaxSide';
const PROP_RAINBOW_SAMPLE_MAX_SIDE_LEGACY = 'MusicCard.v4.15.7.RainbowSampleMaxSide';
const PROP_RAINBOW_MODE = 'MusicCard.v4.15.8.RainbowMode';
const PROP_RAINBOW_CUSTOM_HEX = 'MusicCard.v4.15.8.RainbowCustomHex';
const PROP_RAINBOW_CUSTOM_SELECTION = 'MusicCard.v4.15.8.RainbowCustomSelection';
const PROP_CUSTOM_ENVIRONMENT_ENABLED = 'MusicCard.v4.16.0.CustomEnvironmentColorsEnabled';
const PROP_CUSTOM_ENVIRONMENT_COLORS = 'MusicCard.v4.16.0.CustomEnvironmentColorsJson';
const PROP_LYRICS_JSON = 'MusicCard.v4.15.LyricsJson';
const PROP_TEXT_OPENCC_MODE = 'MusicCard.v4.16.TextOpenCCMode';
const PROP_LYRICS_OPENCC_MODE = 'MusicCard.v4.16.LyricsOpenCCMode';
const PROP_DISPLAY_FONT_NAME = 'MusicCard.DisplayFontName';
const PROP_STYLE_SCHEMA_VERSION = 'MusicCard.StyleSchemaVersion';
const CURRENT_STYLE_SCHEMA_VERSION = 16;
const MAX_BLUR_STRENGTH = 500;
const MAX_TEXT_BLUR_STRENGTH = 50;
const MIN_LETTER_SPACING = -100;
const MAX_LETTER_SPACING = 500;
const FLOAT_INPUT_NOTE = '支持浮点数，精确度0.001。';
const MAX_LYRICS_CONTAINER_WIDTH = 3000;
const MAX_COVER_CORNER_RADIUS = 180;
const COLOR_BLACK_TOKEN = '#black';
const COLOR_WHITE_TOKEN = '#white';
const COLOR_BLACK_RGB = { r: 18, g: 18, b: 18 };
const COLOR_WHITE_RGB = { r: 250, g: 250, b: 250 };
const DEFAULT_RAINBOW_SAMPLE_MAX_SIDE = 150;
const DEFAULT_RAINBOW_MODE = 'sample';
const DEFAULT_RAINBOW_CUSTOM_HEX = '';
const DEFAULT_RAINBOW_CUSTOM_SELECTION = 'palette:0';
const RAINBOW_STYLE_COLOR_COUNT = 5;
const CUSTOM_ENVIRONMENT_COLOR_COUNT = 5;
const DEFAULT_CUSTOM_ENVIRONMENT_COLORS_ENABLED = false;
const OPENCC_MODES = ['off', 't2s', 's2t', 's2twp', 's2hk'];
const DEFAULT_TEXT_OPENCC_MODE = 'off';
const DEFAULT_LYRICS_OPENCC_MODE = 'off';
const RAINBOW_MIN_PERCENT = 0;
const RAINBOW_MAX_PERCENT = 100;
const LYRICS_PLACEHOLDER_TEXT = '请输入文本';
const DT_NOPREFIX = 0x00000800;
// GDI+ DrawString flags used for card text rendered on gdi.CreateImage().
// Horizontal alignment: Near (left); vertical alignment: Center; no wrapping.
const SF_ALIGN_CENTER = 0x10000000;
const SF_ALIGN_FAR = 0x20000000;
const SF_LINE_ALIGN_CENTER = 0x01000000;
const SF_LINE_ALIGN_FAR = 0x02000000;
const SF_NO_WRAP = 0x00001000;
const SF_NO_CLIP = 0x00004000;
const SF_MEASURE_TRAILING_SPACES = 0x00000800;
const MEASURE_STRING_FORMAT = SF_NO_WRAP | SF_NO_CLIP | SF_MEASURE_TRAILING_SPACES;
const CARD_STRING_FORMAT = SF_LINE_ALIGN_CENTER | SF_NO_WRAP | SF_NO_CLIP;
const WATERMARK_STRING_FORMAT = SF_LINE_ALIGN_FAR | SF_NO_WRAP | SF_NO_CLIP;
const LYRICS_STRING_FORMAT_LEFT = SF_NO_WRAP;
const LYRICS_STRING_FORMAT_CENTER = SF_ALIGN_CENTER | SF_NO_WRAP;
const LYRICS_STRING_FORMAT_RIGHT = SF_ALIGN_FAR | SF_NO_WRAP;

function RGBA(r, g, b, a) { return (alphaByte(a) << 24) | ((r & 255) << 16) | ((g & 255) << 8) | (b & 255); }
function RGB(r, g, b) { return RGBA(r, g, b, 255); }
function safe(v, d) { return v === undefined || v === null ? d : String(v); }
function nonEmpty(v) { return v !== undefined && v !== null && String(v).trim() !== ''; }
function round3(value) {
    const n = Number(value);
    return isFinite(n) ? Math.round(n * 1000) / 1000 : 0;
}
function formatNumber(value) {
    const n = round3(value);
    if (!isFinite(n)) return '0';
    if (Object.is && Object.is(n, -0)) return '0';
    return String(n);
}
function parseStoredNumber(value, fallback, minValue, maxValue) {
    const n = parseFloat(value);
    if (!isFinite(n)) return fallback;
    return round3(clamp(n, minValue, maxValue));
}
function parseStoredInteger(value, fallback, minValue, maxValue) {
    const raw = String(value === undefined || value === null ? '' : value).trim();
    if (!/^\d+$/.test(raw)) return fallback;
    const n = parseInt(raw, 10);
    if (!isFinite(n)) return fallback;
    return clamp(n, minValue, maxValue);
}
function normalizeOpenCCMode(value, fallback) {
    let mode = String(value === undefined || value === null ? '' : value).toLowerCase();
    //兼容此前配置：s2tw现在按包含台湾地区词汇的s2twp处理。
    if (mode === 's2tw') mode = 's2twp';
    return OPENCC_MODES.includes(mode) ? mode : (fallback || 'off');
}
function isValidOpenCCModeValue(value) {
    const mode = String(value === undefined || value === null ? '' : value).toLowerCase();
    return OPENCC_MODES.includes(mode) || mode === 's2tw';
}
function openCCModeButtonText(mode) {
    const normalized = normalizeOpenCCMode(mode, 'off');
    return '简繁：' + (normalized === 'off' ? '关闭' : normalized);
}
function nextOpenCCMode(mode) {
    const current = normalizeOpenCCMode(mode, 'off');
    const index = OPENCC_MODES.indexOf(current);
    return OPENCC_MODES[(index + 1) % OPENCC_MODES.length];
}

function parseFloatInput(value, minValue, maxValue) {
    const raw = String(value === undefined || value === null ? '' : value).trim();
    if (!/^[+-]?(?:\d+(?:\.\d{1,3})?|\.\d{1,3})$/.test(raw)) return null;
    const n = parseFloat(raw);
    if (!isFinite(n) || n < minValue || n > maxValue) return null;
    return round3(n);
}
function parseStoredLetterSpacing(value, fallback) {
    const fallbackValue = fallback === undefined || fallback === null ? '' : fallback;
    if (value === undefined || value === null) return fallbackValue;
    const raw = String(value).trim();
    if (!raw) return '';
    const n = parseFloat(raw);
    if (!isFinite(n)) return fallbackValue;
    return round3(clamp(n, MIN_LETTER_SPACING, MAX_LETTER_SPACING));
}
function parseLetterSpacingInput(value) {
    const raw = String(value === undefined || value === null ? '' : value).trim();
    if (!raw) return '';
    return parseFloatInput(raw, MIN_LETTER_SPACING, MAX_LETTER_SPACING);
}
function formatLetterSpacing(value) {
    return value === undefined || value === null || String(value).trim() === '' ? '' : formatNumber(value);
}
function alphaByte(value) {
    const n = Number(value);
    return Math.max(0, Math.min(255, Math.round(isFinite(n) ? n : 0)));
}
function floatPrompt(label, minValue, maxValue, extra) {
    return String(label || '') + '（' + formatNumber(minValue) + '-' + formatNumber(maxValue) + '）' +
        (extra ? '\n' + extra : '') + '\n' + FLOAT_INPUT_NOTE;
}
function cleanNumericTag(v) {
    const t = String(v === undefined || v === null ? '' : v).trim();
    if (!t || t === '?' || t === '-' || t === '--' || t.toLowerCase() === 'unknown') return '';
    return t;
}
function clamp(v, a, b) { return Math.max(a, Math.min(v, b)); }
function sanitizeFileName(s) { return String(s || 'untitled').replace(/[\\/:*?"<>|]/g, '_').trim(); }
function pad2(v) {
    const n = parseInt(v, 10);
    if (isNaN(n)) return String(v || '');
    return n < 10 ? '0' + n : String(n);
}
function styleFlags(bold, italic) {
    let s = 0;
    if (bold) s += 1;
    if (italic) s += 2;
    return s;
}
function colorToRgbObj(c) { return { r: (c >> 16) & 255, g: (c >> 8) & 255, b: c & 255 }; }
function makeColor(r, g, b) { return { r: r, g: g, b: b }; }
function blendRgb(a, b, t) {
    return { r: Math.round(a.r + (b.r - a.r) * t), g: Math.round(a.g + (b.g - a.g) * t), b: Math.round(a.b + (b.b - a.b) * t) };
}
function generateRandomSeed8() {
    return String(Math.floor(Math.random() * 100000000)).padStart(8, '0');
}
function ensureFusionSeed(seedText) {
    return nonEmpty(seedText) ? String(seedText) : generateRandomSeed8();
}
function hashSeedString(seedText) {
    const s = String(seedText || '');
    let h = 2166136261 >>> 0;
    for (let i = 0; i < s.length; i++) {
        h ^= s.charCodeAt(i);
        h = Math.imul(h, 16777619) >>> 0;
    }
    h ^= h >>> 13;
    h = Math.imul(h, 0x5bd1e995) >>> 0;
    h ^= h >>> 15;
    return h >>> 0;
}
function createSeededRandom(seedText) {
    let state = hashSeedString(seedText);
    if (!state) state = 0x9E3779B9;
    return function () {
        state = (Math.imul(state, 1664525) + 1013904223) >>> 0;
        return state / 4294967296;
    };
}
function luminanceOfRgb(c) { return (0.299 * c.r + 0.587 * c.g + 0.114 * c.b) / 255; }
function alphaColor(base, a) { return (alphaByte(a) << 24) | (base & 0x00ffffff); }

function tryGetFontName(name) {
    try {
        if (utils && typeof utils.CheckFont === 'function') return utils.CheckFont(name) ? String(name) : '';
    } catch (e) {}
    try {
        const f = gdi.Font(name, 24, 0);
        if (f && f.Name && String(f.Name).toLowerCase() === String(name).toLowerCase()) return f.Name;
    } catch (e2) {}
    return '';
}
function resolveDefaultFontName() {
    const h = tryGetFontName('HarmonyOS Sans SC');
    if (h) return h;
    const y = tryGetFontName('微软雅黑');
    if (y) return y;
    return '微软雅黑';
}
function fileExists(path) {
    try {
        const fso = new ActiveXObject('Scripting.FileSystemObject');
        return fso.FileExists(path);
    } catch (e) { return false; }
}
function ensureFolder(path) {
    try {
        utils.CreateFolder(path);
        return true;
    } catch (e) {
        try {
            const fso = new ActiveXObject('Scripting.FileSystemObject');
            if (!fso.FolderExists(path)) fso.CreateFolder(path);
            return true;
        } catch (e2) { return false; }
    }
}
function uniquePath(baseDir, fileNameNoExt, ext) {
    const fso = new ActiveXObject('Scripting.FileSystemObject');
    let out = baseDir + fileNameNoExt + ext;
    let i = 1;
    while (fso.FileExists(out)) {
        out = baseDir + fileNameNoExt + ' (' + i + ')' + ext;
        i++;
    }
    return out;
}
function readTextFile(path) {
    const fso = new ActiveXObject('Scripting.FileSystemObject');
    const ts = fso.OpenTextFile(path, 1, false, -1);
    const txt = ts.ReadAll();
    ts.Close();
    return txt;
}
function writeTextFile(path, text) {
    const fso = new ActiveXObject('Scripting.FileSystemObject');
    const folder = fso.GetParentFolderName(path);
    if (folder && !fso.FolderExists(folder)) fso.CreateFolder(folder);
    const ts = fso.OpenTextFile(path, 2, true, -1);
    ts.Write(text);
    ts.Close();
}
const INPUT_CANCELLED = {};
function requestInput(prompt, caption, defaultValue) {
    try {
        return utils.InputBox(window.ID, prompt, caption, defaultValue, true);
    } catch (e) {
        return INPUT_CANCELLED;
    }
}
function inputWasCancelled(value) { return value === INPUT_CANCELLED; }

function showMultilineEditor(title, prompt, defaultValue, onAccept) {
    const initial = String(defaultValue === undefined || defaultValue === null ? '' : defaultValue).replace(/\r\n?/g, '\n');
    if (utils && typeof utils.ShowHtmlDialog === 'function') {
        const html = [
            '<!DOCTYPE html><html><head><meta http-equiv="x-ua-compatible" content="IE=9" />',
            '<meta charset="utf-8"><style>',
            'html,body{margin:0;padding:0;background:#17181d;color:#f4f4f4;font:14px Microsoft YaHei,微软雅黑,sans-serif;overflow:hidden}',
            '.wrap{position:absolute;left:14px;right:14px;top:12px;bottom:54px}',
            '#prompt{height:38px;white-space:pre-wrap;color:#d6d6d6}',
            'textarea{position:absolute;left:0;right:0;top:44px;bottom:0;width:100%;height:calc(100% - 44px);box-sizing:border-box;resize:none;background:#0f1014;color:#fff;border:1px solid #555;padding:10px;font:14px Microsoft YaHei,微软雅黑,sans-serif;line-height:1.5}',
            'button{position:absolute;bottom:12px;width:88px;height:30px;border:1px solid #666;background:#2b2d34;color:#fff}',
            '#ok{right:110px}#cancel{right:14px}',
            '</style><title>MusicCard</title></head><body>',
            '<div class="wrap"><div id="prompt"></div><textarea id="editor"></textarea></div>',
            '<button id="ok">保存</button><button id="cancel">取消</button>',
            '<script>',
            'var args=null,cb=null,closed=false;try{args=window.external.dialogArguments.toArray();}catch(e){}',
            'if(args){document.title=args[0];document.getElementById("prompt").innerText=args[1];document.getElementById("editor").value=args[2];cb=args[3];}',
            'function closeWin(){closed=true;window.open("","_self","");window.close();}',
            'document.getElementById("ok").onclick=function(){if(cb)cb("ok",document.getElementById("editor").value);closeWin();};',
            'document.getElementById("cancel").onclick=function(){if(cb)cb("cancel",document.getElementById("editor").value);closeWin();};',
            'window.onunload=function(){if(!closed&&cb)cb("cancel",document.getElementById("editor").value);};',
            'window.resizeTo(720,520);document.getElementById("editor").focus();',
            '</script></body></html>'
        ].join('');
        try {
            utils.ShowHtmlDialog(window.ID, html, {
                data: [String(title || '多行文本'), String(prompt || ''), initial, function (status, value) {
                    if (status === 'ok' && typeof onAccept === 'function') onAccept(String(value || '').replace(/\r\n?/g, '\n'));
                }]
            });
            return;
        } catch (e) {}
    }

    // Compatibility fallback: type literal \n where a line break is needed.
    const fallback = requestInput(String(prompt || '') + '\n\n当前环境无法打开多行编辑器；可用 \\n 表示换行。', String(title || '多行文本'), initial.replace(/\n/g, '\\n'));
    if (inputWasCancelled(fallback)) return;
    if (typeof onAccept === 'function') onAccept(String(fallback).replace(/\\n/g, '\n'));
}

function normalizeHex(v) {
    const s = String(v || '').trim();
    if (!s) return '';
    const x = s[0] === '#' ? s.slice(1) : s;
    if (!/^[0-9a-fA-F]{6}$/.test(x)) return null;
    return '#' + x.toLowerCase();
}
function hexToRgb(hex) {
    const n = normalizeHex(hex);
    if (!n) return null;
    return { r: parseInt(n.slice(1, 3), 16), g: parseInt(n.slice(3, 5), 16), b: parseInt(n.slice(5, 7), 16) };
}
function normalizeBaseColorToken(value, lowercaseHex) {
    const raw = String(value === undefined || value === null ? '' : value).trim();
    if (!raw) return null;
    if (/^#?black$/i.test(raw)) return COLOR_BLACK_TOKEN;
    if (/^#?white$/i.test(raw)) return COLOR_WHITE_TOKEN;
    const hex = normalizeHex(raw);
    if (!hex) return null;
    return lowercaseHex ? hex.toLowerCase() : hex;
}
function parseRainbowColorSpec(value) {
    const raw = String(value === undefined || value === null ? '' : value).trim();
    const match = /^(?:rainbow|r)%\s*([+-]?(?:\d+(?:\.\d{1,3})?|\.\d{1,3}))(?:\s*\+\s*(.+))?$/i.exec(raw);
    if (!match) return null;
    const percent = parseFloatInput(match[1], RAINBOW_MIN_PERCENT, RAINBOW_MAX_PERCENT);
    if (percent === null) return null;
    const hasExplicitBase = match[2] !== undefined;
    const base = hasExplicitBase ? normalizeBaseColorToken(match[2], true) : '';
    if (hasExplicitBase && !base) return null;
    return {
        percent: percent,
        base: base,
        automaticBase: !hasExplicitBase,
        canonical: 'r%' + formatNumber(percent) + (hasExplicitBase ? '+' + base : '')
    };
}
function normalizeColorSpec(value) {
    const raw = String(value === undefined || value === null ? '' : value).trim();
    if (!raw) return '';
    const rainbow = parseRainbowColorSpec(raw);
    if (rainbow) return rainbow.canonical;
    return normalizeBaseColorToken(raw, false);
}
function isRainbowColorSpec(value) {
    return !!parseRainbowColorSpec(value);
}
function colorSpecInputNote(allowEmptyAuto) {
    return (allowEmptyAuto ? '留空=自动黑/白。\n' : '') +
        '支持 #rrggbb（可省略 #）；black/#black=自动黑色 (18,18,18)，white/#white=自动白色 (250,250,250)，均不区分大小写且可省略 #。\n' +
        '彩虹色格式：rainbow%n 或 rainbow%n+hex，n 为 0-100、最多三位小数；省略 hex 时使用当前自动黑/白；hex 可为六位十六进制、black/#black 或 white/#white。';
}
function colorSpecErrorText(allowEmptyAuto) {
    return '颜色格式无效。\n' + colorSpecInputNote(allowEmptyAuto);
}
function normalizeCustomRainbowHex(value) {
    const raw = String(value === undefined || value === null ? '' : value).trim();
    if (!raw) return '';
    return normalizeBaseColorToken(raw, false);
}
function customRainbowHexInputNote() {
    return '留空=自动黑/白。\n支持 #rrggbb（可省略 #）；black/#black、white/#white 均可省略 # 且不区分大小写。\n此处不允许输入 rainbow/r% 表达式，避免彩虹色嵌套。';
}
function baseColorTokenToRgb(token) {
    const normalized = normalizeBaseColorToken(token, false);
    if (!normalized) return null;
    if (normalized === COLOR_BLACK_TOKEN) return makeColor(COLOR_BLACK_RGB.r, COLOR_BLACK_RGB.g, COLOR_BLACK_RGB.b);
    if (normalized === COLOR_WHITE_TOKEN) return makeColor(COLOR_WHITE_RGB.r, COLOR_WHITE_RGB.g, COLOR_WHITE_RGB.b);
    return hexToRgb(normalized);
}
function resolveColorSpecRgb(spec, autoBase, rainbowRgb) {
    const normalized = normalizeColorSpec(spec);
    if (normalized === '') return colorToRgbObj(autoBase);
    if (!normalized) return null;
    const rainbow = parseRainbowColorSpec(normalized);
    if (rainbow) {
        const base = rainbow.automaticBase ? colorToRgbObj(autoBase) : baseColorTokenToRgb(rainbow.base);
        const target = rainbowRgb || makeColor(255, 0, 0);
        return blendRgb(base, target, rainbow.percent / 100);
    }
    return baseColorTokenToRgb(normalized);
}
function normalizeEnvironmentColorHex(value) {
    const raw = String(value === undefined || value === null ? '' : value).trim();
    if (!raw) return null;
    return normalizeHex(raw);
}
function normalizeEnvironmentColorArray(value) {
    let source = value;
    if (typeof source === 'string') {
        const raw = source.trim();
        if (!raw) return [];
        try { source = JSON.parse(raw); } catch (e) { return []; }
    }
    if (!Array.isArray(source)) return [];
    const out = [];
    for (let i = 0; i < source.length && out.length < CUSTOM_ENVIRONMENT_COLOR_COUNT; i++) {
        const hex = normalizeEnvironmentColorHex(source[i]);
        if (!hex) return [];
        out.push(hex);
    }
    return out.length === CUSTOM_ENVIRONMENT_COLOR_COUNT ? out : [];
}
function parseStoredBoolean(value, fallback) {
    if (value === true || value === false) return value;
    const raw = String(value === undefined || value === null ? '' : value).trim().toLowerCase();
    if (raw === 'true' || raw === '1') return true;
    if (raw === 'false' || raw === '0') return false;
    return !!fallback;
}

const DEFAULT_FONT_NAME = resolveDefaultFontName();
const DEFAULT_DISPLAY_FONT_NAME = tryGetFontName('微软雅黑') || '微软雅黑';
let DISPLAY_FONT_NAME = tryGetFontName(window.GetProperty(PROP_DISPLAY_FONT_NAME, DEFAULT_DISPLAY_FONT_NAME)) || DEFAULT_DISPLAY_FONT_NAME;
const DEFAULT_EXPORT_SCALE = 1;
const DEFAULT_BACKGROUND_STYLE = "fusion";
const DEFAULT_BLUR_STRENGTH = 300;
const DEFAULT_SOLID_BG_HEX = "#000000";
const DEFAULT_COVER_SHADOW_OPACITY = 40;
const DEFAULT_COVER_SHADOW_DEPTH = 3;
const DEFAULT_TEXT_RENDERING_HINT = 3;
const DEFAULT_COVER_CORNER_RADIUS = 0;
const DEFAULT_IRREGULAR_COVER_MODE = 'crop';
const DEFAULT_BLUR_BG_CROP_POSITION = 50;
const LEGACY_ALBUM_SECOND_LINE_EXPRESSION_V2 = "[%datey% ][$if(%discnumber%,Disc %discnumber%[ / %totaldiscs%]$if(%tracknumber%,: ,),)][$if(%tracknumber%,Track $if(%totaltracks%,$num(%tracknumber%,$len(%totaltracks%)),$num(%tracknumber%,2))[ / %totaltracks%],)]";
const LEGACY_ALBUM_SECOND_LINE_EXPRESSION_V3 = "[%datey% · ][$if(%discnumber%,Disc %discnumber%[ / %totaldiscs%]$if(%tracknumber%,: ,),)][$if(%tracknumber%,Track $if(%totaltracks%,$num(%tracknumber%,$len(%totaltracks%)),$num(%tracknumber%,2))[ / %totaltracks%],)]";
const LEGACY_ALBUM_SECOND_LINE_EXPRESSION_V4 = "[%datey%][$if($and(%date%,$or(%discnumber%,%tracknumber%)), · ,)][$if(%discnumber%,Disc %discnumber%[ / %totaldiscs%]$if(%tracknumber%,: ,),)][$if(%tracknumber%,Track $if(%totaltracks%,$num(%tracknumber%,$len(%totaltracks%)),$num(%tracknumber%,2))[ / %totaltracks%],)]";
const DEFAULT_TITLE_LABEL_EXPRESSION = "Title";
const DEFAULT_TITLE_VALUE_EXPRESSION = "$if2(%title%,)";
const DEFAULT_ARTIST_LABEL_EXPRESSION = "Artist";
const DEFAULT_ARTIST_VALUE_EXPRESSION = "$if2(%artist%,%album artist%)";
const DEFAULT_ALBUM_LABEL_EXPRESSION = "Album";
const DEFAULT_ALBUM_VALUE_EXPRESSION = "$if2(%album%,)";
const DEFAULT_ALBUM_SECOND_LINE_EXPRESSION = "[%datey%]$if(%date%,$if(%discnumber%, · ,$if(%tracknumber%, · ,)),)[$if(%discnumber%,Disc %discnumber%[ / %totaldiscs%]$if(%tracknumber%,: ,),)][$if(%tracknumber%,Track $if(%totaltracks%,$num(%tracknumber%,$len(%totaltracks%)),$num(%tracknumber%,2))[ / %totaltracks%],)]";
const DEFAULT_WATERMARK_EXPRESSION = "";
const DEFAULT_STYLE = {
    titleLabel: { size: 28, bold: false, italic: true, font: DEFAULT_FONT_NAME, colorHex: "", opacity: 200, blurStrength: 0, blurOpacity: 0, letterSpacing: "", text: DEFAULT_TITLE_LABEL_EXPRESSION },
    titleValue: { size: 28, bold: true, italic: false, font: DEFAULT_FONT_NAME, colorHex: "", opacity: 255, blurStrength: 0, blurOpacity: 0, letterSpacing: "", text: DEFAULT_TITLE_VALUE_EXPRESSION },
    artistLabel: { size: 28, bold: false, italic: true, font: DEFAULT_FONT_NAME, colorHex: "", opacity: 200, blurStrength: 0, blurOpacity: 0, letterSpacing: "", text: DEFAULT_ARTIST_LABEL_EXPRESSION },
    artistValue: { size: 28, bold: false, italic: false, font: DEFAULT_FONT_NAME, colorHex: "", opacity: 255, blurStrength: 0, blurOpacity: 0, letterSpacing: "", text: DEFAULT_ARTIST_VALUE_EXPRESSION },
    albumLabel: { size: 28, bold: false, italic: true, font: DEFAULT_FONT_NAME, colorHex: "", opacity: 200, blurStrength: 0, blurOpacity: 0, letterSpacing: "", text: DEFAULT_ALBUM_LABEL_EXPRESSION },
    albumValue: { size: 28, bold: false, italic: false, font: DEFAULT_FONT_NAME, colorHex: "", opacity: 255, blurStrength: 0, blurOpacity: 0, letterSpacing: "", text: DEFAULT_ALBUM_VALUE_EXPRESSION },
    metaValue: { size: 20, bold: false, italic: false, font: DEFAULT_FONT_NAME, colorHex: "", opacity: 255, blurStrength: 0, blurOpacity: 0, letterSpacing: "", text: DEFAULT_ALBUM_SECOND_LINE_EXPRESSION },
    watermark: { size: 10, bold: false, italic: false, font: DEFAULT_FONT_NAME, colorHex: "", opacity: 255, blurStrength: 0, blurOpacity: 0, letterSpacing: "", text: DEFAULT_WATERMARK_EXPRESSION }
};
const DEFAULT_LYRICS_CONFIG = {
    enabled: false,
    containerWidth: 0,
    text: "",
    size: 28,
    font: DEFAULT_FONT_NAME,
    bold: false,
    italic: false,
    colorHex: "",
    opacity: 255,
    blurStrength: 0,
    blurOpacity: 0,
    letterSpacing: "",
    topPadding: 0,
    bottomPadding: 0,
    lineGap: 40,
    xAlign: 'left',
    yAlign: 'top',
    dividerEnabled: false,
    dividerThickness: 1,
    dividerTopHex: "",
    dividerTopOpacity: 255,
    dividerMiddleHex: "",
    dividerMiddleOpacity: 255,
    dividerBottomHex: "",
    dividerBottomOpacity: 255,
    dividerTopPadding: 0,
    dividerBottomPadding: 0,
    dividerLeftGap: 20,
    dividerRightGap: 20,
    rightGap: 20
};
const STYLE_KEYS = [
    ['titleLabel', 'Title'],
    ['titleValue', 'Title 文本'],
    ['artistLabel', 'Artist'],
    ['artistValue', 'Artist 文本'],
    ['albumLabel', 'Album'],
    ['albumValue', 'Album 文本第一行'],
    ['metaValue', 'Album 文本第二行'],
    ['watermark', '水印']
];
const SETTINGS_COLUMNS = [
    { key: 'rowLabel', title: '元素', w: 140, type: 'row' },
    { key: 'size', title: '字号', w: 72, type: 'number' },
    { key: 'font', title: '字体', w: 170, type: 'string' },
    { key: 'bold', title: '粗体', w: 66, type: 'bool' },
    { key: 'italic', title: '斜体', w: 66, type: 'bool' },
    { key: 'colorHex', title: 'HEX', w: 170, type: 'hex' },
    { key: 'opacity', title: '不透明度', w: 88, type: 'number' },
    { key: 'blurStrength', title: '模糊强度', w: 96, type: 'number' },
    { key: 'blurOpacity', title: '模糊不透明度', w: 112, type: 'number' },
    { key: 'letterSpacing', title: '字间距', w: 96, type: 'number' },
    { key: 'text', title: '文本内容', w: 164, type: 'text' }
];
function clone(obj) { return JSON.parse(JSON.stringify(obj)); }
function mergedStyle(raw) {
    const out = clone(DEFAULT_STYLE);
    if (raw && typeof raw === 'object') {
        for (let i = 0; i < STYLE_KEYS.length; i++) {
            const key = STYLE_KEYS[i][0];
            if (raw[key] && typeof raw[key] === 'object') {
                for (const k in out[key]) if (raw[key][k] !== undefined) out[key][k] = raw[key][k];
            }
        }
    }
    for (let i = 0; i < STYLE_KEYS.length; i++) {
        const key = STYLE_KEYS[i][0];
        const entry = out[key];
        const def = DEFAULT_STYLE[key];
        entry.size = parseStoredNumber(entry.size, def.size, 0.001, 1000);
        entry.font = String(entry.font || DEFAULT_FONT_NAME);
        entry.bold = !!entry.bold;
        entry.italic = !!entry.italic;
        entry.colorHex = normalizeColorSpec(entry.colorHex) || '';
        entry.opacity = parseStoredNumber(entry.opacity, def.opacity, 0, 255);
        entry.blurStrength = clamp(parseInt(entry.blurStrength, 10) || 0, 0, MAX_TEXT_BLUR_STRENGTH);
        entry.blurOpacity = parseStoredNumber(entry.blurOpacity, def.blurOpacity, 0, 255);
        entry.letterSpacing = parseStoredLetterSpacing(entry.letterSpacing, def.letterSpacing);
        entry.text = String(entry.text === undefined || entry.text === null ? def.text : entry.text);
    }
    return out;
}
function mergedLyrics(raw) {
    const out = clone(DEFAULT_LYRICS_CONFIG);
    if (raw && typeof raw === 'object') for (const k in out) if (raw[k] !== undefined) out[k] = raw[k];
    out.enabled = !!out.enabled;
    out.containerWidth = parseStoredNumber(out.containerWidth, 0, 0, MAX_LYRICS_CONTAINER_WIDTH);
    out.size = parseStoredNumber(out.size, DEFAULT_LYRICS_CONFIG.size, 0.001, 1000);
    out.font = String(out.font || DEFAULT_FONT_NAME);
    out.bold = !!out.bold;
    out.italic = !!out.italic;
    out.colorHex = normalizeColorSpec(out.colorHex) || '';
    out.opacity = parseStoredNumber(out.opacity, DEFAULT_LYRICS_CONFIG.opacity, 0, 255);
    out.blurStrength = clamp(parseInt(out.blurStrength, 10) || 0, 0, MAX_TEXT_BLUR_STRENGTH);
    out.blurOpacity = parseStoredNumber(out.blurOpacity, DEFAULT_LYRICS_CONFIG.blurOpacity, 0, 255);
    out.letterSpacing = parseStoredLetterSpacing(out.letterSpacing, DEFAULT_LYRICS_CONFIG.letterSpacing);
    out.topPadding = parseStoredNumber(out.topPadding, 0, 0, 1000);
    out.bottomPadding = parseStoredNumber(out.bottomPadding, 0, 0, 1000);
    out.lineGap = parseStoredNumber(out.lineGap, DEFAULT_LYRICS_CONFIG.lineGap, 0, 500);
    if (raw && raw.xAlign === undefined && raw.align !== undefined) out.xAlign = raw.align;
    out.xAlign = ['left', 'center', 'right'].includes(String(out.xAlign)) ? String(out.xAlign) : 'left';
    out.yAlign = ['top', 'center', 'bottom'].includes(String(out.yAlign)) ? String(out.yAlign) : 'top';
    out.dividerEnabled = !!out.dividerEnabled;
    out.dividerThickness = parseStoredNumber(out.dividerThickness, DEFAULT_LYRICS_CONFIG.dividerThickness, 0.001, 100);
    out.dividerTopHex = normalizeColorSpec(out.dividerTopHex) || '';
    out.dividerTopOpacity = parseStoredNumber(out.dividerTopOpacity, DEFAULT_LYRICS_CONFIG.dividerTopOpacity, 0, 255);
    out.dividerMiddleHex = normalizeColorSpec(out.dividerMiddleHex) || '';
    out.dividerMiddleOpacity = parseStoredNumber(out.dividerMiddleOpacity, DEFAULT_LYRICS_CONFIG.dividerMiddleOpacity, 0, 255);
    out.dividerBottomHex = normalizeColorSpec(out.dividerBottomHex) || '';
    out.dividerBottomOpacity = parseStoredNumber(out.dividerBottomOpacity, DEFAULT_LYRICS_CONFIG.dividerBottomOpacity, 0, 255);
    out.dividerTopPadding = parseStoredNumber(out.dividerTopPadding, 0, 0, 1000);
    out.dividerBottomPadding = parseStoredNumber(out.dividerBottomPadding, 0, 0, 1000);
    out.dividerLeftGap = parseStoredNumber(out.dividerLeftGap, DEFAULT_LYRICS_CONFIG.dividerLeftGap, 0, 1000);
    out.dividerRightGap = parseStoredNumber(out.dividerRightGap, DEFAULT_LYRICS_CONFIG.dividerRightGap, 0, 1000);
    out.rightGap = parseStoredNumber(out.rightGap, DEFAULT_LYRICS_CONFIG.rightGap, 0, 1000);
    out.text = String(out.text === undefined || out.text === null ? '' : out.text).replace(/\r\n?/g, '\n');
    return out;
}
function rowSupportsText(rowKey) { return !!DEFAULT_STYLE[rowKey]; }
function getStyleRowLabel(rowKey) {
    for (let i = 0; i < STYLE_KEYS.length; i++) if (STYLE_KEYS[i][0] === rowKey) return STYLE_KEYS[i][1];
    return rowKey;
}

let STYLE_CONFIG = (function () {
    try { return mergedStyle(JSON.parse(window.GetProperty(PROP_STYLE_JSON, JSON.stringify(DEFAULT_STYLE)))); }
    catch (e) { return clone(DEFAULT_STYLE); }
})();
let LYRICS_CONFIG = (function () {
    try { return mergedLyrics(JSON.parse(window.GetProperty(PROP_LYRICS_JSON, JSON.stringify(DEFAULT_LYRICS_CONFIG)))); }
    catch (e) { return clone(DEFAULT_LYRICS_CONFIG); }
})();
let STYLE_SCHEMA_VERSION = parseInt(window.GetProperty(PROP_STYLE_SCHEMA_VERSION, 1), 10) || 1;
if (STYLE_SCHEMA_VERSION < CURRENT_STYLE_SCHEMA_VERSION) {
    // Schema v3 introduced the editable Album second-line expression and the " · " year separator.
    if (STYLE_SCHEMA_VERSION < 3) {
        STYLE_CONFIG.metaValue = STYLE_CONFIG.metaValue || clone(DEFAULT_STYLE.metaValue);
        const currentMetaExpression = String(STYLE_CONFIG.metaValue.text || '');
        if (!currentMetaExpression.trim() || currentMetaExpression === LEGACY_ALBUM_SECOND_LINE_EXPRESSION_V2) {
            STYLE_CONFIG.metaValue.text = DEFAULT_ALBUM_SECOND_LINE_EXPRESSION;
        }
    }
    // Before schema v4, Title/Artist/Album value rows were generated internally and
    // their text cells were not editable. Fill only empty legacy cells so custom data survives.
    if (STYLE_SCHEMA_VERSION < 4) {
        const legacyExpressionDefaults = {
            titleValue: DEFAULT_TITLE_VALUE_EXPRESSION,
            artistValue: DEFAULT_ARTIST_VALUE_EXPRESSION,
            albumValue: DEFAULT_ALBUM_VALUE_EXPRESSION
        };
        for (const key in legacyExpressionDefaults) {
            STYLE_CONFIG[key] = STYLE_CONFIG[key] || clone(DEFAULT_STYLE[key]);
            if (!String(STYLE_CONFIG[key].text || '').trim()) STYLE_CONFIG[key].text = legacyExpressionDefaults[key];
        }
    }
    // Schema v6 only changes the built-in Album second-line expression. Migrate
    // exact legacy defaults, but preserve every user-edited expression.
    if (STYLE_SCHEMA_VERSION < 6) {
        STYLE_CONFIG.metaValue = STYLE_CONFIG.metaValue || clone(DEFAULT_STYLE.metaValue);
        const currentMetaExpressionV6 = String(STYLE_CONFIG.metaValue.text || '');
        if (!currentMetaExpressionV6.trim() ||
            currentMetaExpressionV6 === LEGACY_ALBUM_SECOND_LINE_EXPRESSION_V2 ||
            currentMetaExpressionV6 === LEGACY_ALBUM_SECOND_LINE_EXPRESSION_V3) {
            STYLE_CONFIG.metaValue.text = DEFAULT_ALBUM_SECOND_LINE_EXPRESSION;
        }
    }
    // Schema v7 removes the optional-section wrapper around the separator.
    // A literal-only $if() result inside [...] is discarded by title formatting.
    if (STYLE_SCHEMA_VERSION < 7) {
        STYLE_CONFIG.metaValue = STYLE_CONFIG.metaValue || clone(DEFAULT_STYLE.metaValue);
        const currentMetaExpressionV7 = String(STYLE_CONFIG.metaValue.text || '');
        if (!currentMetaExpressionV7.trim() ||
            currentMetaExpressionV7 === LEGACY_ALBUM_SECOND_LINE_EXPRESSION_V2 ||
            currentMetaExpressionV7 === LEGACY_ALBUM_SECOND_LINE_EXPRESSION_V3 ||
            currentMetaExpressionV7 === LEGACY_ALBUM_SECOND_LINE_EXPRESSION_V4) {
            STYLE_CONFIG.metaValue.text = DEFAULT_ALBUM_SECOND_LINE_EXPRESSION;
        }
    }
    // Schema v11 replaces the legacy numeric sentinel -1 with an empty string.
    // Existing v4.15.4/v4.15.5 configurations keep their native-rendering behavior;
    // in v11 and later, a numeric -1 means manual spacing of -1 px.
    if (STYLE_SCHEMA_VERSION < 11) {
        for (let i = 0; i < STYLE_KEYS.length; i++) {
            const key = STYLE_KEYS[i][0];
            if (STYLE_CONFIG[key] && Math.abs(Number(STYLE_CONFIG[key].letterSpacing) + 1) < 0.0005) {
                STYLE_CONFIG[key].letterSpacing = '';
            }
        }
        if (Math.abs(Number(LYRICS_CONFIG.letterSpacing) + 1) < 0.0005) LYRICS_CONFIG.letterSpacing = '';
    }
    // Schema v12 adds named automatic colours and rainbow colour expressions.
    // Existing six-digit HEX values are preserved by normalizeColorSpec().
    // Schema v13 adds sampled/custom rainbow targets and a five-colour cover palette selector.
    // Schema v15 adds independent display-only opencc-js modes for card text and lyrics.
    // Schema v16 records MusicCard version metadata and keeps s2tw→s2twp migration.
    STYLE_SCHEMA_VERSION = CURRENT_STYLE_SCHEMA_VERSION;
}
let EXPORT_SCALE = parseStoredNumber(window.GetProperty(PROP_SCALE, DEFAULT_EXPORT_SCALE), DEFAULT_EXPORT_SCALE, 0.1, 10);
let CUSTOM_EXPORT_SCALE = (function () {
    const raw = parseFloat(window.GetProperty(PROP_CUSTOM_SCALE, ''));
    if (isFinite(raw) && raw >= 0.1 && raw <= 10) return round3(raw);
    return [1, 2, 3, 4].includes(EXPORT_SCALE) ? null : EXPORT_SCALE;
})();
let BACKGROUND_STYLE = String(window.GetProperty(PROP_BG_STYLE, DEFAULT_BACKGROUND_STYLE) || DEFAULT_BACKGROUND_STYLE).toLowerCase();
if (BACKGROUND_STYLE !== 'fusion' && BACKGROUND_STYLE !== 'sample' && BACKGROUND_STYLE !== 'blur' && BACKGROUND_STYLE !== 'ink' && BACKGROUND_STYLE !== 'solid') BACKGROUND_STYLE = DEFAULT_BACKGROUND_STYLE;
let BLUR_STRENGTH = parseInt(window.GetProperty(PROP_BLUR_STRENGTH, DEFAULT_BLUR_STRENGTH), 10);
if (isNaN(BLUR_STRENGTH)) BLUR_STRENGTH = DEFAULT_BLUR_STRENGTH;
BLUR_STRENGTH = clamp(BLUR_STRENGTH, 0, MAX_BLUR_STRENGTH);
let SOLID_BG_HEX = normalizeColorSpec(window.GetProperty(PROP_SOLID_HEX, DEFAULT_SOLID_BG_HEX)) || DEFAULT_SOLID_BG_HEX;
let COVER_SHADOW_OPACITY = parseStoredNumber(window.GetProperty(PROP_SHADOW_OPACITY, DEFAULT_COVER_SHADOW_OPACITY), DEFAULT_COVER_SHADOW_OPACITY, 0, 255);
let COVER_SHADOW_DEPTH = parseStoredNumber(window.GetProperty(PROP_SHADOW_DEPTH, DEFAULT_COVER_SHADOW_DEPTH), DEFAULT_COVER_SHADOW_DEPTH, 0, 100);
let TEXT_RENDERING_HINT = clamp(parseInt(window.GetProperty(PROP_TEXT_RENDERING_HINT, DEFAULT_TEXT_RENDERING_HINT), 10) || 0, 0, 5);
let COVER_CORNER_RADIUS = clamp(parseInt(window.GetProperty(PROP_COVER_CORNER_RADIUS, DEFAULT_COVER_CORNER_RADIUS), 10) || 0, 0, MAX_COVER_CORNER_RADIUS);
let IRREGULAR_COVER_MODE = String(window.GetProperty(PROP_IRREGULAR_COVER_MODE, DEFAULT_IRREGULAR_COVER_MODE) || DEFAULT_IRREGULAR_COVER_MODE).toLowerCase();
if (IRREGULAR_COVER_MODE !== 'crop' && IRREGULAR_COVER_MODE !== 'tile') IRREGULAR_COVER_MODE = DEFAULT_IRREGULAR_COVER_MODE;
let BLUR_BG_CROP_POSITION = parseStoredNumber(
    window.GetProperty(PROP_BLUR_BG_CROP_POSITION,
        window.GetProperty(PROP_BLUR_BG_CROP_POSITION_LEGACY, DEFAULT_BLUR_BG_CROP_POSITION)),
    DEFAULT_BLUR_BG_CROP_POSITION, 0, 100
);
let RAINBOW_SAMPLE_MAX_SIDE = parseStoredInteger(
    window.GetProperty(PROP_RAINBOW_SAMPLE_MAX_SIDE,
        window.GetProperty(PROP_RAINBOW_SAMPLE_MAX_SIDE_LEGACY, DEFAULT_RAINBOW_SAMPLE_MAX_SIDE)),
    DEFAULT_RAINBOW_SAMPLE_MAX_SIDE, 1, 1000
);
let RAINBOW_MODE = String(window.GetProperty(PROP_RAINBOW_MODE, DEFAULT_RAINBOW_MODE) || DEFAULT_RAINBOW_MODE).toLowerCase();
if (RAINBOW_MODE !== 'sample' && RAINBOW_MODE !== 'custom') RAINBOW_MODE = DEFAULT_RAINBOW_MODE;
let RAINBOW_CUSTOM_HEX = normalizeCustomRainbowHex(window.GetProperty(PROP_RAINBOW_CUSTOM_HEX, DEFAULT_RAINBOW_CUSTOM_HEX));
if (RAINBOW_CUSTOM_HEX === null) RAINBOW_CUSTOM_HEX = DEFAULT_RAINBOW_CUSTOM_HEX;
let RAINBOW_CUSTOM_SELECTION = String(window.GetProperty(PROP_RAINBOW_CUSTOM_SELECTION, DEFAULT_RAINBOW_CUSTOM_SELECTION) || DEFAULT_RAINBOW_CUSTOM_SELECTION);
if (RAINBOW_CUSTOM_SELECTION !== 'hex' && !/^palette:[0-4]$/.test(RAINBOW_CUSTOM_SELECTION)) RAINBOW_CUSTOM_SELECTION = DEFAULT_RAINBOW_CUSTOM_SELECTION;
let CUSTOM_ENVIRONMENT_COLORS_ENABLED = parseStoredBoolean(
    window.GetProperty(PROP_CUSTOM_ENVIRONMENT_ENABLED, DEFAULT_CUSTOM_ENVIRONMENT_COLORS_ENABLED),
    DEFAULT_CUSTOM_ENVIRONMENT_COLORS_ENABLED
);
let CUSTOM_ENVIRONMENT_COLOR_HEXES = CUSTOM_ENVIRONMENT_COLORS_ENABLED
    ? normalizeEnvironmentColorArray(window.GetProperty(PROP_CUSTOM_ENVIRONMENT_COLORS, ''))
    : [];
let TEXT_OPENCC_MODE = normalizeOpenCCMode(window.GetProperty(PROP_TEXT_OPENCC_MODE, DEFAULT_TEXT_OPENCC_MODE), DEFAULT_TEXT_OPENCC_MODE);
let LYRICS_OPENCC_MODE = normalizeOpenCCMode(window.GetProperty(PROP_LYRICS_OPENCC_MODE, DEFAULT_LYRICS_OPENCC_MODE), DEFAULT_LYRICS_OPENCC_MODE);

const CONFIG = {
    outputDir: window.GetProperty(PROP_OUTPUT_DIR, window.GetProperty('MusicCard.v4.13.OutputDir', fb.ProfilePath + 'music-card\\')),
    customCoverPath: window.GetProperty(PROP_CUSTOM_COVER, window.GetProperty('MusicCard.v4.13.CustomCoverPath', '')),
    textAutoColor: {
        enabled: true,
        threshold: 0.5,
        darkBackgroundText: RGB(250, 250, 250),
        lightBackgroundText: RGB(18, 18, 18)
    },
    palette: {
        fallback: [makeColor(69, 104, 220), makeColor(176, 106, 179), makeColor(255, 174, 82), makeColor(76, 201, 240)],
        blobAlpha: 110,
        overlayAlpha: 18
    },
    preview: { overlay: RGBA(0, 0, 0, 170), padding: 30, closeSize: 36 }
};

function persistSettings() {
    window.SetProperty(PROP_OUTPUT_DIR, CONFIG.outputDir);
    window.SetProperty(PROP_CUSTOM_COVER, CONFIG.customCoverPath);
    window.SetProperty(PROP_SCALE, EXPORT_SCALE);
    window.SetProperty(PROP_CUSTOM_SCALE, CUSTOM_EXPORT_SCALE === null ? '' : CUSTOM_EXPORT_SCALE);
    window.SetProperty(PROP_STYLE_JSON, JSON.stringify(STYLE_CONFIG));
    window.SetProperty(PROP_BG_STYLE, BACKGROUND_STYLE);
    window.SetProperty(PROP_BLUR_STRENGTH, BLUR_STRENGTH);
    window.SetProperty(PROP_SOLID_HEX, SOLID_BG_HEX);
    window.SetProperty(PROP_SHADOW_OPACITY, COVER_SHADOW_OPACITY);
    window.SetProperty(PROP_SHADOW_DEPTH, COVER_SHADOW_DEPTH);
    window.SetProperty(PROP_TEXT_RENDERING_HINT, TEXT_RENDERING_HINT);
    window.SetProperty(PROP_COVER_CORNER_RADIUS, COVER_CORNER_RADIUS);
    window.SetProperty(PROP_IRREGULAR_COVER_MODE, IRREGULAR_COVER_MODE);
    window.SetProperty(PROP_BLUR_BG_CROP_POSITION, BLUR_BG_CROP_POSITION);
    window.SetProperty(PROP_RAINBOW_SAMPLE_MAX_SIDE, RAINBOW_SAMPLE_MAX_SIDE);
    window.SetProperty(PROP_RAINBOW_MODE, RAINBOW_MODE);
    window.SetProperty(PROP_RAINBOW_CUSTOM_HEX, RAINBOW_CUSTOM_HEX);
    window.SetProperty(PROP_RAINBOW_CUSTOM_SELECTION, RAINBOW_CUSTOM_SELECTION);
    window.SetProperty(PROP_CUSTOM_ENVIRONMENT_ENABLED, CUSTOM_ENVIRONMENT_COLORS_ENABLED);
    window.SetProperty(PROP_CUSTOM_ENVIRONMENT_COLORS, CUSTOM_ENVIRONMENT_COLORS_ENABLED ? JSON.stringify(CUSTOM_ENVIRONMENT_COLOR_HEXES) : '');
    window.SetProperty(PROP_TEXT_OPENCC_MODE, TEXT_OPENCC_MODE);
    window.SetProperty(PROP_LYRICS_OPENCC_MODE, LYRICS_OPENCC_MODE);
    window.SetProperty(PROP_DISPLAY_FONT_NAME, DISPLAY_FONT_NAME);
    window.SetProperty(PROP_LYRICS_JSON, JSON.stringify(LYRICS_CONFIG));
    window.SetProperty(PROP_STYLE_SCHEMA_VERSION, STYLE_SCHEMA_VERSION);
    markSettingsPreviewDirty();
}

const LYRICS_RUNTIME = { initialized: false, trackKey: '', requiresConfirmation: false };
const RAINBOW_COLOR_CACHE = {};
const RAINBOW_COLOR_CACHE_ORDER = [];
const RAINBOW_STYLE_PALETTE_CACHE = {};
const RAINBOW_STYLE_PALETTE_CACHE_ORDER = [];
let LAST_CARD_RENDER_MS = null;
let UI = {
    view: 'main',
    hover: '',
    previewImage: null,
    previewInfo: null,
    previewRenderMs: null,
    previewRect: null,
    closeRect: null,
    buttons: [],
    settingsButtons: {},
    settingsRows: [],
    lyricsButtons: {},
    rainbowPaletteColors: [],
    customEnvironmentColorButtons: [],
    blurSlider: null,
    cornerSlider: null,
    sliderDragging: '',
    copyBusy: false,
    previewSeed: '',
    popupPreviewSeed: '',
    pendingCopySeed: '',
    settingsPreviewEnabled: false,
    settingsPreviewDirty: true,
    settingsPreviewRefreshPending: false,
    settingsPreviewImage: null,
    settingsPreviewRenderMs: null,
    settingsPreviewSeed: '',
    settingsPreviewRect: null,
    settingsTableBottom: 0,
    lyricsSectionBottom: 0,
    settingsInputButton: null,
    settingsCopyImageButton: null,
    settingsResolutionButton: null,
    previewInputButton: null,
    previewSeedCopyButton: null,
    previewSeedRefreshButton: null,
    previewCopyImageButton: null,
    previewResolutionButton: null,
    previewCopyImageBusy: false,
    previewReturnView: 'main',
    sleepButton: null,
    settingsCopyImageBusy: false,
    settingsScrollX: 0,
    settingsScrollY: 0,
    settingsContentW: 940,
    settingsContentH: 0,
    settingsViewport: null,
    settingsVScrollbar: null,
    settingsHScrollbar: null,
    settingsScrollDragging: '',
    settingsScrollDragOffset: 0
};

function disposeImageSafe(img) {
    try { if (img && typeof img.Dispose === 'function') img.Dispose(); } catch (e) {}
}
function markSettingsPreviewDirty() {
    if (typeof UI === 'undefined' || UI.view === 'sleep') return;
    UI.settingsPreviewDirty = true;
    if (UI.settingsPreviewEnabled && UI.view === 'settings') scheduleSettingsPreviewRefresh();
}
function refreshSettingsPreviewNow() {
    if (UI.view === 'sleep' || !UI.settingsPreviewEnabled || UI.view !== 'settings') return;
    try {
        if (BACKGROUND_STYLE === 'fusion' && !UI.settingsPreviewSeed) UI.settingsPreviewSeed = generateRandomSeed8();
        const built = buildCard(pickHandle(), UI.settingsPreviewSeed, EXPORT_SCALE);
        disposeImageSafe(UI.settingsPreviewImage);
        UI.settingsPreviewImage = built.image;
        UI.settingsPreviewRenderMs = built.renderMs;
        if (built.seed) UI.settingsPreviewSeed = built.seed;
        UI.settingsPreviewDirty = false;
    } catch (e) {
        UI.settingsPreviewImage = null;
        UI.settingsPreviewRenderMs = null;
        UI.settingsPreviewDirty = false;
    }
    window.Repaint();
}
function scheduleSettingsPreviewRefresh() {
    if (UI.view === 'sleep' || !UI.settingsPreviewEnabled || UI.view !== 'settings' || UI.settingsPreviewRefreshPending) return;
    UI.settingsPreviewRefreshPending = true;
    const run = function () {
        UI.settingsPreviewRefreshPending = false;
        if (UI.view !== 'sleep' && UI.settingsPreviewEnabled && UI.settingsPreviewDirty && UI.view === 'settings') refreshSettingsPreviewNow();
    };
    if (window && typeof window.SetTimeout === 'function') window.SetTimeout(run, 20);
    else if (typeof setTimeout === 'function') setTimeout(run, 20);
    else run();
}
function deferUiAction(fn) {
    if (window && typeof window.SetTimeout === 'function') window.SetTimeout(fn, 30);
    else if (typeof setTimeout === 'function') setTimeout(fn, 30);
    else fn();
}
function actionToggleSettingsPreview() {
    UI.settingsPreviewEnabled = !UI.settingsPreviewEnabled;
    if (UI.settingsPreviewEnabled) {
        if (!UI.settingsPreviewSeed) UI.settingsPreviewSeed = generateRandomSeed8();
        UI.settingsPreviewDirty = true;
        scheduleSettingsPreviewRefresh();
    } else {
        disposeImageSafe(UI.settingsPreviewImage);
        UI.settingsPreviewImage = null;
        UI.settingsPreviewRenderMs = null;
    }
    window.Repaint();
}

function pickHandle() {
    try {
        const list = plman.GetPlaylistSelectedItems(plman.ActivePlaylist);
        if (list && list.Count > 0) return list[0];
    } catch (e) {}
    try {
        const h = fb.GetFocusItem();
        if (h) return h;
    } catch (e2) {}
    return null;
}
function syncLyricsConfirmationForCurrentTrack() {
    const key = getTrackIdentity(pickHandle());
    if (!LYRICS_RUNTIME.initialized) {
        LYRICS_RUNTIME.initialized = true;
        LYRICS_RUNTIME.trackKey = key;
        return false;
    }
    if (key === LYRICS_RUNTIME.trackKey) return false;
    LYRICS_RUNTIME.trackKey = key;
    LYRICS_RUNTIME.requiresConfirmation = true;
    return true;
}
function confirmLyricsForCurrentTrack() {
    LYRICS_RUNTIME.initialized = true;
    LYRICS_RUNTIME.trackKey = getTrackIdentity(pickHandle());
    LYRICS_RUNTIME.requiresConfirmation = false;
}
function tf(handle, pattern, fallback) {
    try { return safe(fb.TitleFormat(pattern).EvalWithMetadb(handle), fallback || ''); }
    catch (e) { return fallback || ''; }
}
function getInfo(handle) {
    if (!handle) return { title: 'No track selected', artist: '', album: '', year: '', disc: '', discTotal: '', track: '', total: '' };
    const dateRaw = tf(handle, '[%date%]', '');
    const m = String(dateRaw).match(/\d{4}/);
    return {
        title: tf(handle, '$if2(%title%,)', ''),
        artist: tf(handle, '$if2(%artist%,%album artist%)', ''),
        album: tf(handle, '$if2(%album%,)', ''),
        year: m ? m[0] : '',
        disc: cleanNumericTag(tf(handle, '[%discnumber%]', '')),
        discTotal: cleanNumericTag(tf(handle, '[%totaldiscs%]', '') || tf(handle, '[%disctotal%]', '')),
        track: cleanNumericTag(tf(handle, '[%tracknumber%]', '')),
        total: cleanNumericTag(tf(handle, '[%totaltracks%]', '') || tf(handle, '[%tracktotal%]', ''))
    };
}
//opencc-js转换器按模式延迟创建，避免默认关闭时构建四套Trie。
const OPENCC_CONVERTER_OPTIONS = {
    t2s: { from: 't', to: 'cn' },
    s2t: { from: 'cn', to: 't' },
    s2twp: { from: 'cn', to: 'twp' },
    s2hk: { from: 'cn', to: 'hk' }
};
const OPENCC_CONVERTERS = {};
const OPENCC_CONVERTER_ERRORS = {};
let OPENCC_DIAGNOSTIC_SHOWN = false;
function getOpenCCConverter(mode) {
    const normalizedMode = normalizeOpenCCMode(mode, 'off');
    if (normalizedMode === 'off') return null;
    if (OPENCC_CONVERTERS[normalizedMode]) return OPENCC_CONVERTERS[normalizedMode];
    if (!MUSICCARD_OPENCC || typeof MUSICCARD_OPENCC.Converter !== 'function') return null;
    const options = OPENCC_CONVERTER_OPTIONS[normalizedMode];
    if (!options) return null;
    try {
        const started = Date.now();
        const converter = MUSICCARD_OPENCC.Converter(options);
        if (typeof converter !== 'function') throw new Error('OpenCC.Converter未返回函数。');
        OPENCC_CONVERTERS[normalizedMode] = converter;
        OPENCC_CONVERTER_ERRORS[normalizedMode] = '';
        try { console.log('[MusicCard][OpenCC]转换器' + normalizedMode + '初始化成功，耗时' + (Date.now() - started) + 'ms。'); } catch (e) {}
        return converter;
    } catch (e) {
        OPENCC_CONVERTER_ERRORS[normalizedMode] = String(e && e.message ? e.message : e);
        try { console.log('[MusicCard][OpenCC]转换器' + normalizedMode + '初始化失败：' + OPENCC_CONVERTER_ERRORS[normalizedMode]); } catch (e2) {}
        return null;
    }
}
function convertDisplayChineseLine(text, mode, handle) {
    const source = String(text === undefined || text === null ? '' : text);
    const normalizedMode = normalizeOpenCCMode(mode, 'off');
    if (!source || normalizedMode === 'off') return source;
    const converter = getOpenCCConverter(normalizedMode);
    if (!converter) return source;
    try {
        return String(converter(source));
    } catch (e) {
        try { console.log('[MusicCard][OpenCC]模式' + normalizedMode + '转换失败，保持原文：' + e); } catch (e2) {}
        return source;
    }
}
function convertDisplayChinese(text, mode, handle) {
    const source = String(text === undefined || text === null ? '' : text).replace(/\r\n?/g, '\n');
    if (normalizeOpenCCMode(mode, 'off') === 'off' || !source) return source;
    const lines = source.split('\n');
    for (let i = 0; i < lines.length; i++) lines[i] = convertDisplayChineseLine(lines[i], mode, handle);
    return lines.join('\n');
}
function notifyOpenCCUnavailable(mode) {
    if (OPENCC_DIAGNOSTIC_SHOWN) return;
    OPENCC_DIAGNOSTIC_SHOWN = true;
    const normalizedMode = normalizeOpenCCMode(mode, 'off');
    let reasonText = '';
    if (!MUSICCARD_OPENCC || typeof MUSICCARD_OPENCC.Converter !== 'function') {
        reasonText = 'OpenCC依赖文件未能加载或未导出OpenCC.Converter。\n\n' +
            (MUSICCARD_OPENCC_LOAD_ERROR || musicCardFormatOpenCCAttempts() || '没有可用的加载诊断。');
    } else {
        reasonText = 'OpenCC依赖已加载，但转换器初始化失败。\n' +
            '加载路径：' + (MUSICCARD_OPENCC_LOAD_PATH || '未知') + '\n' +
            '转换模式：' + normalizedMode + '\n' +
            '原因：' + (OPENCC_CONVERTER_ERRORS[normalizedMode] || 'OpenCC.Converter未返回可用函数。');
    }
    fb.ShowPopupMessage(
        'OpenCC不可用，简繁转换将保持原文。\n\n' +
        reasonText + '\n\n' +
        '可放置路径：\n' +
        '1.' + MUSICCARD_OPENCC_SCRIPT_RELATIVE_PATH + '（MusicCard主脚本同目录）\n' +
        '2.' + (MUSICCARD_OPENCC_PROFILE_PATH || 'foobar2000配置目录未知') + '\n\n' +
        '请放置正确的' + MUSICCARD_OPENCC_JS_FILENAME + '后重载MusicCard脚本。\n\n' +
        '下载地址：' + MUSICCARD_OPENCC_DOWNLOAD_URL,
        MUSICCARD_TITLE
    );
}
function verifyOpenCCForActiveMode(mode) {
    OPENCC_DIAGNOSTIC_SHOWN = false;
    const converter = getOpenCCConverter(mode);
    if (!converter) notifyOpenCCUnavailable(mode);
    return !!converter;
}

function prepareTextExpression(expression) {
    // %datey% is a MusicCard extension available in all eight text expressions.
    // It keeps only the first four characters of %date%.
    return String(expression || '').replace(/%datey%/gi, '$if(%date%,$substr(%date%,1,4),)');
}
function evaluateTextExpression(handle, expression, fallback) {
    const source = String(expression === undefined || expression === null ? '' : expression);
    if (!source.trim()) return '';
    try {
        const formatter = fb.TitleFormat(prepareTextExpression(source));
        if (handle) return String(formatter.EvalWithMetadb(handle) || '');
        if (formatter && typeof formatter.Eval === 'function') return String(formatter.Eval() || '');
    } catch (e) {}
    return fallback || '';
}
function evaluateAllTextExpressions(handle) {
    const rendered = {
        titleLabel: evaluateTextExpression(handle, STYLE_CONFIG.titleLabel.text, DEFAULT_TITLE_LABEL_EXPRESSION),
        titleValue: handle
            ? evaluateTextExpression(handle, STYLE_CONFIG.titleValue.text, '')
            : 'No track selected',
        artistLabel: evaluateTextExpression(handle, STYLE_CONFIG.artistLabel.text, DEFAULT_ARTIST_LABEL_EXPRESSION),
        artistValue: evaluateTextExpression(handle, STYLE_CONFIG.artistValue.text, ''),
        albumLabel: evaluateTextExpression(handle, STYLE_CONFIG.albumLabel.text, DEFAULT_ALBUM_LABEL_EXPRESSION),
        albumValue: evaluateTextExpression(handle, STYLE_CONFIG.albumValue.text, ''),
        metaValue: evaluateTextExpression(handle, STYLE_CONFIG.metaValue.text, ''),
        watermark: evaluateTextExpression(handle, STYLE_CONFIG.watermark.text, '')
    };
    if (TEXT_OPENCC_MODE !== 'off') {
        for (const key in rendered) rendered[key] = convertDisplayChinese(rendered[key], TEXT_OPENCC_MODE, handle);
    }
    return rendered;
}
function evaluateLyricsLines(handle) {
    if (LYRICS_RUNTIME.requiresConfirmation) return [LYRICS_PLACEHOLDER_TEXT];
    const raw = String(LYRICS_CONFIG.text || '').replace(/\r\n?/g, '\n');
    if (!raw) return [];
    const sourceLines = raw.split('\n');
    const out = [];
    for (let i = 0; i < sourceLines.length; i++) {
        const line = sourceLines[i];
        const renderedLine = line ? evaluateTextExpression(handle, line, line) : '';
        out.push(LYRICS_OPENCC_MODE === 'off' ? renderedLine : convertDisplayChineseLine(renderedLine, LYRICS_OPENCC_MODE, handle));
    }
    return out;
}

function loadCustomCover() {
    try { if (CONFIG.customCoverPath && fileExists(CONFIG.customCoverPath)) return { img: gdi.Image(CONFIG.customCoverPath), hasCover: true }; }
    catch (e) {}
    return null;
}
function createFallbackCover() {
    const size = 900;
    const img = gdi.CreateImage(size, size);
    const gr = img.GetGraphics();
    gr.FillSolidRect(0, 0, size, size, RGBA(36, 39, 45, 255));
    gr.FillSolidRect(150, 150, 600, 600, RGBA(255, 255, 255, 25));
    const f1 = gdi.Font(DEFAULT_FONT_NAME, 64, 1);
    const f2 = gdi.Font(DEFAULT_FONT_NAME, 28, 0);
    gr.SetTextRenderingHint(4);
    gr.GdiDrawText('♪', f1, RGBA(255,255,255,210), 0, 310, size, 80, 0x00000001 | 0x00000004 | DT_NOPREFIX);
    gr.GdiDrawText('No Cover', f2, RGBA(255,255,255,130), 0, 410, size, 48, 0x00000001 | 0x00000004 | DT_NOPREFIX);
    img.ReleaseGraphics(gr);
    return img;
}
function tryGetEmbedded(path) {
    if (!path) return null;
    try { const img = utils.GetAlbumArtEmbedded(path, 0); if (img) return img; } catch (e) {}
    return null;
}
function getCover(handle) {
    const custom = loadCustomCover();
    if (custom) return custom;
    if (!handle) return { img: createFallbackCover(), hasCover: false };
    let img = null;
    try { img = tryGetEmbedded(handle.Path); } catch (e) {}
    if (!img) try { img = tryGetEmbedded(handle.RawPath); } catch (e2) {}
    if (!img) try { img = utils.GetAlbumArtV2(handle, 0); } catch (e3) {}
    if (!img) try { img = utils.GetAlbumArtV2(handle); } catch (e4) {}
    if (img) return { img: img, hasCover: true };
    return { img: createFallbackCover(), hasCover: false };
}
function extractPaletteFromImage(img, requestedCount) {
    const out = [];
    const count = clamp(parseInt(requestedCount, 10) || 6, 1, 20);
    try {
        if (img && typeof img.GetColourSchemeJSON === 'function') {
            const raw = img.GetColourSchemeJSON(count);
            const arr = JSON.parse(raw || '[]');
            for (let i = 0; i < arr.length; i++) if (arr[i] && arr[i].col !== undefined) out.push(colorToRgbObj(arr[i].col));
        }
    } catch (e) {}
    if (!out.length) {
        try {
            if (img && typeof img.GetColourScheme === 'function') {
                const arr2 = img.GetColourScheme(count);
                for (let j = 0; j < arr2.length; j++) out.push(colorToRgbObj(arr2[j]));
            }
        } catch (e2) {}
    }
    if (!out.length) out.push.apply(out, CONFIG.palette.fallback);
    return out;
}
function getCustomEnvironmentRgbColors(requestedCount) {
    const count = clamp(parseInt(requestedCount, 10) || CUSTOM_ENVIRONMENT_COLOR_COUNT, 1, 20);
    const out = [];
    if (!CUSTOM_ENVIRONMENT_COLORS_ENABLED || CUSTOM_ENVIRONMENT_COLOR_HEXES.length !== CUSTOM_ENVIRONMENT_COLOR_COUNT) return out;
    for (let i = 0; i < CUSTOM_ENVIRONMENT_COLOR_HEXES.length && out.length < count; i++) {
        const rgb = hexToRgb(CUSTOM_ENVIRONMENT_COLOR_HEXES[i]);
        if (rgb) out.push(rgb);
    }
    return out;
}
function extractPalette(img, requestedCount) {
    const custom = getCustomEnvironmentRgbColors(requestedCount);
    return custom.length ? custom : extractPaletteFromImage(img, requestedCount);
}
function centerCropResize(img, w, h) {
    if (!img) return createFallbackCover().Resize(w, h, 7);
    const srcW = img.Width, srcH = img.Height;
    const srcRatio = srcW / srcH, dstRatio = w / h;
    let x = 0, y = 0, cw = srcW, ch = srcH;
    if (srcRatio > dstRatio) { ch = srcH; cw = Math.floor(ch * dstRatio); x = Math.floor((srcW - cw) / 2); }
    else { cw = srcW; ch = Math.floor(cw / dstRatio); y = Math.floor((srcH - ch) / 2); }
    return img.Clone(x, y, cw, ch).Resize(w, h, 7);
}

function cropResizeAtPosition(img, w, h, positionPercent) {
    if (!img) return createFallbackCover().Resize(w, h, 7);
    const srcW = img.Width, srcH = img.Height;
    const srcRatio = srcW / srcH, dstRatio = w / h;
    const t = clamp(Number(positionPercent) / 100, 0, 1);
    let x = 0, y = 0, cw = srcW, ch = srcH;
    if (srcRatio > dstRatio) {
        ch = srcH;
        cw = ch * dstRatio;
        x = (srcW - cw) * t; // 0%=left, 100%=right
    } else {
        cw = srcW;
        ch = cw / dstRatio;
        y = (srcH - ch) * t; // 0%=top, 100%=bottom
    }
    return img.Clone(x, y, cw, ch).Resize(w, h, 7);
}

function resizeCoverForMode(img, w, h, forceCrop) {
    if (!img) return createFallbackCover().Resize(w, h, 7);
    if (!forceCrop && IRREGULAR_COVER_MODE === 'tile') return img.Resize(w, h, 7);
    return centerCropResize(img, w, h);
}
function applyRoundedCoverMask(image, radius, forceCircle) {
    if (!image) return image;

    // SMP FillRoundRect expects the corner value itself, not a diameter.
    // Its valid range is 2 * radius <= width/height.
    const maxRadius = Math.max(0, Math.floor(Math.min(image.Width, image.Height) / 2));
    const r = clamp(Math.round(radius), 0, maxRadius);
    if (r <= 0 && !forceCircle) return image;

    // ApplyMask uses an inverse monochrome mask: black keeps the cover,
    // white removes it, and antialiased gray pixels form a smooth edge.
    const mask = gdi.CreateImage(image.Width, image.Height);
    const mg = mask.GetGraphics();
    mg.SetSmoothingMode(2);
    mg.FillSolidRect(0, 0, image.Width, image.Height, RGB(255, 255, 255));
    if (forceCircle) {
        // Radius 180 is a dedicated circle mode. The prepared bitmap is square,
        // so FillEllipse produces a true circle and bypasses FillRoundRect.
        mg.FillEllipse(0, 0, image.Width, image.Height, RGB(0, 0, 0));
    } else {
        mg.FillRoundRect(0, 0, image.Width, image.Height, r, r, RGB(0, 0, 0));
    }
    mask.ReleaseGraphics(mg);
    image.ApplyMask(mask);
    disposeImageSafe(mask);
    return image;
}
function prepareCoverImage(img, w, h, radius, forceCircle) {
    return applyRoundedCoverMask(resizeCoverForMode(img, w, h, forceCircle), radius, forceCircle);
}

function getCoverDisplayWidth(scale, coverImg, hasCover) {
    const fixedHeight = 360 * scale;
    if (COVER_CORNER_RADIUS === MAX_COVER_CORNER_RADIUS) return fixedHeight;
    if (IRREGULAR_COVER_MODE !== 'tile' || !hasCover || !coverImg || !coverImg.Width || !coverImg.Height) return fixedHeight;
    return Math.max(1, fixedHeight * coverImg.Width / coverImg.Height);
}
function getScaledLayout(scale, coverImg, hasCover, lyricsModule) {
    const coverH = 360 * scale;
    const coverW = hasCover ? getCoverDisplayWidth(scale, coverImg, true) : 0;
    const lyricsEnabled = !!(lyricsModule && lyricsModule.enabled && lyricsModule.width > 0);
    const lyricsW = lyricsEnabled ? Math.max(0, lyricsModule.width) : 0;
    const lyricsX = 20 * scale;
    const lyricsY = 20 * scale;
    const lyricsH = 360 * scale;
    const dividerEnabled = lyricsEnabled && !!LYRICS_CONFIG.dividerEnabled;
    const dividerW = dividerEnabled ? Math.max(0.001, LYRICS_CONFIG.dividerThickness * scale) : 0;
    const dividerLeftGap = dividerEnabled ? Math.max(0, LYRICS_CONFIG.dividerLeftGap * scale) : 0;
    const dividerRightGap = dividerEnabled ? Math.max(0, LYRICS_CONFIG.dividerRightGap * scale) : 0;
    const lyricsRightGap = lyricsEnabled && !dividerEnabled ? Math.max(0, LYRICS_CONFIG.rightGap * scale) : 0;
    const dividerX = lyricsX + lyricsW + dividerLeftGap;
    const lyricsShift = lyricsW + (dividerEnabled
        ? dividerLeftGap + dividerW + dividerRightGap
        : lyricsRightGap);
    const coverX = 20 * scale + lyricsShift;
    const coverY = 20 * scale;
    const labelX = hasCover ? (coverX + coverW + 20 * scale) : coverX;
    const valueX = labelX + 100 * scale;
    const minW = hasCover
        ? Math.max(1, 800 * scale + (coverW - 360 * scale) + lyricsShift)
        : Math.max(1, 420 * scale + lyricsShift);
    return {
        cardH: 400 * scale,
        minW: minW,
        rightPadding: 40 * scale,
        lyricsEnabled: lyricsEnabled,
        lyricsX: lyricsX,
        lyricsY: lyricsY,
        lyricsW: lyricsW,
        lyricsH: lyricsH,
        lyricsMetrics: lyricsModule || null,
        lyricsRightGap: lyricsRightGap,
        dividerEnabled: dividerEnabled,
        dividerX: dividerX,
        dividerW: dividerW,
        dividerLeftGap: dividerLeftGap,
        dividerRightGap: dividerRightGap,
        coverX: coverX,
        coverY: coverY,
        coverW: coverW,
        coverH: coverH,
        coverCornerRadius: clamp(Math.round(COVER_CORNER_RADIUS * scale), 0, Math.floor(Math.min(coverW, coverH) / 2)),
        coverIsCircle: COVER_CORNER_RADIUS === MAX_COVER_CORNER_RADIUS,
        shadowDepth: Math.max(0, COVER_SHADOW_DEPTH * scale),
        shadowMaxAlpha: COVER_SHADOW_OPACITY,
        labelX: labelX,
        valueX: valueX,
        rowGap: 80 * scale,
        rowBoxH: 40 * scale,
        rowSpacing: 40 * scale,
        metaGap: 8 * scale,
        metaBoxH: 28 * scale,
        previewClose: CONFIG.preview.closeSize
    };
}
function getElementColor(styleEntry, autoBase, rainbowRgb) {
    const rgb = resolveColorSpecRgb(styleEntry.colorHex, autoBase, rainbowRgb);
    const alpha = parseStoredNumber(styleEntry.opacity, 0, 0, 255);
    if (rgb) return RGBA(rgb.r, rgb.g, rgb.b, alpha);
    return alphaColor(autoBase, alpha);
}
function chooseBaseTextColor(palette) {
    if (!CONFIG.textAutoColor.enabled || !palette || !palette.length) return CONFIG.textAutoColor.darkBackgroundText;
    let sum = 0;
    for (let i = 0; i < palette.length; i++) sum += luminanceOfRgb(palette[i]);
    const avg = sum / palette.length;
    return avg > CONFIG.textAutoColor.threshold ? CONFIG.textAutoColor.lightBackgroundText : CONFIG.textAutoColor.darkBackgroundText;
}
function chooseSolidBaseTextColor(colorSpec, rainbowRgb) {
    if (!CONFIG.textAutoColor.enabled) return CONFIG.textAutoColor.darkBackgroundText;
    const rgb = resolveColorSpecRgb(colorSpec, CONFIG.textAutoColor.darkBackgroundText, rainbowRgb);
    if (!rgb) return CONFIG.textAutoColor.darkBackgroundText;
    const lum = luminanceOfRgb(rgb);
    return lum > CONFIG.textAutoColor.threshold ? CONFIG.textAutoColor.lightBackgroundText : CONFIG.textAutoColor.darkBackgroundText;
}
function getTextHint(baseTextColor) {
    const lum = luminanceOfRgb(colorToRgbObj(baseTextColor));
    return lum < 0.4 ? 5 : 4;
}
function buildLyricsFont(scale) {
    return gdi.Font(
        LYRICS_CONFIG.font || DEFAULT_FONT_NAME,
        Math.max(0.001, round3(LYRICS_CONFIG.size * scale)),
        styleFlags(!!LYRICS_CONFIG.bold, !!LYRICS_CONFIG.italic)
    );
}
function getLyricsStringFormat() {
    if (LYRICS_CONFIG.xAlign === 'center') return LYRICS_STRING_FORMAT_CENTER;
    if (LYRICS_CONFIG.xAlign === 'right') return LYRICS_STRING_FORMAT_RIGHT;
    return LYRICS_STRING_FORMAT_LEFT;
}
function getLyricsBlockStartY(blockH, topPadding, bottomPadding, containerH) {
    const availableH = Math.max(0, containerH - topPadding - bottomPadding);
    const safeBlockH = Math.max(0, blockH || 0);
    const spare = Math.max(0, availableH - safeBlockH);
    if (LYRICS_CONFIG.yAlign === 'center') return topPadding + spare / 2;
    if (LYRICS_CONFIG.yAlign === 'bottom') return topPadding + spare;
    return topPadding;
}
function buildFonts(scale) {
    function mk(entry) {
        return gdi.Font(
            entry.font || DEFAULT_FONT_NAME,
            Math.max(0.001, round3(entry.size * scale)),
            styleFlags(!!entry.bold, !!entry.italic)
        );
    }
    return {
        titleLabel: mk(STYLE_CONFIG.titleLabel),
        titleValue: mk(STYLE_CONFIG.titleValue),
        artistLabel: mk(STYLE_CONFIG.artistLabel),
        artistValue: mk(STYLE_CONFIG.artistValue),
        albumLabel: mk(STYLE_CONFIG.albumLabel),
        albumValue: mk(STYLE_CONFIG.albumValue),
        metaValue: mk(STYLE_CONFIG.metaValue),
        watermark: mk(STYLE_CONFIG.watermark)
    };
}
function textCodePointAt(text, index) {
    const first = text.charCodeAt(index);
    if (first >= 0xD800 && first <= 0xDBFF && index + 1 < text.length) {
        const second = text.charCodeAt(index + 1);
        if (second >= 0xDC00 && second <= 0xDFFF) return ((first - 0xD800) * 0x400) + second - 0xDC00 + 0x10000;
    }
    return first;
}
function textCodePointLength(cp) { return cp > 0xFFFF ? 2 : 1; }
function isTextCombiningCodePoint(cp) {
    return (cp >= 0x0300 && cp <= 0x036F) ||
        (cp >= 0x1AB0 && cp <= 0x1AFF) ||
        (cp >= 0x1DC0 && cp <= 0x1DFF) ||
        (cp >= 0x20D0 && cp <= 0x20FF) ||
        (cp >= 0xFE20 && cp <= 0xFE2F) ||
        (cp >= 0xFE00 && cp <= 0xFE0F) ||
        (cp >= 0xE0100 && cp <= 0xE01EF) ||
        (cp >= 0x1F3FB && cp <= 0x1F3FF);
}
function splitTextUnits(text) {
    const value = String(text || '');
    const units = [];
    let i = 0;
    while (i < value.length) {
        let cp = textCodePointAt(value, i);
        let len = textCodePointLength(cp);
        let unit = value.substr(i, len);
        i += len;
        while (i < value.length) {
            cp = textCodePointAt(value, i);
            len = textCodePointLength(cp);
            if (isTextCombiningCodePoint(cp)) {
                unit += value.substr(i, len);
                i += len;
                continue;
            }
            if (cp === 0x200D) {
                unit += value.substr(i, len);
                i += len;
                if (i < value.length) {
                    const next = textCodePointAt(value, i);
                    const nextLen = textCodePointLength(next);
                    unit += value.substr(i, nextLen);
                    i += nextLen;
                    continue;
                }
            }
            break;
        }
        units.push(unit);
    }
    return units;
}
function measureNativeText(gr, text, font, height) {
    const value = String(text || '');
    const probe = value || 'Ag';
    const measured = gr.MeasureString(probe, font, 0, 0, 100000, Math.max(1, height || 100000), MEASURE_STRING_FORMAT);
    return {
        width: value ? Math.max(0, Number(measured && measured.Width) || 0) : 0,
        height: Math.max(1, Number(measured && measured.Height) || 1)
    };
}
function getLetterSpacing(entry) {
    return parseStoredLetterSpacing(entry && entry.letterSpacing, '');
}
function usesNativeTextRenderer(entry) {
    return getLetterSpacing(entry) === '';
}
function buildSpacedTextMetrics(gr, text, font, height, entry, scale) {
    const value = String(text || '');
    const native = measureNativeText(gr, value, font, height);
    if (usesNativeTextRenderer(entry)) {
        return { manual: false, width: native.width, height: native.height, units: [], positions: [], glyphWidths: [], shiftX: 0 };
    }
    const units = splitTextUnits(value);
    if (!units.length) return { manual: true, width: 0, height: native.height, units: [], positions: [], glyphWidths: [], shiftX: 0 };
    const spacing = Number(getLetterSpacing(entry)) * scale;
    const positions = [];
    const glyphWidths = [];
    let prefix = '';
    let minX = 0;
    let maxX = 0;
    let maxH = native.height;
    for (let i = 0; i < units.length; i++) {
        const prefixWidth = i === 0 ? 0 : measureNativeText(gr, prefix, font, height).width;
        const x = prefixWidth + spacing * i;
        const glyph = measureNativeText(gr, units[i], font, height);
        positions.push(x);
        glyphWidths.push(glyph.width);
        minX = Math.min(minX, x);
        maxX = Math.max(maxX, x + glyph.width);
        maxH = Math.max(maxH, glyph.height);
        prefix += units[i];
    }
    maxX = Math.max(maxX, native.width + spacing * Math.max(0, units.length - 1));
    return {
        manual: true,
        width: Math.max(0, maxX - minX),
        height: maxH,
        units: units,
        positions: positions,
        glyphWidths: glyphWidths,
        shiftX: -minX,
        spacing: spacing
    };
}
function drawTextCore(gr, text, font, color, entry, x, y, w, h, format, scale, metrics) {
    const value = String(text || '');
    if (!value) return;
    const m = metrics || buildSpacedTextMetrics(gr, value, font, h, entry, scale);
    if (!m.manual) {
        gr.DrawString(value, font, color, x, y, w, h, format);
        return;
    }
    let startX = x + m.shiftX;
    if ((format & SF_ALIGN_CENTER) === SF_ALIGN_CENTER) startX = x + (w - m.width) / 2 + m.shiftX;
    else if ((format & SF_ALIGN_FAR) === SF_ALIGN_FAR) startX = x + w - m.width + m.shiftX;
    const verticalFormat = (format & ~(SF_ALIGN_CENTER | SF_ALIGN_FAR)) | SF_NO_WRAP | SF_NO_CLIP;
    const extraW = Math.max(4 * scale, Math.abs(m.spacing || 0) + 4 * scale);
    for (let i = 0; i < m.units.length; i++) {
        const gx = startX + m.positions[i];
        const gw = Math.max(1, m.glyphWidths[i] + extraW);
        gr.DrawString(m.units[i], font, color, gx, y, gw, h, verticalFormat);
    }
}
function drawTextClipped(gr, text, font, color, entry, x, y, w, h, format, scale, metrics) {
    const value = String(text || '');
    if (!value || w <= 0 || h <= 0) return;
    const m = metrics || buildSpacedTextMetrics(gr, value, font, h, entry, scale);
    if (!m.manual) {
        gr.DrawString(value, font, color, x, y, w, h, format);
        return;
    }
    const lw = Math.max(1, Math.ceil(w));
    const lh = Math.max(1, Math.ceil(h));
    const layer = gdi.CreateImage(lw, lh);
    const lg = layer.GetGraphics();
    lg.SetTextRenderingHint(TEXT_RENDERING_HINT);
    drawTextCore(lg, value, font, color, entry, 0, 0, w, h, format, scale, m);
    layer.ReleaseGraphics(lg);
    gr.DrawImage(layer, x, y, w, h, 0, 0, lw, lh);
    disposeImageSafe(layer);
}
function measureLyricsModule(info, scale) {
    if (!LYRICS_CONFIG.enabled) return { enabled: false, width: 0, lines: [], lineMetrics: [], blockH: 0, lineStep: 0 };
    const lines = (info && info.lyricsLines) ? info.lyricsLines : [];
    const temp = gdi.CreateImage(8, 8);
    const gr = temp.GetGraphics();
    gr.SetTextRenderingHint(TEXT_RENDERING_HINT);
    const font = buildLyricsFont(scale);
    const lineMetrics = [];
    let maxW = 0;
    let blockH = 0;
    const lineStep = Math.max(0, LYRICS_CONFIG.lineGap * scale);
    const fallbackHeight = measureNativeText(gr, 'Ag', font, 100000).height;
    for (let i = 0; i < lines.length; i++) {
        const metric = buildSpacedTextMetrics(gr, lines[i], font, 100000, LYRICS_CONFIG, scale);
        metric.height = Math.max(metric.height, fallbackHeight);
        lineMetrics.push(metric);
        maxW = Math.max(maxW, metric.width);
        blockH = Math.max(blockH, i * lineStep + metric.height);
    }
    temp.ReleaseGraphics(gr);
    disposeImageSafe(temp);
    const explicit = Math.max(0, LYRICS_CONFIG.containerWidth * scale);
    const width = explicit > 0
        ? explicit
        : clamp(maxW + 4 * scale, 0, MAX_LYRICS_CONTAINER_WIDTH * scale);
    return {
        enabled: true,
        width: width,
        lines: lines,
        lineMetrics: lineMetrics,
        blockH: blockH,
        lineStep: lineStep
    };
}
function getTextBlurStrength(entry) { return clamp(parseInt(entry && entry.blurStrength, 10) || 0, 0, MAX_TEXT_BLUR_STRENGTH); }
function getTextBlurOpacity(entry) { return parseStoredNumber(entry && entry.blurOpacity, 0, 0, 255); }
function getTextBlurRadius(entry, scale) {
    const strength = getTextBlurStrength(entry);
    return strength > 0 ? clamp(Math.round(strength * scale), 2, 254) : 0;
}
function getTextBlurPad(entry, scale) {
    const r = getTextBlurRadius(entry, scale);
    return r > 0 ? Math.min(508, r * 2) : 0;
}
function drawStyledText(gr, text, font, color, styleEntry, x, y, w, h, format, scale, metrics) {
    const value = String(text || '');
    if (!value) return;
    const m = metrics || buildSpacedTextMetrics(gr, value, font, h, styleEntry, scale);
    const blurRadius = getTextBlurRadius(styleEntry, scale);
    const blurOpacity = getTextBlurOpacity(styleEntry);
    if (blurRadius > 0 && blurOpacity > 0) {
        const pad = getTextBlurPad(styleEntry, scale);
        const lw = Math.max(1, Math.ceil(w + pad * 2));
        const lh = Math.max(1, Math.ceil(h + pad * 2));
        const layer = gdi.CreateImage(lw, lh);
        const lg = layer.GetGraphics();
        lg.SetTextRenderingHint(TEXT_RENDERING_HINT);
        drawTextCore(lg, value, font, alphaColor(color, 255), styleEntry, pad, pad, w, h, format, scale, m);
        layer.ReleaseGraphics(lg);
        try { layer.StackBlur(blurRadius); } catch (e) {}
        gr.DrawImage(layer, x - pad, y - pad, lw, lh, 0, 0, lw, lh, 0, alphaByte(blurOpacity));
        disposeImageSafe(layer);
    }
    drawTextCore(gr, value, font, color, styleEntry, x, y, w, h, format, scale, m);
}
function resolveConfiguredColor(colorSpec, opacity, autoBase, rainbowRgb) {
    const rgb = resolveColorSpecRgb(colorSpec, autoBase, rainbowRgb);
    const alpha = alphaByte(opacity);
    if (rgb) return RGBA(rgb.r, rgb.g, rgb.b, alpha);
    return alphaColor(autoBase, alpha);
}
function drawVerticalThreeStopGradient(gr, x, y, w, h, topColor, middleColor, bottomColor) {
    const safeH = Math.max(0, Math.round(h));
    if (safeH <= 0 || w <= 0) return;
    const steps = Math.min(360, safeH);
    const stripH = safeH / steps;
    const top = colorToRgbObj(topColor), mid = colorToRgbObj(middleColor), bottom = colorToRgbObj(bottomColor);
    const topA = (topColor >>> 24) & 255, midA = (middleColor >>> 24) & 255, bottomA = (bottomColor >>> 24) & 255;
    for (let i = 0; i < steps; i++) {
        const t = steps <= 1 ? 0 : i / (steps - 1);
        let c, a;
        if (t <= 0.5) {
            const q = t * 2; c = blendRgb(top, mid, q); a = Math.round(topA + (midA - topA) * q);
        } else {
            const q = (t - 0.5) * 2; c = blendRgb(mid, bottom, q); a = Math.round(midA + (bottomA - midA) * q);
        }
        const sy = Math.round(y + i * stripH);
        const ey = Math.round(y + (i + 1) * stripH);
        gr.FillSolidRect(x, sy, w, Math.max(1, ey - sy), RGBA(c.r, c.g, c.b, a));
    }
}
function drawLyricsModule(gr, info, layout, scale, baseText, rainbowRgb) {
    if (!layout.lyricsEnabled || layout.lyricsW <= 0) return;
    const module = layout.lyricsMetrics || { lines: [], lineMetrics: [], blockH: 0, lineStep: 0 };
    const lines = module.lines || ((info && info.lyricsLines) ? info.lyricsLines : []);
    const lineMetrics = module.lineMetrics || [];
    const font = buildLyricsFont(scale);
    const format = getLyricsStringFormat();
    const textColor = resolveConfiguredColor(LYRICS_CONFIG.colorHex, LYRICS_CONFIG.opacity, baseText, rainbowRgb);
    const lineStep = Math.max(0, module.lineStep !== undefined ? module.lineStep : LYRICS_CONFIG.lineGap * scale);
    const topPadding = Math.max(0, LYRICS_CONFIG.topPadding * scale);
    const bottomPadding = Math.max(0, LYRICS_CONFIG.bottomPadding * scale);
    const clipH = Math.max(0, layout.lyricsH - topPadding - bottomPadding);
    // blockH was measured from every line origin plus that line's actual measured
    // height, so the final line is explicitly part of top/center/bottom alignment.
    const textStartY = getLyricsBlockStartY(module.blockH || 0, topPadding, bottomPadding, layout.lyricsH);

    const blurRadius = getTextBlurRadius(LYRICS_CONFIG, scale);
    const blurOpacity = getTextBlurOpacity(LYRICS_CONFIG);
    if (lines.length && clipH > 0 && blurRadius > 0 && blurOpacity > 0) {
        const glowW = Math.max(1, Math.ceil(layout.lyricsW));
        const glowH = Math.max(1, Math.ceil(layout.lyricsH));
        const glow = gdi.CreateImage(glowW, glowH);
        const gg = glow.GetGraphics();
        gg.SetTextRenderingHint(TEXT_RENDERING_HINT);
        for (let i = 0; i < lines.length; i++) {
            const metric = lineMetrics[i] || buildSpacedTextMetrics(gg, lines[i], font, 100000, LYRICS_CONFIG, scale);
            const ly = textStartY + i * lineStep;
            const lineH = Math.max(1, metric.height);
            if (ly >= layout.lyricsH - bottomPadding) break;
            drawTextCore(gg, String(lines[i] || ''), font, alphaColor(textColor, 255), LYRICS_CONFIG,
                0, ly, layout.lyricsW, lineH, format, scale, metric);
        }
        glow.ReleaseGraphics(gg);
        try { glow.StackBlur(blurRadius); } catch (e) {}
        gr.DrawImage(glow,
            layout.lyricsX, layout.lyricsY,
            layout.lyricsW, layout.lyricsH,
            0, 0, glow.Width, glow.Height, 0, alphaByte(blurOpacity));
        disposeImageSafe(glow);
    }

    for (let i = 0; i < lines.length; i++) {
        const metric = lineMetrics[i] || { height: Math.max(1, LYRICS_CONFIG.size * scale * 1.2) };
        const ly = layout.lyricsY + textStartY + i * lineStep;
        const clipBottom = layout.lyricsY + layout.lyricsH - bottomPadding;
        if (ly >= clipBottom) break;
        const drawH = Math.max(0, Math.min(metric.height, clipBottom - ly));
        if (drawH > 0) {
            drawTextClipped(gr, String(lines[i] || ''), font, textColor, LYRICS_CONFIG,
                layout.lyricsX, ly, layout.lyricsW, drawH, format, scale, metric);
        }
    }

    if (layout.dividerEnabled && layout.dividerW > 0) {
        const topGap = Math.max(0, LYRICS_CONFIG.dividerTopPadding * scale);
        const bottomGap = Math.max(0, LYRICS_CONFIG.dividerBottomPadding * scale);
        const lineH = Math.max(0, layout.lyricsH - topGap - bottomGap);
        const topColor = resolveConfiguredColor(LYRICS_CONFIG.dividerTopHex, LYRICS_CONFIG.dividerTopOpacity, baseText, rainbowRgb);
        const middleColor = resolveConfiguredColor(LYRICS_CONFIG.dividerMiddleHex, LYRICS_CONFIG.dividerMiddleOpacity, baseText, rainbowRgb);
        const bottomColor = resolveConfiguredColor(LYRICS_CONFIG.dividerBottomHex, LYRICS_CONFIG.dividerBottomOpacity, baseText, rainbowRgb);
        drawVerticalThreeStopGradient(gr, layout.dividerX, layout.lyricsY + topGap, layout.dividerW, lineH, topColor, middleColor, bottomColor);
    }
}
function buildCardTextMetrics(gr, text, fonts, layout, scale) {
    const titleLabel = buildSpacedTextMetrics(gr, text.titleLabel || '', fonts.titleLabel, 100000, STYLE_CONFIG.titleLabel, scale);
    const titleValue = buildSpacedTextMetrics(gr, text.titleValue || '', fonts.titleValue, 100000, STYLE_CONFIG.titleValue, scale);
    const artistLabel = buildSpacedTextMetrics(gr, text.artistLabel || '', fonts.artistLabel, 100000, STYLE_CONFIG.artistLabel, scale);
    const artistValue = buildSpacedTextMetrics(gr, text.artistValue || '', fonts.artistValue, 100000, STYLE_CONFIG.artistValue, scale);
    const albumLabel = buildSpacedTextMetrics(gr, text.albumLabel || '', fonts.albumLabel, 100000, STYLE_CONFIG.albumLabel, scale);
    const albumValue = buildSpacedTextMetrics(gr, text.albumValue || '', fonts.albumValue, 100000, STYLE_CONFIG.albumValue, scale);
    const metaValue = buildSpacedTextMetrics(gr, text.metaValue || '', fonts.metaValue, 100000, STYLE_CONFIG.metaValue, scale);
    const watermark = buildSpacedTextMetrics(gr, text.watermark || '', fonts.watermark, 100000, STYLE_CONFIG.watermark, scale);

    const labelNaturalW = Math.max(titleLabel.width, artistLabel.width, albumLabel.width);
    const labelBlurPad = Math.max(
        getTextBlurPad(STYLE_CONFIG.titleLabel, scale),
        getTextBlurPad(STYLE_CONFIG.artistLabel, scale),
        getTextBlurPad(STYLE_CONFIG.albumLabel, scale)
    );
    const labelColumnW = Math.max(100 * scale, labelNaturalW + labelBlurPad + 20 * scale);
    const valueX = layout.labelX + labelColumnW;

    const rowMinH = 40 * scale;
    const titleH = Math.max(rowMinH, titleLabel.height, titleValue.height);
    const artistH = Math.max(rowMinH, artistLabel.height, artistValue.height);
    const albumH = Math.max(rowMinH, albumLabel.height, albumValue.height);
    const metaH = Math.max(28 * scale, metaValue.height);
    const rowSpacing = 40 * scale;
    const hasMeta = String(text.metaValue || '').trim() !== '';
    const totalH = titleH + rowSpacing + artistH + rowSpacing + albumH + (hasMeta ? layout.metaGap + metaH : 0);
    const startY = (layout.cardH - totalH) / 2;
    const titleY = startY;
    const artistY = titleY + titleH + rowSpacing;
    const albumY = artistY + artistH + rowSpacing;
    const metaY = albumY + albumH + layout.metaGap;

    return {
        titleLabel: titleLabel,
        titleValue: titleValue,
        artistLabel: artistLabel,
        artistValue: artistValue,
        albumLabel: albumLabel,
        albumValue: albumValue,
        metaValue: metaValue,
        watermark: watermark,
        labelColumnW: labelColumnW,
        valueX: valueX,
        titleH: titleH,
        artistH: artistH,
        albumH: albumH,
        metaH: metaH,
        titleY: titleY,
        artistY: artistY,
        albumY: albumY,
        metaY: metaY,
        hasMeta: hasMeta
    };
}
function measureDynamicWidth(info, scale, coverImg, hasCover, lyricsModule) {
    const layout = getScaledLayout(scale, coverImg, hasCover, lyricsModule);
    const temp = gdi.CreateImage(8, 8);
    const gr = temp.GetGraphics();
    const fonts = buildFonts(scale);
    const text = info.renderedText || {};
    const tm = buildCardTextMetrics(gr, text, fonts, layout, scale);
    temp.ReleaseGraphics(gr);
    disposeImageSafe(temp);
    const drawStringSafety = 4 * scale;
    const farX = Math.max(
        tm.valueX + tm.titleValue.width + getTextBlurPad(STYLE_CONFIG.titleValue, scale),
        tm.valueX + tm.artistValue.width + getTextBlurPad(STYLE_CONFIG.artistValue, scale),
        tm.valueX + tm.albumValue.width + getTextBlurPad(STYLE_CONFIG.albumValue, scale),
        tm.valueX + tm.metaValue.width + getTextBlurPad(STYLE_CONFIG.metaValue, scale),
        layout.labelX + tm.watermark.width + getTextBlurPad(STYLE_CONFIG.watermark, scale),
        layout.labelX + tm.labelColumnW
    );
    return Math.max(layout.minW, farX + layout.rightPadding + drawStringSafety);
}
function applyExtendedStackBlur(image, strength, radiusForStrength) {
    const s = clamp(parseInt(strength, 10) || 0, 0, MAX_BLUR_STRENGTH);
    const firstStrength = Math.min(s, 100);
    const firstRadius = clamp(Math.round(radiusForStrength(firstStrength)), 2, 254);
    try { image.StackBlur(firstRadius); } catch (e) {}

    // SMP/StackBlur 单次半径存在上限。0-100 完全沿用旧算法；
    // 100 以上通过追加模糊轮次继续增强，因此 100 保持旧效果，500 明显更强。
    let extra = Math.max(0, s - 100);
    if (!extra) return;

    const fullRadius = clamp(Math.round(radiusForStrength(100)), 2, 254);
    while (extra >= 100) {
        try { image.StackBlur(fullRadius); } catch (e2) {}
        extra -= 100;
    }
    if (extra > 0) {
        const partialRadius = clamp(Math.round(fullRadius * extra / 100), 2, 254);
        try { image.StackBlur(partialRadius); } catch (e3) {}
    }
}

function drawFusionBackground(gr, width, height, palette, scale, seedText) {
    const p = (palette && palette.length) ? palette : CONFIG.palette.fallback;
    const c1 = p[0], c2 = p[1 % p.length], c3 = p[2 % p.length] || c1, c4 = p[3 % p.length] || c2;
    const rnd = createSeededRandom(seedText || generateRandomSeed8());
    const ang1 = Math.floor(rnd() * 360);
    const ang2 = Math.floor((ang1 + 50 + rnd() * 120) % 360);
    gr.FillGradRect(0, 0, width, height, ang1, RGBA(c1.r, c1.g, c1.b, 255), RGBA(c2.r, c2.g, c2.b, 255));
    const mix1 = blendRgb(c3, c1, 0.35), mix2 = blendRgb(c4, c2, 0.35);
    gr.FillGradRect(0, 0, width, height, ang2, RGBA(mix1.r, mix1.g, mix1.b, 92), RGBA(mix2.r, mix2.g, mix2.b, 12));

    const layer = gdi.CreateImage(width, height);
    const lg = layer.GetGraphics();
    lg.SetSmoothingMode(2);
    const count = 3 + Math.floor(rnd() * 4);
    for (let i = 0; i < count; i++) {
        const cc = p[Math.floor(rnd() * p.length)] || c1;
        const alpha = Math.round(78 + rnd() * 54);
        const baseR = height * (0.18 + rnd() * 0.36);
        const deform = 0.82 + rnd() * 0.36;
        const rx = baseR * deform;
        const ry = baseR * (2 - deform);
        const cx = width * (0.12 + rnd() * 0.76);
        const cy = height * (0.12 + rnd() * 0.76);
        lg.FillEllipse(cx - rx, cy - ry, rx * 2, ry * 2, RGBA(cc.r, cc.g, cc.b, alpha));
    }
    layer.ReleaseGraphics(lg);
    applyExtendedStackBlur(layer, BLUR_STRENGTH, function (strength) {
        return (20 + strength * 1.4) * Math.max(1, scale * 0.65);
    });
    gr.DrawImage(layer, 0, 0, width, height, 0, 0, width, height);
    gr.FillSolidRect(0, 0, width, height, RGBA(255, 255, 255, CONFIG.palette.overlayAlpha));
}

function drawSampleBackground(gr, width, height, palette, scale) {
    // “采点”：严格沿用 v4.4 / v4.3 的方式。
    // 色点尺寸随画布变化，但 StackBlur 半径固定为 90，不随导出倍率放大。
    const p = (palette && palette.length) ? palette : CONFIG.palette.fallback;
    const c1 = p[0], c2 = p[1 % p.length], c3 = p[2 % p.length] || c1, c4 = p[3 % p.length] || c2;
    gr.FillGradRect(0, 0, width, height, 90, RGBA(c1.r, c1.g, c1.b, 255), RGBA(c2.r, c2.g, c2.b, 255));
    const mix1 = blendRgb(c3, c1, 0.35), mix2 = blendRgb(c4, c2, 0.35);
    gr.FillGradRect(0, 0, width, height, 0, RGBA(mix1.r, mix1.g, mix1.b, 90), RGBA(mix2.r, mix2.g, mix2.b, 10));
    const layer = gdi.CreateImage(width, height);
    const lg = layer.GetGraphics();
    lg.SetSmoothingMode(2);
    const blobs = [
        { x: width * 0.15, y: height * 0.25, r: height * 0.38, c: c1 },
        { x: width * 0.85, y: height * 0.25, r: height * 0.42, c: c2 },
        { x: width * 0.55, y: height * 0.85, r: height * 0.44, c: c3 },
        { x: width * 0.35, y: height * 0.70, r: height * 0.28, c: c4 }
    ];
    for (let i = 0; i < blobs.length; i++) {
        const b = blobs[i];
        lg.FillEllipse(b.x - b.r, b.y - b.r, b.r * 2, b.r * 2, RGBA(b.c.r, b.c.g, b.c.b, CONFIG.palette.blobAlpha));
    }
    layer.ReleaseGraphics(lg);
    try { layer.StackBlur(90); } catch (e) {}
    gr.DrawImage(layer, 0, 0, width, height, 0, 0, width, height);
    gr.FillSolidRect(0, 0, width, height, RGBA(255, 255, 255, CONFIG.palette.overlayAlpha));
}
function drawBlurBackground(gr, width, height, coverImg, hasCover, palette, scale) {
    // “模糊”：直接放大并模糊封面。0-100 沿用旧算法，100-500 通过追加模糊轮次增强。
    if (hasCover && coverImg) {
        const bg = cropResizeAtPosition(coverImg, width, height, BLUR_BG_CROP_POSITION);
        applyExtendedStackBlur(bg, BLUR_STRENGTH, function (strength) {
            return (8 + strength * 0.72) * scale;
        });
        gr.DrawImage(bg, 0, 0, width, height, 0, 0, bg.Width, bg.Height);
        gr.FillSolidRect(0, 0, width, height, RGBA(255, 255, 255, 18));
        gr.FillGradRect(0, 0, width, height, 0, RGBA(0, 0, 0, 22), RGBA(255, 255, 255, 10));
        const p = (palette && palette.length) ? palette : CONFIG.palette.fallback;
        const c1 = p[0], c2 = p[1 % p.length];
        gr.FillGradRect(0, 0, width, height, 90, RGBA(c1.r, c1.g, c1.b, 28), RGBA(c2.r, c2.g, c2.b, 20));
    } else {
        drawSampleBackground(gr, width, height, palette, scale);
    }
}
function drawInkBackground(gr, width, height, palette, scale) {
    // “墨点”：复现上传的 v4.5 版本真正执行出来的背景，而不是它表面上想执行的逻辑。
    // 原版本读取了未定义的 CONFIG.palette.blobBlur，StackBlur 因此抛错并被空 catch 吞掉。
    // 实际画面由以下部分组成：两层渐变 + 四个未模糊的半透明椭圆色块 + 白色覆盖层。
    // scale 参数保留以兼容统一调用签名；尺寸已经由 width/height 随倍率放大。
    const p = (palette && palette.length) ? palette : CONFIG.palette.fallback;
    const c1 = p[0], c2 = p[1 % p.length], c3 = p[2 % p.length] || c1, c4 = p[3 % p.length] || c2;

    gr.FillGradRect(0, 0, width, height, 90,
        RGBA(c1.r, c1.g, c1.b, 255),
        RGBA(c2.r, c2.g, c2.b, 255));

    const mix1 = blendRgb(c3, c1, 0.35);
    const mix2 = blendRgb(c4, c2, 0.35);
    gr.FillGradRect(0, 0, width, height, 0,
        RGBA(mix1.r, mix1.g, mix1.b, 90),
        RGBA(mix2.r, mix2.g, mix2.b, 10));

    const layer = gdi.CreateImage(width, height);
    const lg = layer.GetGraphics();
    lg.SetSmoothingMode(2);
    const blobs = [
        { x: width * 0.15, y: height * 0.25, r: height * 0.38, c: c1 },
        { x: width * 0.85, y: height * 0.25, r: height * 0.42, c: c2 },
        { x: width * 0.55, y: height * 0.85, r: height * 0.44, c: c3 },
        { x: width * 0.35, y: height * 0.70, r: height * 0.28, c: c4 }
    ];
    for (let i = 0; i < blobs.length; i++) {
        const b = blobs[i];
        lg.FillEllipse(
            b.x - b.r, b.y - b.r, b.r * 2, b.r * 2,
            RGBA(b.c.r, b.c.g, b.c.b, CONFIG.palette.blobAlpha)
        );
    }
    layer.ReleaseGraphics(lg);

    // 故意不执行 StackBlur：这才是上传版本实际呈现的背景。
    gr.DrawImage(layer, 0, 0, width, height, 0, 0, width, height);
    gr.FillSolidRect(0, 0, width, height,
        RGBA(255, 255, 255, CONFIG.palette.overlayAlpha));
}

function rgbToHueUnit(rgb) {
    const r = clamp(Number(rgb.r) || 0, 0, 255) / 255;
    const g = clamp(Number(rgb.g) || 0, 0, 255) / 255;
    const b = clamp(Number(rgb.b) || 0, 0, 255) / 255;
    const maxV = Math.max(r, g, b), minV = Math.min(r, g, b);
    const delta = maxV - minV;
    if (delta <= 1e-9) return null;
    let h;
    if (maxV === r) h = ((g - b) / delta) % 6;
    else if (maxV === g) h = (b - r) / delta + 2;
    else h = (r - g) / delta + 4;
    h /= 6;
    if (h < 0) h += 1;
    return h;
}
function hueUnitToFullRgb(hue) {
    let h = Number(hue);
    if (!isFinite(h)) h = 0;
    h = ((h % 1) + 1) % 1;
    const h6 = h * 6;
    const sector = Math.floor(h6) % 6;
    const f = h6 - Math.floor(h6);
    const q = 1 - f;
    let r = 0, g = 0, b = 0;
    if (sector === 0) { r = 1; g = f; }
    else if (sector === 1) { r = q; g = 1; }
    else if (sector === 2) { g = 1; b = f; }
    else if (sector === 3) { g = q; b = 1; }
    else if (sector === 4) { r = f; b = 1; }
    else { r = 1; b = q; }
    return makeColor(Math.round(r * 255), Math.round(g * 255), Math.round(b * 255));
}
function averageHueFromRgbList(list) {
    let sinSum = 0, cosSum = 0, count = 0;
    for (let i = 0; i < list.length; i++) {
        const hue = rgbToHueUnit(list[i]);
        if (hue === null) continue;
        const angle = hue * Math.PI * 2;
        sinSum += Math.sin(angle);
        cosSum += Math.cos(angle);
        count++;
    }
    if (!count) return 0;
    let angle = Math.atan2(sinSum / count, cosSum / count);
    if (angle < 0) angle += Math.PI * 2;
    return angle / (Math.PI * 2);
}
function readBinaryFileBytes(path) {
    let stream = null;
    try {
        stream = new ActiveXObject('ADODB.Stream');
        stream.Type = 1;
        stream.Open();
        stream.LoadFromFile(path);
        const variant = stream.Read();
        stream.Close();
        stream = null;
        if (typeof VBArray !== 'undefined') return new VBArray(variant).toArray();
        if (variant && typeof variant.toArray === 'function') return variant.toArray();
    } catch (e) {
        try { if (stream) stream.Close(); } catch (e2) {}
    }
    return null;
}

function decodeBase64ToBytes(text) {
    const clean = String(text || '').replace(/\s+/g, '');
    if (!clean) return null;
    const table = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
    const reverse = {};
    for (let i = 0; i < table.length; i++) reverse[table.charAt(i)] = i;
    const out = [];
    let buffer = 0, bits = 0;
    for (let i = 0; i < clean.length; i++) {
        const ch = clean.charAt(i);
        if (ch === '=') break;
        const value = reverse[ch];
        if (value === undefined) continue;
        buffer = (buffer << 6) | value;
        bits += 6;
        if (bits >= 8) {
            bits -= 8;
            out.push((buffer >> bits) & 255);
        }
    }
    return out;
}
function readBinaryFileBytesViaMsxml(path) {
    let stream = null;
    try {
        stream = new ActiveXObject('ADODB.Stream');
        stream.Type = 1;
        stream.Open();
        stream.LoadFromFile(path);
        const binaryVariant = stream.Read();
        stream.Close();
        stream = null;
        let dom = null;
        try { dom = new ActiveXObject('Msxml2.DOMDocument.6.0'); }
        catch (e6) { try { dom = new ActiveXObject('Msxml2.DOMDocument.3.0'); } catch (e3) { dom = new ActiveXObject('Microsoft.XMLDOM'); } }
        const node = dom.createElement('musiccardBinary');
        node.dataType = 'bin.base64';
        node.nodeTypedValue = binaryVariant;
        return decodeBase64ToBytes(node.text);
    } catch (e) {
        try { if (stream) stream.Close(); } catch (e2) {}
        console.log('[MusicCard Rainbow B64] 二进制桥接失败: ' + String(e));
        return null;
    }
}

function readUInt16LE(bytes, offset) {
    return (bytes[offset] | (bytes[offset + 1] << 8)) >>> 0;
}
function readUInt32LE(bytes, offset) {
    return (bytes[offset] | (bytes[offset + 1] << 8) | (bytes[offset + 2] << 16) | (bytes[offset + 3] << 24)) >>> 0;
}
function readInt32LE(bytes, offset) {
    return readUInt32LE(bytes, offset) | 0;
}
function averageHueFromBmpBytes(bytes) {
    if (!bytes || bytes.length < 54 || bytes[0] !== 0x42 || bytes[1] !== 0x4D) return null;
    const pixelOffset = readUInt32LE(bytes, 10);
    const width = Math.abs(readInt32LE(bytes, 18));
    const signedHeight = readInt32LE(bytes, 22);
    const height = Math.abs(signedHeight);
    const bpp = readUInt16LE(bytes, 28);
    const compression = readUInt32LE(bytes, 30);
    if (!width || !height || (bpp !== 24 && bpp !== 32) || compression !== 0) return null;
    const rowStride = Math.floor((bpp * width + 31) / 32) * 4;
    const pixelSize = bpp / 8;
    if (pixelOffset + rowStride * height > bytes.length) return null;
    let sinSum = 0, cosSum = 0, count = 0;
    for (let y = 0; y < height; y++) {
        let pos = pixelOffset + y * rowStride;
        for (let x = 0; x < width; x++, pos += pixelSize) {
            const b = bytes[pos], g = bytes[pos + 1], r = bytes[pos + 2];
            if (bpp === 32 && bytes[pos + 3] === 0) continue;
            const hue = rgbToHueUnit({ r: r, g: g, b: b });
            if (hue === null) continue;
            const angle = hue * Math.PI * 2;
            sinSum += Math.sin(angle);
            cosSum += Math.cos(angle);
            count++;
        }
    }
    if (!count) return 0;
    let angle = Math.atan2(sinSum / count, cosSum / count);
    if (angle < 0) angle += Math.PI * 2;
    return angle / (Math.PI * 2);
}
function deleteFileQuiet(path) {
    try {
        const fso = new ActiveXObject('Scripting.FileSystemObject');
        if (fso.FileExists(path)) fso.DeleteFile(path, true);
    } catch (e) {}
}
function averageHueViaPowerShell(bmpPath, resultPath) {
    const helperPath = fb.ProfilePath + 'music-card\\__musiccard_rainbow_hue_v4_15_8.ps1';
    const script = [
        'param([string]$ImagePath,[string]$ResultPath)',
        'Add-Type -AssemblyName System.Drawing',
        '$bmp=[System.Drawing.Bitmap]::FromFile($ImagePath)',
        '$rect=New-Object System.Drawing.Rectangle(0,0,$bmp.Width,$bmp.Height)',
        '$data=$bmp.LockBits($rect,[System.Drawing.Imaging.ImageLockMode]::ReadOnly,[System.Drawing.Imaging.PixelFormat]::Format32bppArgb)',
        '$stride=[Math]::Abs($data.Stride); $bytes=New-Object byte[] ($stride*$data.Height)',
        '[Runtime.InteropServices.Marshal]::Copy($data.Scan0,$bytes,0,$bytes.Length)',
        '$sin=0.0; $cos=0.0; $count=0',
        'for($y=0;$y -lt $data.Height;$y++){for($x=0;$x -lt $data.Width;$x++){',
        '$i=$y*$stride+$x*4; if($bytes[$i+3] -eq 0){continue};',
        '$b=$bytes[$i]/255.0; $g=$bytes[$i+1]/255.0; $r=$bytes[$i+2]/255.0;',
        '$max=[Math]::Max($r,[Math]::Max($g,$b)); $min=[Math]::Min($r,[Math]::Min($g,$b)); $d=$max-$min; if($d -le 0.000000001){continue};',
        'if($max -eq $r){$h=(($g-$b)/$d)%6}elseif($max -eq $g){$h=(($b-$r)/$d)+2}else{$h=(($r-$g)/$d)+4};',
        '$h=$h/6.0; if($h -lt 0){$h+=1}; $a=$h*2*[Math]::PI; $sin+=[Math]::Sin($a); $cos+=[Math]::Cos($a); $count++',
        '}}',
        '$bmp.UnlockBits($data); $bmp.Dispose()',
        'if($count -le 0){$hue=0}else{$a=[Math]::Atan2($sin/$count,$cos/$count);if($a -lt 0){$a+=2*[Math]::PI};$hue=$a/(2*[Math]::PI)}',
        '[IO.File]::WriteAllText($ResultPath,$hue.ToString([Globalization.CultureInfo]::InvariantCulture))'
    ].join('\r\n');
    try {
        ensureFolder(fb.ProfilePath + 'music-card\\');
        writeTextFile(helperPath, script);
        deleteFileQuiet(resultPath);
        const shell = new ActiveXObject('WScript.Shell');
        const command = 'powershell -NoProfile -ExecutionPolicy Bypass -File "' + helperPath + '" "' + bmpPath + '" "' + resultPath + '"';
        shell.Run(command, 0, true);
        if (!fileExists(resultPath)) return null;
        const hue = parseFloat(String(readTextFile(resultPath)).trim());
        return isFinite(hue) ? hue : null;
    } catch (e) {
        return null;
    } finally {
        deleteFileQuiet(resultPath);
        deleteFileQuiet(helperPath);
    }
}
function anyRainbowColorConfigured() {
    if (BACKGROUND_STYLE === 'solid' && isRainbowColorSpec(SOLID_BG_HEX)) return true;
    for (let i = 0; i < STYLE_KEYS.length; i++) if (isRainbowColorSpec(STYLE_CONFIG[STYLE_KEYS[i][0]].colorHex)) return true;
    if (isRainbowColorSpec(LYRICS_CONFIG.colorHex) ||
        isRainbowColorSpec(LYRICS_CONFIG.dividerTopHex) ||
        isRainbowColorSpec(LYRICS_CONFIG.dividerMiddleHex) ||
        isRainbowColorSpec(LYRICS_CONFIG.dividerBottomHex)) return true;
    return false;
}
function rgbToHexText(rgb) {
    function part(value) {
        const n = clamp(Math.round(Number(value) || 0), 0, 255).toString(16).toLowerCase();
        return n.length < 2 ? '0' + n : n;
    }
    return '#' + part(rgb.r) + part(rgb.g) + part(rgb.b);
}
function sortedCoverStyleColors(img, rawEnvironmentOnly) {
    const source = rawEnvironmentOnly
        ? extractPaletteFromImage(img, RAINBOW_STYLE_COLOR_COUNT)
        : extractPalette(img, RAINBOW_STYLE_COLOR_COUNT);
    const unique = {};
    const out = [];
    function add(rgb) {
        if (!rgb) return;
        const normalized = makeColor(clamp(Math.round(rgb.r), 0, 255), clamp(Math.round(rgb.g), 0, 255), clamp(Math.round(rgb.b), 0, 255));
        const hex = rgbToHexText(normalized);
        if (unique[hex]) return;
        unique[hex] = true;
        out.push(normalized);
    }
    for (let i = 0; i < source.length; i++) add(source[i]);
    for (let j = 0; j < CONFIG.palette.fallback.length && out.length < RAINBOW_STYLE_COLOR_COUNT; j++) add(CONFIG.palette.fallback[j]);
    if (out.length < RAINBOW_STYLE_COLOR_COUNT) add(COLOR_BLACK_RGB);
    if (out.length < RAINBOW_STYLE_COLOR_COUNT) add(COLOR_WHITE_RGB);
    if (rawEnvironmentOnly || !CUSTOM_ENVIRONMENT_COLORS_ENABLED) {
        out.sort(function (a, b) {
            const ah = rgbToHexText(a), bh = rgbToHexText(b);
            return ah < bh ? -1 : (ah > bh ? 1 : 0);
        });
    }
    return out.slice(0, RAINBOW_STYLE_COLOR_COUNT);
}
function getStylePaletteCacheKey(handle, coverObj) {
    const custom = String(CONFIG.customCoverPath || '');
    const img = coverObj && coverObj.img;
    return (custom ? 'custom:' + custom : 'track:' + getTrackIdentity(handle)) +
        '|' + (img ? String(img.Width) + 'x' + String(img.Height) : 'none');
}
function rememberStylePalette(key, colors) {
    RAINBOW_STYLE_PALETTE_CACHE[key] = clone(colors);
    RAINBOW_STYLE_PALETTE_CACHE_ORDER.push(key);
    while (RAINBOW_STYLE_PALETTE_CACHE_ORDER.length > 16) {
        const old = RAINBOW_STYLE_PALETTE_CACHE_ORDER.shift();
        if (old !== key) delete RAINBOW_STYLE_PALETTE_CACHE[old];
    }
}
function clearStylePaletteCache() {
    for (const key in RAINBOW_STYLE_PALETTE_CACHE) delete RAINBOW_STYLE_PALETTE_CACHE[key];
    RAINBOW_STYLE_PALETTE_CACHE_ORDER.length = 0;
}
function getCoverStyleColors(handle, coverObj) {
    const key = getStylePaletteCacheKey(handle, coverObj);
    if (RAINBOW_STYLE_PALETTE_CACHE[key]) return clone(RAINBOW_STYLE_PALETTE_CACHE[key]);
    const colors = sortedCoverStyleColors(coverObj && coverObj.img);
    rememberStylePalette(key, colors);
    return clone(colors);
}
function getCurrentCoverStyleColors() {
    const handle = pickHandle();
    const customEnvironmentKey = CUSTOM_ENVIRONMENT_COLORS_ENABLED
        ? '|env:' + CUSTOM_ENVIRONMENT_COLOR_HEXES.join(',')
        : '|env:auto';
    const quickKey = (CONFIG.customCoverPath ? 'ui-custom:' + String(CONFIG.customCoverPath) : 'ui-track:' + getTrackIdentity(handle)) + customEnvironmentKey;
    if (RAINBOW_STYLE_PALETTE_CACHE[quickKey]) return clone(RAINBOW_STYLE_PALETTE_CACHE[quickKey]);
    const coverObj = getCover(handle);
    try {
        const colors = sortedCoverStyleColors(coverObj && coverObj.img);
        rememberStylePalette(quickKey, colors);
        return clone(colors);
    } finally { disposeImageSafe(coverObj && coverObj.img); }
}
function captureCurrentEnvironmentColorHexes() {
    const coverObj = getCover(pickHandle());
    try {
        const colors = sortedCoverStyleColors(coverObj && coverObj.img, true);
        return colors.slice(0, CUSTOM_ENVIRONMENT_COLOR_COUNT).map(rgbToHexText);
    } finally { disposeImageSafe(coverObj && coverObj.img); }
}
function resolveCustomRainbowColor(handle, coverObj) {
    if (/^palette:[0-4]$/.test(RAINBOW_CUSTOM_SELECTION)) {
        const index = parseInt(RAINBOW_CUSTOM_SELECTION.split(':')[1], 10);
        const colors = getCoverStyleColors(handle, coverObj);
        if (colors[index]) return colors[index];
    }
    const token = normalizeCustomRainbowHex(RAINBOW_CUSTOM_HEX);
    if (token === '') {
        const palette = extractPalette(coverObj && coverObj.img, RAINBOW_STYLE_COLOR_COUNT);
        return colorToRgbObj(chooseBaseTextColor(palette));
    }
    return baseColorTokenToRgb(token) || makeColor(255, 0, 0);
}
function resolveRainbowTargetColor(handle, coverObj) {
    return RAINBOW_MODE === 'custom'
        ? resolveCustomRainbowColor(handle, coverObj)
        : computeCoverRainbowColor(handle, coverObj);
}
function getTrackIdentity(handle) {
    if (!handle) return '';
    let path = '';
    try { path = String(handle.RawPath || handle.Path || ''); } catch (e) {}
    let subsong = '';
    try { subsong = String(handle.SubSong === undefined ? '' : handle.SubSong); } catch (e2) {}
    if (path) return path + '|' + subsong;
    return String(getInfo(handle).artist || '') + '|' + String(getInfo(handle).title || '');
}
function getRainbowCacheKey(handle, coverObj) {
    const custom = String(CONFIG.customCoverPath || '');
    const img = coverObj && coverObj.img;
    return (custom ? 'custom:' + custom : 'track:' + getTrackIdentity(handle)) +
        '|' + (img ? String(img.Width) + 'x' + String(img.Height) : 'none') +
        '|sample:' + String(RAINBOW_SAMPLE_MAX_SIDE);
}
function rememberRainbowColor(key, value) {
    RAINBOW_COLOR_CACHE[key] = value;
    RAINBOW_COLOR_CACHE_ORDER.push(key);
    while (RAINBOW_COLOR_CACHE_ORDER.length > 16) {
        const old = RAINBOW_COLOR_CACHE_ORDER.shift();
        if (old !== key) delete RAINBOW_COLOR_CACHE[old];
    }
}
function clearRainbowColorCache() {
    for (const key in RAINBOW_COLOR_CACHE) delete RAINBOW_COLOR_CACHE[key];
    RAINBOW_COLOR_CACHE_ORDER.length = 0;
}

function computeCoverRainbowColor(handle, coverObj) {
    const key = getRainbowCacheKey(handle, coverObj);
    if (RAINBOW_COLOR_CACHE[key]) return RAINBOW_COLOR_CACHE[key];
    const img = coverObj && coverObj.img;
    let hue = null;
    let method = 'B64-ERR';
    let sampleW = 0, sampleH = 0;
    if (img) {
        const tempDir = fb.ProfilePath + 'music-card\\';
        const bmpPath = tempDir + '__musiccard_rainbow_b64_source_v4_16_0.bmp';
        let sampleImage = null;
        try {
            ensureFolder(tempDir);
            deleteFileQuiet(bmpPath);
            const maxSide = Math.max(img.Width, img.Height);
            const sampleScale = maxSide > RAINBOW_SAMPLE_MAX_SIDE ? RAINBOW_SAMPLE_MAX_SIDE / maxSide : 1;
            sampleW = Math.max(1, Math.round(img.Width * sampleScale));
            sampleH = Math.max(1, Math.round(img.Height * sampleScale));
            sampleImage = img.Resize(sampleW, sampleH, 7);
            if (sampleImage && sampleImage.SaveAs(bmpPath, 'image/bmp')) {
                const bytes = readBinaryFileBytesViaMsxml(bmpPath);
                hue = averageHueFromBmpBytes(bytes);
                if (hue !== null) method = 'B64-OK';
            }
            if (hue === null && sampleImage) hue = averageHueFromRgbList(extractPalette(sampleImage));
        } catch (e) {
            console.log('[MusicCard Rainbow B64] 异常: ' + String(e));
            hue = null;
        } finally {
            disposeImageSafe(sampleImage);
            deleteFileQuiet(bmpPath);
        }
    }
    if (hue === null) hue = averageHueFromRgbList(extractPalette(img));
    const rgb = hueUnitToFullRgb(hue);
    console.log('[MusicCard Rainbow B64] sample=' + sampleW + 'x' + sampleH + ' hue=' + formatNumber(hue) + ' rgb=' + rgb.r + ',' + rgb.g + ',' + rgb.b + ' method=' + method);
    rememberRainbowColor(key, rgb);
    return rgb;
}

function drawSolidBackground(gr, width, height, rainbowRgb) {
    const rgb = resolveColorSpecRgb(SOLID_BG_HEX, RGB(32, 32, 32), rainbowRgb) || { r: 32, g: 32, b: 32 };
    gr.FillSolidRect(0, 0, width, height, RGBA(rgb.r, rgb.g, rgb.b, 255));
}

function drawCoverShadow(gr, x, y, w, h, radius, isCircle, depth, maxAlpha, canvasW, canvasH) {
    if (depth <= 0 || maxAlpha <= 0) return;
    const leftRoom = Math.max(0, x - 1);
    const topRoom = Math.max(0, y - 1);
    const rightRoom = Math.max(0, canvasW - (x + w) - 1);
    const bottomRoom = Math.max(0, canvasH - (y + h) - 1);
    const safeDepth = Math.max(0, Math.min(depth, leftRoom, topRoom, rightRoom, bottomRoom));
    if (safeDepth <= 0) return;

    const rings = Math.max(1, Math.ceil(safeDepth));
    const step = safeDepth / rings;
    const strokeWidth = Math.max(0.5, step);
    gr.SetSmoothingMode(2);
    for (let ring = 1; ring <= rings; ring++) {
        const distance = ring * step;
        const progress = (ring - 1) / Math.max(1, rings);
        const alpha = maxAlpha * Math.pow(1 - progress, 2);
        if (alpha <= 0) continue;
        const sx = x - distance;
        const sy = y - distance;
        const sw = w + distance * 2 - strokeWidth;
        const sh = h + distance * 2 - strokeWidth;
        const color = RGBA(0, 0, 0, alpha);
        if (isCircle) {
            gr.DrawEllipse(sx, sy, sw, sh, strokeWidth, color);
        } else if (radius > 0) {
            const expandedRadius = Math.min(Math.min(sw, sh) / 2, radius + distance);
            gr.DrawRoundRect(sx, sy, sw, sh, expandedRadius, expandedRadius, strokeWidth, color);
        } else {
            gr.DrawRect(sx, sy, sw, sh, strokeWidth, color);
        }
    }
}
function drawCard(gr, info, coverObj, width, height, scale, seedText, lyricsModule, rainbowRgb) {
    const coverImgSrc = coverObj.img;
    const hasCover = !!coverObj.hasCover;
    const layout = getScaledLayout(scale, coverImgSrc, hasCover, lyricsModule);
    layout.cardH = height;
    const palette = extractPalette(coverImgSrc);

    if (BACKGROUND_STYLE === 'fusion') drawFusionBackground(gr, width, height, palette, scale, seedText);
    else if (BACKGROUND_STYLE === 'sample') drawSampleBackground(gr, width, height, palette, scale);
    else if (BACKGROUND_STYLE === 'blur') drawBlurBackground(gr, width, height, coverImgSrc, hasCover, palette, scale);
    else if (BACKGROUND_STYLE === 'solid') drawSolidBackground(gr, width, height, rainbowRgb);
    else drawInkBackground(gr, width, height, palette, scale);

    const baseText = BACKGROUND_STYLE === 'solid' ? chooseSolidBaseTextColor(SOLID_BG_HEX, rainbowRgb) : chooseBaseTextColor(palette);

    // Lyrics must use the same GDI+ text rendering mode as Title/Artist/Album.
    // This is especially important for letterSpacing is empty, where lyrics use
    // the native DrawString() path directly on the card graphics object.
    gr.SetTextRenderingHint(TEXT_RENDERING_HINT);

    const colors = {
        titleLabel: getElementColor(STYLE_CONFIG.titleLabel, baseText, rainbowRgb),
        titleValue: getElementColor(STYLE_CONFIG.titleValue, baseText, rainbowRgb),
        artistLabel: getElementColor(STYLE_CONFIG.artistLabel, baseText, rainbowRgb),
        artistValue: getElementColor(STYLE_CONFIG.artistValue, baseText, rainbowRgb),
        albumLabel: getElementColor(STYLE_CONFIG.albumLabel, baseText, rainbowRgb),
        albumValue: getElementColor(STYLE_CONFIG.albumValue, baseText, rainbowRgb),
        metaValue: getElementColor(STYLE_CONFIG.metaValue, baseText, rainbowRgb),
        watermark: getElementColor(STYLE_CONFIG.watermark, baseText, rainbowRgb)
    };

    drawLyricsModule(gr, info, layout, scale, baseText, rainbowRgb);

    if (hasCover) {
        const bitmapW = Math.max(1, Math.round(layout.coverW));
        const bitmapH = Math.max(1, Math.round(layout.coverH));
        const coverImg = prepareCoverImage(coverImgSrc, bitmapW, bitmapH, layout.coverCornerRadius, layout.coverIsCircle);
        drawCoverShadow(gr, layout.coverX, layout.coverY, layout.coverW, layout.coverH, layout.coverCornerRadius,
            layout.coverIsCircle, layout.shadowDepth, layout.shadowMaxAlpha, width, height);
        gr.DrawImage(coverImg, layout.coverX, layout.coverY, layout.coverW, layout.coverH, 0, 0, coverImg.Width, coverImg.Height);
        disposeImageSafe(coverImg);
    }

    gr.SetTextRenderingHint(TEXT_RENDERING_HINT);
    const fonts = buildFonts(scale);
    const text = info.renderedText || {};
    const tm = buildCardTextMetrics(gr, text, fonts, layout, scale);
    const textW = Math.max(1, width - tm.valueX - 20 * scale);
    const labelW = tm.labelColumnW;

    drawStyledText(gr, text.titleLabel, fonts.titleLabel, colors.titleLabel, STYLE_CONFIG.titleLabel,
        layout.labelX, tm.titleY, labelW, tm.titleH, CARD_STRING_FORMAT, scale, tm.titleLabel);
    drawStyledText(gr, text.titleValue, fonts.titleValue, colors.titleValue, STYLE_CONFIG.titleValue,
        tm.valueX, tm.titleY, textW, tm.titleH, CARD_STRING_FORMAT, scale, tm.titleValue);

    drawStyledText(gr, text.artistLabel, fonts.artistLabel, colors.artistLabel, STYLE_CONFIG.artistLabel,
        layout.labelX, tm.artistY, labelW, tm.artistH, CARD_STRING_FORMAT, scale, tm.artistLabel);
    drawStyledText(gr, text.artistValue, fonts.artistValue, colors.artistValue, STYLE_CONFIG.artistValue,
        tm.valueX, tm.artistY, textW, tm.artistH, CARD_STRING_FORMAT, scale, tm.artistValue);

    drawStyledText(gr, text.albumLabel, fonts.albumLabel, colors.albumLabel, STYLE_CONFIG.albumLabel,
        layout.labelX, tm.albumY, labelW, tm.albumH, CARD_STRING_FORMAT, scale, tm.albumLabel);
    drawStyledText(gr, text.albumValue, fonts.albumValue, colors.albumValue, STYLE_CONFIG.albumValue,
        tm.valueX, tm.albumY, textW, tm.albumH, CARD_STRING_FORMAT, scale, tm.albumValue);

    if (tm.hasMeta) {
        drawStyledText(gr, text.metaValue, fonts.metaValue, colors.metaValue, STYLE_CONFIG.metaValue,
            tm.valueX, tm.metaY, textW, tm.metaH, CARD_STRING_FORMAT, scale, tm.metaValue);
    }

    const watermarkText = String(text.watermark || '');
    if (watermarkText) {
        const watermarkW = Math.max(1, width - layout.labelX - layout.rightPadding);
        drawStyledText(gr, watermarkText, fonts.watermark, colors.watermark, STYLE_CONFIG.watermark,
            layout.labelX, layout.coverY, watermarkW, layout.coverH, WATERMARK_STRING_FORMAT, scale, tm.watermark);
    }
}


// Historical compatibility fix retained from the verified T1 branch.
// Some Windows clipboard pixel-format paths exposed an unpainted/alpha-contaminated
// top row and left column. Copying the adjacent 1px strips at the final gdi.Image
// stage fixes both clipboard and export output without changing the remaining image.
// Keep this repair unless a replacement has been validated against the same regression.
function replaceTopLeftEdgePixels(image, edgeSize) {
    const n = Math.max(1, Math.floor(Number(edgeSize) || 1));
    const width = image ? image.Width : 0;
    const height = image ? image.Height : 0;
    if (!image || width <= n || height <= n) return image;

    const fixed = gdi.CreateImage(width, height);
    const fg = fixed.GetGraphics();
    fg.SetSmoothingMode(0);
    fg.DrawImage(image, 0, 0, width, height, 0, 0, width, height);

    let topStrip = null;
    let leftStrip = null;
    let corner = null;
    try {
        topStrip = image.Clone(0, n, width, n);
        leftStrip = image.Clone(n, 0, n, height);
        corner = image.Clone(n, n, n, n);
        fg.DrawImage(topStrip, 0, 0, width, n, 0, 0, topStrip.Width, topStrip.Height);
        fg.DrawImage(leftStrip, 0, 0, n, height, 0, 0, leftStrip.Width, leftStrip.Height);
        fg.DrawImage(corner, 0, 0, n, n, 0, 0, corner.Width, corner.Height);
    } finally {
        fixed.ReleaseGraphics(fg);
        disposeImageSafe(topStrip);
        disposeImageSafe(leftStrip);
        disposeImageSafe(corner);
    }
    return fixed;
}

function buildCard(handle, seedText, scaleOverride) {
    const renderStartTime = Date.now();
    const requestedScale = parseFloat(scaleOverride);
    const renderScale = isFinite(requestedScale)
        ? round3(clamp(requestedScale, 0.1, 10))
        : EXPORT_SCALE;
    const info = getInfo(handle);
    info.renderedText = evaluateAllTextExpressions(handle);
    info.lyricsLines = evaluateLyricsLines(handle);
    const coverObj = getCover(handle);
    const usesRainbow = anyRainbowColorConfigured();
    const rainbowRgb = usesRainbow ? resolveRainbowTargetColor(handle, coverObj) : null;
    const lyricsModule = measureLyricsModule(info, renderScale);
    const widthFloat = measureDynamicWidth(info, renderScale, coverObj.img, !!coverObj.hasCover, lyricsModule);
    const layout = getScaledLayout(renderScale, coverObj.img, !!coverObj.hasCover, lyricsModule);
    const width = Math.max(1, Math.ceil(widthFloat));
    const height = Math.max(1, Math.ceil(layout.cardH));
    const usedSeed = BACKGROUND_STYLE === 'fusion' ? ensureFusionSeed(seedText) : '';
    const img = gdi.CreateImage(width, height);
    const gr = img.GetGraphics();
    gr.SetSmoothingMode(2);
    drawCard(gr, info, coverObj, width, height, renderScale, usedSeed, lyricsModule, rainbowRgb);
    img.ReleaseGraphics(gr);
    const repaired = replaceTopLeftEdgePixels(img, 1);
    if (repaired !== img) disposeImageSafe(img);
    const finalImage = repaired;
    const renderMs = Math.max(0, Date.now() - renderStartTime);
    LAST_CARD_RENDER_MS = renderMs;
    return { image: finalImage, info: info, width: width, height: height, seed: usedSeed, scale: renderScale, renderMs: renderMs };
}
function saveImage(img, info) {
    if (!ensureFolder(CONFIG.outputDir)) {
        fb.ShowPopupMessage('无法创建输出目录：\n' + CONFIG.outputDir, MUSICCARD_TITLE);
        return null;
    }
    const base = sanitizeFileName((info.title || 'Untitled') + '-' + (info.artist || 'Unknown Artist'));
    const full = uniquePath(CONFIG.outputDir, base, '.png');
    const ok = img.SaveAs(full, 'image/png');
    return ok ? full : null;
}
function copyTextToClipboard(text, silent) {
    try {
        const doc = new ActiveXObject('htmlfile');
        doc.parentWindow.clipboardData.setData('Text', String(text));
        return true;
    } catch (e) {
        try {
            const shell = new ActiveXObject('WScript.Shell');
            const escapedText = String(text).replace(/'/g, "''");
            const cmd = 'powershell -NoProfile -STA -ExecutionPolicy Bypass -Command "Set-Clipboard -Value \'"' + escapedText + '"\'"';
            shell.Run(cmd, 0, true);
            return true;
        } catch (e2) {
            if (!silent) fb.ShowPopupMessage('复制文本到剪贴板失败。\n\n' + e2, MUSICCARD_TITLE);
            return false;
        }
    }
}


function copyImageViaPowerShell(img, silent) {
    if (!ensureFolder(CONFIG.outputDir)) return false;
    const temp = CONFIG.outputDir + '__music_card_clipboard_v4167.png';
    try {
        img.SaveAs(temp, 'image/png');
        const shell = new ActiveXObject('WScript.Shell');
        const escaped = temp.replace(/'/g, "''");
        const cmd = 'powershell -NoProfile -STA -ExecutionPolicy Bypass -Command "' +
            'Add-Type -AssemblyName System.Windows.Forms; Add-Type -AssemblyName System.Drawing; ' +
            '$src=[System.Drawing.Bitmap]::FromFile(\'' + escaped + '\'); ' +
            '$bmp=[System.Drawing.Bitmap]::new($src.Width,$src.Height,[System.Drawing.Imaging.PixelFormat]::Format24bppRgb); ' +
            '$g=[System.Drawing.Graphics]::FromImage($bmp); ' +
            '$g.Clear([System.Drawing.Color]::White); ' +
            '$g.CompositingMode=[System.Drawing.Drawing2D.CompositingMode]::SourceOver; ' +
            '$g.DrawImage($src,0,0,$src.Width,$src.Height); ' +
            '$g.Dispose(); $src.Dispose(); ' +
            '[System.Windows.Forms.Clipboard]::SetImage($bmp); ' +
            '$bmp.Dispose();"';
        shell.Run(cmd, 0, true);
        return true;
    } catch (e) {
        if (!silent) fb.ShowPopupMessage('复制图片到剪贴板失败。\n方法：最终位图1px边缘修复→24bpp RGB\n\n' + e, MUSICCARD_TITLE);
        return false;
    }
}
function rectHit(rect, x, y) { return rect && x >= rect.x && x <= rect.x + rect.w && y >= rect.y && y <= rect.y + rect.h; }
function makeButton(x, y, w, h, text, id) { return { x: x, y: y, w: w, h: h, text: text, id: id }; }
function drawButton(gr, rect, hovered, small) {
    const fill = hovered ? RGBA(255,255,255,42) : RGBA(255,255,255,20);
    const stroke = hovered ? RGBA(255,255,255,110) : RGBA(255,255,255,55);
    const radius = Math.max(4, Math.min(14, Math.floor(rect.h / 2)));
    gr.FillRoundRect(rect.x, rect.y, rect.w, rect.h, radius, radius, fill);
    gr.DrawRoundRect(rect.x, rect.y, rect.w, rect.h, radius, radius, 1, stroke);
    const fontSize = rect.h <= 18 ? 9 : (small ? 14 : 18);
    const font = gdi.Font(DISPLAY_FONT_NAME, fontSize, 0);
    gr.SetTextRenderingHint(4);
    const textColor = (rect.id === 'copy' && UI.copyBusy) ? RGBA(255,255,255,255) : RGBA(255,255,255,235);
    gr.GdiDrawText(rect.text, font, textColor, rect.x, rect.y, rect.w, rect.h, 0x00000001 | 0x00000004 | 0x00000020 | DT_NOPREFIX);
}

function drawColorSwatchButton(gr, rect, hovered, selected) {
    const rgb = rect.rgb || makeColor(0, 0, 0);
    const radius = Math.max(4, Math.min(14, Math.floor(rect.h / 2)));
    gr.FillRoundRect(rect.x, rect.y, rect.w, rect.h, radius, radius, RGBA(rgb.r, rgb.g, rgb.b, 255));
    if (hovered) gr.FillRoundRect(rect.x, rect.y, rect.w, rect.h, radius, radius, RGBA(255, 255, 255, 35));
    gr.DrawRoundRect(rect.x, rect.y, rect.w, rect.h, radius, radius, selected ? 2 : 1,
        selected ? RGBA(255,255,255,220) : RGBA(255,255,255,80));
    if (selected) {
        const font = gdi.Font(DISPLAY_FONT_NAME, 14, 1);
        const inverse = RGBA(255 - rgb.r, 255 - rgb.g, 255 - rgb.b, 255);
        gr.SetTextRenderingHint(4);
        gr.GdiDrawText('✓', font, inverse, rect.x, rect.y, rect.w, rect.h,
            0x00000001 | 0x00000004 | 0x00000020 | DT_NOPREFIX);
    }
}
function drawEnvironmentColorButton(gr, rect, hovered) {
    const rgb = rect.rgb || makeColor(0, 0, 0);
    const radius = Math.max(4, Math.min(14, Math.floor(rect.h / 2)));
    gr.FillRoundRect(rect.x, rect.y, rect.w, rect.h, radius, radius, RGBA(rgb.r, rgb.g, rgb.b, 255));
    if (hovered) gr.FillRoundRect(rect.x, rect.y, rect.w, rect.h, radius, radius, RGBA(255, 255, 255, 35));
    gr.DrawRoundRect(rect.x, rect.y, rect.w, rect.h, radius, radius, 1, RGBA(255,255,255,90));
    const font = gdi.Font(DISPLAY_FONT_NAME, 13, 0);
    const inverse = RGBA(255 - rgb.r, 255 - rgb.g, 255 - rgb.b, 255);
    gr.SetTextRenderingHint(4);
    gr.GdiDrawText(rect.text || rgbToHexText(rgb), font, inverse, rect.x, rect.y, rect.w, rect.h,
        0x00000001 | 0x00000004 | 0x00000020 | DT_NOPREFIX);
}
function layoutMainButtons() {
    const bh = 44;
    const gap = window.Width < 760 ? 10 : 14;
    const bw = window.Width < 760 ? 108 : 128;
    const total = bw * 5 + gap * 4;
    const x = Math.floor((window.Width - total) / 2), y = Math.floor((window.Height - bh) / 2);
    UI.buttons = [
        makeButton(x, y, bw, bh, '预览', 'preview'),
        makeButton(x + (bw + gap), y, bw, bh, UI.copyBusy ? '生成中…' : '复制图片', 'copy'),
        makeButton(x + (bw + gap) * 2, y, bw, bh, '样式配置', 'settings'),
        makeButton(x + (bw + gap) * 3, y, bw, bh, '关于', 'about'),
        makeButton(x + (bw + gap) * 4, y, bw, bh, '休眠', 'sleep')
    ];
}
function buildScrollbarGeometry(viewport, contentW, contentH) {
    const barSize = 16;
    const maxX = Math.max(0, contentW - viewport.w);
    const maxY = Math.max(0, contentH - viewport.h);
    UI.settingsScrollX = clamp(UI.settingsScrollX, 0, maxX);
    UI.settingsScrollY = clamp(UI.settingsScrollY, 0, maxY);

    const v = {
        x: viewport.x + viewport.w, y: viewport.y, w: barSize, h: viewport.h,
        max: maxY, axis: 'vertical'
    };
    v.decRect = { x: v.x, y: v.y, w: barSize, h: barSize, id: 'settingsScrollUp' };
    v.incRect = { x: v.x, y: v.y + v.h - barSize, w: barSize, h: barSize, id: 'settingsScrollDown' };
    v.trackRect = { x: v.x, y: v.y + barSize, w: barSize, h: Math.max(0, v.h - barSize * 2), id: 'settingsVScrollTrack' };
    const vThumbH = maxY > 0 ? Math.max(36, Math.floor(v.trackRect.h * viewport.h / contentH)) : v.trackRect.h;
    const vTravel = Math.max(0, v.trackRect.h - vThumbH);
    const vThumbY = v.trackRect.y + (maxY > 0 ? Math.round(vTravel * UI.settingsScrollY / maxY) : 0);
    v.thumbRect = { x: v.x + 2, y: vThumbY, w: barSize - 4, h: vThumbH, id: 'settingsVScrollThumb' };
    v.travel = vTravel;

    const h = {
        x: viewport.x, y: viewport.y + viewport.h, w: viewport.w, h: barSize,
        max: maxX, axis: 'horizontal'
    };
    h.decRect = { x: h.x, y: h.y, w: barSize, h: barSize, id: 'settingsScrollLeft' };
    h.incRect = { x: h.x + h.w - barSize, y: h.y, w: barSize, h: barSize, id: 'settingsScrollRight' };
    h.trackRect = { x: h.x + barSize, y: h.y, w: Math.max(0, h.w - barSize * 2), h: barSize, id: 'settingsHScrollTrack' };
    const hThumbW = maxX > 0 ? Math.max(36, Math.floor(h.trackRect.w * viewport.w / contentW)) : h.trackRect.w;
    const hTravel = Math.max(0, h.trackRect.w - hThumbW);
    const hThumbX = h.trackRect.x + (maxX > 0 ? Math.round(hTravel * UI.settingsScrollX / maxX) : 0);
    h.thumbRect = { x: hThumbX, y: h.y + 2, w: hThumbW, h: barSize - 4, id: 'settingsHScrollThumb' };
    h.travel = hTravel;

    UI.settingsVScrollbar = v;
    UI.settingsHScrollbar = h;
}

function rainbowSampleSideButtonText() {
    return '取色封面边长 ' + String(RAINBOW_SAMPLE_MAX_SIDE);
}

function settingsPreviewDisplayHeight(contentW) {
    if (!UI.settingsPreviewEnabled) return 0;
    if (UI.settingsPreviewImage && UI.settingsPreviewImage.Width > 0) {
        const iw = UI.settingsPreviewImage.Width;
        const ih = UI.settingsPreviewImage.Height;
        // Only shrink images wider than the table-sized preview container.
        // Images that already fit keep their native 1:1 dimensions.
        return iw > contentW
            ? Math.max(1, Math.round(contentW * ih / iw))
            : Math.max(1, ih);
    }
    return 180;
}
function layoutSettingsUI() {
    UI.settingsButtons = {};
    UI.settingsRows = [];
    UI.lyricsButtons = {};
    UI.settingsCells = [];
    UI.headerCells = [];

    const barSize = 16;
    const viewport = { x: 0, y: 0, w: Math.max(1, window.Width - barSize), h: Math.max(1, window.Height - barSize) };
    let tableTotalW = 0;
    for (let i = 0; i < SETTINGS_COLUMNS.length; i++) tableTotalW += SETTINGS_COLUMNS[i].w + (i ? 6 : 0);
    const rainbowCustomHexButtonW = Math.round(170 * 0.7);
    const line4RequiredW = 878 + 188 + 20;
    const line5BaseControlsW = 696;
    const line5RainbowControlsW = RAINBOW_MODE === 'sample'
        ? 160
        : rainbowCustomHexButtonW + 8 + RAINBOW_STYLE_COLOR_COUNT * (48 + 8) - 8;
    const line5RequiredW = line5BaseControlsW + (BACKGROUND_STYLE === 'blur' ? 298 : 0) + line5RainbowControlsW + 20;
    const environmentRowW = CUSTOM_ENVIRONMENT_COLOR_COUNT * SETTINGS_COLUMNS[0].w + (CUSTOM_ENVIRONMENT_COLOR_COUNT - 1) * 8;
    const contentW = Math.max(940, tableTotalW + 30, 1280, line4RequiredW, line5RequiredW, environmentRowW + 20);
    const line2Y0 = 44, line3Y0 = 80, line4Y0 = 116, line5Y0 = 152;
    const tableY0 = 194 + (CUSTOM_ENVIRONMENT_COLORS_ENABLED ? 38 : 0);
    const rowH = 36;
    const headH = 32;
    const tableBottom0 = tableY0 + headH + 6 + STYLE_KEYS.length * (rowH + 4) - 4;
    const lyricsToggleY0 = tableBottom0 + 12;
    const lyricsConfigRows = LYRICS_CONFIG.enabled ? (LYRICS_CONFIG.dividerEnabled ? 6 : 4) : 0;
    const lyricsConfigH = lyricsConfigRows * 38;
    const previewControlY0 = lyricsToggleY0 + 40 + lyricsConfigH;
    const previewY0 = previewControlY0 + 42;
    const previewDisplayW = tableTotalW;
    const previewH = settingsPreviewDisplayHeight(previewDisplayW);
    const contentH = previewY0 + previewH + 18;

    UI.settingsViewport = viewport;
    UI.settingsContentW = contentW;
    UI.settingsContentH = contentH;
    buildScrollbarGeometry(viewport, contentW + 8, contentH);

    const centeredX = viewport.w >= contentW ? Math.floor((viewport.w - contentW) / 2) : 8;
    const baseX = centeredX - UI.settingsScrollX;
    const yOff = -UI.settingsScrollY;
    const line2Y = line2Y0 + yOff, line3Y = line3Y0 + yOff, line4Y = line4Y0 + yOff, line5Y = line5Y0 + yOff;
    const buttonH = 30, gap = 8;

    let x = baseX;
    UI.settingsButtons.save = makeButton(x, line2Y, 118, buttonH, '保存并返回', 'saveBack'); x += 118 + gap;
    UI.settingsButtons.scale1 = makeButton(x, line2Y, 48, buttonH, '1x', 'scale1'); x += 48 + gap;
    UI.settingsButtons.scale2 = makeButton(x, line2Y, 48, buttonH, '2x', 'scale2'); x += 48 + gap;
    UI.settingsButtons.scale3 = makeButton(x, line2Y, 48, buttonH, '3x', 'scale3'); x += 48 + gap;
    UI.settingsButtons.scale4 = makeButton(x, line2Y, 48, buttonH, '4x', 'scale4'); x += 48 + gap;
    UI.settingsButtons.scaleCustom = makeButton(x, line2Y, 144, buttonH, customScaleButtonText(), 'scaleCustom'); x += 144 + gap;
    UI.settingsButtons.bgFusion = makeButton(x, line2Y, 70, buttonH, '融合', 'bgFusion'); x += 70 + gap;
    UI.settingsButtons.bgInk = makeButton(x, line2Y, 70, buttonH, '墨点', 'bgInk'); x += 70 + gap;
    UI.settingsButtons.bgSample = makeButton(x, line2Y, 70, buttonH, '采点', 'bgSample'); x += 70 + gap;
    UI.settingsButtons.bgBlur = makeButton(x, line2Y, 70, buttonH, '模糊', 'bgBlur'); x += 70 + gap;
    UI.settingsButtons.bgSolid = makeButton(x, line2Y, 70, buttonH, '纯色', 'bgSolid');

    x = baseX;
    UI.settingsButtons.reset = makeButton(x, line3Y, 150, buttonH, '恢复默认配置', 'resetDefaults'); x += 150 + gap;
    UI.settingsButtons.displayFont = makeButton(x, line3Y, 150, buttonH, '修改显示字体', 'displayFont'); x += 150 + gap;
    UI.settingsButtons.listFonts = makeButton(x, line3Y, 150, buttonH, '列出所有字体', 'listFonts'); x += 150 + gap;
    UI.settingsButtons.textRenderingHint = makeButton(x, line3Y, 150, buttonH,
        '文本渲染 ' + TEXT_RENDERING_HINT, 'textRenderingHint'); x += 150 + gap;
    UI.settingsButtons.imp = makeButton(x, line3Y, 115, buttonH, '导入配置', 'importCfg'); x += 115 + gap;
    UI.settingsButtons.exp = makeButton(x, line3Y, 115, buttonH, '导出配置', 'exportCfg'); x += 115 + gap;
    UI.settingsButtons.chooseCfg = makeButton(x, line3Y, 115, buttonH, '选择配置', 'chooseCfg');

    UI.blurSlider = {
        x: baseX + 92, y: line4Y + 6, w: 250, h: 18, id: 'blurSlider', valueId: 'blurSliderValue',
        labelX: baseX, labelW: 86, valueX: baseX + 348, valueW: 38
    };
    const cornerBaseX = baseX + 470;
    UI.cornerSlider = {
        x: cornerBaseX + 92, y: line4Y + 6, w: 250, h: 18, id: 'cornerSlider', valueId: 'cornerSliderValue',
        labelX: cornerBaseX, labelW: 86, valueX: cornerBaseX + 348, valueW: 52
    };
    UI.settingsButtons.rainbowMode = makeButton(baseX + 878, line4Y, 188, buttonH,
        '彩虹色：' + (RAINBOW_MODE === 'sample' ? '取色' : '自定义'), 'rainbowMode');

    let line5X = baseX;
    UI.settingsButtons.customEnvironmentToggle = makeButton(line5X, line5Y, 210, buttonH,
        '自定义环境颜色：' + (CUSTOM_ENVIRONMENT_COLORS_ENABLED ? '打开' : '关闭'), 'customEnvironmentToggle');
    line5X += 218;
    UI.settingsButtons.shadowOpacity = makeButton(line5X, line5Y, 210, buttonH,
        '封面阴影不透明度 ' + formatNumber(COVER_SHADOW_OPACITY), 'shadowOpacity');
    line5X += 218;
    UI.settingsButtons.shadowDepth = makeButton(line5X, line5Y, 109, buttonH,
        '阴影深度 ' + formatNumber(COVER_SHADOW_DEPTH), 'shadowDepth');
    line5X += 117;
    UI.settingsButtons.coverMode = makeButton(line5X, line5Y, 141, buttonH,
        '不规则封面：' + (IRREGULAR_COVER_MODE === 'tile' ? '平铺' : '裁剪'), 'coverMode');
    line5X += 149;
    let rainbowControlX = line5X;
    if (BACKGROUND_STYLE === 'blur') {
        UI.settingsButtons.blurBgCropPosition = makeButton(rainbowControlX, line5Y, 174, buttonH,
            '背景截取封面位置 ' + formatNumber(BLUR_BG_CROP_POSITION) + '%', 'blurBgCropPosition');
        rainbowControlX += 182;
    }
    if (RAINBOW_MODE === 'sample') {
        UI.settingsButtons.rainbowSampleSide = makeButton(rainbowControlX, line5Y, 160, buttonH,
            rainbowSampleSideButtonText(), 'rainbowSampleSide');
    } else {
        const customHexText = RAINBOW_CUSTOM_SELECTION === 'hex'
            ? '✓' + (RAINBOW_CUSTOM_HEX || '自动')
            : 'HEX';
        UI.settingsButtons.rainbowCustomHex = makeButton(rainbowControlX, line5Y, rainbowCustomHexButtonW, buttonH,
            customHexText, 'rainbowCustomHex');
        rainbowControlX += rainbowCustomHexButtonW + 8;
        UI.rainbowPaletteColors = getCurrentCoverStyleColors();
        UI.settingsButtons.rainbowPalette = [];
        for (let pi = 0; pi < RAINBOW_STYLE_COLOR_COUNT; pi++) {
            const selected = RAINBOW_CUSTOM_SELECTION === 'palette:' + String(pi);
            const color = UI.rainbowPaletteColors[pi] || makeColor(0, 0, 0);
            const button = makeButton(rainbowControlX, line5Y, 48, buttonH, selected ? '✓' : '', 'rainbowPalette' + String(pi));
            button.paletteIndex = pi;
            button.rgb = color;
            UI.settingsButtons.rainbowPalette.push(button);
            rainbowControlX += 56;
        }
    }
    UI.settingsButtons.customEnvironmentPalette = [];
    if (CUSTOM_ENVIRONMENT_COLORS_ENABLED) {
        let environmentX = baseX;
        const environmentY = line5Y + 38;
        for (let ei = 0; ei < CUSTOM_ENVIRONMENT_COLOR_COUNT; ei++) {
            const hex = CUSTOM_ENVIRONMENT_COLOR_HEXES[ei] || '#000000';
            const rgb = hexToRgb(hex) || makeColor(0, 0, 0);
            const button = makeButton(environmentX, environmentY, SETTINGS_COLUMNS[0].w, buttonH,
                hex, 'customEnvironmentColor' + String(ei));
            button.environmentIndex = ei;
            button.rgb = rgb;
            UI.settingsButtons.customEnvironmentPalette.push(button);
            environmentX += SETTINGS_COLUMNS[0].w + gap;
        }
    }

    const tableX = baseX + 15;
    const tableY = tableY0 + yOff;
    let cx = tableX;
    for (let i = 0; i < SETTINGS_COLUMNS.length; i++) {
        const col = SETTINGS_COLUMNS[i];
        UI.headerCells.push({ x: cx, y: tableY, w: col.w, h: headH, text: col.title, id: 'hdr_' + col.key, colKey: col.key, type: col.type });
        cx += col.w + 6;
    }

    let y = tableY + headH + 6;
    for (let r = 0; r < STYLE_KEYS.length; r++) {
        const rowKey = STYLE_KEYS[r][0], rowLabel = STYLE_KEYS[r][1];
        UI.settingsRows.push({ key: rowKey, label: rowLabel, x: tableX, y: y, h: rowH });
        cx = tableX;
        for (let c = 0; c < SETTINGS_COLUMNS.length; c++) {
            const col = SETTINGS_COLUMNS[c];
            UI.settingsCells.push({
                x: cx, y: y, w: col.w, h: rowH,
                rowKey: rowKey, rowLabel: rowLabel, colKey: col.key, type: col.type,
                id: 'cell_' + rowKey + '_' + col.key
            });
            cx += col.w + 6;
        }
        y += rowH + 4;
    }

    UI.settingsTableBottom = tableBottom0 + yOff;
    const lyricsToggleY = lyricsToggleY0 + yOff;
    UI.settingsButtons.lyricsToggle = makeButton(baseX, lyricsToggleY, 220, 32,
        '歌词排版：' + (LYRICS_CONFIG.enabled ? '打开' : '关闭'), 'lyricsToggle');
    UI.settingsButtons.textOpenCC = makeButton(baseX + 228, lyricsToggleY, 180, 32,
        openCCModeButtonText(TEXT_OPENCC_MODE), 'textOpenCC');

    function lyricButton(key, x0, y0, w0, text0) {
        UI.lyricsButtons[key] = makeButton(x0, y0, w0, 30, text0, 'lyrics_' + key);
        return UI.lyricsButtons[key];
    }
    if (LYRICS_CONFIG.enabled) {
        let ly = lyricsToggleY + 40;
        const lyricsX = tableX;
        const lyricsW = tableTotalW;
        const lyricGap = 8;
        const lyricsTextValue = String(LYRICS_CONFIG.text || '');
        const lyricsLineCount = lyricsTextValue ? lyricsTextValue.split(/\r?\n/).length : 0;

        const row1W1 = 230, row1W2 = 250, row1W3 = 150, row1W4 = 180;
        const row1W5 = lyricsW - row1W1 - row1W2 - row1W3 - row1W4 - lyricGap * 4;
        lyricButton('containerWidth', lyricsX, ly, row1W1, '容器宽度 ' + formatNumber(LYRICS_CONFIG.containerWidth) + '（0=自动）');
        lyricButton('lyricsText', lyricsX + row1W1 + lyricGap, ly, row1W2, '歌词内容（' + lyricsLineCount + '行）');
        lyricButton('size', lyricsX + row1W1 + row1W2 + lyricGap * 2, ly, row1W3, '字号 ' + formatNumber(LYRICS_CONFIG.size));
        lyricButton('openCCMode', lyricsX + row1W1 + row1W2 + row1W3 + lyricGap * 3, ly, row1W4,
            openCCModeButtonText(LYRICS_OPENCC_MODE));
        lyricButton('font', lyricsX + row1W1 + row1W2 + row1W3 + row1W4 + lyricGap * 4, ly, row1W5,
            '字体：' + (LYRICS_CONFIG.font || DEFAULT_FONT_NAME));

        ly += 38;
        const row2Widths = [110, 110, 165, 155, 175, 190];
        const row2LastW = lyricsW - row2Widths.reduce(function(a,b){return a+b;}, 0) - lyricGap * 6;
        let lx = lyricsX;
        lyricButton('bold', lx, ly, row2Widths[0], '粗体：' + (LYRICS_CONFIG.bold ? '开' : '关')); lx += row2Widths[0] + lyricGap;
        lyricButton('italic', lx, ly, row2Widths[1], '斜体：' + (LYRICS_CONFIG.italic ? '开' : '关')); lx += row2Widths[1] + lyricGap;
        lyricButton('colorHex', lx, ly, row2Widths[2], 'HEX ' + (LYRICS_CONFIG.colorHex || '自动')); lx += row2Widths[2] + lyricGap;
        lyricButton('opacity', lx, ly, row2Widths[3], '不透明度 ' + formatNumber(LYRICS_CONFIG.opacity)); lx += row2Widths[3] + lyricGap;
        lyricButton('blurStrength', lx, ly, row2Widths[4], '模糊强度 ' + LYRICS_CONFIG.blurStrength); lx += row2Widths[4] + lyricGap;
        lyricButton('blurOpacity', lx, ly, row2Widths[5], '模糊不透明度 ' + formatNumber(LYRICS_CONFIG.blurOpacity)); lx += row2Widths[5] + lyricGap;
        lyricButton('letterSpacing', lx, ly, row2LastW, '字间距 ' + formatLetterSpacing(LYRICS_CONFIG.letterSpacing));

        ly += 38;
        const row3Widths = [170, 170, 145, 165, 165];
        const row3LastW = lyricsW - row3Widths.reduce(function(a,b){return a+b;}, 0) - lyricGap * 5;
        lx = lyricsX;
        lyricButton('topPadding', lx, ly, row3Widths[0], '上间距 ' + formatNumber(LYRICS_CONFIG.topPadding)); lx += row3Widths[0] + lyricGap;
        lyricButton('bottomPadding', lx, ly, row3Widths[1], '下间距 ' + formatNumber(LYRICS_CONFIG.bottomPadding)); lx += row3Widths[1] + lyricGap;
        lyricButton('lineGap', lx, ly, row3Widths[2], '行距 ' + formatNumber(LYRICS_CONFIG.lineGap)); lx += row3Widths[2] + lyricGap;
        const xAlignText = LYRICS_CONFIG.xAlign === 'center' ? '中' : (LYRICS_CONFIG.xAlign === 'right' ? '右' : '左');
        const yAlignText = LYRICS_CONFIG.yAlign === 'center' ? '中' : (LYRICS_CONFIG.yAlign === 'bottom' ? '下' : '上');
        lyricButton('xAlign', lx, ly, row3Widths[3], 'x对齐：' + xAlignText); lx += row3Widths[3] + lyricGap;
        lyricButton('yAlign', lx, ly, row3Widths[4], 'y对齐：' + yAlignText); lx += row3Widths[4] + lyricGap;
        lyricButton('rightGap', lx, ly, row3LastW, '容器右侧与封面距离 ' + formatNumber(LYRICS_CONFIG.rightGap));

        ly += 38;
        if (!LYRICS_CONFIG.dividerEnabled) {
            lyricButton('dividerEnabled', lyricsX, ly, 220, '分隔线：关');
        } else {
            const dividerRowW = Math.floor((lyricsW - lyricGap * 5) / 6);
            const dividerLastW = lyricsW - dividerRowW * 5 - lyricGap * 5;
            lx = lyricsX;
            lyricButton('dividerEnabled', lx, ly, dividerRowW, '分隔线：开'); lx += dividerRowW + lyricGap;
            lyricButton('dividerThickness', lx, ly, dividerRowW, '分隔线粗 ' + formatNumber(LYRICS_CONFIG.dividerThickness)); lx += dividerRowW + lyricGap;
            lyricButton('dividerTopPadding', lx, ly, dividerRowW, '分隔线上间距 ' + formatNumber(LYRICS_CONFIG.dividerTopPadding)); lx += dividerRowW + lyricGap;
            lyricButton('dividerBottomPadding', lx, ly, dividerRowW, '分隔线下间距 ' + formatNumber(LYRICS_CONFIG.dividerBottomPadding)); lx += dividerRowW + lyricGap;
            lyricButton('dividerLeftGap', lx, ly, dividerRowW, '分隔线左间距 ' + formatNumber(LYRICS_CONFIG.dividerLeftGap)); lx += dividerRowW + lyricGap;
            lyricButton('dividerRightGap', lx, ly, dividerLastW, '分隔线右间距 ' + formatNumber(LYRICS_CONFIG.dividerRightGap));

            ly += 38;
            const threeW = Math.floor((lyricsW - lyricGap * 2) / 3);
            const threeLastW = lyricsW - threeW * 2 - lyricGap * 2;
            lyricButton('dividerTopHex', lyricsX, ly, threeW, '顶部 HEX ' + (LYRICS_CONFIG.dividerTopHex || '自动'));
            lyricButton('dividerMiddleHex', lyricsX + threeW + lyricGap, ly, threeW, '中间 HEX ' + (LYRICS_CONFIG.dividerMiddleHex || '自动'));
            lyricButton('dividerBottomHex', lyricsX + threeW * 2 + lyricGap * 2, ly, threeLastW, '底部 HEX ' + (LYRICS_CONFIG.dividerBottomHex || '自动'));

            ly += 38;
            lyricButton('dividerTopOpacity', lyricsX, ly, threeW, '顶部不透明度 ' + formatNumber(LYRICS_CONFIG.dividerTopOpacity));
            lyricButton('dividerMiddleOpacity', lyricsX + threeW + lyricGap, ly, threeW, '中间不透明度 ' + formatNumber(LYRICS_CONFIG.dividerMiddleOpacity));
            lyricButton('dividerBottomOpacity', lyricsX + threeW * 2 + lyricGap * 2, ly, threeLastW, '底部不透明度 ' + formatNumber(LYRICS_CONFIG.dividerBottomOpacity));
        }
    }
    UI.lyricsSectionBottom = previewControlY0 + yOff - 8;
    const previewControlY = previewControlY0 + yOff;
    x = baseX;
    UI.settingsButtons.previewToggle = makeButton(x, previewControlY, 170, 32,
        '预览显示：' + (UI.settingsPreviewEnabled ? '打开' : '关闭'), 'settingsPreviewToggle'); x += 170 + gap;
    UI.settingsButtons.settingsPopupPreview = makeButton(x, previewControlY, 130, 32,
        '弹出预览窗口', 'settingsPopupPreview'); x += 130 + gap;
    UI.settingsButtons.settingsSeedInput = makeButton(x, previewControlY, 80, 32, 'Input', 'settingsSeedInput'); x += 80 + gap;
    const settingsSeedText = BACKGROUND_STYLE === 'fusion' ? (UI.settingsPreviewSeed || 'N/A') : 'N/A';
    UI.settingsButtons.settingsSeedCopy = makeButton(x, previewControlY, 250, 32,
        'Copy seed: ' + settingsSeedText, 'settingsSeedCopy'); x += 250 + gap;
    UI.settingsButtons.settingsSeedRefresh = makeButton(x, previewControlY, 80, 32,
        'Refresh', 'settingsSeedRefresh'); x += 80 + gap;
    UI.settingsButtons.settingsCopyImage = makeButton(x, previewControlY, 110, 32,
        UI.settingsCopyImageBusy ? 'Wait…' : 'Copy image', 'settingsCopyImage'); x += 110 + gap;
    UI.settingsButtons.settingsResolution = makeButton(x, previewControlY, 190, 32,
        imageResolutionAndTimeText(UI.settingsPreviewImage, UI.settingsPreviewRenderMs), 'settingsResolution');

    UI.settingsPreviewRect = {
        x: tableX,
        y: previewY0 + yOff,
        w: previewDisplayW,
        h: previewH
    };
}

function getCellDisplayText(rowKey, colKey) {
    const obj = STYLE_CONFIG[rowKey];
    if (!obj) return '';
    switch (colKey) {
        case 'rowLabel': return getStyleRowLabel(rowKey);
        case 'size': return formatNumber(obj.size);
        case 'font': return obj.font || DEFAULT_FONT_NAME;
        case 'bold': return obj.bold ? '开' : '关';
        case 'italic': return obj.italic ? '开' : '关';
        case 'colorHex': return obj.colorHex || '自动';
        case 'opacity': return formatNumber(obj.opacity);
        case 'blurStrength': return String(obj.blurStrength || 0);
        case 'blurOpacity': return formatNumber(obj.blurOpacity || 0);
        case 'letterSpacing': return formatLetterSpacing(obj.letterSpacing);
        case 'text': return rowSupportsText(rowKey) ? (obj.text || '') : '--';
    }
    return '';
}
function drawGridCell(gr, rect, text, hovered, selected, small) {
    const fill = selected ? RGBA(255,255,255,34) : (hovered ? RGBA(255,255,255,24) : RGBA(255,255,255,10));
    const stroke = selected ? RGBA(255,255,255,85) : RGBA(255,255,255,28);
    gr.FillRoundRect(rect.x, rect.y, rect.w, rect.h, 10, 10, fill);
    gr.DrawRoundRect(rect.x, rect.y, rect.w, rect.h, 10, 10, 1, stroke);
    const font = gdi.Font(DISPLAY_FONT_NAME, small ? 12 : 13, 0);
    gr.SetTextRenderingHint(4);
    gr.GdiDrawText(text, font, RGBA(255,255,255,235), rect.x + 6, rect.y, rect.w - 12, rect.h, 0x00000000 | 0x00000004 | 0x00000020 | DT_NOPREFIX);
}
function summarizeStyleEntry(entry) {
    return '字号 ' + entry.size + ' | 字体 ' + (entry.font || DEFAULT_FONT_NAME) + ' | ' + (entry.bold ? '粗体 ' : '') + (entry.italic ? '斜体 ' : '') + '| 颜色 ' + (entry.colorHex || '自动') + ' | 不透明度 ' + entry.opacity + ' | 模糊 ' + (entry.blurStrength || 0) + '/' + (entry.blurOpacity || 0);
}
function drawMainView(gr) {
    layoutMainButtons();
    gr.FillSolidRect(0, 0, window.Width, window.Height, RGB(17, 18, 22));
    for (let i = 0; i < UI.buttons.length; i++) drawButton(gr, UI.buttons[i], UI.hover === UI.buttons[i].id, false);
}
function layoutSleepButton() {
    const bw = 144, bh = 44;
    UI.sleepButton = makeButton(
        Math.floor((window.Width - bw) / 2),
        Math.floor((window.Height - bh) / 2),
        bw, bh,
        '恢复',
        'restore'
    );
}
function drawSleepView(gr) {
    layoutSleepButton();
    gr.FillSolidRect(0, 0, window.Width, window.Height, RGB(10, 11, 14));
    drawButton(gr, UI.sleepButton, UI.hover === UI.sleepButton.id, false);
}
function imageResolutionText(image) {
    return image && image.Width > 0 && image.Height > 0
        ? String(image.Width) + '×' + String(image.Height)
        : 'N/A';
}
function formatRenderDuration(milliseconds) {
    if (milliseconds === null || milliseconds === undefined || !isFinite(Number(milliseconds))) return '';
    const ms = Math.max(0, Math.round(Number(milliseconds)));
    return ms >= 1000 ? formatNumber(ms / 1000) + 's' : String(ms) + 'ms';
}
function imageResolutionAndTimeText(image, milliseconds) {
    const resolution = imageResolutionText(image);
    const duration = formatRenderDuration(milliseconds);
    return duration && resolution !== 'N/A' ? resolution + ' (' + duration + ')' : resolution;
}
function customScaleButtonText() {
    return CUSTOM_EXPORT_SCALE === null ? '自定义x' : '自定义：' + formatNumber(CUSTOM_EXPORT_SCALE) + 'x';
}
function previewSeedLabel(seed) {
    return 'Copy seed: ' + (seed ? seed : 'N/A');
}
function getActivePreviewSeed() {
    return UI.previewReturnView === 'settings' ? (UI.popupPreviewSeed || '') : (UI.previewSeed || '');
}
function setActivePreviewSeed(seed) {
    if (UI.previewReturnView === 'settings') UI.popupPreviewSeed = seed || '';
    else UI.previewSeed = seed || '';
}
function drawPreviewView(gr) {
    gr.FillSolidRect(0, 0, window.Width, window.Height, CONFIG.preview.overlay);
    UI.previewInputButton = null;
    UI.previewSeedCopyButton = null;
    UI.previewSeedRefreshButton = null;
    UI.previewCopyImageButton = null;
    UI.previewResolutionButton = null;
    if (!UI.previewImage) return;

    const pad = CONFIG.preview.padding;
    const maxW = window.Width - pad * 2;
    const maxH = window.Height - pad * 2;
    const rw = UI.previewImage.Width, rh = UI.previewImage.Height;
    const scale = Math.min(maxW / rw, maxH / rh, 1);
    const dw = Math.floor(rw * scale), dh = Math.floor(rh * scale);
    const dx = Math.floor((window.Width - dw) / 2), dy = Math.floor((window.Height - dh) / 2);
    UI.previewRect = { x: dx, y: dy, w: dw, h: dh };
    UI.closeRect = null;
    gr.DrawImage(UI.previewImage, dx, dy, dw, dh, 0, 0, rw, rh);

    const inputW = 72, copyW = 143, refreshW = 60, copyImageW = 96, resolutionW = 160, buttonH = 18, gap = 6;
    const totalW = inputW + copyW + refreshW + copyImageW + resolutionW + gap * 4;
    const bx = Math.floor((window.Width - totalW) / 2);
    let buttonX = bx;
    UI.previewInputButton = makeButton(buttonX, 8, inputW, buttonH, 'Input', 'previewSeedInput'); buttonX += inputW + gap;
    UI.previewSeedCopyButton = makeButton(buttonX, 8, copyW, buttonH,
        previewSeedLabel(getActivePreviewSeed()), 'previewSeedCopy'); buttonX += copyW + gap;
    UI.previewSeedRefreshButton = makeButton(buttonX, 8, refreshW, buttonH,
        'Refresh', 'previewSeedRefresh'); buttonX += refreshW + gap;
    UI.previewCopyImageButton = makeButton(buttonX, 8, copyImageW, buttonH,
        UI.previewCopyImageBusy ? 'Wait…' : 'Copy image', 'previewCopyImage'); buttonX += copyImageW + gap;
    UI.previewResolutionButton = makeButton(buttonX, 8, resolutionW, buttonH,
        imageResolutionAndTimeText(UI.previewImage, UI.previewRenderMs), 'previewResolution');
    drawButton(gr, UI.previewInputButton, UI.hover === UI.previewInputButton.id, true);
    drawButton(gr, UI.previewSeedCopyButton, UI.hover === UI.previewSeedCopyButton.id, true);
    drawButton(gr, UI.previewSeedRefreshButton, UI.hover === UI.previewSeedRefreshButton.id, true);
    drawButton(gr, UI.previewCopyImageButton, UI.hover === UI.previewCopyImageButton.id, true);
    drawButton(gr, UI.previewResolutionButton, UI.hover === UI.previewResolutionButton.id, true);
}

function getSliderValueRect(sl) {
    return { x: sl.valueX, y: sl.y - 4, w: sl.valueW, h: 24 };
}
function drawSliderValueBackground(gr, sl) {
    if (UI.hover !== sl.valueId) return;
    const r = getSliderValueRect(sl);
    gr.FillRoundRect(r.x, r.y, r.w, r.h, 6, 6, RGBA(255,255,255,22));
    gr.DrawRoundRect(r.x, r.y, r.w, r.h, 6, 6, 1, RGBA(255,255,255,58));
}

function drawBlurSlider(gr) {
    const sl = UI.blurSlider;
    if (!sl) return;
    const labelFont = gdi.Font(DISPLAY_FONT_NAME, 14, 0);
    gr.GdiDrawText('模糊强度', labelFont, RGBA(255,255,255,190), sl.labelX, sl.y - 4, sl.labelW, 24,
        0x00000000 | 0x00000004 | 0x00000020 | DT_NOPREFIX);
    const cy = sl.y + Math.floor(sl.h / 2);
    gr.FillSolidRect(sl.x, cy - 3, sl.w, 6, RGBA(255,255,255,40));
    const filled = clamp(Math.round(sl.w * BLUR_STRENGTH / MAX_BLUR_STRENGTH), 0, sl.w);
    if (filled > 0) gr.FillSolidRect(sl.x, cy - 3, filled, 6, RGBA(255,255,255,150));
    const knobX = sl.x + filled;
    gr.FillEllipse(knobX - 7, cy - 7, 14, 14, RGBA(245,245,245,245));
    gr.DrawEllipse(knobX - 7, cy - 7, 14, 14, 1, RGBA(0,0,0,80));
    drawSliderValueBackground(gr, sl);
    gr.GdiDrawText(String(BLUR_STRENGTH), labelFont, RGBA(255,255,255,190), sl.valueX, sl.y - 4, sl.valueW, 24,
        0x00000000 | 0x00000004 | 0x00000020 | DT_NOPREFIX);
}
function updateBlurStrengthFromX(x, saveNow) {
    if (!UI.blurSlider) return;
    BLUR_STRENGTH = clamp(Math.round((x - UI.blurSlider.x) * MAX_BLUR_STRENGTH / UI.blurSlider.w), 0, MAX_BLUR_STRENGTH);
    if (saveNow) persistSettings();
    window.Repaint();
}
function actionSetBlurStrength() {
    const val = requestInput('请输入模糊强度（0-' + MAX_BLUR_STRENGTH + '）', '模糊强度', String(BLUR_STRENGTH));
    if (inputWasCancelled(val)) return;
    const raw = String(val).trim();
    if (!/^\d+$/.test(raw)) {
        fb.ShowPopupMessage('请输入 0-' + MAX_BLUR_STRENGTH + ' 之间的整数。', MUSICCARD_TITLE);
        return;
    }
    const n = parseInt(raw, 10);
    if (n < 0 || n > MAX_BLUR_STRENGTH) {
        fb.ShowPopupMessage('请输入 0-' + MAX_BLUR_STRENGTH + ' 之间的整数。', MUSICCARD_TITLE);
        return;
    }
    BLUR_STRENGTH = n;
    persistSettings();
    window.Repaint();
}

function drawCoverCornerSlider(gr) {
    const sl = UI.cornerSlider;
    if (!sl) return;
    const labelFont = gdi.Font(DISPLAY_FONT_NAME, 14, 0);
    gr.GdiDrawText('封面圆角', labelFont, RGBA(255,255,255,190), sl.labelX, sl.y - 4, sl.labelW, 24,
        0x00000000 | 0x00000004 | 0x00000020 | DT_NOPREFIX);
    const cy = sl.y + Math.floor(sl.h / 2);
    gr.FillSolidRect(sl.x, cy - 3, sl.w, 6, RGBA(255,255,255,40));
    const filled = clamp(Math.round(sl.w * COVER_CORNER_RADIUS / MAX_COVER_CORNER_RADIUS), 0, sl.w);
    if (filled > 0) gr.FillSolidRect(sl.x, cy - 3, filled, 6, RGBA(255,255,255,150));
    const knobX = sl.x + filled;
    gr.FillEllipse(knobX - 7, cy - 7, 14, 14, RGBA(245,245,245,245));
    gr.DrawEllipse(knobX - 7, cy - 7, 14, 14, 1, RGBA(0,0,0,80));
    drawSliderValueBackground(gr, sl);
    gr.GdiDrawText(String(COVER_CORNER_RADIUS), labelFont, RGBA(255,255,255,190), sl.valueX, sl.y - 4, sl.valueW, 24,
        0x00000000 | 0x00000004 | 0x00000020 | DT_NOPREFIX);
}
function updateCoverCornerRadiusFromX(x, saveNow) {
    if (!UI.cornerSlider) return;
    COVER_CORNER_RADIUS = clamp(Math.round((x - UI.cornerSlider.x) * MAX_COVER_CORNER_RADIUS / UI.cornerSlider.w), 0, MAX_COVER_CORNER_RADIUS);
    if (saveNow) persistSettings();
    window.Repaint();
}
function actionSetCoverCornerRadius() {
    const val = requestInput(
        '请输入封面圆角（0-' + MAX_COVER_CORNER_RADIUS + '）。\n输入 ' + MAX_COVER_CORNER_RADIUS + ' 时直接裁成圆形，不使用圆角矩形算法。',
        '封面圆角',
        String(COVER_CORNER_RADIUS)
    );
    if (inputWasCancelled(val)) return;
    const raw = String(val).trim();
    if (!/^\d+$/.test(raw)) {
        fb.ShowPopupMessage('请输入 0-' + MAX_COVER_CORNER_RADIUS + ' 之间的整数。', MUSICCARD_TITLE);
        return;
    }
    const n = parseInt(raw, 10);
    if (n < 0 || n > MAX_COVER_CORNER_RADIUS) {
        fb.ShowPopupMessage('请输入 0-' + MAX_COVER_CORNER_RADIUS + ' 之间的整数。', MUSICCARD_TITLE);
        return;
    }
    COVER_CORNER_RADIUS = n;
    persistSettings();
    window.Repaint();
}

function drawSettingsPreviewPanel(gr) {
    if (!UI.settingsPreviewEnabled || !UI.settingsPreviewRect) return;
    const r = UI.settingsPreviewRect;
    if (r.h <= 0) return;
    gr.FillSolidRect(r.x, r.y, r.w, r.h, RGBA(255,255,255,8));
    gr.DrawRect(r.x, r.y, r.w - 1, r.h - 1, 1, RGBA(255,255,255,32));

    if (UI.settingsPreviewDirty && !UI.settingsPreviewRefreshPending) scheduleSettingsPreviewRefresh();
    if (!UI.settingsPreviewImage) {
        const f = gdi.Font(DISPLAY_FONT_NAME, 14, 0);
        gr.GdiDrawText(UI.settingsPreviewRefreshPending ? '预览生成中…' : '暂无预览', f, RGBA(255,255,255,150),
            r.x, r.y, r.w, r.h, 0x00000001 | 0x00000004 | 0x00000020 | DT_NOPREFIX);
        return;
    }

    const iw = UI.settingsPreviewImage.Width, ih = UI.settingsPreviewImage.Height;
    const needsShrink = iw > r.w;
    const dw = needsShrink ? r.w : iw;
    const dh = needsShrink ? Math.max(1, Math.round(r.w * ih / iw)) : ih;
    const dx = r.x + Math.floor((r.w - dw) / 2);
    gr.DrawImage(UI.settingsPreviewImage, dx, r.y, dw, dh, 0, 0, iw, ih);
    gr.DrawRect(dx, r.y, dw - 1, dh - 1, 1, RGBA(255,255,255,45));
}

function drawScrollbarButton(gr, rect, text, hovered) {
    gr.FillSolidRect(rect.x, rect.y, rect.w, rect.h, hovered ? RGBA(255,255,255,34) : RGBA(255,255,255,16));
    gr.DrawRect(rect.x, rect.y, rect.w - 1, rect.h - 1, 1, RGBA(255,255,255,34));
    const f = gdi.Font(DISPLAY_FONT_NAME, 10, 0);
    gr.GdiDrawText(text, f, RGBA(255,255,255,190), rect.x, rect.y, rect.w, rect.h,
        0x00000001 | 0x00000004 | 0x00000020 | DT_NOPREFIX);
}
function drawScrollbarThumb(gr, rect, active) {
    if (!rect || rect.w <= 0 || rect.h <= 0) return;
    const fill = active ? RGBA(255,255,255,90) : RGBA(255,255,255,55);
    const radius = Math.min(4, rect.w / 2, rect.h / 2);
    if (radius >= 1) gr.FillRoundRect(rect.x, rect.y, rect.w, rect.h, radius, radius, fill);
    else gr.FillSolidRect(rect.x, rect.y, rect.w, rect.h, fill);
}
function drawSettingsScrollbars(gr) {
    const v = UI.settingsVScrollbar, h = UI.settingsHScrollbar;
    if (!v || !h) return;
    gr.FillSolidRect(v.x, v.y, v.w, v.h, RGB(15,16,20));
    gr.FillSolidRect(h.x, h.y, h.w, h.h, RGB(15,16,20));
    drawScrollbarButton(gr, v.decRect, '▲', UI.hover === v.decRect.id);
    drawScrollbarButton(gr, v.incRect, '▼', UI.hover === v.incRect.id);
    gr.FillSolidRect(v.trackRect.x, v.trackRect.y, v.trackRect.w, v.trackRect.h, RGBA(255,255,255,8));
    drawScrollbarThumb(gr, v.thumbRect,
        UI.hover === v.thumbRect.id || UI.settingsScrollDragging === 'vertical');

    drawScrollbarButton(gr, h.decRect, '◀', UI.hover === h.decRect.id);
    drawScrollbarButton(gr, h.incRect, '▶', UI.hover === h.incRect.id);
    gr.FillSolidRect(h.trackRect.x, h.trackRect.y, h.trackRect.w, h.trackRect.h, RGBA(255,255,255,8));
    drawScrollbarThumb(gr, h.thumbRect,
        UI.hover === h.thumbRect.id || UI.settingsScrollDragging === 'horizontal');
    gr.FillSolidRect(v.x, h.y, v.w, h.h, RGB(12,13,17));
}

function drawSettingsView(gr) {
    layoutSettingsUI();
    gr.FillSolidRect(0, 0, window.Width, window.Height, RGB(21, 22, 27));
    const titleFont = gdi.Font(DISPLAY_FONT_NAME, 20, 1);
    gr.SetTextRenderingHint(4);

    const baseX = UI.settingsPreviewRect ? UI.settingsPreviewRect.x : 20;
    gr.GdiDrawText('样式配置', titleFont, RGBA(255,255,255,240), baseX, 10 - UI.settingsScrollY, 130, 28, DT_NOPREFIX);

    const sbs = UI.settingsButtons;
    drawButton(gr, sbs.save, UI.hover === sbs.save.id, true);
    drawButton(gr, sbs.scale1, UI.hover === sbs.scale1.id || EXPORT_SCALE === 1, true);
    drawButton(gr, sbs.scale2, UI.hover === sbs.scale2.id || EXPORT_SCALE === 2, true);
    drawButton(gr, sbs.scale3, UI.hover === sbs.scale3.id || EXPORT_SCALE === 3, true);
    drawButton(gr, sbs.scale4, UI.hover === sbs.scale4.id || EXPORT_SCALE === 4, true);
    drawButton(gr, sbs.scaleCustom, UI.hover === sbs.scaleCustom.id || (CUSTOM_EXPORT_SCALE !== null && Math.abs(EXPORT_SCALE - CUSTOM_EXPORT_SCALE) < 0.0005), true);
    drawButton(gr, sbs.bgFusion, UI.hover === sbs.bgFusion.id || BACKGROUND_STYLE === 'fusion', true);
    drawButton(gr, sbs.bgInk, UI.hover === sbs.bgInk.id || BACKGROUND_STYLE === 'sample', true);
    drawButton(gr, sbs.bgSample, UI.hover === sbs.bgSample.id || BACKGROUND_STYLE === 'ink', true);
    drawButton(gr, sbs.bgBlur, UI.hover === sbs.bgBlur.id || BACKGROUND_STYLE === 'blur', true);
    drawButton(gr, sbs.bgSolid, UI.hover === sbs.bgSolid.id || BACKGROUND_STYLE === 'solid', true);

    drawButton(gr, sbs.reset, UI.hover === sbs.reset.id, true);
    drawButton(gr, sbs.displayFont, UI.hover === sbs.displayFont.id, true);
    drawButton(gr, sbs.listFonts, UI.hover === sbs.listFonts.id, true);
    drawButton(gr, sbs.textRenderingHint, UI.hover === sbs.textRenderingHint.id, true);
    drawButton(gr, sbs.imp, UI.hover === sbs.imp.id, true);
    drawButton(gr, sbs.exp, UI.hover === sbs.exp.id, true);
    drawButton(gr, sbs.chooseCfg, UI.hover === sbs.chooseCfg.id, true);

    drawBlurSlider(gr);
    drawCoverCornerSlider(gr);
    drawButton(gr, sbs.customEnvironmentToggle, UI.hover === sbs.customEnvironmentToggle.id || CUSTOM_ENVIRONMENT_COLORS_ENABLED, true);
    drawButton(gr, sbs.shadowOpacity, UI.hover === sbs.shadowOpacity.id, true);
    drawButton(gr, sbs.shadowDepth, UI.hover === sbs.shadowDepth.id, true);
    drawButton(gr, sbs.coverMode, UI.hover === sbs.coverMode.id, true);
    if (sbs.blurBgCropPosition) drawButton(gr, sbs.blurBgCropPosition, UI.hover === sbs.blurBgCropPosition.id, true);
    if (sbs.rainbowMode) drawButton(gr, sbs.rainbowMode, UI.hover === sbs.rainbowMode.id, true);
    if (sbs.rainbowSampleSide) drawButton(gr, sbs.rainbowSampleSide, UI.hover === sbs.rainbowSampleSide.id, true);
    if (sbs.rainbowCustomHex) drawButton(gr, sbs.rainbowCustomHex, UI.hover === sbs.rainbowCustomHex.id || RAINBOW_CUSTOM_SELECTION === 'hex', true);
    if (sbs.rainbowPalette) for (let rpi = 0; rpi < sbs.rainbowPalette.length; rpi++) {
        const rb = sbs.rainbowPalette[rpi];
        drawColorSwatchButton(gr, rb, UI.hover === rb.id, RAINBOW_CUSTOM_SELECTION === 'palette:' + String(rpi));
    }
    if (sbs.customEnvironmentPalette) for (let cei = 0; cei < sbs.customEnvironmentPalette.length; cei++) {
        const eb = sbs.customEnvironmentPalette[cei];
        drawEnvironmentColorButton(gr, eb, UI.hover === eb.id);
    }

    drawButton(gr, sbs.lyricsToggle, UI.hover === sbs.lyricsToggle.id || LYRICS_CONFIG.enabled, true);
    drawButton(gr, sbs.textOpenCC, UI.hover === sbs.textOpenCC.id || TEXT_OPENCC_MODE !== 'off', true);
    for (const key in UI.lyricsButtons) {
        const b = UI.lyricsButtons[key];
        const selected = (key === 'bold' && LYRICS_CONFIG.bold) ||
            (key === 'italic' && LYRICS_CONFIG.italic) ||
            (key === 'openCCMode' && LYRICS_OPENCC_MODE !== 'off') ||
            (key === 'dividerEnabled' && LYRICS_CONFIG.dividerEnabled);
        drawButton(gr, b, UI.hover === b.id || selected, true);
    }

    for (let i = 0; i < UI.headerCells.length; i++) {
        const h = UI.headerCells[i];
        drawGridCell(gr, h, h.text, UI.hover === h.id, false, false);
    }
    for (let i = 0; i < UI.settingsCells.length; i++) {
        const cell = UI.settingsCells[i];
        const text = getCellDisplayText(cell.rowKey, cell.colKey);
        const small = cell.colKey === 'font' || cell.colKey === 'text';
        drawGridCell(gr, cell, text, UI.hover === cell.id, false, small);
    }

    drawButton(gr, sbs.previewToggle, UI.hover === sbs.previewToggle.id || UI.settingsPreviewEnabled, true);
    drawButton(gr, sbs.settingsPopupPreview, UI.hover === sbs.settingsPopupPreview.id, true);
    drawButton(gr, sbs.settingsSeedInput, UI.hover === sbs.settingsSeedInput.id, true);
    drawButton(gr, sbs.settingsSeedCopy, UI.hover === sbs.settingsSeedCopy.id, true);
    drawButton(gr, sbs.settingsSeedRefresh, UI.hover === sbs.settingsSeedRefresh.id, true);
    drawButton(gr, sbs.settingsCopyImage, UI.hover === sbs.settingsCopyImage.id, true);
    drawButton(gr, sbs.settingsResolution, UI.hover === sbs.settingsResolution.id, true);
    drawSettingsPreviewPanel(gr);
    drawSettingsScrollbars(gr);
}
function on_paint(gr) {
    if (UI.view === 'sleep') drawSleepView(gr);
    else if (UI.view === 'main') drawMainView(gr);
    else if (UI.view === 'preview') drawPreviewView(gr);
    else if (UI.view === 'settings') drawSettingsView(gr);
}

function actionSleep() {
    UI.view = 'sleep';
    UI.hover = '';
    UI.copyBusy = false;
    UI.pendingCopySeed = '';
    UI.previewCopyImageBusy = false;
    UI.settingsCopyImageBusy = false;
    UI.settingsPreviewRefreshPending = false;
    UI.sliderDragging = '';
    UI.settingsScrollDragging = '';
    UI.settingsScrollDragOffset = 0;
    disposeImageSafe(UI.previewImage);
    UI.previewImage = null;
    UI.previewInfo = null;
    UI.previewRenderMs = null;
    UI.previewRect = null;
    disposeImageSafe(UI.settingsPreviewImage);
    UI.settingsPreviewImage = null;
    UI.settingsPreviewRenderMs = null;
    UI.settingsPreviewDirty = true;
    window.Repaint();
}
function actionRestoreFromSleep() {
    UI.view = 'main';
    UI.hover = '';
    UI.sleepButton = null;
    window.Repaint();
}
function actionPreview() {
    let seed = '';
    UI.previewReturnView = 'main';
    UI.popupPreviewSeed = '';
    if (BACKGROUND_STYLE === 'fusion') {
        // 主页预览只复用主页自己的种子；只有主页没有种子时才随机生成。
        seed = UI.previewSeed || generateRandomSeed8();
    }
    const built = buildCard(pickHandle(), seed);
    disposeImageSafe(UI.previewImage);
    UI.previewImage = built.image;
    UI.previewInfo = built.info;
    UI.previewRenderMs = built.renderMs;
    UI.previewSeed = built.seed || '';
    UI.view = 'preview';
    window.Repaint();
}
function rebuildMainPreview(seed) {
    const built = buildCard(pickHandle(), seed || '');
    disposeImageSafe(UI.previewImage);
    UI.previewImage = built.image;
    UI.previewInfo = built.info;
    UI.previewRenderMs = built.renderMs;
    setActivePreviewSeed(built.seed || '');
    window.Repaint();
}
function actionInputPreviewSeed() {
    if (BACKGROUND_STYLE !== 'fusion') {
        fb.ShowPopupMessage('当前背景模式不使用随机种子。', MUSICCARD_TITLE);
        return;
    }
    const v = requestInput('请输入融合背景随机种子（任意字符均可）。留空则随机生成。', '输入种子', getActivePreviewSeed() || '');
    if (inputWasCancelled(v)) return;
    rebuildMainPreview(nonEmpty(v) ? String(v) : generateRandomSeed8());
}
function actionRefreshPreviewSeed() {
    rebuildMainPreview(BACKGROUND_STYLE === 'fusion' ? generateRandomSeed8() : '');
}
function actionCopyCurrentPreviewImage() {
    if (!UI.previewImage || UI.previewCopyImageBusy) return;
    UI.previewCopyImageBusy = true;
    window.Repaint();
    deferUiAction(function () {
        try {
            if (UI.view === 'sleep') return;
            if (UI.previewImage) copyImageViaPowerShell(UI.previewImage, false);
        } finally {
            UI.previewCopyImageBusy = false;
            window.Repaint();
        }
    });
}
function actionPopupPreviewFromSettings() {
    let seed = '';
    if (BACKGROUND_STYLE === 'fusion') {
        seed = UI.settingsPreviewSeed || generateRandomSeed8();
        UI.settingsPreviewSeed = seed;
    }
    UI.previewReturnView = 'settings';
    const built = buildCard(pickHandle(), seed);
    disposeImageSafe(UI.previewImage);
    UI.previewImage = built.image;
    UI.previewInfo = built.info;
    UI.previewRenderMs = built.renderMs;
    UI.popupPreviewSeed = built.seed || seed || '';
    UI.view = 'preview';
    window.Repaint();
}
function actionInputSettingsSeed() {
    if (BACKGROUND_STYLE !== 'fusion') {
        fb.ShowPopupMessage('当前背景模式不使用随机种子。', MUSICCARD_TITLE);
        return;
    }
    const v = requestInput('请输入融合背景随机种子（任意字符均可）。留空则随机生成。', '输入种子', UI.settingsPreviewSeed || '');
    if (inputWasCancelled(v)) return;
    UI.settingsPreviewSeed = nonEmpty(v) ? String(v) : generateRandomSeed8();
    UI.settingsPreviewDirty = true;
    if (UI.settingsPreviewEnabled) refreshSettingsPreviewNow();
    else window.Repaint();
}
function actionCopySettingsSeed() {
    if (BACKGROUND_STYLE !== 'fusion') return;
    if (!UI.settingsPreviewSeed) {
        UI.settingsPreviewSeed = generateRandomSeed8();
    }
    copyTextToClipboard(UI.settingsPreviewSeed, true);
    window.Repaint();
}
function actionRefreshSettingsSeed() {
    if (BACKGROUND_STYLE === 'fusion') UI.settingsPreviewSeed = generateRandomSeed8();
    else UI.settingsPreviewSeed = '';
    UI.settingsPreviewDirty = true;
    if (UI.settingsPreviewEnabled) refreshSettingsPreviewNow();
    else window.Repaint();
}
function actionCopySettingsPreviewImage() {
    if (UI.settingsCopyImageBusy) return;
    UI.settingsCopyImageBusy = true;
    window.Repaint();
    deferUiAction(function () {
        try {
            if (UI.view === 'sleep') return;
            if (UI.settingsPreviewImage && !UI.settingsPreviewDirty) {
                copyImageViaPowerShell(UI.settingsPreviewImage, false);
            } else {
                const seed = BACKGROUND_STYLE === 'fusion' ? ensureFusionSeed(UI.settingsPreviewSeed) : '';
                const built = buildCard(pickHandle(), seed, EXPORT_SCALE);
                if (BACKGROUND_STYLE === 'fusion') UI.settingsPreviewSeed = built.seed || seed;
                copyImageViaPowerShell(built.image, false);
                if (UI.settingsPreviewEnabled) {
                    disposeImageSafe(UI.settingsPreviewImage);
                    UI.settingsPreviewImage = built.image;
                    UI.settingsPreviewRenderMs = built.renderMs;
                    UI.settingsPreviewDirty = false;
                } else {
                    disposeImageSafe(built.image);
                }
            }
        } catch (e) {
            fb.ShowPopupMessage('复制配置预览图片失败。\n\n' + e, MUSICCARD_TITLE);
        } finally {
            UI.settingsCopyImageBusy = false;
            window.Repaint();
        }
    });
}

function finishCopyGeneration() {
    if (UI.view === 'sleep') {
        UI.pendingCopySeed = '';
        UI.copyBusy = false;
        window.Repaint();
        return;
    }
    try {
        const built = buildCard(pickHandle(), UI.pendingCopySeed || '');
        copyImageViaPowerShell(built.image, true);
        if (built.seed) UI.previewSeed = built.seed;
    } finally {
        UI.pendingCopySeed = '';
        UI.copyBusy = false;
        window.Repaint();
    }
}
function actionCopy() {
    if (UI.copyBusy) return;
    let seed = '';
    if (BACKGROUND_STYLE === 'fusion') {
        const defSeed = UI.previewSeed || '';
        const v = requestInput('请输入融合背景随机种子（任意字符均可）。留空则随机生成。', '输入种子', defSeed);
        if (inputWasCancelled(v)) return;
        seed = nonEmpty(v) ? String(v) : generateRandomSeed8();
    }
    UI.pendingCopySeed = seed;
    UI.copyBusy = true;
    window.Repaint();

    deferUiAction(finishCopyGeneration);
}
function actionAbout() {
    fb.ShowPopupMessage(
        MUSICCARD_TITLE + '\n' +
        'by IQ Online Studio, github.com/iqonli\n' +
        '使用GNU Lesser General Public License v3或任何后续版本。\n' +
        '项目地址：' + MUSICCARD_PROJECT_URL + '\n\n' +
        '第三方组件：opencc-js v' + MUSICCARD_OPENCC_JS_VERSION + '（MIT许可证）\n' +
        '项目地址：' + MUSICCARD_OPENCC_PROJECT_URL + '\n' +
        '内置词典：opencc-data v1.4.1（Apache License 2.0许可证）\n' +
        '项目地址：' + MUSICCARD_OPENCC_DATA_PROJECT_URL + '\n\n' +
        '作者：PerryDing (QQ: 34067513)\n' +
        '出品：IQ Online Studio',
        'MusicCard'
    );
}
function actionSaveImage() { const built = buildCard(pickHandle()); const path = saveImage(built.image, built.info); if (path) fb.ShowPopupMessage('已保存：\n' + path, MUSICCARD_TITLE); }
function actionOpenSettings() { UI.view = 'settings'; if (BACKGROUND_STYLE === 'fusion' && !UI.settingsPreviewSeed) UI.settingsPreviewSeed = generateRandomSeed8(); if (UI.settingsPreviewEnabled) { UI.settingsPreviewDirty = true; scheduleSettingsPreviewRefresh(); } window.Repaint(); }
function actionSaveAndReturn() { persistSettings(); UI.view = 'main'; window.Repaint(); }
function actionSetScale(n) {
    EXPORT_SCALE = round3(n);
    CUSTOM_EXPORT_SCALE = null;
    persistSettings();
    window.Repaint();
}
function actionSetCustomScale() {
    const value = requestInput(
        floatPrompt('请输入自定义导出倍率', 0.1, 10, '例如 8.567。'),
        '自定义导出倍率',
        formatNumber(CUSTOM_EXPORT_SCALE !== null ? CUSTOM_EXPORT_SCALE : EXPORT_SCALE)
    );
    if (inputWasCancelled(value)) return;
    const n = parseFloatInput(value, 0.1, 10);
    if (n === null) {
        fb.ShowPopupMessage('请输入 0.1-10 之间、最多三位小数的数值。\n' + FLOAT_INPUT_NOTE, MUSICCARD_TITLE);
        return;
    }
    CUSTOM_EXPORT_SCALE = n;
    EXPORT_SCALE = n;
    persistSettings();
    window.Repaint();
}
function actionSetBackgroundStyle(v) {
    if (v === 'solid') {
        const val = requestInput('请输入纯色背景颜色。\n' + colorSpecInputNote(false), '纯色背景', SOLID_BG_HEX || '#202020');
        if (inputWasCancelled(val)) return;
        const hx = normalizeColorSpec(val);
        if (!hx) {
            fb.ShowPopupMessage(colorSpecErrorText(false), MUSICCARD_TITLE);
            return;
        }
        SOLID_BG_HEX = hx;
    }
    BACKGROUND_STYLE = v;
    if (v === 'fusion' && !UI.settingsPreviewSeed) UI.settingsPreviewSeed = generateRandomSeed8();
    persistSettings();
    window.Repaint();
}
function actionSetShadowOpacity() {
    const val = requestInput(
        floatPrompt('请输入封面阴影不透明度', 0, 255, '输入 0 隐藏阴影。'),
        '封面阴影不透明度',
        formatNumber(COVER_SHADOW_OPACITY)
    );
    if (inputWasCancelled(val)) return;
    const n = parseFloatInput(val, 0, 255);
    if (n === null) {
        fb.ShowPopupMessage('请输入 0-255 之间、最多三位小数的数值。\n' + FLOAT_INPUT_NOTE, MUSICCARD_TITLE);
        return;
    }
    COVER_SHADOW_OPACITY = n;
    persistSettings();
    window.Repaint();
}
function actionSetShadowDepth() {
    const val = requestInput(
        floatPrompt('请输入封面阴影深度', 0, 100, '该数值按 1x 原始尺寸计算，导出时随倍率放大。'),
        '封面阴影深度',
        formatNumber(COVER_SHADOW_DEPTH)
    );
    if (inputWasCancelled(val)) return;
    const n = parseFloatInput(val, 0, 100);
    if (n === null) {
        fb.ShowPopupMessage('请输入 0-100 之间、最多三位小数的数值。\n' + FLOAT_INPUT_NOTE, MUSICCARD_TITLE);
        return;
    }
    COVER_SHADOW_DEPTH = n;
    persistSettings();
    window.Repaint();
}
function actionToggleIrregularCoverMode() {
    IRREGULAR_COVER_MODE = IRREGULAR_COVER_MODE === 'tile' ? 'crop' : 'tile';
    persistSettings();
    window.Repaint();
}
function actionSetBlurBackgroundCropPosition() {
    const val = requestInput(
        floatPrompt(
            '请输入背景截取封面位置（百分比）', 0, 100,
            '上下裁剪：0%=顶部，50%=中间，100%=底部。\n左右裁剪：0%=左侧，50%=中间，100%=右侧。'
        ),
        '背景截取封面位置',
        formatNumber(BLUR_BG_CROP_POSITION)
    );
    if (inputWasCancelled(val)) return;
    const n = parseFloatInput(val, 0, 100);
    if (n === null) {
        fb.ShowPopupMessage('请输入 0-100 之间、最多三位小数的数值。\n' + FLOAT_INPUT_NOTE, MUSICCARD_TITLE);
        return;
    }
    BLUR_BG_CROP_POSITION = n;
    persistSettings();
    window.Repaint();
}


function actionToggleCustomEnvironmentColors() {
    if (CUSTOM_ENVIRONMENT_COLORS_ENABLED) {
        CUSTOM_ENVIRONMENT_COLORS_ENABLED = false;
        CUSTOM_ENVIRONMENT_COLOR_HEXES = [];
    } else {
        const fresh = captureCurrentEnvironmentColorHexes();
        if (fresh.length !== CUSTOM_ENVIRONMENT_COLOR_COUNT) {
            fb.ShowPopupMessage('无法从当前封面获取 5 个环境颜色。', MUSICCARD_TITLE);
            return;
        }
        CUSTOM_ENVIRONMENT_COLOR_HEXES = fresh;
        CUSTOM_ENVIRONMENT_COLORS_ENABLED = true;
    }
    clearRainbowColorCache();
    clearStylePaletteCache();
    persistSettings();
    window.Repaint();
}
function actionSetCustomEnvironmentColor(index) {
    if (!CUSTOM_ENVIRONMENT_COLORS_ENABLED) return;
    const n = clamp(parseInt(index, 10) || 0, 0, CUSTOM_ENVIRONMENT_COLOR_COUNT - 1);
    const current = CUSTOM_ENVIRONMENT_COLOR_HEXES[n] || '#000000';
    const val = requestInput(
        '请输入普通六位 HEX 颜色。允许省略 #。\n不允许留空，也不允许 black、white 或 rainbow/r% 表达式。',
        '自定义环境颜色 ' + String(n + 1),
        current
    );
    if (inputWasCancelled(val)) return;
    const normalized = normalizeEnvironmentColorHex(val);
    if (!normalized) {
        fb.ShowPopupMessage('颜色格式无效。请输入普通六位 HEX；不允许空值、black、white 或 rainbow/r%。', MUSICCARD_TITLE);
        return;
    }
    CUSTOM_ENVIRONMENT_COLOR_HEXES[n] = normalized;
    clearRainbowColorCache();
    clearStylePaletteCache();
    persistSettings();
    window.Repaint();
}

function actionToggleRainbowMode() {
    RAINBOW_MODE = RAINBOW_MODE === 'sample' ? 'custom' : 'sample';
    persistSettings();
    markSettingsPreviewDirty();
    window.Repaint();
}
function actionSetRainbowCustomHex() {
    const val = requestInput(
        '请输入自定义彩虹色。\n' + customRainbowHexInputNote(),
        '自定义彩虹色 HEX',
        RAINBOW_CUSTOM_HEX
    );
    if (inputWasCancelled(val)) return;
    const normalized = normalizeCustomRainbowHex(val);
    if (normalized === null) {
        fb.ShowPopupMessage('颜色格式无效。\n' + customRainbowHexInputNote(), MUSICCARD_TITLE);
        return;
    }
    RAINBOW_CUSTOM_HEX = normalized;
    RAINBOW_CUSTOM_SELECTION = 'hex';
    persistSettings();
    markSettingsPreviewDirty();
    window.Repaint();
}
function actionSelectRainbowPaletteColor(index) {
    const n = clamp(parseInt(index, 10) || 0, 0, RAINBOW_STYLE_COLOR_COUNT - 1);
    RAINBOW_CUSTOM_SELECTION = 'palette:' + String(n);
    persistSettings();
    markSettingsPreviewDirty();
    window.Repaint();
}

function actionSetRainbowSampleMaxSide() {
    const val = requestInput(
        '请输入取色封面边长（整数，1-1000）。\n值越大，平均色相越接近原图，但计算越慢。\n修改后会清空彩虹色缓存，下次生成含彩虹色卡片时重新计算。',
        '取色封面边长',
        String(RAINBOW_SAMPLE_MAX_SIDE)
    );
    if (inputWasCancelled(val)) return;
    const raw = String(val).trim();
    if (!/^\d+$/.test(raw)) {
        fb.ShowPopupMessage('请输入 1-1000 之间的整数。', MUSICCARD_TITLE);
        return;
    }
    const n = parseInt(raw, 10);
    if (!isFinite(n) || n < 1 || n > 1000) {
        fb.ShowPopupMessage('请输入 1-1000 之间的整数。', MUSICCARD_TITLE);
        return;
    }
    RAINBOW_SAMPLE_MAX_SIDE = n;
    clearRainbowColorCache();
    persistSettings();
    markSettingsPreviewDirty();
    window.Repaint();
}

function actionSetTextRenderingHint() {
    const help =
        '请输入 SetTextRenderingHint() 设置值（0-5）：\n\n' +
        '0  SystemDefault\n    跟随系统设置\n' +
        '1  SingleBitPerPixelGridFit\n    纯单色像素，有字体微调\n' +
        '2  SingleBitPerPixel\n    纯单色像素，无字体微调\n' +
        '3  AntiAliasGridFit\n    灰度抗锯齿，有字体微调\n' +
        '4  AntiAlias\n    灰度抗锯齿，无字体微调\n' +
        '5  ClearTypeGridFit\n    RGB 子像素 ClearType\n\n' +
        '建议：\n' +
        '• 导出 PNG 推荐 3：平滑、无彩色 ClearType 边缘。\n' +
        '• 追求绝对纯色像素可选 1，但曲线和中文可能有锯齿。\n' +
        '• 不建议导出图片使用 5，可能出现红蓝彩边。';
    const val = requestInput(help, 'SetTextRenderingHint()', String(TEXT_RENDERING_HINT));
    if (inputWasCancelled(val)) return;
    const raw = String(val).trim();
    if (!/^[0-5]$/.test(raw)) {
        fb.ShowPopupMessage('请输入 0-5 之间的整数。', MUSICCARD_TITLE);
        return;
    }
    TEXT_RENDERING_HINT = parseInt(raw, 10);
    persistSettings();
    window.Repaint();
}

function actionCycleTextOpenCCMode() {
    TEXT_OPENCC_MODE = nextOpenCCMode(TEXT_OPENCC_MODE);
    try { console.log('[MusicCard][OpenCC]卡片文字模式=' + TEXT_OPENCC_MODE); } catch (e) {}
    persistSettings();
    if (TEXT_OPENCC_MODE !== 'off') verifyOpenCCForActiveMode(TEXT_OPENCC_MODE);
    window.Repaint();
}
function actionCycleLyricsOpenCCMode() {
    LYRICS_OPENCC_MODE = nextOpenCCMode(LYRICS_OPENCC_MODE);
    try { console.log('[MusicCard][OpenCC]歌词模式=' + LYRICS_OPENCC_MODE); } catch (e) {}
    persistSettings();
    if (LYRICS_OPENCC_MODE !== 'off') verifyOpenCCForActiveMode(LYRICS_OPENCC_MODE);
    window.Repaint();
}

function actionResetDefaults() {
    STYLE_CONFIG = clone(DEFAULT_STYLE);
    EXPORT_SCALE = DEFAULT_EXPORT_SCALE;
    CUSTOM_EXPORT_SCALE = null;
    BACKGROUND_STYLE = DEFAULT_BACKGROUND_STYLE;
    BLUR_STRENGTH = DEFAULT_BLUR_STRENGTH;
    SOLID_BG_HEX = DEFAULT_SOLID_BG_HEX;
    COVER_SHADOW_OPACITY = DEFAULT_COVER_SHADOW_OPACITY;
    COVER_SHADOW_DEPTH = DEFAULT_COVER_SHADOW_DEPTH;
    TEXT_RENDERING_HINT = DEFAULT_TEXT_RENDERING_HINT;
    COVER_CORNER_RADIUS = DEFAULT_COVER_CORNER_RADIUS;
    IRREGULAR_COVER_MODE = DEFAULT_IRREGULAR_COVER_MODE;
    BLUR_BG_CROP_POSITION = DEFAULT_BLUR_BG_CROP_POSITION;
    RAINBOW_SAMPLE_MAX_SIDE = DEFAULT_RAINBOW_SAMPLE_MAX_SIDE;
    RAINBOW_MODE = DEFAULT_RAINBOW_MODE;
    RAINBOW_CUSTOM_HEX = DEFAULT_RAINBOW_CUSTOM_HEX;
    RAINBOW_CUSTOM_SELECTION = DEFAULT_RAINBOW_CUSTOM_SELECTION;
    CUSTOM_ENVIRONMENT_COLORS_ENABLED = DEFAULT_CUSTOM_ENVIRONMENT_COLORS_ENABLED;
    CUSTOM_ENVIRONMENT_COLOR_HEXES = [];
    TEXT_OPENCC_MODE = DEFAULT_TEXT_OPENCC_MODE;
    LYRICS_OPENCC_MODE = DEFAULT_LYRICS_OPENCC_MODE;
    DISPLAY_FONT_NAME = DEFAULT_DISPLAY_FONT_NAME;
    OPENCC_DIAGNOSTIC_SHOWN = false;
    LAST_CARD_RENDER_MS = null;
    clearRainbowColorCache();
    clearStylePaletteCache();
    LYRICS_CONFIG = clone(DEFAULT_LYRICS_CONFIG);
    persistSettings();
    window.Repaint();
    fb.ShowPopupMessage('已恢复默认配置。', MUSICCARD_TITLE);
}
function actionEditScript() {
    try { if (window && typeof window.EditScript === 'function') { window.EditScript(); return; } } catch (e) {}
    fb.ShowPopupMessage('当前 SMP 环境不支持直接打开脚本编辑器。\n请手动右键面板 → Configure... 编辑。', MUSICCARD_TITLE);
}
function actionReloadScript() {
    try { if (window && typeof window.Reload === 'function') { window.Reload(); return; } if (window && typeof window.ReloadScript === 'function') { window.ReloadScript(); return; } } catch (e) {}
    fb.ShowPopupMessage('当前 SMP 环境不支持脚本重载 API。\n请手动重新打开 Configure 后 Apply。', MUSICCARD_TITLE);
}
function setCustomCoverPath() {
    try {
        const val = requestInput('请输入本地图片完整路径（png/jpg/webp 等）', '设置自定义封面路径', CONFIG.customCoverPath || '');
        if (inputWasCancelled(val)) return;
        const path = String(val).trim();
        if (!path) return;
        if (!fileExists(path)) { fb.ShowPopupMessage('文件不存在：\n' + path, MUSICCARD_TITLE); return; }
        const img = gdi.Image(path);
        if (!img) throw new Error('无法载入图片');
        CONFIG.customCoverPath = path;
        clearRainbowColorCache();
        clearStylePaletteCache();
        persistSettings();
        fb.ShowPopupMessage('已设置自定义封面。', MUSICCARD_TITLE);
    } catch (e) { fb.ShowPopupMessage('设置自定义封面失败。\n' + e, MUSICCARD_TITLE); }
}
function clearCustomCover() { CONFIG.customCoverPath = ''; clearRainbowColorCache(); clearStylePaletteCache(); persistSettings(); fb.ShowPopupMessage('已清除自定义封面，恢复优先使用内嵌封面。', MUSICCARD_TITLE); }
function setOutputDir() {
    try {
        const val = requestInput('请输入输出目录完整路径，例如 D:\\MusicCards\\', '设置输出目录', CONFIG.outputDir || '');
        if (inputWasCancelled(val)) return;
        let path = String(val).trim();
        if (!path) return;
        if (!/[\\/]$/.test(path)) path += '\\';
        CONFIG.outputDir = path;
        persistSettings();
        fb.ShowPopupMessage('输出目录已更新：\n' + CONFIG.outputDir, MUSICCARD_TITLE);
    } catch (e) { fb.ShowPopupMessage('设置输出目录失败。\n' + e, MUSICCARD_TITLE); }
}

function getTextContentPrompt(rowKey, label) {
    const defaultExpression = DEFAULT_STYLE[rowKey] && DEFAULT_STYLE[rowKey].text !== undefined
        ? String(DEFAULT_STYLE[rowKey].text)
        : '';
    let detail =
        label + ' - foobar2000 标题格式化表达式\n\n' +
        '八个文本项目均支持标准字段、纯文本、[可选段]、$if()、$if2()、$num()、$len() 等语法。\n' +
        'MusicCard 扩展字段：%datey% = %date% 的年份部分。\n';
    if (rowKey === 'metaValue') {
        detail += '默认 Track 规则：有 %totaltracks% 时补到总曲数位数；没有时补到 2 位。\n';
    }
    detail += '\n默认表达式：\n' + (defaultExpression || '（空）');
    return detail;
}
function editStyleElement(key, label) {
    try {
        const draft = clone(STYLE_CONFIG[key]);
        let v, n;
        v = requestInput(floatPrompt(label + ' - 字号', 0.001, 1000), '编辑 ' + label, formatNumber(draft.size));
        if (inputWasCancelled(v)) return;
        n = parseFloatInput(v, 0.001, 1000);
        if (n === null) return fb.ShowPopupMessage('字号无效。\n' + FLOAT_INPUT_NOTE, MUSICCARD_TITLE);
        draft.size = n;

        v = requestInput(label + ' - 字体名', '编辑 ' + label, draft.font || DEFAULT_FONT_NAME);
        if (inputWasCancelled(v)) return;
        draft.font = String(v).trim() || DEFAULT_FONT_NAME;

        v = requestInput(label + ' - 粗体？ 1=是 0=否', '编辑 ' + label, draft.bold ? '1' : '0');
        if (inputWasCancelled(v)) return;
        draft.bold = String(v).trim() === '1';

        v = requestInput(label + ' - 斜体？ 1=是 0=否', '编辑 ' + label, draft.italic ? '1' : '0');
        if (inputWasCancelled(v)) return;
        draft.italic = String(v).trim() === '1';

        v = requestInput(label + ' - 颜色\n' + colorSpecInputNote(true), '编辑 ' + label, draft.colorHex || '');
        if (inputWasCancelled(v)) return;
        const hx = normalizeColorSpec(v);
        if (String(v).trim() === '') draft.colorHex = '';
        else if (hx) draft.colorHex = hx;
        else return fb.ShowPopupMessage(colorSpecErrorText(true), MUSICCARD_TITLE);

        v = requestInput(floatPrompt(label + ' - 不透明度', 0, 255), '编辑 ' + label, formatNumber(draft.opacity));
        if (inputWasCancelled(v)) return;
        n = parseFloatInput(v, 0, 255);
        if (n === null) return fb.ShowPopupMessage('不透明度无效。\n' + FLOAT_INPUT_NOTE, MUSICCARD_TITLE);
        draft.opacity = n;

        v = requestInput(label + ' - 模糊强度 0-' + MAX_TEXT_BLUR_STRENGTH + '（整数）', '编辑 ' + label, String(draft.blurStrength || 0));
        if (inputWasCancelled(v)) return;
        draft.blurStrength = clamp(parseInt(v, 10) || 0, 0, MAX_TEXT_BLUR_STRENGTH);

        v = requestInput(floatPrompt(label + ' - 模糊不透明度', 0, 255), '编辑 ' + label, formatNumber(draft.blurOpacity || 0));
        if (inputWasCancelled(v)) return;
        n = parseFloatInput(v, 0, 255);
        if (n === null) return fb.ShowPopupMessage('模糊不透明度无效。\n' + FLOAT_INPUT_NOTE, MUSICCARD_TITLE);
        draft.blurOpacity = n;

        v = requestInput(floatPrompt(label + ' - 字间距（px）', MIN_LETTER_SPACING, MAX_LETTER_SPACING,
            '留空使用原生普通文字绘制；输入数值（包括 0 和 -1）使用逐字绘制。'),
            '编辑 ' + label, formatLetterSpacing(draft.letterSpacing));
        if (inputWasCancelled(v)) return;
        n = parseLetterSpacingInput(v);
        if (n === null) return fb.ShowPopupMessage('字间距无效。\n' + FLOAT_INPUT_NOTE, MUSICCARD_TITLE);
        draft.letterSpacing = n;

        if (rowSupportsText(key)) {
            v = requestInput(getTextContentPrompt(key, label), '编辑 ' + label, draft.text !== undefined ? String(draft.text) : '');
            if (inputWasCancelled(v)) return;
            draft.text = String(v);
        }
        STYLE_CONFIG[key] = draft;
        persistSettings();
        window.Repaint();
    } catch (e) {
        fb.ShowPopupMessage('编辑样式失败。\n' + e, MUSICCARD_TITLE);
    }
}
function promptColumnValue(title, defaultValue) {
    return requestInput(title, '整列修改', defaultValue);
}
function toggleWholeBoolColumn(colKey) {
    let allTrue = true;
    for (let i = 0; i < STYLE_KEYS.length; i++) {
        if (!STYLE_CONFIG[STYLE_KEYS[i][0]][colKey]) { allTrue = false; break; }
    }
    const newVal = !allTrue;
    for (let i = 0; i < STYLE_KEYS.length; i++) STYLE_CONFIG[STYLE_KEYS[i][0]][colKey] = newVal;
    persistSettings();
    window.Repaint();
}
function applyColumnEdit(colKey) {
    try {
        if (colKey === 'rowLabel') {
            fb.ShowPopupMessage('这一列是元素名称列。点击左侧每一行可按整行编辑。\n点击其他列表头可以按整列修改。', MUSICCARD_TITLE);
            return;
        }
        if (colKey === 'bold' || colKey === 'italic') return toggleWholeBoolColumn(colKey);
        let v, i, obj, n;
        if (colKey === 'size') {
            v = promptColumnValue(floatPrompt('请输入整列字号', 0.001, 1000), formatNumber(STYLE_CONFIG.titleLabel.size));
            if (inputWasCancelled(v)) return;
            n = parseFloatInput(v, 0.001, 1000); if (n === null) return;
            for (i = 0; i < STYLE_KEYS.length; i++) STYLE_CONFIG[STYLE_KEYS[i][0]].size = n;
        } else if (colKey === 'font') {
            v = promptColumnValue('请输入整列字体名', STYLE_CONFIG.titleLabel.font || DEFAULT_FONT_NAME);
            if (inputWasCancelled(v)) return;
            v = String(v).trim() || DEFAULT_FONT_NAME;
            for (i = 0; i < STYLE_KEYS.length; i++) STYLE_CONFIG[STYLE_KEYS[i][0]].font = v;
        } else if (colKey === 'colorHex') {
            v = promptColumnValue('请输入整列颜色。\n' + colorSpecInputNote(true), STYLE_CONFIG.titleLabel.colorHex || '');
            if (inputWasCancelled(v)) return;
            if (String(v).trim() !== '') {
                const hx = normalizeColorSpec(v);
                if (!hx) return fb.ShowPopupMessage(colorSpecErrorText(true), MUSICCARD_TITLE);
                v = hx;
            } else v = '';
            for (i = 0; i < STYLE_KEYS.length; i++) STYLE_CONFIG[STYLE_KEYS[i][0]].colorHex = v;
        } else if (colKey === 'opacity' || colKey === 'blurOpacity') {
            const title = colKey === 'opacity' ? '请输入整列不透明度' : '请输入整列模糊不透明度';
            v = promptColumnValue(floatPrompt(title, 0, 255), formatNumber(STYLE_CONFIG.titleLabel[colKey] || 0));
            if (inputWasCancelled(v)) return;
            n = parseFloatInput(v, 0, 255); if (n === null) return;
            for (i = 0; i < STYLE_KEYS.length; i++) STYLE_CONFIG[STYLE_KEYS[i][0]][colKey] = n;
        } else if (colKey === 'blurStrength') {
            v = promptColumnValue('请输入整列模糊强度 0-' + MAX_TEXT_BLUR_STRENGTH + '（整数）', String(STYLE_CONFIG.titleLabel.blurStrength || 0));
            if (inputWasCancelled(v)) return;
            n = clamp(parseInt(v, 10) || 0, 0, MAX_TEXT_BLUR_STRENGTH);
            for (i = 0; i < STYLE_KEYS.length; i++) STYLE_CONFIG[STYLE_KEYS[i][0]].blurStrength = n;
        } else if (colKey === 'letterSpacing') {
            v = promptColumnValue(floatPrompt('请输入整列字间距（px）', MIN_LETTER_SPACING, MAX_LETTER_SPACING,
                '留空使用原生普通文字绘制；输入数值（包括 0 和 -1）使用逐字绘制。'),
                formatLetterSpacing(STYLE_CONFIG.titleLabel.letterSpacing));
            if (inputWasCancelled(v)) return;
            n = parseLetterSpacingInput(v); if (n === null) return;
            for (i = 0; i < STYLE_KEYS.length; i++) STYLE_CONFIG[STYLE_KEYS[i][0]].letterSpacing = n;
        } else if (colKey === 'text') {
            v = promptColumnValue('请输入整列标题格式化表达式（会应用到全部 8 个文本项目）', STYLE_CONFIG.titleLabel.text || '');
            if (inputWasCancelled(v)) return;
            const vv = String(v);
            for (i = 0; i < STYLE_KEYS.length; i++) { obj = STYLE_CONFIG[STYLE_KEYS[i][0]]; obj.text = vv; }
        }
        persistSettings();
        window.Repaint();
    } catch (e) {
        fb.ShowPopupMessage('整列修改失败。\n' + e, MUSICCARD_TITLE);
    }
}
function applyDisplayFont() {
    try {
        const v = requestInput(
            '请输入MusicCard面板显示字体名。\n仅修改前端界面字体，不修改导出图片中的卡片文字或歌词字体。\n可使用右侧“列出所有字体”复制插件可识别的准确名称。',
            '修改显示字体',
            DISPLAY_FONT_NAME
        );
        if (inputWasCancelled(v)) return;
        const requested = String(v).trim();
        if (!requested) {
            fb.ShowPopupMessage('显示字体名不能为空。', MUSICCARD_TITLE);
            return;
        }
        const recognized = tryGetFontName(requested);
        if (!recognized) {
            fb.ShowPopupMessage(
                'MusicCard无法识别字体：' + requested + '\n\n' +
                '请点击“列出所有字体”，从已经过插件识别校验的字体族名中复制。',
                MUSICCARD_TITLE
            );
            return;
        }
        DISPLAY_FONT_NAME = recognized;
        persistSettings();
        window.Repaint();
    } catch (e) {
        fb.ShowPopupMessage('修改显示字体失败。\n' + e, MUSICCARD_TITLE);
    }
}

function deleteFileQuietly(path) {
    try {
        const fso = new ActiveXObject('Scripting.FileSystemObject');
        if (fso.FileExists(path)) fso.DeleteFile(path, true);
    } catch (e) {}
}

function enumerateRecognizedSystemFonts() {
    const tempPath = musicCardJoinPath(fb.ProfilePath, '__music_card_fonts_v4167.txt');
    deleteFileQuietly(tempPath);
    try {
        const shell = new ActiveXObject('WScript.Shell');
        const escaped = tempPath.replace(/'/g, "''");
        const cmd = 'powershell -NoProfile -ExecutionPolicy Bypass -Command "' +
            'Add-Type -AssemblyName System.Drawing; ' +
            '$collection=New-Object System.Drawing.Text.InstalledFontCollection; ' +
            '$names=@($collection.Families | ForEach-Object {$_.Name} | Sort-Object -Unique); ' +
            '[System.IO.File]::WriteAllLines(\'' + escaped + '\',$names,[System.Text.Encoding]::Unicode); ' +
            '$collection.Dispose();"';
        const exitCode = shell.Run(cmd, 0, true);
        if (exitCode !== 0 || !fileExists(tempPath)) throw new Error('PowerShell字体枚举失败，退出码：' + exitCode);
        const rawNames = readTextFile(tempPath).replace(/^\uFEFF/, '').split(/\r?\n/);
        const result = [];
        const seen = {};
        for (let i = 0; i < rawNames.length; i++) {
            const candidate = String(rawNames[i] || '').trim();
            if (!candidate || candidate.charAt(0) === '@') continue;
            const recognized = tryGetFontName(candidate);
            if (!recognized) continue;
            const key = String(recognized).toLowerCase();
            if (seen[key]) continue;
            seen[key] = true;
            result.push(String(recognized));
        }
        if (tryGetFontName(DISPLAY_FONT_NAME)) {
            const displayKey = String(DISPLAY_FONT_NAME).toLowerCase();
            if (!seen[displayKey]) result.push(DISPLAY_FONT_NAME);
        }
        result.sort(function (a, b) { return String(a).localeCompare(String(b)); });
        return result;
    } finally {
        deleteFileQuietly(tempPath);
    }
}

function showRecognizedFontListDialog(fontNames) {
    if (!utils || typeof utils.ShowHtmlDialog !== 'function') {
        showMultilineEditor(
            'MusicCard可识别字体',
            '以下名称均已通过MusicCard字体识别校验。可复制准确名称后关闭窗口。',
            fontNames.join('\n'),
            function () {}
        );
        return;
    }
    const html = [
        '<!DOCTYPE html><html><head><meta http-equiv="x-ua-compatible" content="IE=9" />',
        '<meta charset="utf-8"><style>',
        'html,body{margin:0;padding:0;background:#17181d;color:#f3f3f3;font:13px Microsoft YaHei,微软雅黑,sans-serif;overflow:hidden}',
        '.title{position:absolute;left:14px;right:14px;top:10px;height:28px;font-size:16px;font-weight:600}',
        '.hint{position:absolute;left:14px;right:14px;top:39px;height:42px;color:#aaa;line-height:19px}',
        '#search{position:absolute;left:14px;right:14px;top:84px;width:calc(100% - 28px);height:30px;box-sizing:border-box;background:#101116;color:#fff;border:1px solid #555;padding:5px 8px}',
        '.box{position:absolute;left:14px;right:14px;top:122px;bottom:54px;border:1px solid #4b4d55;overflow:auto;background:#101116}',
        '.row{height:30px;line-height:30px;padding:0 10px;border-bottom:1px solid #292b33;white-space:nowrap;overflow:hidden;text-overflow:ellipsis;cursor:default}',
        '.row:hover{background:#292c35}.row.selected{background:#35445f}',
        'button{position:absolute;bottom:12px;height:30px;border:1px solid #666;background:#2b2d34;color:#fff}',
        '#copy{right:112px;width:108px}#close{right:14px;width:88px}',
        '</style><title>MusicCard可识别字体</title></head><body>',
        '<div class="title">系统字体（MusicCard可识别）</div>',
        '<div class="hint" id="hint"></div>',
        '<input id="search" type="text" placeholder="筛选字体名">',
        '<div class="box" id="box"></div>',
        '<button id="copy">复制名称</button><button id="close">关闭</button>',
        '<script>',
        'var args=null,items=[],cb=null,currentFont="",selected="",closed=false;',
        'try{args=window.external.dialogArguments.toArray();}catch(e){}',
        'if(args){try{items=JSON.parse(args[0]);}catch(e2){items=[];}currentFont=String(args[1]||"");cb=args[2];}',
        'function closeWin(){closed=true;window.open("","_self","");window.close();}',
        'function selectRow(el,name){selected=name;var rs=document.getElementsByClassName("row");for(var i=0;i<rs.length;i++)rs[i].className="row";el.className="row selected";}',
        'function render(){var q=document.getElementById("search").value.toLowerCase(),box=document.getElementById("box");box.innerHTML="";var shown=0;for(var i=0;i<items.length;i++){var name=String(items[i]);if(q&&name.toLowerCase().indexOf(q)<0)continue;var row=document.createElement("div");row.className="row";row.textContent=name;row.title=name;row.setAttribute("data-name",name);row.onclick=function(){selectRow(this,this.getAttribute("data-name"));};row.ondblclick=function(){selectRow(this,this.getAttribute("data-name"));if(cb)cb("copy",selected);};box.appendChild(row);shown++;}document.getElementById("hint").innerText="共 "+items.length+" 个字体族，当前显示字体："+currentFont+"。仅列出经MusicCard识别复核通过的名称；双击或选中后复制。当前筛选："+shown+"。";}',
        'document.getElementById("search").onkeyup=render;',
        'document.getElementById("copy").onclick=function(){if(selected&&cb)cb("copy",selected);};',
        'document.getElementById("close").onclick=closeWin;',
        'document.onkeydown=function(e){e=e||window.event;if(e.keyCode===27)closeWin();};',
        'window.onunload=function(){if(!closed&&cb)cb("close","");};',
        'render();window.resizeTo(720,650);try{window.moveTo(Math.max(0,Math.floor((screen.availWidth-720)/2)),Math.max(0,Math.floor((screen.availHeight-650)/2)));}catch(e){}document.getElementById("search").focus();',
        '</script></body></html>'
    ].join('');
    utils.ShowHtmlDialog(window.ID, html, {
        data: [JSON.stringify(fontNames), DISPLAY_FONT_NAME, function (status, fontName) {
            if (status !== 'copy' || !fontName) return;
            if (copyTextToClipboard(fontName, false)) {
                try { console.log('[MusicCard][字体]已复制字体名：' + fontName); } catch (e) {}
            }
        }]
    });
}

function actionListAllFonts() {
    try {
        const fonts = enumerateRecognizedSystemFonts();
        if (!fonts.length) {
            fb.ShowPopupMessage('没有读取到可被MusicCard识别的系统字体。', MUSICCARD_TITLE);
            return;
        }
        showRecognizedFontListDialog(fonts);
    } catch (e) {
        fb.ShowPopupMessage('读取系统字体失败。\n' + e, MUSICCARD_TITLE);
    }
}
function applyCellEdit(rowKey, colKey) {
    try {
        if (colKey === 'rowLabel') return editStyleElement(rowKey, getStyleRowLabel(rowKey));
        const obj = STYLE_CONFIG[rowKey];
        let v, n;
        if (colKey === 'bold' || colKey === 'italic') {
            obj[colKey] = !obj[colKey]; persistSettings(); window.Repaint(); return;
        }
        if (colKey === 'size') {
            v = requestInput(floatPrompt(getStyleRowLabel(rowKey) + ' - 字号', 0.001, 1000), '编辑单元格', formatNumber(obj.size));
            if (inputWasCancelled(v)) return;
            n = parseFloatInput(v, 0.001, 1000); if (n !== null) obj.size = n;
        } else if (colKey === 'font') {
            v = requestInput(getStyleRowLabel(rowKey) + ' - 字体名', '编辑单元格', obj.font || DEFAULT_FONT_NAME);
            if (inputWasCancelled(v)) return;
            obj.font = String(v).trim() || DEFAULT_FONT_NAME;
        } else if (colKey === 'colorHex') {
            v = requestInput(getStyleRowLabel(rowKey) + ' - 颜色\n' + colorSpecInputNote(true), '编辑单元格', obj.colorHex || '');
            if (inputWasCancelled(v)) return;
            if (String(v).trim() === '') obj.colorHex = '';
            else { const hx = normalizeColorSpec(v); if (!hx) return fb.ShowPopupMessage(colorSpecErrorText(true), MUSICCARD_TITLE); obj.colorHex = hx; }
        } else if (colKey === 'opacity' || colKey === 'blurOpacity') {
            const title = colKey === 'opacity' ? '不透明度' : '模糊不透明度';
            v = requestInput(floatPrompt(getStyleRowLabel(rowKey) + ' - ' + title, 0, 255), '编辑单元格', formatNumber(obj[colKey] || 0));
            if (inputWasCancelled(v)) return;
            n = parseFloatInput(v, 0, 255); if (n !== null) obj[colKey] = n;
        } else if (colKey === 'blurStrength') {
            v = requestInput(getStyleRowLabel(rowKey) + ' - 模糊强度 0-' + MAX_TEXT_BLUR_STRENGTH + '（整数）', '编辑单元格', String(obj.blurStrength || 0));
            if (inputWasCancelled(v)) return;
            obj.blurStrength = clamp(parseInt(v, 10) || 0, 0, MAX_TEXT_BLUR_STRENGTH);
        } else if (colKey === 'letterSpacing') {
            v = requestInput(floatPrompt(getStyleRowLabel(rowKey) + ' - 字间距（px）', MIN_LETTER_SPACING, MAX_LETTER_SPACING,
                '留空使用原生普通文字绘制；输入数值（包括 0 和 -1）使用逐字绘制。'),
                '编辑单元格', formatLetterSpacing(obj.letterSpacing));
            if (inputWasCancelled(v)) return;
            n = parseLetterSpacingInput(v); if (n !== null) obj.letterSpacing = n;
        } else if (colKey === 'text') {
            if (!rowSupportsText(rowKey)) return;
            v = requestInput(getTextContentPrompt(rowKey, getStyleRowLabel(rowKey)), '编辑单元格', obj.text !== undefined ? String(obj.text) : '');
            if (inputWasCancelled(v)) return;
            obj.text = String(v);
        }
        persistSettings(); window.Repaint();
    } catch (e) {
        fb.ShowPopupMessage('单元格编辑失败。\n' + e, MUSICCARD_TITLE);
    }
}
function actionToggleLyricsLayout() {
    LYRICS_CONFIG.enabled = !LYRICS_CONFIG.enabled;
    persistSettings();
    window.Repaint();
}
function editLyricsText() {
    showMultilineEditor(
        '编辑歌词',
        '输入多行歌词。每一行独立排版；可使用 foobar2000 标题格式化表达式和 %datey%。',
        LYRICS_CONFIG.text || '',
        function (value) {
            LYRICS_CONFIG.text = String(value || '').replace(/\r\n?/g, '\n');
            confirmLyricsForCurrentTrack();
            persistSettings();
            if (UI.view === 'settings' && UI.settingsPreviewEnabled) {
                UI.settingsPreviewDirty = true;
                scheduleSettingsPreviewRefresh();
            }
            window.Repaint();
        }
    );
}
function promptLyricsInteger(field, title, minValue, maxValue, hint) {
    const v = requestInput((hint ? hint + '\n\n' : '') + '请输入 ' + minValue + '-' + maxValue + ' 之间的整数。', title, String(LYRICS_CONFIG[field]));
    if (inputWasCancelled(v)) return;
    const raw = String(v).trim();
    if (!/^\d+$/.test(raw)) { fb.ShowPopupMessage('请输入有效整数。', MUSICCARD_TITLE); return; }
    const n = parseInt(raw, 10);
    if (n < minValue || n > maxValue) { fb.ShowPopupMessage('请输入 ' + minValue + '-' + maxValue + ' 之间的整数。', MUSICCARD_TITLE); return; }
    LYRICS_CONFIG[field] = n;
    persistSettings();
    window.Repaint();
}
function promptLyricsFloat(field, title, minValue, maxValue, hint) {
    const prompt = floatPrompt('请输入' + title, minValue, maxValue, hint || '');
    const v = requestInput(prompt, title, formatNumber(LYRICS_CONFIG[field]));
    if (inputWasCancelled(v)) return;
    const n = parseFloatInput(v, minValue, maxValue);
    if (n === null) {
        fb.ShowPopupMessage('输入无效。\n' + FLOAT_INPUT_NOTE, MUSICCARD_TITLE);
        return;
    }
    LYRICS_CONFIG[field] = n;
    persistSettings(); window.Repaint();
}
function promptLyricsLetterSpacing() {
    const prompt = floatPrompt('请输入歌词字间距（px）', MIN_LETTER_SPACING, MAX_LETTER_SPACING,
        '留空使用原生普通文字绘制；输入数值（包括 0 和 -1）使用逐字绘制。');
    const v = requestInput(prompt, '歌词字间距（px）', formatLetterSpacing(LYRICS_CONFIG.letterSpacing));
    if (inputWasCancelled(v)) return;
    const n = parseLetterSpacingInput(v);
    if (n === null) {
        fb.ShowPopupMessage('输入无效。\n' + FLOAT_INPUT_NOTE, MUSICCARD_TITLE);
        return;
    }
    LYRICS_CONFIG.letterSpacing = n;
    persistSettings(); window.Repaint();
}
function promptLyricsHex(field, title) {
    const v = requestInput('请输入颜色。\n' + colorSpecInputNote(true), title, LYRICS_CONFIG[field] || '');
    if (inputWasCancelled(v)) return;
    if (!String(v).trim()) LYRICS_CONFIG[field] = '';
    else {
        const hx = normalizeColorSpec(v);
        if (!hx) { fb.ShowPopupMessage(colorSpecErrorText(true), MUSICCARD_TITLE); return; }
        LYRICS_CONFIG[field] = hx;
    }
    persistSettings();
    window.Repaint();
}
function actionLyricsButton(key) {
    switch (key) {
        case 'lyricsText': return editLyricsText();
        case 'containerWidth': return promptLyricsFloat('containerWidth', '歌词容器宽度', 0, MAX_LYRICS_CONTAINER_WIDTH, '输入 0 自动计算，以最长的一行文字宽度为容器宽度。');
        case 'size': return promptLyricsFloat('size', '歌词字号', 0.001, 1000, '');
        case 'openCCMode': return actionCycleLyricsOpenCCMode();
        case 'font': {
            const v = requestInput('请输入歌词字体名', '歌词字体', LYRICS_CONFIG.font || DEFAULT_FONT_NAME);
            if (inputWasCancelled(v)) return;
            LYRICS_CONFIG.font = String(v).trim() || DEFAULT_FONT_NAME; persistSettings(); window.Repaint(); return;
        }
        case 'bold': LYRICS_CONFIG.bold = !LYRICS_CONFIG.bold; persistSettings(); window.Repaint(); return;
        case 'italic': LYRICS_CONFIG.italic = !LYRICS_CONFIG.italic; persistSettings(); window.Repaint(); return;
        case 'colorHex': return promptLyricsHex('colorHex', '歌词 HEX');
        case 'opacity': return promptLyricsFloat('opacity', '歌词不透明度', 0, 255, '');
        case 'blurStrength': return promptLyricsInteger('blurStrength', '歌词模糊强度', 0, MAX_TEXT_BLUR_STRENGTH, '该效果绘制为文字外侧光晕；0 表示关闭。');
        case 'blurOpacity': return promptLyricsFloat('blurOpacity', '歌词模糊不透明度', 0, 255, '0 表示关闭。');
        case 'letterSpacing': return promptLyricsLetterSpacing();
        case 'topPadding': return promptLyricsFloat('topPadding', '歌词上间距', 0, 1000, '距离歌词容器顶部。');
        case 'bottomPadding': return promptLyricsFloat('bottomPadding', '歌词下间距', 0, 1000, '距离歌词容器底部。');
        case 'lineGap': return promptLyricsFloat('lineGap', '歌词行距', 0, 500, '表示相邻两行起点之间的距离。');
        case 'xAlign': LYRICS_CONFIG.xAlign = LYRICS_CONFIG.xAlign === 'left' ? 'center' : (LYRICS_CONFIG.xAlign === 'center' ? 'right' : 'left'); persistSettings(); window.Repaint(); return;
        case 'yAlign': LYRICS_CONFIG.yAlign = LYRICS_CONFIG.yAlign === 'top' ? 'center' : (LYRICS_CONFIG.yAlign === 'center' ? 'bottom' : 'top'); persistSettings(); window.Repaint(); return;
        case 'rightGap': return promptLyricsFloat('rightGap', '歌词容器右侧与封面距离', 0, 1000, '');
        case 'dividerEnabled': LYRICS_CONFIG.dividerEnabled = !LYRICS_CONFIG.dividerEnabled; persistSettings(); window.Repaint(); return;
        case 'dividerThickness': return promptLyricsFloat('dividerThickness', '分隔线粗', 0.001, 100, '');
        case 'dividerTopHex': return promptLyricsHex('dividerTopHex', '分隔线顶部 HEX');
        case 'dividerTopOpacity': return promptLyricsFloat('dividerTopOpacity', '分隔线顶部不透明度', 0, 255, '');
        case 'dividerMiddleHex': return promptLyricsHex('dividerMiddleHex', '分隔线中间 HEX');
        case 'dividerMiddleOpacity': return promptLyricsFloat('dividerMiddleOpacity', '分隔线中间不透明度', 0, 255, '');
        case 'dividerBottomHex': return promptLyricsHex('dividerBottomHex', '分隔线底部 HEX');
        case 'dividerBottomOpacity': return promptLyricsFloat('dividerBottomOpacity', '分隔线底部不透明度', 0, 255, '');
        case 'dividerTopPadding': return promptLyricsFloat('dividerTopPadding', '分隔线上间距', 0, 1000, '距离歌词容器顶部。');
        case 'dividerBottomPadding': return promptLyricsFloat('dividerBottomPadding', '分隔线下间距', 0, 1000, '距离歌词容器底部。');
        case 'dividerLeftGap': return promptLyricsFloat('dividerLeftGap', '分隔线左间距', 0, 1000, '歌词容器右边缘到分隔线之间的距离。');
        case 'dividerRightGap': return promptLyricsFloat('dividerRightGap', '分隔线右间距', 0, 1000, '分隔线到封面或后续内容之间的距离。');
    }
}

function exportConfigFile() {
    try {
        const defaultPath = fb.ProfilePath + 'music_card_style_export_v4_16_7.json';
        const val = requestInput('请输入导出配置文件路径', '导出配置', defaultPath);
        if (inputWasCancelled(val)) return;
        const path = String(val).trim();
        if (!path) return;
        const payload = {
            musicCardVersion: MUSICCARD_VERSION,
            styleSchemaVersion: CURRENT_STYLE_SCHEMA_VERSION,
            exportScale: EXPORT_SCALE,
            customExportScale: CUSTOM_EXPORT_SCALE,
            backgroundStyle: BACKGROUND_STYLE,
            blurStrength: BLUR_STRENGTH,
            solidHex: SOLID_BG_HEX,
            coverShadowOpacity: COVER_SHADOW_OPACITY,
            coverShadowDepth: COVER_SHADOW_DEPTH,
            textRenderingHint: TEXT_RENDERING_HINT,
            coverCornerRadius: COVER_CORNER_RADIUS,
            irregularCoverMode: IRREGULAR_COVER_MODE,
            blurBackgroundCropPosition: BLUR_BG_CROP_POSITION,
            rainbowSampleMaxSide: RAINBOW_SAMPLE_MAX_SIDE,
            rainbowMode: RAINBOW_MODE,
            rainbowCustomHex: RAINBOW_CUSTOM_HEX,
            rainbowCustomSelection: RAINBOW_CUSTOM_SELECTION,
            customEnvironmentColorsEnabled: CUSTOM_ENVIRONMENT_COLORS_ENABLED,
            customEnvironmentColors: CUSTOM_ENVIRONMENT_COLORS_ENABLED ? CUSTOM_ENVIRONMENT_COLOR_HEXES.slice() : [],
            textOpenCCMode: TEXT_OPENCC_MODE,
            lyricsOpenCCMode: LYRICS_OPENCC_MODE,
            displayFontName: DISPLAY_FONT_NAME,
            lyrics: LYRICS_CONFIG,
            style: STYLE_CONFIG
        };
        writeTextFile(path, JSON.stringify(payload, null, 2));
        fb.ShowPopupMessage('配置已导出：\n' + path, MUSICCARD_TITLE);
    } catch (e) {
        fb.ShowPopupMessage('导出配置失败。\n' + e, MUSICCARD_TITLE);
    }
}
function isObjectRecord(value) {
    return !!value && typeof value === 'object' && !Array.isArray(value);
}
function isValidMusicCardConfigPayload(payload) {
    if (!isObjectRecord(payload) || !isObjectRecord(payload.style)) return false;
    if (payload.musicCardVersion !== undefined && !/^\d+\.\d+\.\d+$/.test(String(payload.musicCardVersion))) return false;
    if (payload.styleSchemaVersion !== undefined) {
        const schemaVersion = parseInt(payload.styleSchemaVersion, 10);
        if (!isFinite(schemaVersion) || schemaVersion < 1 || schemaVersion > 9999) return false;
    }
    let validStyleRows = 0;
    for (let i = 0; i < STYLE_KEYS.length; i++) {
        const row = payload.style[STYLE_KEYS[i][0]];
        if (isObjectRecord(row) && (row.size !== undefined || row.font !== undefined || row.opacity !== undefined || row.text !== undefined)) validStyleRows++;
    }
    if (validStyleRows < 4) return false;
    if (payload.exportScale !== undefined) {
        const scale = parseFloat(payload.exportScale);
        if (!isFinite(scale) || scale < 0.1 || scale > 10) return false;
    }
    if (payload.backgroundStyle !== undefined && !['fusion', 'sample', 'blur', 'ink', 'solid'].includes(String(payload.backgroundStyle))) return false;
    if (payload.blurBackgroundCropPosition !== undefined) {
        const cropPosition = parseFloat(payload.blurBackgroundCropPosition);
        if (!isFinite(cropPosition) || cropPosition < 0 || cropPosition > 100) return false;
    }
    if (payload.rainbowSampleMaxSide !== undefined) {
        const rawRainbowSide = String(payload.rainbowSampleMaxSide === null ? '' : payload.rainbowSampleMaxSide).trim();
        if (rawRainbowSide) {
            if (!/^\d+$/.test(rawRainbowSide)) return false;
            const rainbowSide = parseInt(rawRainbowSide, 10);
            if (!isFinite(rainbowSide) || rainbowSide < 1 || rainbowSide > 1000) return false;
        }
    }
    if (payload.rainbowMode !== undefined && !['sample', 'custom'].includes(String(payload.rainbowMode))) return false;
    if (payload.rainbowCustomHex !== undefined && normalizeCustomRainbowHex(payload.rainbowCustomHex) === null) return false;
    if (payload.rainbowCustomSelection !== undefined && String(payload.rainbowCustomSelection) !== 'hex' && !/^palette:[0-4]$/.test(String(payload.rainbowCustomSelection))) return false;
    if (payload.customEnvironmentColorsEnabled !== undefined && typeof payload.customEnvironmentColorsEnabled !== 'boolean') return false;
    if (payload.customEnvironmentColors !== undefined) {
        if (!Array.isArray(payload.customEnvironmentColors)) return false;
        if (payload.customEnvironmentColors.length !== 0 && normalizeEnvironmentColorArray(payload.customEnvironmentColors).length !== CUSTOM_ENVIRONMENT_COLOR_COUNT) return false;
    }
    if (payload.textOpenCCMode !== undefined && !isValidOpenCCModeValue(payload.textOpenCCMode)) return false;
    if (payload.lyricsOpenCCMode !== undefined && !isValidOpenCCModeValue(payload.lyricsOpenCCMode)) return false;
    if (payload.lyrics !== undefined && !isObjectRecord(payload.lyrics)) return false;
    return true;
}
function loadConfigPayload(path) {
    const candidates = [];
    function addCandidate(value) {
        const text = String(value === undefined || value === null ? '' : value).replace(/^\uFEFF/, '');
        if (text && !candidates.includes(text)) candidates.push(text);
    }
    try { addCandidate(readTextFile(path)); } catch (e) {}
    try {
        if (utils && typeof utils.ReadTextFile === 'function') addCandidate(utils.ReadTextFile(path, 65001));
    } catch (e2) {}
    try {
        if (utils && typeof utils.ReadTextFile === 'function') addCandidate(utils.ReadTextFile(path, 1200));
    } catch (e3) {}

    let lastError = null;
    for (let i = 0; i < candidates.length; i++) {
        try {
            const payload = JSON.parse(candidates[i]);
            if (!isValidMusicCardConfigPayload(payload)) throw new Error('不是有效的 MusicCard 配置文件');
            return payload;
        } catch (e4) {
            lastError = e4;
        }
    }
    throw lastError || new Error('无法读取配置文件');
}
function applyImportedConfigPayload(payload) {
    const importedSchemaVersion = parseInt(payload.styleSchemaVersion, 10) || 1;
    if (payload.exportScale !== undefined) {
        EXPORT_SCALE = parseStoredNumber(payload.exportScale, EXPORT_SCALE, 0.1, 10);
        const importedCustom = payload.customExportScale !== undefined ? parseFloat(payload.customExportScale) : NaN;
        CUSTOM_EXPORT_SCALE = isFinite(importedCustom) && importedCustom >= 0.1 && importedCustom <= 10
            ? round3(importedCustom)
            : ([1, 2, 3, 4].includes(EXPORT_SCALE) ? null : EXPORT_SCALE);
    }
    if (payload.backgroundStyle && ['fusion', 'sample', 'blur', 'ink', 'solid'].includes(payload.backgroundStyle)) BACKGROUND_STYLE = payload.backgroundStyle;
    if (payload.blurStrength !== undefined) BLUR_STRENGTH = clamp(parseInt(payload.blurStrength, 10) || 0, 0, MAX_BLUR_STRENGTH);
    if (payload.solidHex !== undefined) SOLID_BG_HEX = normalizeColorSpec(payload.solidHex) || SOLID_BG_HEX;
    if (payload.coverShadowOpacity !== undefined) COVER_SHADOW_OPACITY = parseStoredNumber(payload.coverShadowOpacity, COVER_SHADOW_OPACITY, 0, 255);
    if (payload.coverShadowDepth !== undefined) COVER_SHADOW_DEPTH = parseStoredNumber(payload.coverShadowDepth, COVER_SHADOW_DEPTH, 0, 100);
    if (payload.textRenderingHint !== undefined) TEXT_RENDERING_HINT = clamp(parseInt(payload.textRenderingHint, 10) || 0, 0, 5);
    if (payload.coverCornerRadius !== undefined) COVER_CORNER_RADIUS = clamp(parseInt(payload.coverCornerRadius, 10) || 0, 0, MAX_COVER_CORNER_RADIUS);
    if (payload.irregularCoverMode !== undefined &&
        ['crop', 'tile'].includes(String(payload.irregularCoverMode).toLowerCase())) {
        IRREGULAR_COVER_MODE = String(payload.irregularCoverMode).toLowerCase();
    }
    if (payload.blurBackgroundCropPosition !== undefined) {
        BLUR_BG_CROP_POSITION = parseStoredNumber(
            payload.blurBackgroundCropPosition, BLUR_BG_CROP_POSITION, 0, 100
        );
    }
    const importedRainbowSampleMaxSide = parseStoredInteger(
        payload.rainbowSampleMaxSide, DEFAULT_RAINBOW_SAMPLE_MAX_SIDE, 1, 1000
    );
    if (RAINBOW_SAMPLE_MAX_SIDE !== importedRainbowSampleMaxSide) clearRainbowColorCache();
    RAINBOW_SAMPLE_MAX_SIDE = importedRainbowSampleMaxSide;
    if (payload.rainbowMode !== undefined && ['sample', 'custom'].includes(String(payload.rainbowMode))) RAINBOW_MODE = String(payload.rainbowMode);
    if (payload.rainbowCustomHex !== undefined) {
        const importedRainbowHex = normalizeCustomRainbowHex(payload.rainbowCustomHex);
        if (importedRainbowHex !== null) RAINBOW_CUSTOM_HEX = importedRainbowHex;
    }
    if (payload.rainbowCustomSelection !== undefined) {
        const importedSelection = String(payload.rainbowCustomSelection);
        if (importedSelection === 'hex' || /^palette:[0-4]$/.test(importedSelection)) RAINBOW_CUSTOM_SELECTION = importedSelection;
    }
    if (payload.customEnvironmentColorsEnabled !== undefined) {
        CUSTOM_ENVIRONMENT_COLORS_ENABLED = !!payload.customEnvironmentColorsEnabled;
        const importedEnvironmentColors = normalizeEnvironmentColorArray(payload.customEnvironmentColors || []);
        CUSTOM_ENVIRONMENT_COLOR_HEXES = CUSTOM_ENVIRONMENT_COLORS_ENABLED ? importedEnvironmentColors : [];
        if (CUSTOM_ENVIRONMENT_COLORS_ENABLED && CUSTOM_ENVIRONMENT_COLOR_HEXES.length !== CUSTOM_ENVIRONMENT_COLOR_COUNT) {
            CUSTOM_ENVIRONMENT_COLOR_HEXES = captureCurrentEnvironmentColorHexes();
        }
    }
    TEXT_OPENCC_MODE = normalizeOpenCCMode(payload.textOpenCCMode, DEFAULT_TEXT_OPENCC_MODE);
    LYRICS_OPENCC_MODE = normalizeOpenCCMode(payload.lyricsOpenCCMode, DEFAULT_LYRICS_OPENCC_MODE);
    if (payload.displayFontName !== undefined) {
        const importedDisplayFont = tryGetFontName(payload.displayFontName);
        if (importedDisplayFont) DISPLAY_FONT_NAME = importedDisplayFont;
    }
    OPENCC_DIAGNOSTIC_SHOWN = false;
    clearRainbowColorCache();
    clearStylePaletteCache();
    if (payload.lyrics) LYRICS_CONFIG = mergedLyrics(payload.lyrics);
    if (payload.style) {
        STYLE_CONFIG = mergedStyle(payload.style);
        if (importedSchemaVersion < 3) {
            STYLE_CONFIG.metaValue = STYLE_CONFIG.metaValue || clone(DEFAULT_STYLE.metaValue);
            const importedMetaExpression = String(STYLE_CONFIG.metaValue.text || '');
            if (!importedMetaExpression.trim() || importedMetaExpression === LEGACY_ALBUM_SECOND_LINE_EXPRESSION_V2) {
                STYLE_CONFIG.metaValue.text = DEFAULT_ALBUM_SECOND_LINE_EXPRESSION;
            }
        }
        if (importedSchemaVersion < 4) {
            const importedExpressionDefaults = {
                titleValue: DEFAULT_TITLE_VALUE_EXPRESSION,
                artistValue: DEFAULT_ARTIST_VALUE_EXPRESSION,
                albumValue: DEFAULT_ALBUM_VALUE_EXPRESSION
            };
            for (const key in importedExpressionDefaults) {
                STYLE_CONFIG[key] = STYLE_CONFIG[key] || clone(DEFAULT_STYLE[key]);
                if (!String(STYLE_CONFIG[key].text || '').trim()) STYLE_CONFIG[key].text = importedExpressionDefaults[key];
            }
        }
        if (importedSchemaVersion < 6) {
            STYLE_CONFIG.metaValue = STYLE_CONFIG.metaValue || clone(DEFAULT_STYLE.metaValue);
            const importedMetaExpressionV6 = String(STYLE_CONFIG.metaValue.text || '');
            if (!importedMetaExpressionV6.trim() ||
                importedMetaExpressionV6 === LEGACY_ALBUM_SECOND_LINE_EXPRESSION_V2 ||
                importedMetaExpressionV6 === LEGACY_ALBUM_SECOND_LINE_EXPRESSION_V3) {
                STYLE_CONFIG.metaValue.text = DEFAULT_ALBUM_SECOND_LINE_EXPRESSION;
            }
        }
        if (importedSchemaVersion < 7) {
            STYLE_CONFIG.metaValue = STYLE_CONFIG.metaValue || clone(DEFAULT_STYLE.metaValue);
            const importedMetaExpressionV7 = String(STYLE_CONFIG.metaValue.text || '');
            if (!importedMetaExpressionV7.trim() ||
                importedMetaExpressionV7 === LEGACY_ALBUM_SECOND_LINE_EXPRESSION_V2 ||
                importedMetaExpressionV7 === LEGACY_ALBUM_SECOND_LINE_EXPRESSION_V3 ||
                importedMetaExpressionV7 === LEGACY_ALBUM_SECOND_LINE_EXPRESSION_V4) {
                STYLE_CONFIG.metaValue.text = DEFAULT_ALBUM_SECOND_LINE_EXPRESSION;
            }
        }
        if (importedSchemaVersion < 11) {
            for (let i = 0; i < STYLE_KEYS.length; i++) {
                const key = STYLE_KEYS[i][0];
                if (STYLE_CONFIG[key] && Math.abs(Number(STYLE_CONFIG[key].letterSpacing) + 1) < 0.0005) {
                    STYLE_CONFIG[key].letterSpacing = '';
                }
            }
        }
    }
    if (importedSchemaVersion < 11 && Math.abs(Number(LYRICS_CONFIG.letterSpacing) + 1) < 0.0005) {
        LYRICS_CONFIG.letterSpacing = '';
    }
    STYLE_SCHEMA_VERSION = CURRENT_STYLE_SCHEMA_VERSION;
    persistSettings();
    window.Repaint();
}
function importConfigFromPath(path, showSuccess) {
    const payload = loadConfigPayload(path);
    const sourceVersion = payload.musicCardVersion !== undefined ? String(payload.musicCardVersion) : '旧版/未标注';
    const sourceSchema = parseInt(payload.styleSchemaVersion, 10) || 1;
    applyImportedConfigPayload(payload);
    try { console.log('[MusicCard][配置]已读取配置版本：MusicCard ' + sourceVersion + '；schema ' + sourceSchema + '；文字简繁=' + TEXT_OPENCC_MODE + '；歌词简繁=' + LYRICS_OPENCC_MODE); } catch (e) {}
    if (showSuccess !== false) {
        fb.ShowPopupMessage(
            '配置已导入：\n' + path + '\n\n' +
            '来源版本：' + sourceVersion + '\n' +
            '配置schema：' + sourceSchema + '\n' +
            '文字简繁：' + TEXT_OPENCC_MODE + '\n' +
            '歌词简繁：' + LYRICS_OPENCC_MODE + '\n' +
            '显示字体：' + DISPLAY_FONT_NAME,
            MUSICCARD_TITLE
        );
    }
}
function importConfigFile() {
    try {
        const defaultPath = fb.ProfilePath + 'music_card_style_export_v4_16_7.json';
        const val = requestInput('请输入导入配置文件路径', '导入配置', defaultPath);
        if (inputWasCancelled(val)) return;
        const path = String(val).trim();
        if (!path || !fileExists(path)) {
            fb.ShowPopupMessage('配置文件不存在。', MUSICCARD_TITLE);
            return;
        }
        importConfigFromPath(path, true);
    } catch (e) {
        fb.ShowPopupMessage('导入配置失败。\n' + e, MUSICCARD_TITLE);
    }
}
function formatConfigFileTime(value) {
    try {
        const d = new Date(value);
        if (isNaN(d.getTime())) return String(value || '');
        function p2(n) { return String(n).padStart(2, '0'); }
        return d.getFullYear() + '-' + p2(d.getMonth() + 1) + '-' + p2(d.getDate()) +
            ' ' + p2(d.getHours()) + ':' + p2(d.getMinutes());
    } catch (e) {
        return String(value || '');
    }
}
function scanProfileConfigFiles() {
    const fso = new ActiveXObject('Scripting.FileSystemObject');
    const rootPath = String(fb.ProfilePath || '');
    if (!rootPath || !fso.FolderExists(rootPath)) return [];
    const result = [];
    const seen = {};
    const maxFiles = 500;
    const maxDepth = 8;
    const maxScannedJson = 5000;
    const maxVisitedFolders = 600;
    let scannedJson = 0;
    let visitedFolders = 0;

    function walk(folder, depth) {
        if (!folder || depth > maxDepth || result.length >= maxFiles ||
            scannedJson >= maxScannedJson || visitedFolders >= maxVisitedFolders) return;
        visitedFolders++;
        try {
            const files = new Enumerator(folder.Files);
            for (; !files.atEnd() && result.length < maxFiles; files.moveNext()) {
                const file = files.item();
                const name = String(file.Name || '');
                if (!/\.json$/i.test(name)) continue;
                scannedJson++;
                if (scannedJson > maxScannedJson) break;
                const path = String(file.Path || '');
                if (!path || seen[path.toLowerCase()]) continue;
                seen[path.toLowerCase()] = true;
                try {
                    if (Number(file.Size || 0) > 8 * 1024 * 1024) continue;
                    const payload = loadConfigPayload(path);
                    result.push({
                        name: name,
                        path: path,
                        modified: formatConfigFileTime(file.DateLastModified),
                        version: payload.musicCardVersion !== undefined ? String(payload.musicCardVersion) : '旧版',
                        schema: parseInt(payload.styleSchemaVersion, 10) || 1
                    });
                } catch (e) {
                    // Invalid JSON and unrelated JSON files are deliberately filtered out.
                }
            }
        } catch (e2) {}

        if (depth >= maxDepth || result.length >= maxFiles ||
            scannedJson >= maxScannedJson || visitedFolders >= maxVisitedFolders) return;
        try {
            const folders = new Enumerator(folder.SubFolders);
            for (; !folders.atEnd() && result.length < maxFiles; folders.moveNext()) {
                walk(folders.item(), depth + 1);
            }
        } catch (e3) {}
    }

    walk(fso.GetFolder(rootPath), 0);
    result.sort(function (a, b) {
        const ma = String(a.modified || ''), mb = String(b.modified || '');
        if (ma === mb) return String(a.name).localeCompare(String(b.name));
        return ma < mb ? 1 : -1;
    });
    return result;
}
function showConfigChooserDialog(files) {
    const rows = files.map(function (item) {
        return {
            name: item.name,
            modified: item.modified,
            version: item.version,
            schema: item.schema,
            path: item.path
        };
    });
    const html = [
        '<!DOCTYPE html><html><head><meta http-equiv="x-ua-compatible" content="IE=9" />',
        '<meta charset="utf-8"><style>',
        'html,body{margin:0;padding:0;background:#17181d;color:#f3f3f3;font:13px Microsoft YaHei,微软雅黑,sans-serif;overflow:hidden}',
        '.title{position:absolute;left:14px;right:14px;top:10px;height:28px;font-size:16px;font-weight:600}',
        '.hint{position:absolute;left:14px;right:14px;top:39px;height:24px;color:#aaa}',
        '.box{position:absolute;left:14px;right:14px;top:66px;bottom:54px;border:1px solid #4b4d55;overflow:auto;background:#101116}',
        'table{width:100%;border-collapse:collapse;table-layout:fixed}',
        'th{position:sticky;top:0;background:#252730;color:#ddd;text-align:left;padding:8px;border-bottom:1px solid #555}',
        'td{padding:7px 8px;border-bottom:1px solid #292b33;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}',
        'tr.data:hover{background:#292c35}tr.selected{background:#35445f}',
        '.name{width:25%}.time{width:18%}.schema{width:14%}.path{width:43%}',
        'button{position:absolute;bottom:12px;width:92px;height:30px;border:1px solid #666;background:#2b2d34;color:#fff}',
        '#open{right:112px}#cancel{right:14px}',
        '</style><title>选择 MusicCard 配置</title></head><body>',
        '<div class="title">选择配置</div>',
        '<div class="hint">已过滤无效或不属于 MusicCard 的 JSON。双击一行即可载入。</div>',
        '<div class="box"><table><thead><tr><th class="name">文件名</th><th class="time">修改时间</th><th class="schema">版本/schema</th><th class="path">路径</th></tr></thead><tbody id="body"></tbody></table></div>',
        '<button id="open">打开</button><button id="cancel">取消</button>',
        '<script>',
        'var args=null,items=[],cb=null,selected=-1,closed=false;',
        'try{args=window.external.dialogArguments.toArray();}catch(e){}',
        'if(args){try{items=JSON.parse(args[0]);}catch(e2){items=[];}cb=args[1];}',
        'function closeWin(){closed=true;window.open("","_self","");window.close();}',
        'function choose(i){selected=i;var rs=document.querySelectorAll("tr.data");for(var k=0;k<rs.length;k++)rs[k].className="data"+(k===i?" selected":"");}',
        'function openSelected(){if(selected<0)return;if(cb)cb("open",String(selected));closeWin();}',
        'var body=document.getElementById("body");',
        'for(var i=0;i<items.length;i++){(function(index){var it=items[index],tr=document.createElement("tr");tr.className="data";',
        'function td(text,cls){var c=document.createElement("td");c.className=cls;c.textContent=text;c.title=text;tr.appendChild(c);}',
        'td(it.name,"name");td(it.modified,"time");td(it.version+"/s"+it.schema,"schema");td(it.path,"path");',
        'tr.onclick=function(){choose(index);};tr.ondblclick=function(){choose(index);openSelected();};body.appendChild(tr);})(i);}',
        'document.getElementById("open").onclick=openSelected;',
        'document.getElementById("cancel").onclick=function(){closeWin();};',
        'window.onunload=function(){if(!closed&&cb)cb("cancel","");};',
        'document.onkeydown=function(e){e=e||window.event;if(e.keyCode===13)openSelected();else if(e.keyCode===27)closeWin();};',
        'window.resizeTo(980,580);try{window.moveTo(Math.max(0,Math.floor((screen.availWidth-980)/2)),Math.max(0,Math.floor((screen.availHeight-580)/2)));}catch(e){}if(items.length)choose(0);',
        '</script></body></html>'
    ].join('');
    utils.ShowHtmlDialog(window.ID, html, {
        data: [JSON.stringify(rows), function (status, indexText) {
            if (status !== 'open') return;
            const index = parseInt(indexText, 10);
            if (isNaN(index) || index < 0 || index >= files.length) return;
            try {
                importConfigFromPath(files[index].path, true);
            } catch (e) {
                fb.ShowPopupMessage('导入配置失败。\n' + e, MUSICCARD_TITLE);
            }
        }]
    });
}
function chooseConfigFile() {
    try {
        const files = scanProfileConfigFiles();
        if (!files.length) {
            fb.ShowPopupMessage('没有在 foobar2000 配置文件夹中找到有效的 MusicCard JSON 配置。', MUSICCARD_TITLE);
            return;
        }
        if (!utils || typeof utils.ShowHtmlDialog !== 'function') {
            fb.ShowPopupMessage('当前 SMP 环境不支持配置选择窗口，请使用“导入配置”。', MUSICCARD_TITLE);
            return;
        }
        showConfigChooserDialog(files);
    } catch (e) {
        fb.ShowPopupMessage('扫描配置文件失败。\n' + e, MUSICCARD_TITLE);
    }
}

function setSettingsScroll(x, y) {
    const vp = UI.settingsViewport || { w: Math.max(1, window.Width - 16), h: Math.max(1, window.Height - 16) };
    UI.settingsScrollX = clamp(Math.round(x), 0, Math.max(0, UI.settingsContentW + 8 - vp.w));
    UI.settingsScrollY = clamp(Math.round(y), 0, Math.max(0, UI.settingsContentH - vp.h));
    window.Repaint();
}
function settingsScrollbarHit(x, y) {
    const v = UI.settingsVScrollbar, h = UI.settingsHScrollbar;
    if (v) {
        for (const r of [v.decRect, v.incRect, v.thumbRect, v.trackRect]) if (rectHit(r, x, y)) return r.id;
    }
    if (h) {
        for (const r of [h.decRect, h.incRect, h.thumbRect, h.trackRect]) if (rectHit(r, x, y)) return r.id;
    }
    return '';
}
function handleSettingsScrollbarClick(x, y) {
    const v = UI.settingsVScrollbar, h = UI.settingsHScrollbar;
    if (!v || !h) return false;
    if (rectHit(v.decRect, x, y)) { setSettingsScroll(UI.settingsScrollX, UI.settingsScrollY - 48); return true; }
    if (rectHit(v.incRect, x, y)) { setSettingsScroll(UI.settingsScrollX, UI.settingsScrollY + 48); return true; }
    if (rectHit(h.decRect, x, y)) { setSettingsScroll(UI.settingsScrollX - 64, UI.settingsScrollY); return true; }
    if (rectHit(h.incRect, x, y)) { setSettingsScroll(UI.settingsScrollX + 64, UI.settingsScrollY); return true; }
    if (rectHit(v.trackRect, x, y) && !rectHit(v.thumbRect, x, y)) {
        setSettingsScroll(UI.settingsScrollX, UI.settingsScrollY + (y < v.thumbRect.y ? -UI.settingsViewport.h * 0.8 : UI.settingsViewport.h * 0.8));
        return true;
    }
    if (rectHit(h.trackRect, x, y) && !rectHit(h.thumbRect, x, y)) {
        setSettingsScroll(UI.settingsScrollX + (x < h.thumbRect.x ? -UI.settingsViewport.w * 0.8 : UI.settingsViewport.w * 0.8), UI.settingsScrollY);
        return true;
    }
    return false;
}

function on_mouse_move(x, y) {
    if (UI.view === 'sleep') {
        const hover = UI.sleepButton && rectHit(UI.sleepButton, x, y) ? UI.sleepButton.id : '';
        if (hover !== UI.hover) { UI.hover = hover; window.Repaint(); }
        return;
    }
    if (UI.settingsScrollDragging && UI.view === 'settings') {
        if (UI.settingsScrollDragging === 'vertical') {
            const v = UI.settingsVScrollbar;
            const pos = clamp(y - UI.settingsScrollDragOffset - v.trackRect.y, 0, v.travel);
            setSettingsScroll(UI.settingsScrollX, v.max > 0 && v.travel > 0 ? pos * v.max / v.travel : 0);
        } else {
            const h = UI.settingsHScrollbar;
            const pos = clamp(x - UI.settingsScrollDragOffset - h.trackRect.x, 0, h.travel);
            setSettingsScroll(h.max > 0 && h.travel > 0 ? pos * h.max / h.travel : 0, UI.settingsScrollY);
        }
        return;
    }
    if (UI.sliderDragging && UI.view === 'settings') {
        if (UI.sliderDragging === 'blur') updateBlurStrengthFromX(x, false);
        else if (UI.sliderDragging === 'corner') updateCoverCornerRadiusFromX(x, false);
        return;
    }
    let hover = '';
    if (UI.view === 'main') {
        for (let i = 0; i < UI.buttons.length; i++) if (rectHit(UI.buttons[i], x, y)) hover = UI.buttons[i].id;
    } else if (UI.view === 'preview') {
        if (UI.previewInputButton && rectHit(UI.previewInputButton, x, y)) hover = UI.previewInputButton.id;
        else if (UI.previewSeedCopyButton && rectHit(UI.previewSeedCopyButton, x, y)) hover = UI.previewSeedCopyButton.id;
        else if (UI.previewSeedRefreshButton && rectHit(UI.previewSeedRefreshButton, x, y)) hover = UI.previewSeedRefreshButton.id;
        else if (UI.previewCopyImageButton && rectHit(UI.previewCopyImageButton, x, y)) hover = UI.previewCopyImageButton.id;
        else if (UI.previewResolutionButton && rectHit(UI.previewResolutionButton, x, y)) hover = UI.previewResolutionButton.id;
    } else if (UI.view === 'settings') {
        const scrollHover = settingsScrollbarHit(x, y);
        if (scrollHover) hover = scrollHover;
        const sb = UI.settingsButtons;
        const arr = [sb.save, sb.scale1, sb.scale2, sb.scale3, sb.scale4, sb.scaleCustom, sb.bgFusion, sb.bgInk, sb.bgSample, sb.bgBlur, sb.bgSolid, sb.reset, sb.displayFont, sb.listFonts, sb.textRenderingHint, sb.imp, sb.exp, sb.chooseCfg, sb.shadowOpacity, sb.shadowDepth, sb.coverMode, sb.blurBgCropPosition, sb.rainbowMode, sb.rainbowSampleSide, sb.rainbowCustomHex, sb.lyricsToggle, sb.textOpenCC, sb.previewToggle, sb.settingsPopupPreview, sb.settingsSeedInput, sb.settingsSeedCopy, sb.settingsSeedRefresh, sb.settingsCopyImage, sb.settingsResolution];
        if (!hover) for (let i = 0; i < arr.length; i++) if (arr[i] && rectHit(arr[i], x, y)) hover = arr[i].id;
        if (!hover && sb.rainbowPalette) for (let rpi = 0; rpi < sb.rainbowPalette.length; rpi++) { const rb = sb.rainbowPalette[rpi]; if (rectHit(rb, x, y)) { hover = rb.id; break; } }
        if (!hover) for (const key in UI.lyricsButtons) { const b = UI.lyricsButtons[key]; if (rectHit(b, x, y)) { hover = b.id; break; } }
        if (!hover && UI.blurSlider && rectHit(getSliderValueRect(UI.blurSlider), x, y)) hover = UI.blurSlider.valueId;
        if (!hover && UI.cornerSlider && rectHit(getSliderValueRect(UI.cornerSlider), x, y)) hover = UI.cornerSlider.valueId;
        if (!hover && UI.blurSlider && rectHit(UI.blurSlider, x, y)) hover = UI.blurSlider.id;
        if (!hover && UI.cornerSlider && rectHit(UI.cornerSlider, x, y)) hover = UI.cornerSlider.id;
        if (!hover) for (let j = 0; j < UI.headerCells.length; j++) if (rectHit(UI.headerCells[j], x, y)) hover = UI.headerCells[j].id;
        if (!hover) for (let k = 0; k < UI.settingsCells.length; k++) if (rectHit(UI.settingsCells[k], x, y)) hover = UI.settingsCells[k].id;
    }
    if (hover !== UI.hover) { UI.hover = hover; window.Repaint(); }
}
function on_mouse_leave() { if (UI.hover) { UI.hover = ''; window.Repaint(); } }
function on_mouse_lbtn_down(x, y) {
    if (UI.view === 'sleep') return;
    if (UI.view !== 'settings') return;
    const v = UI.settingsVScrollbar, h = UI.settingsHScrollbar;
    if (v && rectHit(v.thumbRect, x, y) && v.max > 0) {
        UI.settingsScrollDragging = 'vertical';
        UI.settingsScrollDragOffset = y - v.thumbRect.y;
        return;
    }
    if (h && rectHit(h.thumbRect, x, y) && h.max > 0) {
        UI.settingsScrollDragging = 'horizontal';
        UI.settingsScrollDragOffset = x - h.thumbRect.x;
        return;
    }
    if (settingsScrollbarHit(x, y)) return;
    if (UI.blurSlider && rectHit(UI.blurSlider, x, y)) {
        UI.sliderDragging = 'blur';
        updateBlurStrengthFromX(x, false);
    } else if (UI.cornerSlider && rectHit(UI.cornerSlider, x, y)) {
        UI.sliderDragging = 'corner';
        updateCoverCornerRadiusFromX(x, false);
    }
}
function on_mouse_lbtn_up(x, y) {
    if (UI.view === 'sleep') {
        if (UI.sleepButton && rectHit(UI.sleepButton, x, y)) actionRestoreFromSleep();
        return;
    }
    if (UI.settingsScrollDragging) {
        UI.settingsScrollDragging = '';
        UI.settingsScrollDragOffset = 0;
        return;
    }
    if (UI.sliderDragging) {
        const dragged = UI.sliderDragging;
        UI.sliderDragging = '';
        if (dragged === 'blur') updateBlurStrengthFromX(x, true);
        else if (dragged === 'corner') updateCoverCornerRadiusFromX(x, true);
        return;
    }
    if (UI.view === 'preview') {
        if (UI.previewInputButton && rectHit(UI.previewInputButton, x, y)) { actionInputPreviewSeed(); return; }
        if (UI.previewSeedCopyButton && rectHit(UI.previewSeedCopyButton, x, y) && getActivePreviewSeed()) { copyTextToClipboard(getActivePreviewSeed(), true); return; }
        if (UI.previewSeedRefreshButton && rectHit(UI.previewSeedRefreshButton, x, y)) { actionRefreshPreviewSeed(); return; }
        if (UI.previewCopyImageButton && rectHit(UI.previewCopyImageButton, x, y)) { actionCopyCurrentPreviewImage(); return; }
        if (UI.previewResolutionButton && rectHit(UI.previewResolutionButton, x, y)) { copyTextToClipboard(imageResolutionText(UI.previewImage), true); return; }
        const returnToSettings = UI.previewReturnView === 'settings';
        UI.view = returnToSettings ? 'settings' : 'main';
        UI.previewReturnView = 'main';
        UI.popupPreviewSeed = '';
        window.Repaint();
        return;
    }
    if (UI.view === 'main') {
        for (let i = 0; i < UI.buttons.length; i++) {
            const b = UI.buttons[i];
            if (!rectHit(b, x, y)) continue;
            if (b.id === 'preview') actionPreview();
            else if (b.id === 'copy') { if (!UI.copyBusy) actionCopy(); }
            else if (b.id === 'settings') actionOpenSettings();
            else if (b.id === 'about') actionAbout();
            else if (b.id === 'sleep') actionSleep();
            return;
        }
        return;
    }
    if (UI.view === 'settings') {
        if (handleSettingsScrollbarClick(x, y)) return;
        if (UI.blurSlider && rectHit(getSliderValueRect(UI.blurSlider), x, y)) return actionSetBlurStrength();
        if (UI.cornerSlider && rectHit(getSliderValueRect(UI.cornerSlider), x, y)) return actionSetCoverCornerRadius();
        const sb = UI.settingsButtons;
        if (rectHit(sb.save, x, y)) return actionSaveAndReturn();
        if (rectHit(sb.imp, x, y)) return importConfigFile();
        if (rectHit(sb.exp, x, y)) return exportConfigFile();
        if (rectHit(sb.chooseCfg, x, y)) return chooseConfigFile();
        if (rectHit(sb.scale1, x, y)) return actionSetScale(1);
        if (rectHit(sb.scale2, x, y)) return actionSetScale(2);
        if (rectHit(sb.scale3, x, y)) return actionSetScale(3);
        if (rectHit(sb.scale4, x, y)) return actionSetScale(4);
        if (rectHit(sb.scaleCustom, x, y)) return actionSetCustomScale();
        if (rectHit(sb.bgFusion, x, y)) return actionSetBackgroundStyle('fusion');
        if (rectHit(sb.bgInk, x, y)) return actionSetBackgroundStyle('sample');
        if (rectHit(sb.bgSample, x, y)) return actionSetBackgroundStyle('ink');
        if (rectHit(sb.bgBlur, x, y)) return actionSetBackgroundStyle('blur');
        if (rectHit(sb.bgSolid, x, y)) return actionSetBackgroundStyle('solid');
        if (rectHit(sb.customEnvironmentToggle, x, y)) return actionToggleCustomEnvironmentColors();
        if (rectHit(sb.shadowOpacity, x, y)) return actionSetShadowOpacity();
        if (rectHit(sb.shadowDepth, x, y)) return actionSetShadowDepth();
        if (rectHit(sb.coverMode, x, y)) return actionToggleIrregularCoverMode();
        if (sb.blurBgCropPosition && rectHit(sb.blurBgCropPosition, x, y)) return actionSetBlurBackgroundCropPosition();
        if (sb.rainbowMode && rectHit(sb.rainbowMode, x, y)) return actionToggleRainbowMode();
        if (sb.rainbowSampleSide && rectHit(sb.rainbowSampleSide, x, y)) return actionSetRainbowSampleMaxSide();
        if (sb.rainbowCustomHex && rectHit(sb.rainbowCustomHex, x, y)) return actionSetRainbowCustomHex();
        if (sb.rainbowPalette) for (let rpi = 0; rpi < sb.rainbowPalette.length; rpi++) if (rectHit(sb.rainbowPalette[rpi], x, y)) return actionSelectRainbowPaletteColor(rpi);
        if (sb.customEnvironmentPalette) for (let cei = 0; cei < sb.customEnvironmentPalette.length; cei++) if (rectHit(sb.customEnvironmentPalette[cei], x, y)) return actionSetCustomEnvironmentColor(cei);
        if (rectHit(sb.lyricsToggle, x, y)) return actionToggleLyricsLayout();
        if (rectHit(sb.textOpenCC, x, y)) return actionCycleTextOpenCCMode();
        for (const key in UI.lyricsButtons) if (rectHit(UI.lyricsButtons[key], x, y)) return actionLyricsButton(key);
        if (rectHit(sb.textRenderingHint, x, y)) return actionSetTextRenderingHint();
        if (rectHit(sb.previewToggle, x, y)) return actionToggleSettingsPreview();
        if (rectHit(sb.settingsPopupPreview, x, y)) return actionPopupPreviewFromSettings();
        if (rectHit(sb.settingsSeedInput, x, y)) return actionInputSettingsSeed();
        if (rectHit(sb.settingsSeedCopy, x, y)) return actionCopySettingsSeed();
        if (rectHit(sb.settingsSeedRefresh, x, y)) return actionRefreshSettingsSeed();
        if (rectHit(sb.settingsCopyImage, x, y)) return actionCopySettingsPreviewImage();
        if (rectHit(sb.settingsResolution, x, y)) return copyTextToClipboard(imageResolutionText(UI.settingsPreviewImage), true);
        if (rectHit(sb.reset, x, y)) return actionResetDefaults();
        if (rectHit(sb.displayFont, x, y)) return applyDisplayFont();
        if (rectHit(sb.listFonts, x, y)) return actionListAllFonts();
        for (let i = 0; i < UI.headerCells.length; i++) if (rectHit(UI.headerCells[i], x, y)) return applyColumnEdit(UI.headerCells[i].colKey);
        for (let j = 0; j < UI.settingsCells.length; j++) if (rectHit(UI.settingsCells[j], x, y)) return applyCellEdit(UI.settingsCells[j].rowKey, UI.settingsCells[j].colKey);
    }
}
function on_mouse_wheel(step) {
    if (UI.view !== 'settings') return;
    setSettingsScroll(UI.settingsScrollX, UI.settingsScrollY - step * 60);
}

function on_mouse_rbtn_up(x, y) {
    if (UI.view === 'sleep') return true;
    const menu = window.CreatePopupMenu();
    menu.AppendMenuItem(0, 1, '保存当前图片为 PNG');
    menu.AppendMenuSeparator();
    menu.AppendMenuItem(0, 7, '编辑脚本');
    menu.AppendMenuItem(0, 8, '重载');
    menu.AppendMenuSeparator();
    menu.AppendMenuItem(0, 10, '导出倍率 1x');
    menu.AppendMenuItem(0, 11, '导出倍率 2x');
    menu.AppendMenuItem(0, 12, '导出倍率 3x');
    menu.AppendMenuItem(0, 16, '导出倍率 4x');
    menu.AppendMenuItem(0, 20, customScaleButtonText());
    menu.AppendMenuSeparator();
    menu.AppendMenuItem(0, 13, '背景样式：融合');
    menu.AppendMenuItem(0, 14, '背景样式：墨点');
    menu.AppendMenuItem(0, 15, '背景样式：采点');
    menu.AppendMenuItem(0, 17, '背景样式：模糊');
    menu.AppendMenuItem(0, 19, '背景样式：纯色');
    menu.AppendMenuSeparator();
    menu.AppendMenuItem(0, 18, '恢复默认配置');
    menu.AppendMenuSeparator();
    menu.AppendMenuItem(0, 2, '设置自定义封面路径…');
    if (CONFIG.customCoverPath) menu.AppendMenuItem(0, 3, '清除自定义封面（恢复内嵌封面）');
    menu.AppendMenuSeparator();
    menu.AppendMenuItem(0, 4, '设置输出目录…');
    menu.AppendMenuSeparator();
    menu.AppendMenuItem(0, 6, '使用说明');
    const ret = menu.TrackPopupMenu(x, y);
    if (menu && typeof menu.Dispose === 'function') menu.Dispose();
    switch (ret) {
        case 1: actionSaveImage(); break;
        case 2: setCustomCoverPath(); break;
        case 3: clearCustomCover(); break;
        case 4: setOutputDir(); break;
        case 6:
            fb.ShowPopupMessage(
                'MusicCard v4.16.7：\n' +
                '• 样式配置页按四行工具栏重新排版，避免按钮重叠\n' +
                '• 表格后可打开配置预览；配置变化后自动刷新\n' +
                '• 默认配置来自指定的 MusicCard 配置文件\n' +
                '• 所有输入框均可正确区分 OK 与 Cancel\n' +
                '• 新增水印元素：底端与封面底端对齐，左端与 Title / Artist / Album 标签对齐\n' +
                '• 预览 Copy image 增加 Wait… 状态，配置页可用当前种子弹出预览窗口\n' +
                '• 主页加入休眠模式：释放预览图并只保留恢复按钮，降低卡顿\n' +
                '• 普通预览顶部加入 Input / Copy seed / Refresh / Copy image，按钮为上一版的 1.2 倍\n' +
                '• 全部 8 个文本内容均支持 foobar2000 标题格式化表达式与 %datey%\n' +
                '• 支持不规则封面裁剪/平铺、封面圆角和圆角渐变阴影；圆角 180 直接裁成圆形\n' +
                '• 样式配置支持横向、纵向滚动；配置预览按控件区宽度铺满并使用当前导出倍率\n' +
                '• 无封面时移除封面占位，文字从左侧 20 px 开始\n' +
                '• Album 第二行仅在年份与 Disc/Track 同时存在时显示 · 分隔符\n' +
                '• 8 个文字元素支持独立模糊强度与模糊不透明度，作为静态文字光晕绘制\n' +
                '• 可展开歌词排版模块：自动/固定宽度、多行裁切、对齐、渐变分隔线，并整体推动后续布局\n' +
                '• 字号、布局坐标、阴影深度、不透明度和分隔线粗支持三位小数\n' +
                '• 文字与歌词支持字间距；留空使用原生绘制，输入数值（包括 0 和 -1）使用逐字绘制\n' +
                '• 支持 0.1x-10x 自定义导出倍率和预览分辨率复制\n' +
                '• HEX 支持 black/#black、white/#white，以及 rainbow%n / rainbow%n+hex 彩虹色表达式\n' +
                '• 彩虹色可使用 B64 精确封面取色，或自定义 HEX/自动黑白/5 个封面风格色\n' +
        '• 所有卡片生成均记录耗时，并显示在分辨率按钮中\n' +
        '• 可启用 5 个自定义环境颜色，全局接管背景、自动配色和自定义彩虹色的环境色来源\n' +
        '• 可单独修改MusicCard面板显示字体，不影响导出图片中的文字和歌词字体\n' +
        '• 可列出系统字体，并只显示经MusicCard识别校验通过的准确字体族名\n' +
        '•Title至水印与歌词可分别使用opencc-js-1.4.1执行t2s/s2t/s2twp/s2hk显示转换，不修改原文\n' +
        '•依赖加载顺序：先尝试MusicCard主脚本同目录，再尝试foobar2000配置目录（fb.ProfilePath）\n' +
        '•opencc-js-1.4.1采用MIT许可证；项目地址：https://github.com/nk2028/opencc-js\n' +
        '•opencc-data-1.4.1词典采用Apache-2.0许可证；项目地址：https://github.com/nk2028/opencc-data\n' +
        '•OpenCC加载失败时会显示尝试路径、具体原因和依赖下载地址\n' +
                '• 切换曲目后歌词暂显“请输入文本”，保存歌词编辑器后恢复保留内容\n' +
                '• 导出图片文件名：标题-艺术家.png\n' +
                '• 配置文件默认名称：music_card_style_export_v4_16_7.json\n',
                MUSICCARD_TITLE
            ); break;
        case 7: actionEditScript(); break;
        case 8: actionReloadScript(); break;
        case 10: actionSetScale(1); break;
        case 11: actionSetScale(2); break;
        case 12: actionSetScale(3); break;
        case 16: actionSetScale(4); break;
        case 20: actionSetCustomScale(); break;
        case 13: actionSetBackgroundStyle('fusion'); break;
        case 14: actionSetBackgroundStyle('sample'); break;
        case 15: actionSetBackgroundStyle('ink'); break;
        case 17: actionSetBackgroundStyle('blur'); break;
        case 18: actionResetDefaults(); break;
        case 19: actionSetBackgroundStyle('solid'); break;
    }
    return true;
}
function handleSelectionChange() {
    syncLyricsConfirmationForCurrentTrack();
    if (UI.view === 'sleep') return;
    if (UI.view === 'preview') {
        const returnToSettings = UI.previewReturnView === 'settings';
        UI.view = returnToSettings ? 'settings' : 'main';
        UI.previewReturnView = 'main';
        UI.popupPreviewSeed = '';
        UI.previewImage = null;
        UI.previewRenderMs = null;
        window.Repaint();
        return;
    }
    if (UI.view === 'settings' && UI.settingsPreviewEnabled) {
        UI.settingsPreviewDirty = true;
        scheduleSettingsPreviewRefresh();
    }
}
function on_selection_changed() { handleSelectionChange(); }
function on_playlist_items_selection_change() { handleSelectionChange(); }
function on_item_focus_change() { handleSelectionChange(); }
function on_playlist_switch() { handleSelectionChange(); }
function on_playback_new_track() { handleSelectionChange(); }
function on_metadb_changed() {
    clearRainbowColorCache();
    clearStylePaletteCache();
    if (UI.view === 'settings' && UI.settingsPreviewEnabled) {
        UI.settingsPreviewDirty = true;
        scheduleSettingsPreviewRefresh();
    }
}

function initializePreviewSeeds() {
    const seed = generateRandomSeed8();
    UI.previewSeed = seed;
    UI.settingsPreviewSeed = seed;
    UI.popupPreviewSeed = '';
}

initializePreviewSeeds();
syncLyricsConfirmationForCurrentTrack();
if (CUSTOM_ENVIRONMENT_COLORS_ENABLED && CUSTOM_ENVIRONMENT_COLOR_HEXES.length !== CUSTOM_ENVIRONMENT_COLOR_COUNT) {
    CUSTOM_ENVIRONMENT_COLOR_HEXES = captureCurrentEnvironmentColorHexes();
    if (CUSTOM_ENVIRONMENT_COLOR_HEXES.length !== CUSTOM_ENVIRONMENT_COLOR_COUNT) CUSTOM_ENVIRONMENT_COLORS_ENABLED = false;
}
persistSettings();
actionSleep();

