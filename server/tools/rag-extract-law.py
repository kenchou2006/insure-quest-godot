"""Extract the regulation chunks for the compliance RAG into server/rag/law-chunks.json.

Usage (download the four official pages into one folder first, then run with python3 -I):
  curl -sL -o RAW/G0380226.html "https://law.moj.gov.tw/LawClass/LawAll.aspx?pcode=G0380226"   # 金融消費者保護法
  curl -sL -o RAW/G0390016.html "https://law.moj.gov.tw/LawClass/LawAll.aspx?pcode=G0390016"   # 保險業務員管理規則
  curl -sL -o RAW/FL039170.html "https://law.lia-roc.org.tw/Law/Content?lsid=FL039170"       # 保險業招攬廣告自律規範
  curl -sL -o RAW/FL079183.html "https://law.lia-roc.org.tw/Law/Content?lsid=FL079183"       # 金融服務業公平待客原則
  python3 -I server/tools/rag-extract-law.py RAW server/rag/law-chunks.json
Text is copied verbatim; review every chunk against the source before committing a refresh.
"""
import sys, re, html, os, json
R, OUT = sys.argv[1], sys.argv[2]
FETCHED = '2026-10-23'
CN = '零一二三四五六七八九十'
def cn(n):
    if n <= 10: return CN[n] if n < 10 else '十'
    if n < 20: return '十' + (CN[n-10] if n > 10 else '')
    return CN[n//10] + '十' + (CN[n%10] if n%10 else '')
chunks = []
def add(doc, url, revised, ref, text, topic=''):
    text = re.sub(r'[ \t　]+', '', text).strip()
    chunks.append({'id': f'{doc}|{ref}', 'doc': doc, 'ref': ref, 'cite': f'《{doc}》{ref}', 'text': text, 'url': url, 'revised': revised, 'fetched': FETCHED, 'topic': topic})

def moj(p):
    s = open(os.path.join(R, p + '.html'), encoding='utf-8').read()
    d = re.search(r'修正日期：</th>\s*<td>\s*([^<]+)', s)
    rows = re.findall(r'<div class="col-no">\s*<a[^>]*>([^<]+)</a>.*?<div class="law-article">(.*?)</div>\s*</div>', s, re.S)
    arts = {}
    for no, body in rows:
        lines = [html.unescape(re.sub(r'<[^>]+>', '', x)).strip() for x in re.findall(r'<div class="line-\d+[^"]*">(.*?)</div>', body, re.S)]
        if not lines: lines = [html.unescape(re.sub(r'<[^>]+>', '', body)).strip()]
        arts[re.sub(r'\s', '', no)] = [l for l in lines if l]
    return re.sub(r'\s+', ' ', d.group(1)).strip(), arts

# 金融消費者保護法
rev, a = moj('G0380226'); url = 'https://law.moj.gov.tw/LawClass/LawAll.aspx?pcode=G0380226'
for no, topic in [('第7條','公平誠信、善良管理人注意'), ('第8條','廣告與招攬不得虛偽隱匿'), ('第9條','適合度'), ('第10條','說明與揭露義務'), ('第11條','違反說明或適合度之賠償責任')]:
    add('金融消費者保護法', url, rev, no, '\n'.join(a[no]), topic)

# 保險業務員管理規則 第19條 依款切
rev, a = moj('G0390016'); url = 'https://law.moj.gov.tw/LawClass/LawAll.aspx?pcode=G0390016'
art19 = '\n'.join(a['第19條'])
lead = art19.split('一、')[0].strip()
items = re.findall(r'(十[一二三四五六七]?|[一二三四五六七八九])、(.*?)(?=(?:十[一二三四五六七]?|[一二三四五六七八九])、|前項業務員|$)', art19, re.S)
keep = {1,2,3,4,5,8,11,13,14,17}
for k, body in items:
    n = (10 + ('一二三四五六七'.index(k[1]) + 1)) if k.startswith('十') and len(k) > 1 else (10 if k == '十' else '一二三四五六七八九'.index(k) + 1)
    if n in keep:
        add('保險業務員管理規則', url, rev, f'第19條第1項第{n}款', f'{lead}\n{k}、{body.strip()}', '業務員招攬禁止行為')
add('保險業務員管理規則', url, rev, '第15條', '\n'.join(a['第15條']), '招攬行為定義、解釋商品內容及條款')

# 保險業招攬廣告自律規範 (LIA)
s = open(os.path.join(R, 'FL039170.html'), encoding='utf-8').read()
t = html.unescape(re.sub(r'<[^>]+>', '\n', re.sub(r'<script.*?</script>|<style.*?</style>', '', s, flags=re.S)))
rev = re.search(r'修正日期：\s*\n\s*(民國[^\n]+)', t).group(1).strip()
url = 'https://law.lia-roc.org.tw/Law/Content?lsid=FL039170'
body = t[t.find('第 1 條'):]
parts = re.split(r'\n\s*(第 [\d-]+ 條)\s*\n', '\n' + body)
arts = {}
for i in range(1, len(parts) - 1, 2):
    arts[parts[i].replace(' ', '')] = re.sub(r'\n\s*', '', parts[i+1]).strip()
a4 = arts['第4條']
lead4 = a4.split('一、')[0]
for k, n, topic in [('二','2','內容正確、不得誇大、不得與存款比較'), ('五','5','利率費用報酬風險衡平揭露'), ('七','7','分紅保單不得以分紅率招攬或比較'), ('八','8','禁止勸誘解約、誤認政府保證、誇大業績等'), ('九','9','不得使人誤信保證本金或獲利')]:
    m = re.search(k + r'、(.*?)(?=[一二三四五六七八九十]、(?!\S{0,3}）)|$)', a4)
    seg = re.search(k + '、' + r'(.*?)(?=' + ('[三四五六七八九十]' if k=='二' else '[六七八九十]' if k=='五' else '[八九十]' if k=='七' else '九' if k=='八' else '$') + r'、)', a4 + ('' if k!='九' else ''))
    txt = (k + '、' + seg.group(1)) if seg else (k + '、' + a4.split(k + '、', 1)[1])
    add('保險業招攬廣告自律規範', url, rev, f'第4條第{n}款', lead4 + '\n' + txt.strip(), topic)
for no, topic in [('第4-2條','醫療險理賠警語'), ('第5條','投資型商品廣告：風險警語、不得保證本金或獲利'), ('第5-1條','保證承保與高齡廣告：揭露除外責任')]:
    add('保險業招攬廣告自律規範', url, rev, no, arts[no], topic)

# 金融服務業公平待客原則（表格）
s = open(os.path.join(R, 'FL079183.html'), encoding='utf-8').read()
t = html.unescape(re.sub(r'<[^>]+>', '\n', re.sub(r'<script.*?</script>|<style.*?</style>', '', s, flags=re.S)))
rev = re.search(r'修正日期：\s*\n\s*(民國[^\n]+)', t).group(1).strip()
url = 'https://law.lia-roc.org.tw/Law/Content?lsid=FL079183'
blocks, left, right = [], [], []
for line in t.splitlines():
    if line.strip().startswith(('├', '└')):
        if left or right: blocks.append((''.join(left), ''.join(right))); left, right = [], []
        continue
    if line.count('│') >= 3:
        cols = line.split('│')
        left.append(cols[1].strip()); right.append(cols[2].strip())
for l, r in blocks:
    m = re.match(r'([一二三四五六七八九十]+)、(.*)', l)
    if not m or '具體基本內容' in r: continue
    n = '一二三四五六七八九十'.index(m.group(1)) + 1 if len(m.group(1)) == 1 else 10
    if n < 3: continue
    r = re.sub(r'（[一二三四五六七八九十]+）其他業法相關規範（如附表\s*1\s*至\s*3）。', '', r)
    add('金融服務業公平待客原則', url, rev, f'原則{m.group(1)}（{m.group(2)}）', f'{m.group(2)}：{r}', m.group(2))
json.dump({'note': '法規原文擷取（逐字）。修改前請對照 url 的現行條文；revised = 來源頁面所示修正日期，fetched = 擷取日。', 'chunks': chunks}, open(OUT, 'w', encoding='utf-8'), ensure_ascii=False, indent=1)
print(len(chunks))
for c in chunks: print(c['cite'], '|', len(c['text']), '|', c['text'][:70].replace('\n', ' / '))

# Off-topic principles (酬金、申訴、專業性、友善、誠信) list other regulations only
d = json.load(open(OUT, encoding="utf-8"))
d["chunks"] = [c for c in d["chunks"] if not any(k in c["ref"] for k in ("原則六", "原則七", "原則八", "原則九", "原則十"))]
json.dump(d, open(OUT, "w", encoding="utf-8"), ensure_ascii=False, indent=1)
