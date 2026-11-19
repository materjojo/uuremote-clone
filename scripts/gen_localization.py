#!/usr/bin/env python3
"""从官方 zh-Hans/en Localizable.strings 生成三端本地化资源。
源文件来自 uuyc_4.48.1_nochannel.pkg（nrd-mac-client），三端文案同源。
"""
import re, json, os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, 'shared', 'localization')

PAIR = re.compile(r'"((?:[^"\\]|\\.)*)"\s*=\s*"((?:[^"\\]|\\.)*)"\s*;')

def parse(path):
    raw = open(path, 'rb').read()
    text = raw.decode('utf-16') if raw[:2] in (b'\xff\xfe', b'\xfe\xff') else raw.decode('utf-8', 'replace')
    out = {}
    for m in PAIR.finditer(text):
        k, v = m.group(1), m.group(2)
        k = k.replace('\\"', '"').replace('\\n', '\n')
        v = v.replace('\\"', '"').replace('\\n', '\n')
        out[k] = v
    return out

def xml_escape(s):
    return (s.replace('&', '&amp;').replace('<', '&lt;').replace('>', '&gt;')
             .replace('"', '\\"').replace("'", "\\'").replace('\n', '\\n'))

def main():
    zh = parse(os.path.join(SRC, 'zh-Hans.strings'))
    en = parse(os.path.join(SRC, 'en.strings'))
    print(f'parsed zh={len(zh)} en={len(en)}')

    # 生成 JSON 字典（最大的公共源），键为英文、值为中文
    merged = {k: zh.get(k, en.get(k, k)) for k in set(zh) | set(en)}
    os.makedirs(os.path.join(ROOT, 'shared', 'localization', 'generated'), exist_ok=True)
    with open(os.path.join(ROOT, 'shared', 'localization', 'generated', 'localized.json'), 'w', encoding='utf-8') as f:
        json.dump(merged, f, ensure_ascii=False, indent=1, sort_keys=True)

    # Android strings.xml（用合法资源名，非法键以 _ 开头哈希）
    def res_name(k):
        name = re.sub(r'[^a-z0-9_]', '_', k.lower())
        if not name or name[0].isdigit():
            name = '_' + name
        return name
    for lang, table in (('zh-rCN', zh), ('en', en)):
        d = os.path.join(ROOT, 'platforms', 'android', 'app', 'src', 'main', 'res', f'values-{lang}')
        os.makedirs(d, exist_ok=True)
        seen = set()
        with open(os.path.join(d, 'strings.xml'), 'w', encoding='utf-8') as f:
            f.write('<?xml version="1.0" encoding="utf-8"?>\n<resources>\n')
            for k, v in table.items():
                n = res_name(k)
                if n in seen:
                    continue
                seen.add(n)
                f.write(f'    <string name="{n}">{xml_escape(v)}</string>\n')
            f.write('</resources>\n')

    # Windows resx（键保留原文，值中文）
    win_dir = os.path.join(ROOT, 'platforms', 'windows', 'Properties')
    os.makedirs(win_dir, exist_ok=True)
    with open(os.path.join(win_dir, 'Resources.resx'), 'w', encoding='utf-8') as f:
        f.write('<?xml version="1.0" encoding="utf-8"?>\n')
        f.write('<root>\n')
        f.write('  <resheader name="resmimetype"><value>text/microsoft-resx</value></resheader>\n')
        f.write('  <resheader name="version"><value>2.0</value></resheader>\n')
        f.write('  <resheader name="reader"><value>System.Resources.ResXResourceReader</value></resheader>\n')
        f.write('  <resheader name="writer"><value>System.Resources.ResXResourceWriter</value></resheader>\n')
        for k, v in merged.items():
            f.write(f'  <data name="{xml_escape(k)}" xml:space="preserve"><value>{xml_escape(v)}</value></data>\n')
        f.write('</root>\n')

    print('generated: localized.json, android values-zh-rCN/values-en, windows Resources.resx')

if __name__ == '__main__':
    main()
