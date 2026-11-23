"""Structured errors for Cascade Console.

Every failure raised inside the interpreter or the geometry backend is a
``CCError`` carrying a *distinct numeric code*, a stable machine-readable
``code_name``, and a plain-language message.  The Swift apps map ``code``
straight onto their own error surface, so codes must never be reused for a
different meaning.  Ranges:

    1xxx  command language (parse / lookup / history)
    2xxx  geometry (parameters / OCCT failures / empty results)
    3xxx  files (scripts / import / export)
    5xxx  internal faults (a bug, not user error)
"""


class Codes:
    PARSE = 1001            # line could not be tokenised / malformed syntax
    UNKNOWN_COMMAND = 1002  # command word not in the catalog
    ARITY = 1003            # wrong number of arguments / missing keyword
    BAD_EXPRESSION = 1004   # numeric expression failed to evaluate
    UNDEFINED_NAME = 1005   # referenced object / profile / variable missing
    DUPLICATE_NAME = 1006   # create target already exists
    NOTHING_TO_UNDO = 1007  # undo with an empty undo stack
    NOTHING_TO_REDO = 1008  # redo with an empty redo stack
    BAD_NAME = 1009         # object name is not a valid identifier

    INVALID_PARAM = 2001    # e.g. radius <= 0, height <= 0, zero axis
    GEOMETRY_FAILED = 2002  # OCCT raised / operation did not complete
    EMPTY_RESULT = 2003     # operation produced a null or zero-volume shape
    BAD_PROFILE = 2004      # profile has < 3 points or is self-evidently bad
    BAD_EDGE_INDEX = 2005   # fillet/chamfer edge index out of range

    FILE_NOT_FOUND = 3001   # script / import path does not exist
    FILE_READ = 3002        # script could not be read / decoded
    EXPORT_FAILED = 3003    # STEP/STL/view writer failed
    SCRIPT_FAILED = 3004    # a line inside a script failed (wraps its code)

    INTERNAL = 5001         # unexpected exception in our own code
    NOT_IMPLEMENTED = 5002  # command/toolkit not in this build (integration: CC-SYS-000)


class CCError(Exception):
    """One structured failure.

    ``line_no`` / ``source`` are filled in by the script runner so a user
    opening their script file can find the offending line immediately.
    """

    def __init__(self, code, code_name, message, line_no=None, source=None):
        super().__init__(message)
        self.code = code
        self.code_name = code_name
        self.message = message
        self.line_no = line_no
        self.source = source

    def __str__(self):
        where = ""
        if self.source:
            where = f"{self.source}"
            if self.line_no is not None:
                where += f":{self.line_no}"
            where += ": "
        return f"[E{self.code} {self.code_name}] {where}{self.message}"


def parse_error(msg):
    return CCError(Codes.PARSE, "PARSE", msg)


def unknown_command(word):
    return CCError(Codes.UNKNOWN_COMMAND, "UNKNOWN_COMMAND",
                   f"Unknown command '{word}'. Type 'help' for the command list.")


def arity(cmd, msg):
    return CCError(Codes.ARITY, "ARITY", f"'{cmd}': {msg}")


def bad_expression(token, why):
    return CCError(Codes.BAD_EXPRESSION, "BAD_EXPRESSION",
                   f"Could not evaluate '{token}': {why}.")


def undefined_name(kind, name):
    return CCError(Codes.UNDEFINED_NAME, "UNDEFINED_NAME",
                   f"No {kind} named '{name}' exists yet.")


def duplicate_name(kind, name):
    return CCError(Codes.DUPLICATE_NAME, "DUPLICATE_NAME",
                   f"A {kind} named '{name}' already exists. "
                   f"Delete it first ('delete {name}') or pick another name.")


def invalid_param(msg):
    return CCError(Codes.INVALID_PARAM, "INVALID_PARAM", msg)


def geometry_failed(op, why):
    return CCError(Codes.GEOMETRY_FAILED, "GEOMETRY_FAILED",
                   f"{op} failed inside Open CASCADE: {why}")


def empty_result(op):
    return CCError(Codes.EMPTY_RESULT, "EMPTY_RESULT",
                   f"{op} produced an empty shape — check the inputs overlap / sizes.")
