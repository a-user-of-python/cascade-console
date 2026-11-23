"""Automated tests for the Cascade Console core prototype.

Run:  ~/workspace/stl2step-venv/bin/python -m unittest discover -s tests -v
(from the CorePrototype folder, or pass the folder path to discover.)
"""

import json
import math
import os
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)),
                                "..", "python"))

from cc import CCError, Codes, Interpreter  # noqa: E402


def vol(interp, name):
    return interp.geo.volume(interp.objects[name])


class PrimitiveTests(unittest.TestCase):
    def setUp(self):
        self.i = Interpreter()

    def test_box_volume_and_bbox(self):
        self.i.execute("box b 10 20 30")
        self.assertAlmostEqual(vol(self.i, "b"), 6000.0, places=6)
        self.assertEqual(tuple(round(v, 6) for v in self.i.geo.bbox(self.i.objects["b"])),
                         (0, 0, 0, 10, 20, 30))

    def test_cylinder_volume(self):
        self.i.execute("cylinder c 5 10")
        self.assertAlmostEqual(vol(self.i, "c"), math.pi * 25 * 10, places=4)

    def test_sphere_volume(self):
        self.i.execute("sphere s 5")
        self.assertAlmostEqual(vol(self.i, "s"), 4 / 3 * math.pi * 125, places=4)

    def test_cone_volume(self):
        self.i.execute("cone k 6 3 9")
        expect = math.pi * 9 / 3 * (36 + 18 + 9)
        self.assertAlmostEqual(vol(self.i, "k"), expect, places=4)

    def test_torus_volume(self):
        self.i.execute("torus t 10 3")
        expect = 2 * math.pi ** 2 * 10 * 9
        self.assertAlmostEqual(vol(self.i, "t"), expect, places=3)

    def test_placement_at(self):
        self.i.execute("box b 10 10 10 at 100,50,-5")
        bb = self.i.geo.bbox(self.i.objects["b"])
        self.assertEqual(tuple(round(v, 6) for v in bb), (100, 50, -5, 110, 60, 5))

    def test_invalid_radius_code(self):
        with self.assertRaises(CCError) as cm:
            self.i.execute("sphere s -1")
        self.assertEqual(cm.exception.code, Codes.INVALID_PARAM)

    def test_duplicate_name_code(self):
        self.i.execute("box b 1 1 1")
        with self.assertRaises(CCError) as cm:
            self.i.execute("box b 2 2 2")
        self.assertEqual(cm.exception.code, Codes.DUPLICATE_NAME)
        self.assertAlmostEqual(vol(self.i, "b"), 1.0)  # original untouched


class BooleanTests(unittest.TestCase):
    def setUp(self):
        self.i = Interpreter()
        self.i.execute("box a 10 20 30")
        self.i.execute("box b 10 20 30 at 5,0,0")

    def test_union(self):
        self.i.execute("union u a b")
        self.assertAlmostEqual(vol(self.i, "u"), 9000.0, places=5)

    def test_cut(self):
        self.i.execute("cut c a b")
        self.assertAlmostEqual(vol(self.i, "c"), 3000.0, places=5)

    def test_intersect(self):
        self.i.execute("intersect x a b")
        self.assertAlmostEqual(vol(self.i, "x"), 3000.0, places=5)

    def test_inputs_unchanged(self):
        self.i.execute("union u a b")
        self.assertAlmostEqual(vol(self.i, "a"), 6000.0, places=5)
        self.assertAlmostEqual(vol(self.i, "b"), 6000.0, places=5)

    def test_undefined_operand_code(self):
        with self.assertRaises(CCError) as cm:
            self.i.execute("union u a nope")
        self.assertEqual(cm.exception.code, Codes.UNDEFINED_NAME)


