#!/usr/bin/env python3
"""Generate tolerant Dart DTOs from ayeaye's OpenAPI schema.

Tolerant on purpose: the server is a moving target and a mobile client that
throws on an unexpected null is worse than one that renders a blank field.
Every reader goes through the _as* helpers in json.dart.
"""
import json, re, sys, os

SKIP_PREFIX = ('Body_',)
SKIP = {
    'HTTPValidationError', 'ValidationError',
    'OAuthClientMetadata', 'OAuthGrantOut',
    'AuthorizeDecisionIn', 'AuthorizeDecisionOut', 'AuthorizePreviewOut',
}

def camel(s):
    parts = s.split('_')
    return parts[0] + ''.join(p[:1].upper() + p[1:] for p in parts[1:])

RESERVED = {'is', 'in', 'do', 'if', 'for', 'new', 'class', 'default', 'this', 'var', 'with', 'switch', 'return', 'void', 'const', 'final', 'true', 'false', 'null', 'enum', 'extends', 'super', 'assert', 'break', 'case', 'catch', 'continue', 'else', 'while', 'try', 'throw', 'rethrow', 'part', 'show', 'hide'}

def fieldname(s):
    n = camel(s)
    return n + '_' if n in RESERVED else n

class T:
    """A resolved Dart type plus how to read/write it."""
    def __init__(self, dart, kind, nullable, inner=None, ref=None, dateonly=False):
        self.dart, self.kind, self.nullable = dart, kind, nullable
        self.inner, self.ref, self.dateonly = inner, ref, dateonly

    @property
    def decl(self):
        return self.dart + ('?' if self.nullable else '')

def resolve(spec, nullable=False):
    """Map an OpenAPI schema node onto a Dart type."""
    if '$ref' in spec:
        name = spec['$ref'].rsplit('/', 1)[-1]
        return T(name, 'ref', nullable, ref=name)

    if 'anyOf' in spec or 'oneOf' in spec:
        variants = spec.get('anyOf') or spec.get('oneOf')
        nonnull = [v for v in variants if v.get('type') != 'null']
        has_null = len(nonnull) != len(variants)
        if len(nonnull) == 1:
            return resolve(nonnull[0], nullable or has_null)
        # a genuine union (none in this API today) degrades to dynamic
        return T('dynamic', 'dyn', False)

    t = spec.get('type')
    fmt = spec.get('format')
    if t == 'string':
        if fmt == 'date-time':
            return T('DateTime', 'datetime', nullable)
        if fmt == 'date':
            return T('DateTime', 'datetime', nullable, dateonly=True)
        return T('String', 'string', nullable)
    if t == 'integer':
        return T('int', 'int', nullable)
    if t == 'number':
        return T('double', 'double', nullable)
    if t == 'boolean':
        return T('bool', 'bool', nullable)
    if t == 'array':
        inner = resolve(spec.get('items', {}))
        return T(f'List<{inner.decl}>', 'list', nullable, inner=inner)
    if t == 'object' or 'additionalProperties' in spec:
        ap = spec.get('additionalProperties')
        if isinstance(ap, dict) and ap:
            inner = resolve(ap)
            return T(f'Map<String, {inner.decl}>', 'map', nullable, inner=inner)
        return T('Map<String, dynamic>', 'jsonmap', nullable)
    return T('dynamic', 'dyn', False)

def reader(t, expr):
    """Dart expression reading `expr` (a dynamic) as type `t`."""
    if t.kind == 'string':
        return f'asString({expr})' if t.nullable else f"asString({expr}) ?? ''"
    if t.kind == 'int':
        return f'asInt({expr})' if t.nullable else f'asInt({expr}) ?? 0'
    if t.kind == 'double':
        return f'asDouble({expr})' if t.nullable else f'asDouble({expr}) ?? 0'
    if t.kind == 'bool':
        return f'asBool({expr})' if t.nullable else f'asBool({expr}) ?? false'
    if t.kind == 'datetime':
        return f'asDate({expr})' if t.nullable else f'asDate({expr}) ?? DateTime.fromMillisecondsSinceEpoch(0)'
    if t.kind == 'ref':
        inner = f'{t.ref}.fromJson(asMap({expr})!)'
        return f'{expr} == null ? null : {inner}' if t.nullable else f'{t.ref}.fromJson(asMap({expr}) ?? const {{}})'
    if t.kind == 'list':
        it = reader(t.inner, 'e')
        body = f'asList({expr}).map((e) => {it}).toList()'
        return body  # asList tolerates null -> []
    if t.kind == 'map':
        it = reader(t.inner, 'v')
        return f'asMap({expr})?.map((k, v) => MapEntry(k, {it})) ?? const {{}}' if not t.nullable \
            else f'asMap({expr})?.map((k, v) => MapEntry(k, {it}))'
    if t.kind == 'jsonmap':
        return f'asMap({expr})' if t.nullable else f'asMap({expr}) ?? const {{}}'
    return expr

