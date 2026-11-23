#!/usr/bin/env python3
"""Cascade Console core prototype — command line entry point.

Usage:
    python3 cascade_console.py                  interactive console
    python3 cascade_console.py script.ccs       run a script, print results
    python3 cascade_console.py -c "box b 10 20 30" "volume b"

Run with the project venv (~/workspace/stl2step-venv/bin/python) so the
Open CASCADE bindings import.  Errors print as [E<code> NAME] message and
the process exit code is the numeric error code modulo 256 in script/-c
mode, so shells and CI can branch on failure class.
"""

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from cc import CCError, Interpreter, Log  # noqa: E402


def main(argv):
    log_path = os.environ.get("CC_LOG")
    interp = Interpreter(log=Log(log_path) if log_path else None)

    if len(argv) >= 2 and argv[1] == "-c":
        for line in argv[2:]:
            try:
                out = interp.execute(line)
            except CCError as err:
                print(str(err), file=sys.stderr)
                return err.code % 256
            if out:
                print(out)
        return 0

    if len(argv) == 2:
        try:
            print(interp.run_script(argv[1]))
        except CCError as err:
            print(str(err), file=sys.stderr)
            return err.code % 256
        return 0

    if len(argv) > 2:
        print(__doc__, file=sys.stderr)
        return 2

    print("Cascade Console prototype — type 'help', 'quit' to exit.")
    while True:
        try:
            line = input("cc> ")
        except (EOFError, KeyboardInterrupt):
            print()
            return 0
        if line.strip().lower() in ("quit", "exit"):
            return 0
        try:
            out = interp.execute(line)
        except CCError as err:
            print(str(err))
            continue
        if out:
            print(out)


if __name__ == "__main__":
    sys.exit(main(sys.argv))
