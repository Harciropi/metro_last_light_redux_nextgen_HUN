"""Encode the editable local Hungarian text into the current installer payload."""
from pathlib import Path
import argparse,json,struct
from resource_format import lng_raw,decode_text
parser=argparse.ArgumentParser();parser.add_argument('--check',action='store_true');args=parser.parse_args()
ROOT=Path(__file__).resolve().parents[1]
source=ROOT/'.private/source'
original=(source/'original/stable_us.lng').read_bytes()
chars,start,pairs=lng_raw(original)
rows=json.loads((source/'hungarian.json').read_text(encoding='utf8'))
assert len(rows)==len(pairs) and all(r['key_hex']==k.hex() for r,(k,v) in zip(rows,pairs))
chars=[c.translate(str.maketrans('ôÔûÛ','őŐűŰ')) for c in chars]
codec={c:bytes([i+2]) for i,c in enumerate(chars)};codec['\n']=b'\x01'
data=b''.join(k+b'\0'+b''.join(codec[c] for c in r['text'])+b'\0' for r,(k,v) in zip(rows,pairs))
prefix=bytearray(original[:start-4]);prefix[24:24+2*len(chars)]=''.join(chars).encode('utf-16le')
result=bytes(prefix)+struct.pack('<I',len(data))+data
check,_,encoded=lng_raw(result)
assert [decode_text(v,check) for k,v in encoded]==[r['text'] for r in rows]
target=ROOT/'installer/payload/stable_us.lng'
if args.check:assert target.read_bytes()==result,'The editable translation differs from the installer payload'
else:target.write_bytes(result)
assert [k for k,v in encoded]==[k for k,v in pairs]
duplicates=len(rows)-len({k for k,v in encoded})
print(f'{len(rows)} entries, {duplicates} duplicate occurrences; key order, text and control markers verified exactly.')
