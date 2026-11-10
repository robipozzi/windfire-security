"""tests/suite_report.py: the per-test summary that run-test-suite.sh prints from the JUnit reports"""
import re

import suite_report

ANSI = re.compile(r"\033\[[0-9;]*m")

REPORT = """<?xml version="1.0" encoding="utf-8"?>
<testsuites><testsuite name="pytest">
  <testcase classname="live.test_auth_endpoint" name="test_valid_credentials_return_a_token" />
  <testcase classname="live.test_auth_endpoint" name="test_bad_credentials_are_rejected">
    <failure message="AssertionError: expected 401&#10;second line">traceback</failure>
  </testcase>
  <testcase classname="live.test_health_tls" name="test_tls_handshake">
    <error message="failed on setup with &quot;login failed&quot;">traceback</error>
  </testcase>
  <testcase classname="live.test_client_library" name="test_authenticate_returns_token">
    <skipped type="pytest.skip" message="client not installed">skip</skipped>
  </testcase>
  <testcase classname="unit.test_shell_scripts" name="test_bash_syntax[a.sh]" />
  <testcase classname="unit.test_shell_scripts" name="test_bash_syntax[b.sh]" />
  <testcase classname="unit.test_shell_scripts" name="test_shellcheck_errors[a.sh]">
    <skipped type="pytest.skip" message="shellcheck not installed" />
  </testcase>
  <testcase classname="unit.test_shell_scripts" name="test_shellcheck_errors[b.sh]">
    <skipped type="pytest.skip" message="shellcheck not installed" />
  </testcase>
  <testcase classname="unit.test_api.TestHealth" name="test_health[x]" />
  <testcase classname="unit.test_api.TestHealth" name="test_health[y]">
    <failure message="boom" />
  </testcase>
</testsuite></testsuites>
"""


def _write(tmp_path, text=REPORT):
    path = tmp_path / "report.xml"
    path.write_text(text)
    return path


def test_group_and_test_names():
    assert suite_report.group_name("live.test_auth_endpoint") == "Auth endpoint"
    assert suite_report.group_name("live.test_health_tls") == "Health TLS"
    assert suite_report.group_name("unit.test_api.TestHealth") == "API"
    assert suite_report.split_name("test_bash_syntax[run.sh]") == ("bash syntax", "run.sh")
    assert suite_report.split_name("test_jwks_has_rs256_signing_key") == ("JWKS has RS256 signing key", None)


def test_statuses_and_reasons(tmp_path):
    rows = suite_report.read_report(_write(tmp_path))
    by_name = {(row[1], row[2]): (row[3], row[4]) for row in rows}
    assert by_name[("valid credentials return a token", None)] == ("PASS", "")
    assert by_name[("bad credentials are rejected", None)] == ("FAIL", "AssertionError: expected 401")
    assert by_name[("TLS handshake", None)] == ("FAIL", 'failed on setup with "login failed"')
    assert by_name[("authenticate returns token", None)] == ("SKIP", "client not installed")


def test_parametrized_cases_collapse_only_when_they_agree(tmp_path):
    lines = suite_report.summary_lines(suite_report.read_report(_write(tmp_path)))
    labels = {label: (status, detail) for label, status, detail in lines}
    assert labels["Shell scripts / bash syntax"] == ("PASS", "2 cases")
    assert labels["Shell scripts / shellcheck errors"] == ("SKIP", "2 cases: shellcheck not installed")
    assert labels["API / health [x]"] == ("PASS", "")
    assert labels["API / health [y]"] == ("FAIL", "boom")
    assert "API / health" not in labels


def test_totals_count_every_case(tmp_path):
    total, counts = suite_report.totals(suite_report.read_report(_write(tmp_path)))
    assert total == 10
    assert counts == {"PASS": 4, "FAIL": 3, "SKIP": 3}


def test_render(tmp_path):
    text = ANSI.sub("", "\n".join(suite_report.render("Live tier (dev)", _write(tmp_path))))
    assert text.splitlines()[0] == "===> Live tier (dev) <==="
    assert "Total: 10  Passed: 4  Failed: 3  Skipped: 3" in text


def test_missing_or_empty_report(tmp_path):
    missing = ANSI.sub("", "\n".join(suite_report.render("Offline tier", tmp_path / "nope.xml")))
    assert "No test report" in missing
    empty = _write(tmp_path, '<testsuites><testsuite name="pytest" /></testsuites>')
    assert "No test selected" in ANSI.sub("", "\n".join(suite_report.render("Offline tier", empty)))
