#!/usr/bin/env python3
"""Bounded, untrusted native-build diagnostics; never determines a CI verdict."""

import argparse
from collections import OrderedDict
import re
from pathlib import Path

ANSI = re.compile(r"\x1b\[[0-?]*[ -/]*[@-~]")
STAGES = (
    "target evaluation",
    "reference build",
    "reference output validation",
    "macOS bundle validation",
    "independent rebuild",
    "reproducibility mismatch",
    "runtime tests",
)
TITLE = re.compile(r"^Native verification: (.{1,160}) \[([^\]]+)\]$")
SYSTEM = re.compile(r"^(?:x86_64-linux|aarch64-linux|aarch64-darwin)$")
# Most specific diagnostics precede wrappers such as Cargo's 'build script failed'.
PATTERNS = (
    re.compile(r"\bThe system library .{1,240} was not found\b", re.I),
    re.compile(r"\bAWS_LC_SYS_USE_SYSTEM=1 requires .{1,240}", re.I),
    re.compile(
        r"\bThe environment variable .{1,100} has been set but no compatible .{1,180}",
        re.I,
    ),
    re.compile(r"\bCan't probe for .{1,200}", re.I),
    re.compile(r"\bHunk #\d+ FAILED\b.{0,180}", re.I),
    re.compile(r"\berror\[E\d+\]: .{1,230}", re.I),
    re.compile(r"\bfatal error: .{1,220}", re.I),
    re.compile(
        r"\berror: (?!Cannot build|failed to run custom build command).{1,230}", re.I
    ),
    re.compile(r"\berror: failed to run custom build command .{1,200}", re.I),
)


def extract_error(lines):
    """Return one evidence line, or empty; do not invent an explanation."""
    best = None
    for line in lines:
        line = ANSI.sub("", line).strip()[:1200]
        for rank, pattern in enumerate(PATTERNS):
            match = pattern.search(line)
            if match and (best is None or rank < best[0]):
                best = (rank, match.group(0).strip()[:260])
                break
    return best[1] if best else ""


def from_log(path):
    # Logs are untrusted, potentially large, and need not be fully read.
    limit = 16 * 1024 * 1024

    def lines():
        with Path(path).open("r", encoding="utf-8", errors="replace") as stream:
            seen = 0
            while seen < limit:
                line = stream.readline(min(4096, limit - seen))
                if not line:
                    break
                seen += len(line)
                yield line

    return extract_error(lines())


def safe_text(value, max_length=260):
    """Escape untrusted text for inline Markdown and disable @mentions."""
    value = re.sub(r"[\x00-\x1f\x7f]", " ", str(value))[:max_length]
    value = value.replace("@", "@\u200b")
    return re.sub(r"([\\`*_{}\[\]()<>!|])", r"\\\1", value)


def command_escape(text, *, property=False):
    text = str(text)[:400]
    text = re.sub(r"[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]", " ", text)
    text = text.replace("%", "%25").replace("\r", "%0D").replace("\n", "%0A")
    if property:
        text = text.replace(":", "%3A").replace(",", "%2C")
    return text


def annotation(label, stage, hint):
    if stage not in STAGES:
        raise ValueError("Unknown verification stage")
    title = f"Native verification: {label[:160]} [{stage}]"
    # Annotation contents are evidence from the unprivileged job, never a verdict.
    message = hint or "See this job's native build log for the failure."
    return f"::error title={command_escape(title, property=True)}::{command_escape(message)}"