class FinishAndTransformTests(unittest.TestCase):
    def setUp(self):
        self.i = Interpreter()
        self.i.execute("box b 10 20 30")

    def test_fillet_reduces_volume(self):
        self.i.execute("fillet f b 1")
        v = vol(self.i, "f")
        self.assertLess(v, 6000.0)
        self.assertGreater(v, 5900.0)

    def test_chamfer_reduces_volume(self):
        self.i.execute("chamfer c b 1")
        v = vol(self.i, "c")
        self.assertLess(v, 6000.0)
        self.assertGreater(v, 5000.0)

    def test_fillet_bad_edge_code(self):
        with self.assertRaises(CCError) as cm:
            self.i.execute("fillet f b 1 edges 99")
        self.assertEqual(cm.exception.code, Codes.BAD_EDGE_INDEX)

    def test_translate_moves_bbox_not_volume(self):
        self.i.execute("translate m b 100 0 0")
        self.assertAlmostEqual(vol(self.i, "m"), 6000.0, places=5)
        bb = self.i.geo.bbox(self.i.objects["m"])
        self.assertAlmostEqual(bb[0], 100.0, places=5)

    def test_rotate_swaps_xy_extents(self):
        self.i.execute("rotate r b 0 0 1 90")
        bb = self.i.geo.bbox(self.i.objects["r"])
        extents = (bb[3] - bb[0], bb[4] - bb[1], bb[5] - bb[2])
        self.assertAlmostEqual(extents[0], 20.0, places=4)
        self.assertAlmostEqual(extents[1], 10.0, places=4)
        self.assertAlmostEqual(extents[2], 30.0, places=4)
        self.assertAlmostEqual(vol(self.i, "r"), 6000.0, places=4)

    def test_rotate_zero_axis_code(self):
        with self.assertRaises(CCError) as cm:
            self.i.execute("rotate r b 0 0 0 45")
        self.assertEqual(cm.exception.code, Codes.INVALID_PARAM)


class ProfileTests(unittest.TestCase):
    def test_extrude_rectangle(self):
        i = Interpreter()
        i.execute("profile p 0,0 40,0 40,20 0,20")
        i.execute("extrude e p 10")
        self.assertAlmostEqual(vol(i, "e"), 8000.0, places=5)

    def test_profile_too_few_points(self):
        i = Interpreter()
        with self.assertRaises(CCError) as cm:
            i.execute("profile p 0,0 10,0")
        self.assertEqual(cm.exception.code, Codes.ARITY)


class LanguageTests(unittest.TestCase):
    def setUp(self):
        self.i = Interpreter()

    def test_variables_and_expressions(self):
        self.i.execute("set w = 12")
        self.i.execute("box b $w 2*$w $w/2")
        self.assertAlmostEqual(vol(self.i, "b"), 12 * 24 * 6, places=5)

    def test_undefined_variable_code(self):
        with self.assertRaises(CCError) as cm:
            self.i.execute("box b $nope 1 1")
        self.assertEqual(cm.exception.code, Codes.BAD_EXPRESSION)

    def test_unknown_command_code(self):
        with self.assertRaises(CCError) as cm:
            self.i.execute("splorge b 1 2 3")
        self.assertEqual(cm.exception.code, Codes.UNKNOWN_COMMAND)

    def test_arity_code(self):
        with self.assertRaises(CCError) as cm:
            self.i.execute("box b 1 2")
        self.assertEqual(cm.exception.code, Codes.ARITY)

    def test_comments_and_blank_lines(self):
        self.assertEqual(self.i.execute("# just a comment"), "")
        self.assertEqual(self.i.execute("   "), "")
        self.i.execute("box b 1 1 1 # trailing comment")
        self.assertIn("b", self.i.objects)

    def test_copy_rename_delete(self):
        self.i.execute("box a 2 2 2")
        self.i.execute("copy b a")
        self.i.execute("rename c b")
        self.assertIn("c", self.i.objects)
        self.i.execute("delete a")
        self.assertNotIn("a", self.i.objects)
        with self.assertRaises(CCError) as cm:
            self.i.execute("delete a")
        self.assertEqual(cm.exception.code, Codes.UNDEFINED_NAME)

    def test_undo_redo(self):
        self.i.execute("box a 2 2 2")
        self.i.execute("box b 3 3 3")
        self.i.execute("undo")
        self.assertNotIn("b", self.i.objects)
        self.assertIn("a", self.i.objects)
        self.i.execute("undo")
        self.assertNotIn("a", self.i.objects)
        self.i.execute("redo")
        self.assertIn("a", self.i.objects)
        self.i.execute("redo")
        self.assertIn("b", self.i.objects)

    def test_undo_restores_variables(self):
        self.i.execute("set w = 5")
        self.i.execute("set w = 9")
        self.i.execute("undo")
        self.assertEqual(self.i.vars["w"], 5.0)

    def test_failed_command_leaves_no_undo_step(self):
        self.i.execute("box a 1 1 1")
        depth = len(self.i.undo_stack)
        with self.assertRaises(CCError):
            self.i.execute("box a 9 9 9")  # duplicate — must fail cleanly
        self.assertEqual(len(self.i.undo_stack), depth)
        self.i.execute("undo")
        self.assertNotIn("a", self.i.objects)  # undid the real creation

    def test_nothing_to_undo_code(self):
        with self.assertRaises(CCError) as cm:
            self.i.execute("undo")
        self.assertEqual(cm.exception.code, Codes.NOTHING_TO_UNDO)

    def test_log_records_success_and_error(self):
        self.i.execute("box a 1 1 1")
        with self.assertRaises(CCError):
            self.i.execute("box a 1 1 1")
        levels = [r["level"] for r in self.i.log.records]
        self.assertIn("info", levels)
        self.assertIn("error", levels)
        err = [r for r in self.i.log.records if r["level"] == "error"][0]
        self.assertEqual(err["code"], Codes.DUPLICATE_NAME)


