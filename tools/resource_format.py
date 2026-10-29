import struct
def parse(path):
    data = path.read_bytes()
    pos = 24

    def u(fmt):
        nonlocal pos
        v = struct.unpack_from(fmt, data, pos)
        pos += struct.calcsize(fmt)
        return v[0] if len(v) == 1 else v

    def s():
        nonlocal pos
        end = data.index(0, pos)
        v = data[pos:end].decode('utf8')
        pos = end + 1
        return v
    na, ne, nd = u('<III')
    arcs = []
    for _ in range(na):
        name = s()
        folders = [s() for _ in range(u('<I'))]
        size = u('<I')
        arcs.append(dict(name=name, folders=folders, size=size))
    arc_end = pos
    entries = []
    for _ in range(ne):
        start = pos
        t = u('<H')
        if t == 0:
            arc, offset, unpacked, packed = u('<HIII')
            n, key = u('<BB')
            e = dict(type='file', arc=arc, offset=offset, unpacked=unpacked, packed=packed)
        elif t == 8:
            count, first = u('<HI')
            n, key = u('<BB')
            e = dict(type='folder', count=count, first=first)
        else:
            raise ValueError((path, pos, t))
        e['name'] = bytes((x ^ key for x in data[pos:pos + n - 1])).decode('utf8')
        pos += n
        e['start'] = start
        e['end'] = pos
        entries.append(e)
    assert pos + nd * 20 + 8 == len(data), (pos, nd, len(data))
    paths = {}

    def walk(i, prefix=''):
        e = entries[i]
        p = (prefix + '/' + e['name']).lstrip('/')
        if e['type'] == 'file':
            paths[p.replace('\\', '/').lower()] = i
        else:
            for child in range(e['first'], e['first'] + e['count']):
                walk(child, p)
    walk(0)
    return dict(data=data, arcs=arcs, entries=entries, paths=paths, arc_end=arc_end, entries_end=pos, guid=data[8:24])

def lng_raw(data):
    p = 24
    chars = []
    while data[p:p + 2] != b'\x00\x00':
        chars.append(data[p:p + 2].decode('utf-16le'))
        p += 2
    p += 2
    payload_len = struct.unpack_from('<I', data, p)[0]
    p += 4
    assert payload_len == len(data) - p
    start = p
    pairs = []
    while p < len(data):
        end = data.index(0, p)
        key = data[p:end]
        p = end + 1
        end = data.index(0, p)
        value = data[p:end]
        p = end + 1
        pairs.append((key, value))
    assert p == len(data)
    return (chars, start, pairs)

def decode_text(raw, chars):
    assert all((b == 1 or 2 <= b < len(chars) + 2 for b in raw))
    return ''.join(('\n' if b == 1 else chars[b - 2] for b in raw))