def writer(t, name):
    """Dart expression serialising field `name` of type `t`."""
    if t.kind == 'datetime':
        fn = 'fmtDate' if t.dateonly else 'fmtDateTime'
        return f'{fn}({name})'
    if t.kind == 'ref':
        return f'{name}?.toJson()' if t.nullable else f'{name}.toJson()'
    if t.kind == 'list':
        if t.inner.kind == 'ref':
            return f'{name}{"?" if t.nullable else ""}.map((e) => e.toJson()).toList()'
        return name
    return name

def main():
    spec = json.load(open(sys.argv[1]))
    schemas = spec['components']['schemas']
    out_dir = sys.argv[2]
    os.makedirs(out_dir, exist_ok=True)

    names = [n for n in sorted(schemas)
             if n not in SKIP and not n.startswith(SKIP_PREFIX)]

    # Input models get a toJson; output models get a fromJson. Some need both.
    def is_input(n):
        return bool(re.search(r'(In|Create|Update|Save|Verify|Change|Redeem|Place|Move|Pin)$', n))

    lines = [
        '// GENERATED by tool/gen_models.py from the instance /api/openapi.json.',
        '// Do not edit by hand; re-run the generator instead.',
        "//",
        "// ignore_for_file: unnecessary_this",
        '',
        "import 'json.dart';",
        '',
    ]

    for n in names:
        s = schemas[n]
        props = s.get('properties') or {}
        required = set(s.get('required') or [])
        if not props:
            # a bodyless marker schema; emit an empty class so refs still resolve
            lines += [f'class {n} {{', f'  const {n}();',
                      f'  factory {n}.fromJson(Map<String, dynamic> j) => const {n}();',
                      '  Map<String, dynamic> toJson() => const {};', '}', '']
            continue

        fields = []
        for k, v in props.items():
            nullable = k not in required
            t = resolve(v, nullable=False)
            # explicit anyOf-null already marked it nullable; absent-from-required
            # means the server may omit it, so it is nullable unless it has a
            # default we can fall back on.
            if not t.nullable and nullable and 'default' not in v:
                t = resolve(v, nullable=True)
            fields.append((k, fieldname(k), t, v))

        lines.append(f'class {n} {{')
        lines.append(f'  const {n}({{')
        for _, fn, t, v in fields:
            need = not t.nullable and 'default' not in v and t.kind not in ('list', 'map', 'jsonmap')
            if need:
                lines.append(f'    required this.{fn},')
            else:
                lines.append(f'    this.{fn}{default_for(t, v)},')
        lines.append('  });')
        lines.append('')
        for _, fn, t, _v in fields:
            lines.append(f'  final {t.decl} {fn};')
        lines.append('')
        # fromJson
        lines.append(f'  factory {n}.fromJson(Map<String, dynamic> j) => {n}(')
        for k, fn, t, _v in fields:
            lines.append(f"        {fn}: {reader(t, f'j[{json.dumps(k)}]')},")
        lines.append('      );')
        lines.append('')
        # toJson — omit nulls so PATCH semantics stay "only what I sent"
        lines.append('  Map<String, dynamic> toJson() {')
        lines.append('    final j = <String, dynamic>{};')
        for k, fn, t, _v in fields:
            w = writer(t, fn)
            if t.nullable:
                lines.append(f'    if ({fn} != null) j[{json.dumps(k)}] = {w};')
            else:
                lines.append(f'    j[{json.dumps(k)}] = {w};')
        lines.append('    return j;')
        lines.append('  }')
        lines.append('}')
        lines.append('')

    open(os.path.join(out_dir, 'models.dart'), 'w').write('\n'.join(lines))
    print(f'wrote {len(names)} classes')

def default_for(t, v):
    if t.nullable:
        return ''
    if t.kind == 'list':
        return ' = const []'
    if t.kind in ('map', 'jsonmap'):
        return ' = const {}'
    d = v.get('default')
    if d is None:
        return ''
    if isinstance(d, bool):
        return f' = {str(d).lower()}'
    if isinstance(d, (int, float)):
        return f' = {d}'
    if isinstance(d, str):
        return f' = {json.dumps(d)}'
    return ''

main()