class ScriptAndExportTests(unittest.TestCase):
    def test_script_file_and_demo_geometry(self):
        i = Interpreter()
        with tempfile.TemporaryDirectory() as td:
            path = os.path.join(td, "s.ccs")
            with open(path, "w") as fh:
                fh.write("# comment\nset h = 7\nbox b 10 10 $h\nvolume b\n")
            out = i.run_script(path)
            self.assertIn("Ran 3 command(s)", out)
            self.assertAlmostEqual(vol(i, "b"), 700.0, places=5)

    def test_script_missing_file_code(self):
        i = Interpreter()
        with self.assertRaises(CCError) as cm:
            i.run_script("/nonexistent/nope.ccs")
        self.assertEqual(cm.exception.code, Codes.FILE_NOT_FOUND)

    def test_script_error_reports_line(self):
        i = Interpreter()
        with tempfile.TemporaryDirectory() as td:
            path = os.path.join(td, "bad.ccs")
            with open(path, "w") as fh:
                fh.write("box b 1 1 1\nbox b 2 2 2\n")
            with self.assertRaises(CCError) as cm:
                i.run_script(path)
            self.assertEqual(cm.exception.code, Codes.SCRIPT_FAILED)
            self.assertEqual(cm.exception.line_no, 2)

    def test_step_and_stl_export(self):
        i = Interpreter()
        i.execute("box b 10 20 30")
        with tempfile.TemporaryDirectory() as td:
            step = os.path.join(td, "b.step")
            stl = os.path.join(td, "b.stl")
            i.execute(f"export step {step} b")
            i.execute(f"export stl {stl} b")
            self.assertGreater(os.path.getsize(step), 1000)
            self.assertGreater(os.path.getsize(stl), 100)
            with open(step) as fh:
                self.assertIn("ISO-10303-21", fh.read(2000))

    def test_step_round_trip_volume(self):
        """Re-import the exported STEP with a fresh OCCT reader."""
        from OCP.STEPControl import STEPControl_Reader
        from OCP.BRepGProp import BRepGProp
        from OCP.GProp import GProp_GProps
        i = Interpreter()
        i.execute("cylinder c 5 10")
        with tempfile.TemporaryDirectory() as td:
            step = os.path.join(td, "c.step")
            i.execute(f"export step {step} c")
            reader = STEPControl_Reader()
            self.assertEqual(int(reader.ReadFile(step)), 1)  # IFSelect_RetDone
            reader.TransferRoots()
            shape = reader.OneShape()
            props = GProp_GProps()
            BRepGProp.VolumeProperties_s(shape, props)
            self.assertAlmostEqual(props.Mass(), math.pi * 25 * 10, places=3)

    def test_view_data(self):
        i = Interpreter()
        i.execute("box b 10 20 30")
        i.execute("sphere s 5")
        with tempfile.TemporaryDirectory() as td:
            path = os.path.join(td, "view.json")
            out = i.execute(f"view {path}")
            self.assertIn("2 object(s)", out)
            with open(path) as fh:
                doc = json.load(fh)
            self.assertEqual(doc["format"], "cascade-console-view")
            self.assertEqual(len(doc["objects"]), 2)
            for obj in doc["objects"]:
                self.assertGreater(obj["triangleCount"], 0)
                self.assertEqual(len(obj["indices"]), obj["triangleCount"] * 3)
                self.assertEqual(len(obj["vertices"]) % 3, 0)
                # every vertex must lie inside the (slightly padded) bbox
                bb = obj["bbox"]
                vs = obj["vertices"]
                for k in range(0, len(vs), 3):
                    for axis in range(3):
                        self.assertGreaterEqual(vs[k + axis], bb[axis] - 0.01)
                        self.assertLessEqual(vs[k + axis], bb[axis + 3] + 0.01)


