"""Source-preserving catalog extractor for the pinned raylib public headers.

This is deliberately a bounded header extractor, not a general C preprocessor.
It retains all conditional alternatives rather than selecting the host's build.
"""
import hashlib
import re
import json
import subprocess

HEADERS = ('raylib.h', 'raymath.h', 'rlgl.h', 'rcamera.h', 'rgestures.h', 'config.h')
IMPLEMENTATION = {'rlgl.h': 'RLGL_IMPLEMENTATION', 'rcamera.h': 'RCAMERA_IMPLEMENTATION',
                  'rgestures.h': 'RGESTURES_IMPLEMENTATION'}


def blank(text):
    return ''.join('\n' if c == '\n' else ' ' for c in text)


def without_comments(text):
    pattern = r'"(?:\\.|[^"\\])*"|\'(?:\\.|[^\'\\])*\'|/\*.*?\*/|//[^\n]*'
    return re.sub(pattern, lambda m: blank(m[0]) if m[0].startswith('/') else m[0], text, flags=re.S)


def normalized(text):
    return ' '.join(text.split())


def close_at(text, at, opening, closing):
    depth = 0
    literal = None
    escape = False
    for i in range(at, len(text)):
        c = text[i]
        if literal:
            if escape:
                escape = False
            elif c == '\\':
                escape = True
            elif c == literal:
                literal = None
        elif c in ('"', "'"):
            literal = c
        elif c == opening:
            depth += 1
        elif c == closing:
            depth -= 1
            if depth == 0:
                return i
    raise ValueError(f'Unclosed {opening} at offset {at}')


def split_top(text, separator=','):
    parts, start, depth = [], 0, 0
    for i, c in enumerate(text):
        if c in '({[':
            depth += 1
        elif c in ')}]':
            depth -= 1
        elif c == separator and depth == 0:
            parts.append(text[start:i].strip())
            start = i + 1
    parts.append(text[start:].strip())
    return [part for part in parts if part]


def directives(text):
    """Return a directive-masked view and source-condition snapshots by line."""
    rows = text.splitlines(keepends=True)
    masked, conditions, definitions = [], {}, []
    stack = []
    i = 0
    while i < len(rows):
        line = i + 1
        conditions[line] = [frame['active'] for frame in stack]
        row = rows[i]
        if not re.match(r'^\s*#', row):
            masked.append(row)
            i += 1
            continue
        logical = row
        consumed = [row]
        while logical.rstrip('\r\n').endswith('\\'):
            i += 1
            if i == len(rows):
                raise ValueError('Unterminated preprocessor continuation')
            conditions[i+1] = list(conditions[line])
            logical = logical.rstrip('\r\n')[:-1] + rows[i]
            consumed.append(rows[i])
        m = re.match(r'^\s*#\s*(\w+)\s*(.*)', logical, re.S)
        command, body = m[1], normalized(m[2])
        if command in ('if', 'ifdef', 'ifndef'):
            expression = body if command == 'if' else ('!' if command == 'ifndef' else '') + f'defined({body})'
            stack.append(dict(previous=[expression], active=expression))
        elif command in ('elif', 'else'):
            if not stack:
                raise ValueError('Unmatched conditional alternative')
            frame = stack[-1]
            prefix = '!( ' + ' || '.join(frame['previous']) + ' )'
            frame['active'] = prefix + (f' && ({body})' if command == 'elif' else '')
            if command == 'elif':
                frame['previous'].append(body)
        elif command == 'endif':
            if not stack:
                raise ValueError('Unmatched #endif')
            stack.pop()
        elif command == 'define':
            definition = re.match(r'([A-Za-z_]\w*)(\([^)]*\))?\s*(.*)', body, re.S)
            if not definition:
                raise ValueError(f'Unrecognized define on line {line}')
            definitions.append(dict(name=definition[1], parameters=definition[2], value=definition[3],
                                    line=line, condition=conditions[line], signature='#define ' + body))
        masked.extend(blank(part) for part in consumed)
        i += 1
    return ''.join(masked), conditions, definitions


def source_context(raw, header, line):
    module, section = {'raylib.h': 'core', 'raymath.h': 'raymath', 'rlgl.h': 'rlgl',
                       'rcamera.h': 'camera', 'rgestures.h': 'gestures', 'config.h': 'configuration'}[header], 'declarations'
    for row in raw.splitlines()[:line]:
        match = re.search(r'\(Module: (\w+)\)', row)
        if match:
            module = {'rcamera':'camera', 'rgestures':'gestures'}.get(match[1], match[1])
        match = re.match(r'// Module:\s*(\w+)\s*-', row)
        if match:
            module = {'rcore':'core', 'rtextures':'textures', 'rshapes':'shapes',
                      'rtext':'text', 'rmodels':'models', 'raudio':'audio'}.get(match[1], match[1])
        if row.startswith('// ') and re.search(r'functions|management|operators|Module Functions Definition', row, re.I):
            if not re.match(r'// (NOTE|WARNING|TODO|Function specifiers)', row):
                section = row[3:].strip()
    return module, section


