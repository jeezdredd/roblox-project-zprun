import argparse
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
LONG_OPEN = re.compile(r"\[(=*)\[")
CLOSERS = ("end", "else", "elseif", "until", "}", ")")


class LexError(Exception):
    pass


def long_bracket_end(text, start, level):
    closing = "]" + "=" * level + "]"
    end = text.find(closing, start)
    if end < 0:
        raise LexError(f"unterminated long bracket at offset {start}")
    return end + len(closing)


def quoted_end(text, start, quote):
    index = start + 1
    while index < len(text):
        char = text[index]
        if char == "\\":
            index += 2
            continue
        if char == quote:
            return index + 1
        if char == "\n":
            raise LexError(f"unterminated string at offset {start}")
        index += 1
    raise LexError(f"unterminated string at offset {start}")


def interpolated_end(text, start):
    index = start + 1
    while index < len(text):
        char = text[index]
        if char == "\\":
            index += 2
            continue
        if char == "`":
            return index + 1
        if char == "{":
            index = code_until_brace(text, index + 1)
            continue
        index += 1
    raise LexError(f"unterminated interpolated string at offset {start}")


def code_until_brace(text, start):
    depth = 0
    index = start
    while index < len(text):
        char = text[index]
        if text.startswith("--", index):
            raise LexError(f"comment inside interpolation at offset {index}")
        if char in "'\"":
            index = quoted_end(text, index, char)
            continue
        if char == "`":
            index = interpolated_end(text, index)
            continue
        match = LONG_OPEN.match(text, index)
        if match:
            index = long_bracket_end(text, match.end(), len(match.group(1)))
            continue
        if char == "{":
            depth += 1
        elif char == "}":
            if depth == 0:
                return index + 1
            depth -= 1
        index += 1
    raise LexError(f"unterminated interpolation at offset {start}")


def segments(text):
    result = []
    index = 0
    code_start = 0
    while index < len(text):
        char = text[index]
        if text.startswith("--", index):
            if index > code_start:
                result.append(("code", text[code_start:index]))
            match = LONG_OPEN.match(text, index + 2)
            if match:
                end = long_bracket_end(text, match.end(), len(match.group(1)))
            else:
                end = text.find("\n", index)
                end = len(text) if end < 0 else end
            result.append(("comment", text[index:end]))
            index = end
            code_start = index
            continue
        if char in "'\"":
            end = quoted_end(text, index, char)
        elif char == "`":
            end = interpolated_end(text, index)
        else:
            match = LONG_OPEN.match(text, index)
            end = long_bracket_end(text, match.end(), len(match.group(1))) if match else None
        if end is not None:
            if index > code_start:
                result.append(("code", text[code_start:index]))
            result.append(("string", text[index:end]))
            index = end
            code_start = index
            continue
        index += 1
    if code_start < len(text):
        result.append(("code", text[code_start:]))
    return result


def is_directive(comment):
    return comment.startswith("--!")


def strip(text):
    parts = segments(text)
    kept = []
    for kind, body in parts:
        if kind == "comment" and not is_directive(body):
            kept.append(("removed", ""))
        else:
            kept.append((kind, body))
    rebuilt = []
    removed_on_line = []
    line = []
    removed = False
    for kind, body in kept:
        if kind == "removed":
            removed = True
            continue
        chunks = body.split("\n")
        for position, chunk in enumerate(chunks):
            if position > 0:
                rebuilt.append("".join(line))
                removed_on_line.append(removed)
                line = []
                removed = False
            line.append(chunk)
    rebuilt.append("".join(line))
    removed_on_line.append(removed)
    output = []
    dropped = []
    for content, had_comment in zip(rebuilt, removed_on_line):
        if had_comment and content.strip() == "":
            dropped.append(True)
            output.append(None)
        else:
            output.append(content.rstrip() if had_comment else content)
            dropped.append(False)
    lines = []
    previous_dropped = False
    for content, was_dropped in zip(output, dropped):
        if was_dropped:
            previous_dropped = True
            continue
        if previous_dropped and content.strip() == "" and lines and lines[-1].strip() == "":
            previous_dropped = False
            continue
        if previous_dropped and lines and lines[-1].strip() == "" and content.strip().startswith(CLOSERS):
            lines.pop()
        previous_dropped = False
        lines.append(content)
    return "\n".join(lines)


def signature(text):
    pieces = []
    for kind, body in segments(text):
        if kind == "comment":
            if is_directive(body):
                pieces.append(body)
            continue
        if kind == "string":
            pieces.append(body)
        else:
            pieces.append(re.sub(r"\s+", " ", body))
    return re.sub(r"\s+", " ", " ".join(pieces)).strip()


def comments(text):
    found = []
    offset_line = 1
    for kind, body in segments(text):
        if kind == "comment" and not is_directive(body):
            found.append({"line": offset_line, "text": body})
        offset_line += body.count("\n")
    return found


def luau_files(paths):
    for raw in paths:
        path = Path(raw)
        if path.is_dir():
            yield from sorted(path.rglob("*.luau"))
        elif path.suffix == ".luau":
            yield path


def main():
    parser = argparse.ArgumentParser(description="Remove Luau comments except --! directives, or check that none remain.")
    parser.add_argument("paths", nargs="*", default=["src"])
    parser.add_argument("--check", action="store_true", help="exit 1 if any comment remains, change nothing")
    parser.add_argument("--dump", metavar="JSON", help="write every comment with file and line to JSON, change nothing")
    args = parser.parse_args()
    failures = 0
    offenders = []
    dump = {}
    changed = 0
    for path in luau_files(args.paths):
        text = path.read_text(encoding="utf-8")
        try:
            found = comments(text)
        except LexError as error:
            print(f"lex error {path}: {error}", file=sys.stderr)
            failures += 1
            continue
        relative = str(path.resolve().relative_to(ROOT))
        if args.dump:
            if found:
                dump[relative] = found
            continue
        if args.check:
            if found:
                offenders.append((relative, len(found), found[0]["line"]))
            continue
        if not found:
            continue
        result = strip(text)
        if signature(result) != signature(text):
            print(f"token mismatch, left unchanged: {relative}", file=sys.stderr)
            failures += 1
            continue
        if comments(result):
            print(f"comments survived, left unchanged: {relative}", file=sys.stderr)
            failures += 1
            continue
        path.write_text(result, encoding="utf-8")
        changed += 1
    if args.dump:
        Path(args.dump).write_text(json.dumps(dump, indent=1, ensure_ascii=False), encoding="utf-8")
        print(f"dumped {sum(len(v) for v in dump.values())} comments from {len(dump)} files")
    elif args.check:
        for relative, count, first in offenders:
            print(f"{relative}:{first}: {count} comment(s)")
        if offenders:
            print(f"{len(offenders)} file(s) contain comments; run python3 tools/strip_comments.py", file=sys.stderr)
            failures += 1
    else:
        print(f"stripped {changed} file(s)")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
