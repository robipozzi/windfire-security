"""
Per-test summary of one tier of the Windfire Security test suite, built from its pytest JUnit XML report.

    python suite_report.py "<tier label>" <junit.xml>

Prints every test as `Group / test name  PASS|FAIL|SKIP (reason)`, like the Windfire Calendar test application,
then the totals. Cases of a parametrized test are collapsed into one row when they all end the same way.
Always exits 0: the tier result is decided by pytest's exit code, not by this report.
"""
import sys
import xml.etree.ElementTree as ET
from collections import OrderedDict

RESET = "\033[0m"
BOLD = "\033[1m"
COLORS = {"PASS": "\033[32m", "FAIL": "\033[31m", "SKIP": "\033[33m"}
BLUE = "\033[34m"
REASON_MAX = 200
ACRONYMS = {"api": "API", "tls": "TLS", "jwks": "JWKS", "jwt": "JWT", "rs256": "RS256", "oidc": "OIDC"}


def _words(identifier):
    return [ACRONYMS.get(word, word) for word in identifier.split("_") if word]


def group_name(classname):
    """live.test_auth_endpoint -> Auth endpoint (a test class, if any, is ignored)"""
    parts = classname.split(".")
    module = next((p for p in parts if p.startswith("test_")), parts[-1])
    words = _words(module.removeprefix("test_"))
    if not words:
        return module
    first = words[0] if words[0].isupper() else words[0].capitalize()
    return " ".join([first] + words[1:])


def split_name(name):
    """test_bash_syntax[run.sh] -> ("bash syntax", "run.sh")"""
    base, _, param = name.partition("[")
    return " ".join(_words(base.removeprefix("test_"))), param[:-1] if param.endswith("]") else None


def _reason(element):
    text = element.get("message") or (element.text or "")
    text = text.strip().splitlines()[0] if text.strip() else ""
    return text[:REASON_MAX] or element.tag


def case_status(testcase):
    for tag, status in (("failure", "FAIL"), ("error", "FAIL"), ("skipped", "SKIP")):
        element = testcase.find(tag)
        if element is not None:
            return status, _reason(element)
    return "PASS", ""


def read_report(path):
    """[(group, test, param, status, reason)] in execution order"""
    root = ET.parse(path).getroot()
    rows = []
    for testcase in root.iter("testcase"):
        test, param = split_name(testcase.get("name", ""))
        status, reason = case_status(testcase)
        rows.append((group_name(testcase.get("classname", "")), test, param, status, reason))
    return rows


def summary_lines(rows):
    """[(label, status, detail)]: parametrized cases with one shared outcome become a single row"""
    by_test = OrderedDict()
    for group, test, param, status, reason in rows:
        by_test.setdefault((group, test), []).append((param, status, reason))
    lines = []
    for (group, test), cases in by_test.items():
        label = f"{group} / {test}"
        outcomes = {(status, reason) for _, status, reason in cases}
        if len(cases) == 1 or len(outcomes) == 1:
            _, status, reason = cases[0]
            detail = reason
            if len(cases) > 1:
                detail = f"{len(cases)} cases" + (f": {reason}" if reason else "")
            lines.append((label, status, detail))
        else:
            for param, status, reason in cases:
                lines.append((f"{label} [{param}]", status, reason))
    return lines


def totals(rows):
    counts = {status: sum(1 for row in rows if row[3] == status) for status in ("PASS", "FAIL", "SKIP")}
    return len(rows), counts


def render(label, path):
    out = [f"{BOLD}{BLUE}===> {label} <==={RESET}"]
    try:
        rows = read_report(path)
    except (OSError, ET.ParseError) as e:
        out.append(f"  {COLORS['SKIP']}No test report ({e}){RESET}")
        return out
    if not rows:
        out.append(f"  {COLORS['SKIP']}No test selected{RESET}")
        return out
    lines = summary_lines(rows)
    width = max(len(text) for text, _, _ in lines)
    for text, status, detail in lines:
        out.append(f"  {COLORS[status]}{text.ljust(width)}  {status}{f'  ({detail})' if detail else ''}{RESET}")
    total, counts = totals(rows)
    color = COLORS["FAIL"] if counts["FAIL"] else COLORS["PASS"]
    out.append(f"  {BOLD}{color}Total: {total}  Passed: {counts['PASS']}  "
               f"Failed: {counts['FAIL']}  Skipped: {counts['SKIP']}{RESET}")
    return out


def main(argv):
    if len(argv) != 3:
        print(f"usage: {argv[0]} <tier label> <junit.xml>", file=sys.stderr)
        return 0
    print("\n".join(render(argv[1], argv[2])))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