def extract_header(raw, header):
    clean = without_comments(raw)
    end = len(clean)
    if header in IMPLEMENTATION:
        macro = IMPLEMENTATION[header]
        match = re.search(r'^\s*#\s*(?:if\s+defined\(' + macro + r'\)|ifdef\s+' + macro + r')', clean, re.M)
        if not match:
            raise ValueError(f'Missing public/implementation boundary in {header}')
        end = match.start()
    public = clean[:end]
    code, conditions, macros = directives(public)
    entries = []
    if header in IMPLEMENTATION:
        line = clean.count('\n', 0, clean.index('#', end)) + 1
        name = IMPLEMENTATION[header]
        entries.append(dict(id=f'{header[:-2]}:switch:{name}', header=header, kind='switch',
                            name=name, module=header[:-2], section='Implementation opt-in',
                            line=line, signature=normalized(raw.splitlines()[line-1]), conditions=[]))
    function_bodies = []
    prefix = 'RMAPI' if header == 'raymath.h' else 'RLAPI'
    if header == 'rgestures.h':
        start = re.compile(r'^\s*(?:void|bool|int|float|Vector2)\s+([A-Za-z_]\w*)\s*\(', re.M)
    elif header == 'config.h':
        start = re.compile(r'(?!)')
    else:
        start = re.compile(r'^\s*' + prefix + r'\s+[^\n(;{}]*?\b([A-Za-z_]\w*)\s*\(', re.M)

    def add(kind, name, signature, offset, **extra):
        # Leading whitespace in a match must not shift the declaration location.
        while offset < len(code) and code[offset].isspace():
            offset += 1
        line = code.count('\n', 0, offset) + 1
        module, section = source_context(raw, header, line)
        entries.append(dict(id=f'{header[:-2]}:{kind}:{name}', header=header, kind=kind,
                            name=name, module=module, section=section,
                            signature=normalized(signature), line=line,
                            conditions=conditions.get(line, []), **extra))

    for match in start.finditer(code):
        opening = code.index('(', match.start())
        closing = close_at(code, opening, '(', ')')
        following = closing + 1
        while following < len(code) and code[following].isspace():
            following += 1
        if following >= len(code) or code[following] not in ';{':
            raise ValueError(f'Unsupported function declaration: {header}:{match[1]}')
        add('function', match[1], code[match.start():closing+1], match.start(),
            parameters=normalized(code[opening+1:closing]))
        if code[following] == '{':
            function_bodies.append((following, close_at(code, following, '{', '}') + 1))

    # Retain optional C++ operations as distinct overload contracts.
    for match in re.finditer(r'^\s*inline\s+[^\n{;]+?\b(operator\s*[^\w\s(]+)\s*\(', code, re.M):
        opening = code.index('(', match.start())
        closing = close_at(code, opening, '(', ')')
        signature = normalized(code[match.start():closing+1])
        params = code[opening+1:closing]
        types = ','.join(normalized(re.sub(r'\b\w+\s*$', '', part)) for part in split_top(params))
        operator = re.sub(r'\s+', '', match[1])
        add('operator', operator + '(' + types + ')', signature, match.start())
        brace = code.index('{', closing)
        function_bodies.append((brace, close_at(code, brace, '{', '}') + 1))

    top = list(code)
    for first, last in function_bodies:
        top[first:last] = blank(code[first:last])
    top = ''.join(top)

    covered = []
    for match in re.finditer(r'\btypedef\s+', top):
        if any(first <= match.start() < last for first, last in covered):
            continue
        semicolon = top.find(';', match.end())
        brace = top.find('{', match.end(), semicolon+1)
        if brace >= 0:
            close = close_at(top, brace, '{', '}')
            semicolon = top.index(';', close)
            tail = top[close+1:semicolon].strip()
            if not re.fullmatch(r'\w+', tail):
                raise ValueError(f'Unsupported typedef tail {header}: {tail}')
            name = tail
            declaration = top[match.start():semicolon+1]
            enum = bool(re.match(r'typedef\s+enum\b', declaration))
            body = top[brace+1:close]
            add('enum' if enum else 'type', name, declaration, match.start(),
                members=split_top(body, ',' if enum else ';'))
            if enum:
                previous = None
                cursor = brace + 1
                for member in split_top(body):
                    value = re.fullmatch(r'(\w+)(?:\s*=\s*(.*))?', member, re.S)
                    if not value:
                        raise ValueError(f'Unsupported enum member: {member}')
                    at = top.index(value[1], cursor, close)
                    expression = normalized(value[2]) if value[2] is not None else ('0' if previous is None else f'{previous} + 1')
                    add('enumerator', value[1], member, at, enum=name, value=expression)
                    cursor = at + len(value[1])
                    previous = value[1]
        else:
            if semicolon < 0:
                raise ValueError('Unterminated typedef')
            declaration = top[match.start():semicolon+1]
            callback = re.search(r'\(\s*\*\s*(\w+)\s*\)', declaration)
            name = callback[1] if callback else re.search(r'(\w+)\s*;', declaration)[1]
            kind = 'callback' if callback else ('opaque' if re.match(r'typedef\s+struct\s+\w+\s+\w+;', declaration) else 'alias')
            add(kind, name, declaration, match.start())
        covered.append((match.start(), semicolon+1))

    for match in re.finditer(r'^\s*static\s+constexpr\s+\w+\s+(\w+)\s*=\s*([^;]+);', top, re.M):
        offset = match.start() + len(match[0]) - len(match[0].lstrip())
        add('constant', match[1], match[0], offset, value=normalized(match[2]))

    for macro in macros:
        module, section = source_context(raw, header, macro['line'])
        kind = 'configuration' if header == 'config.h' else 'macro'
        entries.append(dict(id=f'{header[:-2]}:{kind}:{macro["name"]}', header=header,
                            kind=kind, name=macro['name'], module=module, section=section,
                            signature=macro['signature'], line=macro['line'], conditions=macro['condition'],
                            value=macro['value'], parameters=macro['parameters']))
    defined = {macro['name'] for macro in macros}
    switch_pattern = r'(?:RAYMATH_|RLGL_|RCAMERA_|RGESTURES_|GRAPHICS_API_|SUPPORT_|RL_|MAX_)\w+|BUILD_LIBTYPE_SHARED|USE_LIBTYPE_SHARED|EXTERNAL_CONFIG_FLAGS'
    for match in re.finditer(r'^\s*#\s*(?:if|ifdef|ifndef|elif)\b([^\n]*)', public, re.M):
        for switch in re.findall(r'\b(?:' + switch_pattern + r')\b', match[1]):
            if switch not in defined:
                line = public.count('\n', 0, public.index('#', match.start(), match.end())) + 1
                module, section = source_context(raw, header, line)
                entries.append(dict(id=f'{header[:-2]}:switch:{switch}', header=header, kind='switch',
                                    name=switch, module=module, section=section, line=line,
                                    signature=normalized(match[0]), conditions=conditions.get(line, [])))
    if header == 'config.h':
        for match in re.finditer(r'^\s*//\s*#define\s+(\w+)\s+([^\n]+)', raw, re.M):
            line = raw.count('\n', 0, raw.index('//', match.start(), match.end())) + 1
            value = match[2].split('//', 1)[0].strip()
            module, section = source_context(raw, header, line)
            entries.append(dict(id=f'config:configuration:{match[1]}', header=header, kind='configuration',
                                name=match[1], module=module, section=section, line=line,
                                signature=f'#define {match[1]} {value}', value=value,
                                conditions=['documented override (commented out)']))

    grouped = {}
    for entry in entries:
        variant = {key: entry[key] for key in ('line', 'signature', 'conditions', 'value', 'parameters', 'members') if key in entry}
        if entry['id'] not in grouped:
            grouped[entry['id']] = {key: value for key, value in entry.items() if key not in ('conditions', 'value', 'parameters', 'members')}
            grouped[entry['id']]['variants'] = []
            if 'enum' in entry:
                grouped[entry['id']]['enum'] = entry['enum']
        if variant not in grouped[entry['id']]['variants']:
            grouped[entry['id']]['variants'].append(variant)
    return sorted(grouped.values(), key=lambda e: (e['line'], e['kind'], e['name']))