class CatalogFormTests(unittest.TestCase):
    """Agent 1 catalog dialect: trailing 'as <name>' + catalog aliases."""

    def setUp(self):
        self.i = Interpreter()

    def test_primitive_as_form(self):
        self.i.execute("box 10 20 30 as plate")
        self.assertAlmostEqual(vol(self.i, "plate"), 6000.0, places=5)

    def test_fuse_as_form_in_place_reuse(self):
        self.i.execute("box 10 20 30 as body")
        self.i.execute("box 10 20 30 at 5,0,0 as boss")
        self.i.execute("fuse body boss as body")  # catalog in-place idiom
        self.assertAlmostEqual(vol(self.i, "body"), 9000.0, places=5)

    def test_common_alias(self):
        self.i.execute("box a 10 10 10")
        self.i.execute("box b 10 10 10 at 5,0,0")
        self.i.execute("common a b as overlap")
        self.assertAlmostEqual(vol(self.i, "overlap"), 500.0, places=5)

    def test_cut_minus_form(self):
        self.i.execute("box a 10 10 10")
        self.i.execute("box b 10 10 10 at 5,0,0")
        self.i.execute("cut a minus b as left")
        self.assertAlmostEqual(vol(self.i, "left"), 500.0, places=5)

    def test_fillet_as_form(self):
        self.i.execute("box b 10 20 30")
        self.i.execute("fillet b 1 as f")
        self.assertLess(vol(self.i, "f"), 6000.0)

    def test_translate_and_rotate_as_form(self):
        self.i.execute("box b 10 20 30")
        self.i.execute("translate b 100 0 0 as m")
        self.assertAlmostEqual(self.i.geo.bbox(self.i.objects["m"])[0],
                               100.0, places=5)
        self.i.execute("rotate b 0 0 1 90 as r")
        self.assertAlmostEqual(vol(self.i, "r"), 6000.0, places=4)

    def test_extrude_as_form(self):
        self.i.execute("profile p 0,0 40,0 40,20 0,20")
        self.i.execute("extrude p 10 as e")
        self.assertAlmostEqual(vol(self.i, "e"), 8000.0, places=5)

    def test_duplicate_and_rename_catalog_forms(self):
        self.i.execute("box a 2 2 2")
        self.i.execute("duplicate a as b")
        self.assertIn("b", self.i.objects)
        self.i.execute("rename b as c")
        self.assertIn("c", self.i.objects)
        self.assertNotIn("b", self.i.objects)

    def test_show_vars_and_measure_volume_alias(self):
        self.i.execute("set w = 3")
        self.assertIn("w = 3.0", self.i.execute("show-vars"))
        self.i.execute("box b 2 2 2")
        self.assertIn("8.000000", self.i.execute("measure-volume b"))


if __name__ == "__main__":
    unittest.main()
