"""Fictional Files-provider fixtures; no session or permission record generation."""
import hashlib
import io
import struct
import zipfile
import zlib

TITLE = '# Folio GUI 合成验收'
TEXT = TITLE + '\r\n\r\n虚构订单：纸飞机 3 架，金额 12 元。\r\n\r\n| 项目 | 数量 |\r\n| --- | ---: |\r\n| 纸飞机 | 3 |\r\n\r\n- [ ] 验收条目\r\n\r\n![合成红蓝方块](assets/pixel.png)\r\n\r\n外部版本：BASE\r\n'
EXTERNAL_TEXT = TEXT.replace('外部版本：BASE', '外部版本：EXTERNAL-CONFLICT')

def chunk(kind, data):
    return struct.pack('>I', len(data)) + kind + data + struct.pack('>I', zlib.crc32(kind + data))

def files():
    pixels = b''.join(b'\0' + b''.join(bytes((220,60,70)) if (x//8+y//8)%2 else bytes((40,100,220)) for x in range(32)) for y in range(32))
    png = b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB',32,32,8,2,0,0,0)) + chunk(b'IDAT',zlib.compress(pixels)) + chunk(b'IEND',b'')
    return {'FolioGUIFixture/folio-gui.md': b'\xef\xbb\xbf' + TEXT.encode(),
            'FolioGUIFixture/assets/pixel.png': png,
            'FolioGUIFixture/README.txt': '全部材料均为虚构。请通过 Files 系统选择器打开 folio-gui.md，再明确选择 FolioGUIFixture 授权图片目录。\n'.encode()}

def archive():
    out=io.BytesIO()
    with zipfile.ZipFile(out,'w',compression=zipfile.ZIP_STORED) as z:
        for name,data in sorted(files().items()):
            info=zipfile.ZipInfo(name,date_time=(2026,10,3,0,0,0));info.external_attr=0o100600<<16
            z.writestr(info,data)
    return out.getvalue()

def manifest():
    digest=lambda data:hashlib.sha256(data).hexdigest()
    return {'files':{name:{'sha256':digest(data),'bytes':len(data)} for name,data in files().items()},
            'zip_sha256':digest(archive()),'encoding':'UTF-8 BOM; CRLF Markdown',
            'scope':'fictional document and generated RGB image only; zero permission/session metadata'}