def extract_catalog(source, revision):
    entries, headers = [], {}
    for header in HEADERS:
        path = source / 'src' / header
        raw = path.read_text()
        headers[header] = dict(path=f'src/{header}', sha256=hashlib.sha256(path.read_bytes()).hexdigest())
        entries.extend(extract_header(raw, header))
    for entry in entries:
        entry['source'] = f'https://github.com/raysan5/raylib/blob/{revision}/src/{entry["header"]}#L{entry["line"]}'
    return dict(schema=1, project='raysan5/raylib', version='6.0', revision=revision,
                scope=list(HEADERS), headers=headers, entries=entries)


def clang_audit(source, catalog):
    """Compare functions and active support declarations with compiler ASTs."""
    rows = []
    # Cover inactive typedef/macro alternatives as well as the host's active AST.
    for header in HEADERS:
        clean = without_comments((source / 'src' / header).read_text())
        if header in IMPLEMENTATION:
            macro = IMPLEMENTATION[header]
            clean = clean[:re.search(r'^\s*#\s*(?:if\s+defined\(' + macro + r'\)|ifdef\s+' + macro + r')', clean, re.M).start()]
        support = [entry for entry in catalog['entries'] if entry['header'] == header]
        for pattern, kinds in [(r'^[ \t]*typedef\b', ('type', 'alias', 'opaque', 'enum', 'callback')),
                               (r'^[ \t]*#\s*define\b', ('macro', 'configuration')),
                               (r'^[ \t]*static constexpr\b', ('constant',))]:
            lines = {clean.count('\n', 0, match.start()) + 1 for match in re.finditer(pattern, clean, re.M)}
            recorded = {variant['line'] for entry in support if entry['kind'] in kinds for variant in entry['variants']}
            if lines - recorded:
                raise ValueError(f'{header}: support declarations missing at lines {sorted(lines-recorded)}')
    configurations = [('raylib.h', 'c', []), ('raymath.h', 'c', []), ('rlgl.h', 'c', []),
                      ('rcamera.h', 'c', ['-DRCAMERA_STANDALONE', '-include', 'stdbool.h']),
                      ('rgestures.h', 'c', ['-DRGESTURES_STANDALONE']), ('raymath.h', 'c++', [])]
    for header, language, flags in configurations:
        command = ['clang', '-x', language, '-std=' + ('c++17' if language == 'c++' else 'c11'),
                   '-Xclang', '-ast-dump=json', '-fsyntax-only', *flags, str(source / 'src' / header)]
        result = subprocess.run(command, text=True, capture_output=True, timeout=90)
        if result.returncode:
            raise ValueError(f'Clang audit failed for {header}: {result.stderr[-2000:]}')
        declarations = []
        def walk(node):
            location = node.get('loc', {})
            location = location.get('expansionLoc', location)
            if node.get('kind') in ('FunctionDecl', 'TypedefDecl', 'EnumConstantDecl', 'VarDecl') and location and not location.get('includedFrom'):
                declarations.append(node)
            for child in node.get('inner', []):
                walk(child)
        walk(json.loads(result.stdout))
        functions = [node for node in declarations if node['kind'] == 'FunctionDecl']
        actual = {node['name'] for node in functions if not node['name'].startswith('operator')}
        expected = {entry['name'] for entry in catalog['entries'] if entry['header'] == header and entry['kind'] == 'function'}
        if actual != expected:
            raise ValueError(f'{header}: AST/catalog mismatch: missing={sorted(actual-expected)}, extra={sorted(expected-actual)}')
        operators = [node for node in functions if node['name'].startswith('operator')]
        if language == 'c++':
            expected_operators = [entry for entry in catalog['entries'] if entry['header'] == header and entry['kind'] == 'operator']
            actual_signatures = {re.sub(r'\s+', '', node['name'] + '(' + ','.join(
                child['type']['qualType'] for child in node.get('inner', []) if child.get('kind') == 'ParmVarDecl') + ')') for node in operators}
            expected_signatures = {re.sub(r'\s+', '', entry['name']) for entry in expected_operators}
            if actual_signatures != expected_signatures:
                raise ValueError('C++ overload signatures differ from the compiler AST')
        for ast_kind, kinds in [('TypedefDecl', ('type', 'enum', 'alias', 'opaque', 'callback')),
                                ('EnumConstantDecl', ('enumerator',))]:
            active = {node['name'] for node in declarations if node['kind'] == ast_kind}
            support = {entry['name'] for entry in catalog['entries'] if entry['header'] == header and entry['kind'] in kinds}
            if active - support:
                raise ValueError(f'{header}: active {ast_kind} missing from catalog: {sorted(active-support)}')
        if language == 'c++':
            constants = {node['name'] for node in declarations if node['kind'] == 'VarDecl' and node.get('constexpr')}
            expected_constants = {entry['name'] for entry in catalog['entries'] if entry['header'] == header and entry['kind'] == 'constant'}
            if constants != expected_constants:
                raise ValueError(f'{header}: C++ constants differ from the compiler AST')
        rows.append(dict(header=header, language=language, functions=len(actual), operators=len(operators), passed=True))
    return rows