def render_job_failures(jobs, repo, run_id, fetch_annotations):
    """Format failed jobs without following job-supplied URLs or trusting log claims."""
    failures = [
        j
        for j in jobs
        if j.get("conclusion") == "failure"
        and isinstance(j.get("id"), int)
        and j["id"] > 0
        and isinstance(j.get("name"), str)
    ]
    native = [j for j in failures if j["name"].startswith("Rebuild: ")]
    other = [
        j
        for j in failures
        if not j["name"].startswith("Rebuild: ")
        and j["name"] != "Package verification gate"
    ]
    if native:
        # A failing gate is downstream of native jobs, not a second build error.
        failures = native + other
    else:
        failures = other or failures
    grouped = OrderedDict()
    for job in failures[:20]:
        name = job["name"]
        match = re.fullmatch(r"Rebuild: ([^ ]+) / (.{1,160})", name)
        system, label = (
            match.groups() if match and SYSTEM.fullmatch(match[1]) else ("", name)
        )
        stage, hint = "", ""
        check_url = job.get("check_run_url", "")
        valid = re.fullmatch(
            rf"https://api\.github\.com/repos/{re.escape(repo)}/check-runs/(\d+)",
            check_url if isinstance(check_url, str) else "",
        )
        if valid and match:
            try:
                # One request per failed native job; fail open for commentary ONLY.
                notes = fetch_annotations(int(valid[1]))[:30]
                for note in notes:
                    if note.get("annotation_level") != "failure":
                        continue
                    title = TITLE.fullmatch(note.get("title") or "")
                    if (
                        not title
                        or title[2] not in STAGES
                        or (
                            title[1] != label
                            and not (
                                label == "opendeck-core + opendeck"
                                and title[1] in ("opendeck-core", "opendeck")
                            )
                        )
                    ):
                        continue
                    label, stage, hint = (
                        title[1],
                        title[2],
                        str(note.get("message") or "")[:260],
                    )
                    if hint == "See this job's native build log for the failure.":
                        hint = ""
                    break
            except (OSError, ValueError, TypeError, KeyError):
                pass
        # Group only when an actual, identical diagnostic line was extracted.
        key = (label, stage, hint) if hint else (label, system, job["id"])
        record = grouped.setdefault(
            key,
            {
                "label": label,
                "stage": stage,
                "hint": hint,
                "jobs": [],
                "blocked": False,
            },
        )
        record["jobs"].append((system, job["id"]))
        if (
            match
            and match[2] == "opendeck-core + opendeck"
            and label == "opendeck-core"
        ):
            record["blocked"] = True

    if not grouped:
        return "No failed jobs were reported; see the workflow run.\n"
    lines = [
        "**Failed jobs** (CI-reported diagnostics, not independent root-cause analyses):",
        "",
    ]
    for record in grouped.values():
        link_items = []
        for system, job_id in record["jobs"]:
            name = safe_text(system or "job", 40)
            link_items.append(
                f"[{name}](https://github.com/{repo}/actions/runs/{run_id}/job/{job_id})"
            )
        lines.append(
            f"- **{safe_text(record['label'], 160)}** — {', '.join(link_items)}"
        )
        if record["stage"]:
            detail = (
                f"{record['stage']}: {record['hint']}"
                if record["hint"]
                else record["stage"]
            )
            lines.append(f"  - {safe_text(detail, 340)}")
        if record["blocked"]:
            lines.append(
                "  - Wrapped OpenDeck verification was blocked by the core failure."
            )
    if len(failures) > 20:
        lines.append(
            f"- {len(failures) - 20} additional failed jobs; see the workflow run."
        )
    lines += [
        "",
        "Job annotations and full logs remain available via the links above.",
        "",
    ]
    return "\n".join(lines)


def render_update_diagnostics(items):
    """Compact an updater issue's excerpts without conflating unknown failures."""
    grouped = OrderedDict()
    for item in items:
        hint = extract_error(str(item.get("excerpt", "")).splitlines())
        key = (
            (item["label"], item["phase"], hint)
            if hint
            else (item["label"], item["phase"], item["system"])
        )
        group = grouped.setdefault(key, {"sample": item, "systems": [], "hint": hint})
        if item["system"] not in group["systems"]:
            group["systems"].append(item["system"])
    lines = []
    remaining = 46000
    for group in grouped.values():
        if remaining <= 0:
            lines.append("Additional excerpts omitted; consult the workflow logs.")
            break
        item = group["sample"]
        systems = ", ".join(group["systems"])
        heading = (
            f"**{safe_text(item['label'], 160)}** "
            f"({safe_text(systems, 160)}, {safe_text(item['phase'], 80)})"
        )
        summary = group["hint"] or str(item.get("error", "build failed"))
        lines.extend([heading, f"Highlighted error: {safe_text(summary)}", ""])
        excerpt = (
            str(item.get("excerpt", "")).strip() or "No additional output captured."
        )
        excerpt = excerpt.replace("```", "[code fence]").replace("@", "@\u200b")
        excerpt = excerpt[-min(3500, remaining) :]
        remaining -= len(excerpt)
        lines.extend(["```text", excerpt, "```", ""])
        if len(group["systems"]) > 1:
            lines.extend(
                [
                    "One representative excerpt shown; see each native job for full logs.",
                    "",
                ]
            )
    return lines


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="command", required=True)
    x = sub.add_parser("extract")
    x.add_argument("log")
    a = sub.add_parser("annotate")
    a.add_argument("--label", required=True)
    a.add_argument("--stage", choices=STAGES, required=True)
    a.add_argument("--hint", default="")
    args = parser.parse_args()
    if args.command == "extract":
        print(from_log(args.log))
    else:
        print(annotation(args.label, args.stage, args.hint))


if __name__ == "__main__":
    main()
